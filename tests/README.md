# thai-doc-engine: use vs don't-use showcase

Paired `.typ` files. Each pair uses the same Thai/mixed content — one
plain Typst (`no-use.typ`), one with `#show: thai-document-engine.with(...)`
(`use.typ`) — so the difference is visible by compiling both to PDF and
comparing pages side by side. Typst has no assertion/diff framework, so
"test" here means: every file must compile cleanly (exit 0, non-empty PDF).

## Run all compile-checks

From repo root:

```sh
for f in tests/**/*.typ; do
  out="tests/out/$(echo "$f" | tr / _ .pdf)"
  typst compile --root . "$f" "$out" || echo "FAILED: $f"
done
```

(requires a `**` glob-enabled shell, e.g. `shopt -s globstar` in bash, or
use `find tests -name '*.typ'` instead)

## What to look for in each pair

| Dir | Feature | Look for |
|---|---|---|
| `01-phrase-break` | BudouX phrase segmentation | `no-use`: a Thai phrase can be cut mid-word at a line end. `use`: phrases stay whole. |
| `02-phrase-method` | `phrase-method` variants | `box`/`glue`/`wj` all keep phrases whole (different mechanism); `off` behaves like plain Typst. |
| `03-number-unit` | number+unit no-break | `no-use`: "128 KB" / "920-925 MHz" / "3 บอร์ด" can split across lines. `use`: never split. |
| `04-latin-hyphenation` | scoped English hyphenation | `no-use`: long English words/URLs don't hyphenate (stay `lang: "th"`), causing raggedness/overflow. `use`: they hyphenate correctly. |
| `05-keep-phrases` | curated keep-phrase list | `no-use`: "มหาวิทยาลัยเกษตรศาสตร์" can split mid-word. `use`: always whole (typography.json `keep-phrases`). |
| `06-headings-numbering` | heading style | `no-use`: default unnumbered headings. `use`: "1.1"-style numbering, bold TH Sarabun New. |
| `07-figures-tables` | captions/table style | `no-use`: "Figure 1"/"Table 1" English captions. `use`: "ภาพที่"/"ตารางที่" Thai captions, top placement for tables. |
| `08-lists` | list indent | `no-use`: Typst default indent. `use`: 1.5em/0.65em tuned indent. |
| `09-links` | link style | `no-use`: default blue link. `use`: black + underlined. |
| `10-header-footer-topic` | page furniture | `no-use`: bare pages. `use`: header rule + text, footer rule + page numbers, centered title block. |
| `12-stress-long` | worst-case density | `no-use`: dense out-of-dictionary compound Thai (technical + celebrity/place-name jargon, no real word spaces) breaks unpredictably. `use`: BudouX still finds sane phrase boundaries. |

## Notes

- All files assume `TH Sarabun New` is installed; missing-font warnings
  don't fail compilation (Typst substitutes a fallback), but the visual
  comparison is only meaningful with the real font installed.
- `_fixtures.typ` holds shared long-form stress paragraphs (`tech-paragraphs`,
  `place-paragraphs`, `stress-paragraphs`) imported by several pairs to
  keep the comparisons long/dense without duplicating the text in every
  file — not itself a compile target (no `#show`/page content).
- `use.typ` files import `@local/thai-doc-engine:1.0.0` — requires the
  package to be installed under the Typst local package cache (already
  present on this machine at
  `~/.local/share/typst/packages/local/thai-doc-engine/1.0.0`). Note this
  differs from `example.typ` at the repo root, which imports plain
  `"thai-doc-engine:1.0.0"` — that import currently fails to compile
  (`typst compile` errors with "file not found"); it should likely also
  be `@local/thai-doc-engine:1.0.0`.
