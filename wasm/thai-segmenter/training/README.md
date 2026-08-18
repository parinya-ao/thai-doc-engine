# Training data for the Thai segmenter

`models/th.json` is Google's stock BudouX model, trained on 1,153 lines of Wisesight
social-media text (see `../NOTICE`). Academic Thai is a different distribution, and the model
shows it: it cuts inside ordinary compound words, which is why the Typst package carries a
~300-entry `../tests/keep-phrases.txt` patch list. This directory holds what is needed to train
a replacement.

Nothing here trains anything. The two mise tasks fetch corpora and label them; the training run
is manual.

## Layout

| Path | What it is |
| --- | --- |
| `download.py` | fetches the three corpora into `data/raw/` |
| `prepare.py` | labels them into BudouX's U+2581 format in `data/prepared/` |
| `label.py` | the in-domain half: this repo's own documents, labelled the same way |
| `corpus.txt` | the plain Thai runs this repo's documents feed the plugin (`mise run corpus`) |
| `data/` | everything downloaded or derived — **gitignored, never commit it** |

## Sources

| Corpus | Boundaries | Size | Licence |
| --- | --- | --- | --- |
| **LST20** (NECTEC) | gold, 73k sentences | 16 MB zip | research and open source free of charge; **redistribution and modification prohibited**, commercial use by arrangement with NECTEC |
| **VISTEC-TP-TH-2021** | gold, 50k Twitter sentences | 47 MB | CC BY-SA 4.0 (`mrpeerat/OSKut`) |
| **Thai Wikipedia** (`pythainlp/thai-wiki-dataset-v4`) | none — labelled by PyThaiNLP | 326 MB parquet | CC BY-SA 3.0 |

LST20 is fetched from NECTEC's open-data portal, which serves it without an account; the
HuggingFace dataset card instead sends you to `aiforthai.in.th` behind a login for the same
corpus. The licence text ships inside the zip as `LST20_Corpus/AGREEMENT.txt`.

Two corpora that were considered and are not here:

- **Thai National Corpus** has no raw-text release. The only download is a 773 MB AntConc-4
  database, plus frequency lists — neither is a labelled or plain-text corpus.
- **OSCAR** (`oscar-corpus/OSCAR-2301`) is gated `manual` on HuggingFace and upstream has
  suspended access grants, so the Thai subset cannot be obtained. CulturaX carries the same
  OSCAR text behind a lighter gate if that ever becomes worth the token.

## Format

One sentence per line, U+2581 (`▁`) at every word boundary — BudouX's own training format, the
same one `label.py` writes, so the files concatenate. It is also what `src/bin/eval.rs` reads in
`score` mode, so every `*.val.txt` doubles as a gold set for measuring a model.

Two rules `prepare.py` applies that the raw corpora do not:

- **Unreachable boundaries are dropped, not taught.** `phrase_boundaries` never breaks before a
  non-starter (U+0E30–U+0E3A, U+0E45–U+0E4E) or after a leading vowel (U+0E40–U+0E44), per
  `../src/lib.rs`. A gold boundary there cannot be predicted, so keeping it would only drag the
  decision threshold around.
- **Spaces stay in the text** and the boundary goes *after* the space, so the model sees the
  character context it will actually meet at runtime.

VISTEC's `<compound>ศาล|พระภูมิ</compound>` spans lose their internal split: splitting compounds
is the exact failure being trained out. Its `<ne>` and `<msp value="...">` tags are dropped,
keeping the surface text — the misspelling as written, which is what the model will meet.

## Use

```bash
mise run download_train_dataset      # ~390 MB into data/raw/
mise run prepare_train_dataset       # data/prepared/{lst20,vistec,thwiki,all}.{train,val}.txt
```

Both take flags: `--only lst20` (repeatable) and `--force` for the download, `--only`,
`--wiki-lines N`, `--min-thai N` and `--holdout-every N` for the preparation. Wikipedia is
sampled (200k sentences by default, fixed seed) because its labels come from a dictionary
tokeniser rather than an annotator — a word missing from the dictionary comes back shattered, so
it should not outweigh the two gold corpora.

Add this repo's own documents on top, which is what `label.py` is for:

```bash
python label.py --out data/prepared/indomain.train.txt \
  --holdout data/prepared/indomain.val.txt ../../../docs ../../../tests
```

## Training, manually

In a checkout of [google/budoux](https://github.com/google/budoux), against the prepared files:

```bash
python scripts/encode_data.py <train.txt> -o encoded.txt
python scripts/train.py encoded.txt -o weights.txt
python scripts/build_model.py weights.txt -o th.json
```

`train.py` is an anytime algorithm: interrupting it leaves a valid model. Copy the result over
`../models/th.json`, then `mise run build_wasm`. `cargo test` asserts the model's total weight
(4401) as a fingerprint of the shipped weights, so a new model fails that assertion until the
constant is updated — deliberately.

Before and after, measure:

```bash
mise run eval score wasm/thai-segmenter/training/data/prepared/lst20.val.txt 1
mise run eval score wasm/thai-segmenter/training/data/prepared/vistec.val.txt 1
```

Score with `min-chunk 1`. The gold here is *word* boundaries, while the shipped runtime merges
chunks under three clusters, so the default `3` measures the merge pass as much as the model:
the stock `th.json` scores F1 0.885 against `lst20.val.txt` at `1` and 0.696 at `3`, from the
same weights. Use `3` only to compare two models under production settings.
