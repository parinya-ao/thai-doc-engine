#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pythainlp>=5.0", "pyarrow>=17"]
# ///
"""Turn the corpora ``download.py`` fetched into BudouX training files.

Output is the format ``label.py`` already produces -- one sentence per line,
U+2581 at every word boundary -- so the files here and the in-domain file that
script writes simply concatenate.  It is also the format ``src/bin/eval.rs``
reads in ``score`` mode, which makes every holdout file a gold set for
measuring the model that is currently shipped.

Three readers, because the three sources carry boundaries differently:

* ``lst20``  -- CoNLL-style columns, one token per line, blank line ends a
  sentence.  Gold.
* ``vistec`` -- one sentence per line, ``|`` between words, with the corpus's
  misspelling and named-entity tags layered on top.  Gold.
* ``thwiki`` -- plain article text with no boundaries at all, so PyThaiNLP's
  dictionary tokeniser labels it, exactly as ``label.py`` does.  Not gold: a
  word missing from the dictionary comes back shattered, which is why
  ``--wiki-lines`` keeps this source from outweighing the other two.

Two rules apply to every source:

* A boundary the runtime can never emit is deleted rather than taught.
  ``phrase_boundaries`` refuses to break before a non-starter or after a
  leading vowel (``src/lib.rs``), so a gold boundary in those positions is
  unreachable -- keeping it only drags the decision threshold around.
* Spaces stay in the text, and the boundary goes *after* the space, so the
  model sees the same character context it will see at runtime.

Usage:

    uv run prepare.py                       # everything, into data/prepared
    uv run prepare.py --only lst20 --holdout-every 8
"""

import argparse
import pathlib
import random
import re
import sys
import unicodedata

sys.path.insert(0, str(pathlib.Path(__file__).parent))

# label.py owns the corpus conventions this script has to match: the delimiter,
# what counts as a Thai sentence, and how the tokeniser is built.
from label import DELIM, RUN, THAI, build_tokenizer  # noqa: E402

# The two orthographical classes src/lib.rs guards: characters that may not
# start a chunk (following vowels, tone marks, thanthakhat, phinthu) and vowels
# written before the consonant they modify.
NON_STARTER = set(range(0x0E30, 0x0E3B)) | set(range(0x0E45, 0x0E4F))
LEADING_VOWEL = set(range(0x0E40, 0x0E45))

# VISTEC layers three annotations over the same lines that carry the word
# boundaries. Dropping the <ne> and <msp value="..."> tags keeps the surface
# text -- the misspelling as written, which is what the model will meet.
TAG = re.compile(r"</?(?:ne|msp)(?:\s[^>]*)?>")
# <compound>ศาล|พระภูมิ</compound> marks words the corpus splits but that are
# one compound. Those internal splits are the exact failure this model is being
# retrained to stop making, so the boundary inside a compound is dropped.
COMPOUND = re.compile(r"<compound>(.*?)</compound>", re.DOTALL)


def legalise(line):
    """Drop delimiters at positions the runtime could never break at."""
    chars = list(line)
    out = []
    for i, c in enumerate(chars):
        if c != DELIM:
            out.append(c)
            continue
        nxt = next((d for d in chars[i + 1 :] if d != DELIM), "")
        prev = out[-1] if out else ""
        if not prev or not nxt:
            continue  # nothing to separate: line edge
        if ord(nxt) in NON_STARTER or ord(prev) in LEADING_VOWEL:
            continue
        if out[-1] == DELIM:
            continue  # a delimiter the previous drop left doubled
        out.append(c)
    return "".join(out).strip(DELIM)


def join(tokens):
    """Join tokens with DELIM, keeping whitespace inside the chunk before it."""
    chunks = []
    for token in tokens:
        if not token:
            continue
        if not token.strip():
            # A space is a boundary signal, not a chunk: hang it off the chunk
            # it follows so the break lands after it.
            if chunks:
                chunks[-1] += " "
            continue
        chunks.append(token)
    return DELIM.join(chunks)


def read_lst20(root):
    """Sentences from LST20's tab-separated files. `_` is the space token."""
    files = sorted(p for p in root.rglob("*.txt") if p.is_file())
    if not files:
        sys.exit(f"no *.txt under {root} -- run download.py first")
    for path in files:
        tokens = []
        for line in path.read_text(encoding="utf8", errors="replace").splitlines():
            if not line.strip():
                if tokens:
                    yield join(tokens)
                    tokens = []
                continue
            token = line.split("\t")[0]
            tokens.append(" " if token == "_" else token)
        if tokens:
            yield join(tokens)


def read_vistec(root):
    """Sentences from VISTEC's `|`-separated files, tags stripped."""
    files = sorted(root.glob("*_proprocessed.txt"))
    if not files:
        sys.exit(f"no *_proprocessed.txt under {root} -- run download.py first")
    for path in files:
        for line in path.read_text(encoding="utf8", errors="replace").splitlines():
            line = TAG.sub("", line)
            line = COMPOUND.sub(lambda m: m.group(1).replace("|", ""), line).strip()
            if line:
                yield join(line.split("|"))


def read_thwiki(root, limit, seed, min_thai):
    """Thai sentences from the wiki dump, tokenised by the PyThaiNLP teacher."""
    import pyarrow.parquet as pq

    files = sorted(root.rglob("*.parquet"))
    if not files:
        sys.exit(f"no *.parquet under {root} -- run download.py first")

    # Sample before tokenising: newmm over the whole dump would take hours to
    # produce far more text than the gold corpora should be diluted with.
    rng = random.Random(seed)
    pool, seen = [], 0
    for path in files:
        for batch in pq.ParquetFile(path).iter_batches(batch_size=512, columns=["text"]):
            for text in batch.column("text").to_pylist():
                for run in RUN.findall(text or ""):
                    run = run.strip()
                    if len(THAI.findall(run)) < min_thai:
                        continue
                    seen += 1
                    if len(pool) < limit:
                        pool.append(run)
                    else:  # reservoir: every sentence keeps an equal chance
                        j = rng.randrange(seen)
                        if j < limit:
                            pool[j] = run
    print(f"  thwiki: sampled {len(pool)} of {seen} sentences", flush=True)

    vocabulary = read_vocabulary()
    tokenizer = build_tokenizer(vocabulary)
    print(f"  thwiki: tokenising with newmm + {len(vocabulary)} curated words", flush=True)
    for run in pool:
        yield join(tokenizer.word_tokenize(run))


def read_vocabulary():
    """The curated word list label.py folds into the tokeniser's dictionary."""
    path = pathlib.Path(__file__).parent.parent / "tests" / "keep-phrases.txt"
    return [
        line.strip()
        for line in path.read_text(encoding="utf8").splitlines()
        if line.strip() and not line.startswith("#")
    ]


def clean(lines, min_thai):
    """Legalise, drop the too-short and the duplicates, preserve order."""
    seen, out = set(), []
    for line in lines:
        line = legalise(unicodedata.normalize("NFC", line).strip())
        if len(THAI.findall(line)) < min_thai or DELIM not in line or line in seen:
            continue
        seen.add(line)
        out.append(line)
    return out


def write(lines, out_dir, name, every):
    """Write name.train.txt and name.val.txt, holding out every Nth line."""
    train = [l for i, l in enumerate(lines) if i % every != 0]
    val = [l for i, l in enumerate(lines) if i % every == 0]
    for part, rows in (("train", train), ("val", val)):
        path = out_dir / f"{name}.{part}.txt"
        path.write_text("\n".join(rows) + "\n", encoding="utf8")
        boundaries = sum(l.count(DELIM) for l in rows)
        print(f"  {path.name}: {len(rows)} lines, {boundaries} boundaries, {sum(map(len, rows))} chars")
    return train, val


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    here = pathlib.Path(__file__).parent
    parser.add_argument("--raw", type=pathlib.Path, default=here / "data" / "raw", help="download.py's output")
    parser.add_argument("-o", "--out", type=pathlib.Path, default=here / "data" / "prepared", help="output directory")
    parser.add_argument("--only", choices=["lst20", "vistec", "thwiki"], action="append", help="one source (repeatable)")
    parser.add_argument("--holdout-every", type=int, default=8, help="1 in N lines held out (default 8)")
    parser.add_argument("--min-thai", type=int, default=12, help="skip lines with fewer Thai characters")
    parser.add_argument("--wiki-lines", type=int, default=200_000, help="sentences to sample from Wikipedia")
    parser.add_argument("--seed", type=int, default=20260818, help="seed for the Wikipedia sample")
    args = parser.parse_args()

    raw, out = args.raw.expanduser().resolve(), args.out.expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)

    readers = {
        "lst20": lambda: read_lst20(raw / "lst20"),
        "vistec": lambda: read_vistec(raw / "vistec"),
        "thwiki": lambda: read_thwiki(raw / "thwiki", args.wiki_lines, args.seed, args.min_thai),
    }

    for name in args.only or list(readers):
        print(f"{name}:", flush=True)
        write(clean(readers[name](), args.min_thai), out, name, args.holdout_every)

    # Merge from disk rather than from this run, so `--only thwiki` still leaves
    # all.*.txt agreeing with the per-source files sitting next to it.
    print("all:")
    for part in ("train", "val"):
        rows = [
            line
            for name in readers
            if (out / f"{name}.{part}.txt").exists()
            for line in (out / f"{name}.{part}.txt").read_text(encoding="utf8").splitlines()
            if line
        ]
        path = out / f"all.{part}.txt"
        path.write_text("\n".join(rows) + "\n", encoding="utf8")
        print(f"  {path.name}: {len(rows)} lines, {sum(l.count(DELIM) for l in rows)} boundaries")

    print(f"\nprepared corpora in {out}")


if __name__ == "__main__":
    main()
