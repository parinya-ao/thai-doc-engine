#!/usr/bin/env python3
"""Label in-domain Thai text with word boundaries, in BudouX's training format.

The vendored ``models/th.json`` was trained on 1,153 lines of Thai social-media
text (Wisesight; see ../NOTICE and training/README.md).  Academic Thai is a
different distribution, and the model shows it: it cuts inside ordinary compound
words -- ยั่ง|ยืน, ดำเนิน|งาน, มหาวิทยาลัย|เกษตรศาสตร์ -- which is why the Typst
package grew a 300-word ``keep-phrases`` list to patch the output afterwards.

This script produces the in-domain half of the fine-tuning data: it pulls the
Thai from a document tree, tokenises it with PyThaiNLP, and writes one sentence
per line with U+2581 at every word boundary -- the same format
``scripts/prepare_wisesight.py`` produces upstream, so the two concatenate.

The tokeniser is the teacher.  ``newmm`` is dictionary maximal-matching, which
is exactly right for the failure being fixed (a word in the dictionary is never
split) and exactly wrong for words that are not in it (ลอร่า comes back as
ล|อ|ร่า).  So the dictionary is extended with the curated word list before
tokenising: that list is the vocabulary this corpus needs, and folding it into
the teacher is how it ends up in the weights instead of in a runtime lookup.

Usage:

    python label.py --out source_domain.txt PATH [PATH ...]
    python label.py --out train.txt --holdout val.txt --holdout-every 8 PATH
"""

import argparse
import pathlib
import re
import sys

# U+2581 LOWER ONE EIGHTH BLOCK, BudouX's boundary marker.
DELIM = "▁"

# A run of Thai, plus the spaces, Latin words, digits and light punctuation that
# occur inside a Thai sentence.  Deliberately excludes the braces, hashes and
# backslashes that make up Typst markup, so a run stops at the markup around it.
RUN = re.compile(r"[฀-๿][฀-๿0-9A-Za-z .,%()–-]*[฀-๿]")
THAI = re.compile(r"[฀-๿]")


def extract(paths, min_thai):
    """Thai sentences from every file under `paths`, de-duplicated, in order."""
    seen, out = set(), []
    files = []
    for path in paths:
        p = pathlib.Path(path)
        files.extend(sorted(p.rglob("*.typ")) + sorted(p.rglob("*.md")) if p.is_dir() else [p])
    for path in files:
        # target/ holds build artefacts and repomix dumps are flattened copies of
        # files already in the list; both would only duplicate the corpus.
        if "target" in path.parts or "repomix" in path.name:
            continue
        try:
            text = path.read_text(encoding="utf8")
        except (OSError, UnicodeDecodeError):
            continue
        for run in RUN.findall(text):
            run = run.strip()
            if len(THAI.findall(run)) < min_thai or run in seen:
                continue
            seen.add(run)
            out.append(run)
    return out


def build_tokenizer(extra_words):
    from pythainlp.tokenize import Tokenizer
    from pythainlp.corpus.common import thai_words

    words = set(thai_words()) | set(extra_words)
    return Tokenizer(custom_dict=words, engine="newmm")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("paths", nargs="+", help="files or directories to harvest Thai text from")
    parser.add_argument("-o", "--out", required=True, help="training output path")
    parser.add_argument("--holdout", help="write every Nth sentence here instead, as a held-out set")
    parser.add_argument("--holdout-every", type=int, default=8, help="1 in N sentences held out (default 8)")
    parser.add_argument(
        "--vocabulary",
        help="newline-separated words to add to the tokeniser's dictionary "
        "(defaults to ../tests/keep-phrases.txt next to this script)",
    )
    parser.add_argument("--min-thai", type=int, default=12, help="skip runs with fewer Thai characters")
    args = parser.parse_args()

    vocabulary_path = args.vocabulary or pathlib.Path(__file__).parent.parent / "tests" / "keep-phrases.txt"
    vocabulary = [
        line.strip()
        for line in pathlib.Path(vocabulary_path).read_text(encoding="utf8").splitlines()
        if line.strip() and not line.startswith("#")
    ]

    sentences = extract(args.paths, args.min_thai)
    if not sentences:
        sys.exit("no Thai text found under: " + ", ".join(args.paths))

    tokenizer = build_tokenizer(vocabulary)
    lines = [DELIM.join(t for t in tokenizer.word_tokenize(s) if t.strip()) for s in sentences]

    if args.holdout:
        every = args.holdout_every
        held = [line for i, line in enumerate(lines) if i % every == 0]
        kept = [line for i, line in enumerate(lines) if i % every != 0]
        pathlib.Path(args.holdout).write_text("\n".join(held) + "\n", encoding="utf8")
        print(f"{len(held)} sentences -> {args.holdout}")
    else:
        kept = lines

    pathlib.Path(args.out).write_text("\n".join(kept) + "\n", encoding="utf8")
    print(f"{len(kept)} sentences, {sum(len(l) for l in kept)} chars -> {args.out}")
    print(f"vocabulary: {len(vocabulary)} curated words added to the dictionary")


if __name__ == "__main__":
    main()
