# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview
Typst package `thai-doc-engine` (Thai-English academic document engine) plus a Rust/WASM
plugin `wasm/thai-segmenter` (Rust port of Google's BudouX phrase-segmentation model) that
prevents Typst's line breaker from splitting Thai text mid-phrase.

- `package/thai-doc-engine/1.0.0/` — the Typst package: `lib.typ` (show rules), `typst.toml`
  (manifest), `typography.json` (Thai word config), and the committed built plugin binary
  `thai_segmenter.wasm`.
- `wasm/thai-segmenter/` — Rust source for the plugin (`src/lib.rs`), built via
  `wasm-minimal-protocol` (Typst's plugin ABI, not wasm-bindgen) to `wasm32-unknown-unknown`.
- `docs/` and `example/` are currently empty placeholders.

## Build / test
No Makefile or CI in this repo. Raw commands (run from repo root):

- Test the Rust segmenter (native target): `cargo test --release --manifest-path wasm/thai-segmenter/Cargo.toml`
- Build the wasm plugin: `cargo build --release --manifest-path wasm/thai-segmenter/Cargo.toml --target wasm32-unknown-unknown`
  (requires `rustup target add wasm32-unknown-unknown` once), then copy the output into
  `package/thai-doc-engine/1.0.0/thai_segmenter.wasm` — the built binary is committed so that
  compiling Typst docs never requires Rust/cargo.
- The sibling project this repo was split from (`~/university/final_project_docs/mise.toml`)
  defines `mise run build_wasm` and `mise run keep_phrases` wrapping the same steps — not
  present in this repo, but useful context if such tooling reappears here.
- Compile a Typst doc: `typst compile --root . --pdf-standard a-4`
- Lint: `cargo clippy --manifest-path wasm/thai-segmenter/Cargo.toml`; format: `cargo fmt --manifest-path wasm/thai-segmenter/Cargo.toml` (uses `wasm/thai-segmenter/rustfmt.toml`).

## Gotchas
- `package/thai-doc-engine/thai-doc-engine` is a symlink to an absolute path outside this repo
  (`~/university/final_project_docs/...`) on the author's machine. It's a known artifact tied to
  local setup, not repo content — don't "fix" or dereference it as part of this project.
- Two licenses coexist: top-level `LICENSE` is AGPLv3, but the vendored BudouX model and the
  Rust crate (`wasm/thai-segmenter/Cargo.toml`) are Apache-2.0, matching upstream BudouX.
- `wasm/thai-segmenter/src/lib.rs` tests assert the BudouX model weight total equals a magic
  number (4401) as a fingerprint of `models/th.json`. Updating the model intentionally breaks
  this test until the constant is updated too.
- Typst plugin functions are memoized/pure; the segmenter runs once per compilation input.
- `repomix-output.xml` (root and `wasm/`) are generated flattened-repo dumps — read source files
  directly instead of these.
