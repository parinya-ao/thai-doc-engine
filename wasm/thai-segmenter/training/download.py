#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["huggingface-hub>=0.34"]
# ///
"""Fetch the Thai corpora that ``prepare.py`` turns into BudouX training data.

Three sources, chosen for what they can actually deliver (see README.md):

* **LST20** -- NECTEC's five-layer annotated corpus.  Gold word boundaries.
  The HuggingFace card sends you to aiforthai.in.th behind a login; NECTEC's
  own open-data portal serves the same corpus as a plain zip, no account.
* **VISTEC-TP-TH-2021** -- 49,997 manually segmented Twitter sentences,
  annotated to LST20's guidelines.  Gold, and a different register.
* **Thai Wikipedia** -- pythainlp's cleaned dump.  No gold boundaries; it is
  raw text for a tokeniser to label, which is why prepare.py caps how much of
  it lands in the training set.

The Thai National Corpus is absent because it has no raw-text release, and
OSCAR because its HuggingFace gate is closed to new requests.

Nothing here trains anything, and nothing here is redistributable: LST20's
licence forbids it, so training/data/ is gitignored.

Usage:

    uv run download.py --out ../training/data/raw
    uv run download.py --only lst20 --force
"""

import argparse
import pathlib
import shutil
import sys
import urllib.error
import urllib.request
import zipfile

# NECTEC's open-data portal, the login-free route to the same corpus the
# HuggingFace loader expects you to fetch by hand from aiforthai.in.th.
LST20_URL = (
    "https://opend-portal.nectec.or.th/dataset/d1364791-84bc-4b65-9904-79aa0aa2c5a6"
    "/resource/063e2392-1eba-4099-a732-fbaf1ba9a293/download/opend_lst20_corpus.zip"
)
VISTEC_BASE = "https://raw.githubusercontent.com/mrpeerat/OSKut/main/VISTEC-TP-TH-2021"
VISTEC_FILES = (
    "train/VISTEC-TP-TH-2021_train_proprocessed.txt",
    "test/VISTEC-TP-TH-2021_test_proprocessed.txt",
)
WIKI_REPO = "pythainlp/thai-wiki-dataset-v4"

# Sizes as served on 2026-08-18.  A download that comes back wildly smaller is
# a captive portal or an error page, not a corpus, so warn rather than let
# prepare.py fail on HTML later.
EXPECTED = {
    "opend_lst20_corpus.zip": 16_117_011,
    "VISTEC-TP-TH-2021_train_proprocessed.txt": 39_409_213,
    "VISTEC-TP-TH-2021_test_proprocessed.txt": 9_865_605,
}


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def fetch(url, dest, force):
    """Download `url` to `dest`, unless it is already there."""
    if dest.exists() and not force:
        print(f"  have {dest.name} ({human(dest.stat().st_size)})")
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    print(f"  get  {dest.name} <- {url}")
    try:
        with urllib.request.urlopen(url, timeout=60) as response, tmp.open("wb") as out:
            shutil.copyfileobj(response, out, length=1 << 20)
    except (urllib.error.URLError, TimeoutError) as e:
        tmp.unlink(missing_ok=True)
        sys.exit(f"failed to download {url}: {e}")
    tmp.replace(dest)

    size = dest.stat().st_size
    expected = EXPECTED.get(dest.name)
    if expected and abs(size - expected) > expected // 10:
        print(f"  WARN {dest.name} is {human(size)}, expected about {human(expected)}")
    else:
        print(f"  ok   {dest.name} ({human(size)})")
    return dest


def get_lst20(out, force):
    print("LST20 (NECTEC, research use only, do not redistribute)")
    archive = fetch(LST20_URL, out / "opend_lst20_corpus.zip", force)
    target = out / "lst20"
    if target.exists() and not force:
        print(f"  have {target.name}/ extracted")
        return
    shutil.rmtree(target, ignore_errors=True)
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(target)
    # The portal describes the layout only as "CoNLL-2003-style", so show what
    # actually came out -- prepare.py globs for *.txt rather than assuming.
    files = sorted(p for p in target.rglob("*") if p.is_file())
    print(f"  ok   {len(files)} files under {target}")
    for p in files[:5]:
        print(f"       {p.relative_to(target)} ({human(p.stat().st_size)})")
    if len(files) > 5:
        print(f"       ... and {len(files) - 5} more")


def get_vistec(out, force):
    print("VISTEC-TP-TH-2021 (CC BY-SA 4.0)")
    for name in VISTEC_FILES:
        fetch(f"{VISTEC_BASE}/{name}", out / "vistec" / pathlib.PurePosixPath(name).name, force)


def get_thwiki(out, force):
    print(f"Thai Wikipedia via {WIKI_REPO} (CC BY-SA 3.0)")
    from huggingface_hub import snapshot_download

    target = out / "thwiki"
    if target.exists() and any(target.rglob("*.parquet")) and not force:
        print(f"  have {target.name}/")
        return
    path = snapshot_download(
        WIKI_REPO,
        repo_type="dataset",
        allow_patterns=["data/*.parquet"],
        local_dir=target,
    )
    total = sum(p.stat().st_size for p in pathlib.Path(path).rglob("*.parquet"))
    print(f"  ok   {target} ({human(total)})")


SOURCES = {"lst20": get_lst20, "vistec": get_vistec, "thwiki": get_thwiki}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    default_out = pathlib.Path(__file__).parent / "data" / "raw"
    parser.add_argument("-o", "--out", type=pathlib.Path, default=default_out, help="download directory")
    parser.add_argument("--only", choices=sorted(SOURCES), action="append", help="fetch just this source (repeatable)")
    parser.add_argument("--force", action="store_true", help="refetch even if the file is already there")
    args = parser.parse_args()

    out = args.out.expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)
    for name in args.only or list(SOURCES):
        SOURCES[name](out, args.force)
    print(f"\nraw corpora in {out}")


if __name__ == "__main__":
    main()
