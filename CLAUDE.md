# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview
Typst package `thai-doc-engine` (Thai-English academic document engine) plus a Rust/WASM
plugin `wasm/thai-segmenter` (Rust port of Google's BudouX phrase-segmentation model) that
prevents Typst's line breaker from splitting Thai text mid-phrase.

- `package/thai-doc-engine/1.0.0/` — the Typst package: `lib.typ` is a thin re-export shim over
  `src/` (`config.typ` → `metrics.typ` → `cover.typ`/`engine.typ`, a layered DAG with no cycles),
  `typst.toml` (manifest), `typography.json` (Thai word config), and the committed built plugin
  binary `thai_segmenter.wasm`.
- `wasm/thai-segmenter/` — Rust source for the plugin (`src/lib.rs`), built via
  `wasm-minimal-protocol` (Typst's plugin ABI, not wasm-bindgen) to `wasm32-unknown-unknown`.
- `docs/cover.md` documents the `cover()` design math (Van de Graaf canon, Swiss grid, optical
  centre, WCAG contrast) implemented in `src/cover.typ`. `example/example.typ` is the package's
  usage example.

## Build / test
No CI in this repo; `mise.toml` at the root wraps the common steps (`mise tasks` lists them).
Raw equivalents in parentheses, all run from the repo root:

- Test, lint and format-check the segmenter: `mise run test_wasm`
  (`cargo test --release --manifest-path wasm/thai-segmenter/Cargo.toml --features cli`)
- Build the wasm plugin and install it into the Typst package: `mise run build_wasm`
  (`cargo build --release --manifest-path wasm/thai-segmenter/Cargo.toml --target
  wasm32-unknown-unknown`, requires `rustup target add wasm32-unknown-unknown` once, then copy
  the output into `package/thai-doc-engine/1.0.0/thai_segmenter.wasm` — the built binary is
  committed so that compiling Typst docs never requires Rust/cargo).
- Measure the segmenter: `mise run eval <dump|score|stats|bench> <file> [min-chunk]` — see
  `wasm/thai-segmenter/src/bin/eval.rs` and `wasm/thai-segmenter/training/README.md`.
- Fetch and label training corpora: `mise run download_train_dataset`, `mise run
  prepare_train_dataset`. Training itself stays manual, in a `google/budoux` checkout.
- Compile every fixture under `tests/` into `tests/out/`: `mise run typst_test` — the repo's only
  Typst-level test (Typst has no assertion framework, so "pass" means compiles to a non-empty
  PDF). Exits non-zero on the first failing fixture's account, after trying them all.
- Compile a single Typst doc: `typst compile --root . --pdf-standard a-4`
- Lint: `cargo clippy --manifest-path wasm/thai-segmenter/Cargo.toml`; format: `cargo fmt --manifest-path wasm/thai-segmenter/Cargo.toml` (uses `wasm/thai-segmenter/rustfmt.toml`).

## Gotchas
- `package/thai-doc-engine/thai-doc-engine` is a symlink to an absolute path outside this repo
  (`~/university/final_project_docs/...`) on the author's machine. It's a known artifact tied to
  local setup, not repo content — don't "fix" or dereference it as part of this project.
- Two licenses coexist: top-level `LICENSE` is AGPLv3, but the vendored BudouX model and the
  Rust crate (`wasm/thai-segmenter/Cargo.toml`) are Apache-2.0, matching upstream BudouX.
- `models/th.json` is a retrained model (LST20 + VISTEC), not upstream BudouX's. Upstream's is
  kept beside it as `models/th.json.bak`. `wasm/thai-segmenter/src/lib.rs` tests assert the
  weight total equals a magic number (3039) as a fingerprint of `models/th.json`, and
  `tests/invariants.rs` holds a ratchet on how many of 300 curated words the model still splits
  (227). Updating the model intentionally breaks both until the constants are updated too — the
  ratchet may only go down.
- Typst plugin functions are memoized/pure; the segmenter runs once per compilation input.
- `repomix-output.xml` (root and `wasm/`) are generated flattened-repo dumps — read source files
  directly instead of these.
