// config.typ — Layer 0: plugin binding, phrase-segmenter wrappers, typography config
//
// ===== Thai phrase line breaking (BudouX / WebAssembly) =====
//
// Typst does not natively support `word-break: auto-phrase` (typst/typst#8097) yet, but
// handles Thai word segmentation via the ICU LSTM segmenter. The remaining task is the
// opposite: preventing line breaks in the middle of a "phrase".
//
// The phrase segmenter uses Google's BudouX model (AdaBoost, budoux/models/th.json)
// compiled as a WebAssembly plugin. The Rust source is located at wasm/thai-segmenter/
// and built via `mise run build_wasm`. Typst treats plugin functions as pure and
// memoizes them, resulting in execution only once per compilation.
//
// The previous implementation used a static list of 40 words (e.g., การ, ความ, ผู้, เนื่องจาก)
// concatenated into a single regex alternation. The limitation was the closed vocabulary—terms
// like "เฟิร์มแวร์" (firmware) or "บูตโหลดเดอร์" (bootloader) were absent and unprotected.
// BudouX learns phrase boundaries from corpora, covering unseen vocabulary.
//
// The plugin also prevents phrase boundaries from splitting grapheme clusters. Tested against
// 1,439 phrases in this repository, it matched the official Google BudouX output for 1,434
// phrases. The remaining 5 are points where the raw model attempted to split but the guard
// prevented it (4 preceding "ๆ" and 1 splitting "ดําเนินการ").
#let _segmenter = plugin("../thai_segmenter.wasm")

// min-chunk = Minimum phrase length, counted in *orthographic clusters* — glyph stacks, not
// characters. Phrases shorter than this will be merged with the next phrase within the plugin.
// Reason: BudouX's Thai model segments finely at the "word" level. Words like การ/ความ/ที่/ของ/และ
// become individual phrases where lines could break, which the legacy static list prevented.
// Using "length" instead of a "word list" dynamically covers unlisted words.
//
// Clusters rather than characters because that is what a reader sees: "หน้า" and "เพื่อ" are four
// and five characters but two clusters each, no wider on the page than "ที่", so a character count
// waves them through as if they were full words. Measured on this repo's Thai text, min-chunk 3
// in clusters drops the same share of the model's cuts (1,692 of 2,851) that min-chunk 4 in
// characters used to (1,839) — which is why the default moved from 4 to 3 when the unit changed.
#let thai-chunks(text, min-chunk) = (
  str(_segmenter.segment(bytes(text), bytes(str(min-chunk)))).split("\u{1F}")
)

// glue -> Original text with U+2060 inserted only at merged boundaries (default mode).
#let thai-glue(text, min-chunk) = (
  str(_segmenter.glue(bytes(text), bytes(str(min-chunk))))
)

// weld -> Original text with U+2060 inserted at every "mid-phrase" break point.
// Used when phrase-method: "wj".
#let thai-weld(text, min-chunk) = (
  str(_segmenter.weld(bytes(text), bytes(str(min-chunk))))
)

// U+2060 WORD JOINER — UAX#14 Rule LB11 (`× WJ`, `WJ ×`) prevents line breaks at that
// position (same mechanism used by CSS). Still used in the "number + unit" rule below.
#let thai-wj = "\u{2060}"

// ===== Data-driven words extracted to typography.json in this package =====
// Can only be overridden via the `typography:` argument (dict or path). Previously supported
// via `--input typography=/docs/xxx.json`, but as a local package, Typst restricts filesystem
// access to the package's own directory. Root-absolute paths fail within json(). Documents
// requiring custom typography must call json() from the document side (which has full --root
// access) and pass it as a dict to the `typography:` parameter.
#let typography-defaults = json("../typography.json")

#let load-typography(overrides) = {
  let extra = if overrides == none {
    let from-cli = sys.inputs.at("typography", default: none)
    if from-cli == none { (:) } else { json(from-cli) }
  } else if type(overrides) == str {
    json(overrides)
  } else {
    overrides
  }
  typography-defaults + extra
}

// Unmatchable pattern used to disable rules instead of an `if` wrapper. Show rules declared
// inside an `if` block only apply within that block. NUL never appears in Typst source.
#let thai-never = "\u{0}"

// Rust regex uses leftmost-first matching. Longer words must precede shorter ones,
// otherwise "จาก" matches before "เนื่องจาก".
#let thai-alternation(words) = (
  "(?:" + words.filter(w => w != "").sorted(key: w => -w.len()).join("|") + ")"
)
