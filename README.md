# thai-doc-engine

A Typst package for Thai-English academic documents (built for KU Computer Engineering
final-project theses). It provides a Knuth-Plass tuned document template plus a Rust/WebAssembly
plugin that stops Typst's line breaker from splitting Thai text mid-phrase — something Typst's
built-in ICU word segmenter doesn't handle on its own.

## Installation

Not published to the Typst package registry. Install it as a local package: copy
`package/thai-doc-engine/1.0.0/` into Typst's local package directory under
`thai-doc-engine/1.0.0/` (e.g. `~/.local/share/typst/packages/local/thai-doc-engine/1.0.0/` on
Linux). See the [Typst docs on local packages](https://github.com/typst/packages#local-packages)
for other platforms.

## Usage

```typst
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with(
  header-left: "Kasetsart University",
  header-right: "Department of Computer Engineering",
)
```

See `example.typ` at the repo root for a minimal working example.

## Building the WASM plugin

The compiled plugin (`thai_segmenter.wasm`) is committed to the package directory, so compiling
Typst documents never requires Rust or cargo. Rebuilding is only needed when changing the Rust
source in `wasm/thai-segmenter/` or its phrase model — see `CLAUDE.md` for the build/test
commands.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you
would like to change.

Please make sure to update tests as appropriate.

## License

[AGPL-3.0](LICENSE) for the Typst package and document engine.

The vendored BudouX phrase model and the Rust wasm crate (`wasm/thai-segmenter/`) are licensed
separately under Apache-2.0, matching the upstream [BudouX](https://github.com/google/budoux)
project — see `wasm/thai-segmenter/LICENSE.budoux` and `wasm/thai-segmenter/NOTICE`.
