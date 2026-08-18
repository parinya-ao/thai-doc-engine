// lib.typ
// Advanced Thai-English Document Engine for Typst (Production-Ready)
// Powered by Knuth-Plass Optimization & Hybrid Dynamic Space Distribution
//
// Core standard template for all documents in docs/ (week-2 to week-6)
// Usage: #import "@local/thai-doc-engine:1.0.0": *
//        #show: thai-document-engine.with(...)

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
#let _segmenter = plugin("thai_segmenter.wasm")

// min-chunk = Minimum phrase length. Phrases shorter than this will be merged with the
// next phrase within the plugin.
// Reason: BudouX's Thai model segments finely at the "word" level. Words like การ/ความ/ที่/ของ/และ
// become individual phrases where lines could break, which the legacy static list prevented.
// Using "length" instead of a "word list" dynamically covers unlisted words.
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
#let typography-defaults = json("typography.json")

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

#let thai-document-engine(
  topic: none,
  header-left: none,
  header-right: none,
  numbering-style: "1.1",
  footer-left: none,
  margin: 2.5cm,
  paper: "a4",
  phrase-break: true,
  phrase-method: auto, // "box" | "glue" | "wj" | "off"  (auto -> typography.json)
  phrase-min-run: auto, // Minimum Thai characters to trigger segmenter (auto -> typography.json)
  phrase-min-chunk: auto, // Minimum phrase length. Shorter phrases merge with the next.
  phrase-keep: (),
  typography: none, // dict or path to override typography.json values
  leading: 0.2em,
  body,
) = {
  // ===== 0. Typography Data =====
  let th-config = load-typography(typography)
  let phrase-method = if phrase-method == auto {
    th-config.at("phrase-method", default: "box")
  } else { phrase-method }
  let phrase-min-run = if phrase-min-run == auto {
    th-config.at("phrase-min-run", default: 8)
  } else { phrase-min-run }
  let phrase-min-chunk = if phrase-min-chunk == auto {
    th-config.at("phrase-min-chunk", default: 4)
  } else { phrase-min-chunk }
  let phrase-keep = if phrase-keep.len() > 0 {
    phrase-keep
  } else { th-config.at("keep-phrases", default: ()) }
  let unit-classifiers = th-config.at("unit-classifiers", default: ())

  assert(
    phrase-method in ("glue", "box", "wj", "off"),
    message: "phrase-method must be \"glue\", \"box\", \"wj\", or \"off\" — got "
      + repr(phrase-method),
  )

  // ===== 1. Base Page Setup =====
  set page(
    paper: paper,
    margin: margin,
    header: context [
      #set text(
        font: "TH Sarabun New",
        size: 13pt,
        fill: black,
        weight: "regular",
      )
      #if header-left != none or header-right != none [
        #grid(
          columns: (1fr, 1fr),
          align: (left, right),
          [#header-left], [#header-right],
        )
        #v(-0.4em)
        #line(length: 100%, stroke: 0.4pt + rgb("#000000"))
      ]
    ],
    footer: context [
      #line(length: 100%, stroke: 0.4pt + rgb("#999999"))
      #v(0.4em)
      #set text(font: "TH Sarabun New", size: 14pt, fill: rgb("#666666"))
      #grid(
        columns: (1fr, 1fr),
        align: (left, right),
        [#footer-left],
        [Page #counter(page).display("1") / #counter(page).final().first()],
      )
    ],
  )

  // ===== 2. Advanced Text & Typography Engine =====
  // Utilizes Font Fallback for Latin and Thai text, managing the Vertical Envelope.
  set text(
    font: "TH Sarabun New",
    size: 16pt,
    lang: "th",
    region: "th",
    hyphenate: true, // Enables English hyphenation rules
    costs: (
      hyphenation: 30%, // Lowered penalty to encourage hyphenation, reducing justification gaps
      runt: 150%, // Prevents the last line of a paragraph from containing a single word
      widow: 300%, // Prevents the last line of a paragraph from being pushed to a new page
      orphan: 300%, // Prevents the first line of a paragraph from remaining at the bottom of a page
    ),
    // See `sarabun-metrics` below for the measured numbers. Short version: cap-height is only
    // 0.476em, while a level-4 tone mark stacked on a level-3 vowel (bold "ปั๊ม") reaches
    // 0.836em. top-edge: "cap-height" would let tone marks overflow the line box by 0.36em and
    // collide with the line above. "ascender"/"descender" resolve to the OS/2 *typo* metrics
    // (+0.85em / -0.25em), which fit the Thai ink envelope almost exactly — 0.014em of headroom
    // above the tone marks, 0.003em below the sara-uu. Line box is therefore 1.10em.
    top-edge: "ascender",
    bottom-edge: "descender",
    fill: black,
    // overhang: true is the default Typst behavior (hanging punctuation at justify bounds).
    // Explicitly declared to prevent silent behavior changes if defaults shift in the future.
    overhang: true,
  )

  // The hypher crate lacks Thai patterns -> lang: "th" disables hyphenation document-wide,
  // neutralizing costs.hyphenation above and preventing long English words from breaking.
  // This causes justified lines to stretch (Thai only has phrase-level spaces to stretch).
  // Switches only Latin text runs to "en" — Latin and Thai are separate shaping runs by default.
  //
  // Uses Script_Extensions instead of [A-Za-z]: ASCII classes miss Latin characters with
  // diacritics (Rührwerk, Ampère). These words would otherwise never switch to "en" and
  // remain unhyphenated.
  show regex("\\b\\p{scx=Latn}{4,}\\b"): set text(lang: "en")

  // Number + Unit ("128 KB", "920-925 MHz", "16 pt", "3 บอร์ด") must not break across lines.
  // Appends WJ after spaces: LB11 (`× WJ`) precedes LB18 (`SP ÷`), preventing breaks. The space
  // character remains in the justification pool to stretch, unlike U+00A0 which removes it.
  //
  // Latin side is limited to 1-4 characters and closed with \b (KB, MHz, pt, ms, dBm). Thai
  // side is constrained by a classifier list. Both prevent merging non-unit words with trailing
  // model numbers (e.g., "AVR128DA28 โดย" should break). BudouX cannot help here as the space
  // places the unit in a different run than the number.
  show regex(
    "\\p{N}\\s+(?:\\p{scx=Latn}{1,4}\\b|"
      + thai-alternation(unit-classifiers)
      + ")",
  ): it => it.text.replace(regex("\\s+"), " " + thai-wj)

  // auto-phrase: Segment phrases with BudouX and prevent line breaks mid-phrase.
  //
  // "box": Wraps each phrase. Typst represents boxes as U+FFFC in strings passed to the ICU line
  // segmenter, treated as CB class. Rule LB20 (`÷ CB`, `CB ÷`) permits breaks on both sides,
  // restricting breaks to box boundaries only. Advantage over WJ: No foreign characters leak
  // into the PDF text layer — sign_signature/main.py reads character-by-character to find
  // signatories; U+2060 breaks this search.
  //
  // The {n,} quantifier acts as a minimum length threshold: shorter runs are untouched. This
  // optimizes plugin calls and avoids interfering with signature blocks.
  show regex(if phrase-break and phrase-method != "off" {
    "\\p{sc=Thai}{" + str(phrase-min-run) + ",}"
  } else { thai-never }): it => {
    if phrase-method == "glue" {
      thai-glue(it.text, phrase-min-chunk)
    } else if phrase-method == "wj" {
      thai-weld(it.text, phrase-min-chunk)
    } else {
      let phrases = thai-chunks(it.text, phrase-min-chunk)
      if phrases.len() <= 1 { it } else { phrases.map(box).join() }
    }
  }

  // Technical terms that must not break mid-word. Boundaries are actual word boundaries,
  // permitting direct box() usage. Must be declared *after* BudouX rules — benchmarked:
  // post-declaration affects 74 points, pre-declaration 92 points (Typst prioritizes later rules).
  // Generated from corpus using `mise run keep_phrases` (words pythainlp keeps whole but the model splits).
  show regex(if phrase-keep.len() > 0 {
    thai-alternation(phrase-keep)
  } else { thai-never }): it => box(it)

  // hyphenate: false acts as a safeguard — the show regex rule above can penetrate raw blocks,
  // and splitting variables mid-word is a known bug.
  show raw: set text(font: "DejaVu Sans Mono", size: 11pt, hyphenate: false)
  show math.equation: it => it

  // ===== 4. Paragraph & Global Layout Rules =====
  set par(
    justify: true,
    linebreaks: "optimized", // Enables Knuth-Plass Global Optimization algorithm
    // Adjusts per-line tracking alongside existing glue (±1.5%) to mitigate extreme stretching
    // (rivers) on Thai lines with few word-space stretch points. Omits spacing parameter,
    // relying on default glue behavior.
    justification-limits: (tracking: (min: -0.015em, max: 0.015em)),
    first-line-indent: (amount: 1.5em, all: true),
    // Line box ascender..descender = 1.10em (OS/2 typo metrics, see sarabun-metrics), so
    // baseline-to-baseline = 1.10em + leading. At the 0.2em default that is 1.30em = 20.8pt on
    // 16pt text. NOTE: the 1.5x / 23.2-24.0pt figure used by Thai official correspondence
    // standards needs leading: 0.4em, i.e. `thai-leading(1.5)`. The 0.2em default is kept for
    // backwards compatibility -- changing it reflows every existing document.
    // Documents hitting page limits can pass a smaller leading from the caller side.
    leading: leading,
    spacing: 0.75em,
  )

  // ===== 5. Figures / Tables / Lists =====
  // Applies Thai numbering and prefixes to enable @label referencing from the body.
  set figure(numbering: "1")
  show figure: set block(breakable: true)
  show figure.where(kind: image): set figure(supplement: [ภาพที่])
  show figure.where(kind: table): set figure(supplement: [ตารางที่])
  show figure.where(kind: table): set figure(placement: none)
  show figure.where(kind: table): set figure.caption(position: top)
  show figure.where(kind: table): set text(size: 14pt)
  show figure.caption: set text(size: 14pt)

  set table(stroke: 0.5pt + rgb("#888888"), inset: 6pt)
  show table.cell: it => {
    set par(justify: false) // Disables justification within tables to prevent excessive spacing
    it
  }
  set list(indent: 1.5em, body-indent: 0.65em)
  set enum(indent: 1.5em, body-indent: 0.65em)

  // ===== 6. Headings Setup =====
  set heading(numbering: numbering-style)
  show bibliography: set heading(numbering: numbering-style)

  show heading: it => block(
    above: 1.2em,
    below: 0.8em,
    sticky: true,
    {
      set text(font: "TH Sarabun New", weight: "bold", fill: black)
      if it.numbering != none {
        strong(counter(heading).display(it.numbering))
        h(0.6em)
      }
      it.body
    },
  )

  show heading.where(level: 1): set text(size: 18pt)
  show heading.where(level: 2): set text(size: 16pt)

  // ===== 7. Links & Abstract Block =====
  show link: set text(fill: black)
  show link: it => underline(it, stroke: black)

  if topic != none {
    align(center)[
      #block(above: 1em, below: 1.5em)[
        #text(size: 20pt, weight: "bold")[#topic]
      ]
    ]
  }

  set bibliography(
    style: "ieee",
    title: [เอกสารอ้างอิง],
  )

  // ===== Main Content Injection =====
  body
}

// ===== Cover page =====
//
// Implements the "Corporate Clean" annual-report cover system described in docs/cover.md:
// five functional zones, Van de Graaf ninths page geometry, a 12-column Swiss grid, optical-
// centre placement, 60-30-10 colour with WCAG-checkable contrast, and phrase-safe Thai
// display typesetting.
//
// Two things the spec assumes are not true here, so the numbers below are re-derived:
//
//   1. It is written for neo-grotesque Latin display faces (Inter/Helvetica metrics) and
//      recommends *loopless* Thai (Sukhumvit Set, Prompt). This package targets TH Sarabun
//      New, which is looped, ships only Regular/Bold, and draws much smaller on the em.
//   2. Its Thai leading band (k in [1.50, 1.80]) is a blanket safety margin, not a measurement
//      of this font.
//
// Everything in `sarabun-metrics` was measured directly -- the glyf/OS-2 tables of
// "TH Sarabun New.ttf", cross-checked against what Typst actually lays out via measure().

#let sarabun-metrics = (
  upem: 1000,
  // Typst's top-edge/bottom-edge: "ascender"/"descender" resolve to the OS/2 *typo* metrics,
  // NOT hhea (which is +0.844 / -0.457 in this font). This is the pair that matters.
  ascender: 0.85,
  descender: -0.25,
  line-box: 1.10, // ascender - descender
  cap-height: 0.476,
  x-height: 0.340,
  // Worst-case *shaped* ink, from measure(top-edge: "bounds"). The extremes are a level-4
  // tone mark stacked over a level-3 vowel (bold "ปั๊ม") and a below-base vowel (bold "ญู").
  ink-top: 0.836,
  ink-bottom: -0.247,
  // Latin cap 0.476 vs a neo-grotesque's ~0.727, x-height 0.340 vs ~0.52: both ratios land on
  // 1.53. Multiply the Latin-calibrated sizes in docs/cover.md by this to match optical size.
  optical-scale: 1.53,
)

// Baseline-to-baseline = line-box + leading, so a target factor k needs this leading.
// Collision check: clearance between line n's lowest ink and line n+1's highest ink is
// (k - 1.083)em, so k = 1.083 is where Thai tone marks actually touch below-base vowels --
// far tighter than the k >= 1.50 docs/cover.md assumes. Display type can safely go to ~1.30.
#let thai-leading(k) = (k - sarabun-metrics.line-box) * 1em

#let _thai-digits = (
  "0": "๐",
  "1": "๑",
  "2": "๒",
  "3": "๓",
  "4": "๔",
  "5": "๕",
  "6": "๖",
  "7": "๗",
  "8": "๘",
  "9": "๙",
)

// thai-numerals: 2568 -> ๒๕๖๘. Non-digits pass through unchanged.
#let thai-numerals(value) = (
  str(value).clusters().map(c => _thai-digits.at(c, default: c)).join()
)

// WCAG 2.1 relative luminance, L = 0.2126R + 0.7152G + 0.0722B over sRGB-linearised channels.
#let relative-luminance(c) = {
  let (r, g, b, ..) = rgb(c).components()
  let lin(x) = {
    let v = x / 100%
    if v <= 0.04045 { v / 12.92 } else { calc.pow((v + 0.055) / 1.055, 2.4) }
  }
  0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

// contrast-ratio: (L1 + 0.05) / (L2 + 0.05), lighter over darker. >= 4.5 is WCAG AA for body
// text, >= 7 is AAA. Large display type (>= 24pt bold / 30pt regular) needs only 3 / 4.5.
#let contrast-ratio(fg, bg) = {
  let (a, b) = (relative-luminance(fg), relative-luminance(bg))
  let (hi, lo) = if a > b { (a, b) } else { (b, a) }
  (hi + 0.05) / (lo + 0.05)
}

// cover-margins: page geometry canons from docs/cover.md. All three are expressed as
// proportions of the page, never as fixed millimetres, which is what makes the cover render
// correctly on every paper size without a per-paper table.
//
// "van-de-graaf" projects the classical ninths construction: inner W/9, top H/9, outer 2W/9,
// bottom 2H/9. On A4 that is 23.33 / 33.0 / 46.67 / 66.0 mm, text block 140 x 198 mm.
#let cover-margins(w, h, canon) = {
  let (u, v) = (w / 9, h / 9)
  if canon == "van-de-graaf" {
    (left: u, top: v, right: 2 * u, bottom: 2 * v)
  } else if canon == "iso" {
    // docs/cover.md, ISO 216 row: inner : top : outer : bottom = 1 : 1.2 : 1.5 : 2.
    (left: u, top: 1.2 * v, right: 1.5 * u, bottom: 2 * v)
  } else if canon == "symmetric" {
    (left: u, top: v, right: u, bottom: v)
  } else {
    panic(
      "canon must be \"van-de-graaf\", \"iso\", or \"symmetric\" — got " + repr(canon),
    )
  }
}

// thai-merge-keeps: drop any phrase boundary that falls strictly inside a curated whole word.
//
// BudouX's Thai model segments at morpheme level, so at the default min-chunk it cuts
// "ยั่งยืน" into ยั่ง|ยืน and "ดำเนินงาน" into ดำเนิน|งาน. In running text those boundaries
// rarely land on a line end; in a two-line display title they very often do.
//
// thai-document-engine corrects this with a second `show regex` rule declared after the BudouX
// one. That cannot work here: by the time the second rule runs, the first has already replaced
// the text with a sequence of separate boxes, so the curated word is no longer a contiguous
// text run for the regex to match. Rewriting the boundary list *before* anything is boxed is
// the reliable fix, and it is what the cover uses.
//
// Offsets are UTF-8 byte indices throughout — str.len(), str.matches() and str.slice() all
// agree on that unit, so multi-byte Thai clusters stay intact.
#let thai-merge-keeps(phrases, keeps) = {
  if keeps.len() == 0 or phrases.len() <= 1 { return phrases }
  let full = phrases.join()
  let cuts = ()
  let acc = 0
  for p in phrases.slice(0, -1) {
    acc += p.len()
    cuts.push(acc)
  }
  let protected = full.matches(regex(thai-alternation(keeps)))
  let kept = cuts.filter(c => not protected.any(m => c > m.start and c < m.end))
  let out = ()
  let prev = 0
  for c in kept {
    out.push(full.slice(prev, c))
    prev = c
  }
  out.push(full.slice(prev))
  out
}

// Default bar heights for the generated hero. A fixed sequence rather than a PRNG: Typst has
// no RNG, and a deterministic field keeps the cover byte-identical across recompiles.
#let cover-hero-heights = (0.22, 0.55, 0.38, 0.81, 0.64, 1.0, 0.47, 0.72, 0.31, 0.58, 0.44, 0.19)

#let cover(
  brand: none, // Zone 1 — brand lockup, sits on the top margin
  title: none, // Zone 2 — document classification title (Thai)
  title-en: none, // Zone 2 — Latin counterpart
  subtitle: none, // Zone 2 — supporting line
  period: none, // Zone 3 — fiscal year / planning horizon
  meta: (), // Zone 5 — array of regulatory metadata items
  hero: auto, // Zone 4 — auto = generated geometry, none = empty, or any content
  palette: (:), // (base:, brand:, signal:) — 60 / 30 / 10
  sizes: (:), // pt overrides, pre-scaling
  canon: "van-de-graaf",
  optical: 0.45, // title centre as a fraction of page height (0.382 = golden alternative)
  columns: 12,
  gutter: auto, // auto -> 4mm scaled; 12 cols at 4mm gives exactly 8mm columns on A4
  font: "TH Sarabun New",
  numerals: "arabic", // "arabic" | "thai"
  k-display: 1.35, // leading factor for the display title
  k-body: 1.55, // leading factor for everything else
  tracking: -0.01em,
  fit: true, // shrink the display type until the title stack fits its budget
  min-hero: auto, // floor on the hero band before the title is allowed to shrink into it
  grid-debug: false,
  counter-reset: true,
  phrase-break: true,
  phrase-min-run: auto, // auto -> typography.json
  phrase-min-chunk: auto, // auto -> typography.json
  phrase-keep: auto, // auto -> typography.json keep-phrases
  typography: none, // dict or path, as per thai-document-engine
  orphan-guard: true,
) = {
  // Same data-driven config the engine uses. The keep-phrase layer matters more here than in
  // body text: BudouX's Thai model segments at morpheme level, so at the default min-chunk it
  // cuts "ยั่งยืน" into ยั่ง|ยืน and "ดำเนินงาน" into ดำเนิน|งาน. In a paragraph those rarely land
  // on a line end; in a two-line display title they very often do.
  let th-config = load-typography(typography)
  let phrase-min-run = if phrase-min-run == auto {
    th-config.at("phrase-min-run", default: 8)
  } else { phrase-min-run }
  let phrase-min-chunk = if phrase-min-chunk == auto {
    th-config.at("phrase-min-chunk", default: 4)
  } else { phrase-min-chunk }
  let phrase-keep = if phrase-keep == auto {
    th-config.at("keep-phrases", default: ())
  } else { phrase-keep }

  let pal = (
    // Defaults clear WCAG AAA on the base: brand 16.88:1, signal 9.45:1.
    base: rgb("#FFFFFF"),
    brand: rgb("#0F1D33"),
    signal: rgb("#8C1220"),
  ) + palette

  // Latin-calibrated sizes from docs/cover.md multiplied through optical-scale and rounded:
  // display 36-54pt -> 55-83pt, subtitle 16-24pt -> 24-37pt, metadata 9-11pt -> 14-17pt.
  let sz = (
    brand: 15pt,
    title: 64pt,
    title-en: 26pt,
    subtitle: 24pt,
    period: 64pt,
    meta: 14pt,
  ) + sizes

  assert(
    numerals in ("arabic", "thai"),
    message: "numerals must be \"arabic\" or \"thai\" — got " + repr(numerals),
  )

  // margin: 0pt makes place() coordinates absolute page coordinates; header/footer/numbering
  // are cleared so a cover placed inside thai-document-engine does not inherit page furniture.
  // `paper` is deliberately NOT set — the one-off page inherits it from the enclosing
  // `set page`, which is what lets the same call render on a4, a5, a3 or us-letter.
  page(
    margin: 0pt,
    header: none,
    footer: none,
    numbering: none,
    fill: pal.base,
    {
      // These MUST be issued before the `context` below, not inside it. A context expression
      // resolves styles at its own position, so set rules written after it opens are invisible
      // to the measure() calls within — which silently mis-measures the title stack (wrong
      // font, and top-edge defaulting to "cap-height" instead of "ascender") and drops the
      // period zone on top of the last title line.
      set text(
        font: font,
        lang: "th",
        region: "th",
        fill: pal.brand,
        // The measured ink fit — see sarabun-metrics.
        top-edge: "ascender",
        bottom-edge: "descender",
      )
      // Thai display type is never justified (docs/cover.md, Multi-Line Step 3): with no
      // native word spaces, stretching a line opens ragged gaps between phrases instead.
      set par(justify: false, leading: thai-leading(k-body))

      // layout(), not page.width/page.height: on a `flipped` page those two still report the
      // unflipped 210x297, so a landscape cover would be laid out to portrait dimensions and
      // run off the sheet. With margin: 0pt the layout container is exactly the page box.
      layout(size => {
        let (w, h) = (size.width, size.height)
        // Scale against A4 on whichever axis binds first. For the A series this is exact either
        // way (aspect is preserved: A5 -> 0.707, A3 -> 1.414), and it is the only form that
        // survives a non-ISO aspect ratio. Width alone would set landscape A4 at 1.414x on a
        // 210mm-tall page; the geometric mean is no better there, because flipping a sheet
        // leaves its area — and therefore sqrt(area) — completely unchanged. Taking the minimum
        // costs about 4% on us-letter (0.939 vs 0.983) and cannot overflow on any paper.
        let s = calc.min(w / 210mm, h / 297mm)
        let m = cover-margins(w, h, canon)
        let text-w = w - m.left - m.right
        let g = if gutter == auto { 4mm * s } else { gutter }
        let col-w = (text-w - (columns - 1) * g) / columns
        let min-hero = if min-hero == auto { 22mm * s } else { min-hero }

        // Phrase-safe Thai breaking, reusing the BudouX plugin wrappers above. This is
        // docs/cover.md's four-step multi-line recipe: thai-chunks() is the morphological
        // parse (Step 1), box() per phrase is the break-control marker (Step 2, and the
        // equivalent of word-break: keep-all in Step 3), and merging the final two phrases is
        // the orphan guard.
        let phrased(body) = {
          show regex(if phrase-break {
            "\\p{sc=Thai}{" + str(phrase-min-run) + ",}"
          } else { thai-never }): it => {
            let phrases = thai-merge-keeps(
              thai-chunks(it.text, phrase-min-chunk),
              phrase-keep,
            )
            if phrases.len() <= 1 {
              it
            } else if orphan-guard and phrases.len() >= 3 {
              let head = phrases.slice(0, -2).map(box)
              (head + (box(phrases.at(-2) + phrases.at(-1)),)).join()
            } else {
              phrases.map(box).join()
            }
          }
          body
        }

        let line-at(y, stroke-w, colour) = place(
          top + left,
          dx: m.left,
          dy: y,
          line(length: text-w, stroke: stroke-w + colour),
        )

        // Vertical rhythm between zones, scaled with the paper.
        let gap = 5mm * s

        // --- Zone 1: brand lockup --------------------------------------------------------
        let brand-block = if brand == none { none } else {
          block(width: text-w, {
            set text(size: sz.brand * s, weight: "bold", tracking: 0.1em)
            phrased(brand)
          })
        }
        let brand-h = if brand-block == none { 0pt } else {
          measure(block(width: text-w, brand-block)).height
        }

        // --- Zone 5: regulatory metadata, sitting on the bottom margin line --------------
        let meta-block = if meta.len() == 0 { none } else {
          block(width: text-w, {
            set text(size: sz.meta * s, fill: pal.brand.lighten(20%))
            grid(
              columns: (1fr,) * meta.len(),
              column-gutter: g,
              align: left,
              ..meta.map(item => phrased(item)),
            )
          })
        }
        let meta-h = if meta-block == none { 0pt } else {
          measure(block(width: text-w, meta-block)).height
        }
        let meta-y = h - m.bottom - meta-h

        // --- Zone 3: temporal periodisation ---------------------------------------------
        // Thai digits draw ~5% shorter than Latin ones in this font (๒๕๖๘ tops out at 0.460em
        // vs 0.484em for 2568), so they get a small compensating bump.
        let period-block = if period == none { none } else {
          let body = if numerals == "thai" and type(period) in (int, str) {
            thai-numerals(period)
          } else { period }
          block(width: text-w, {
            set text(
              size: sz.period * s * (if numerals == "thai" { 1.06 } else { 1.0 }),
              weight: "bold",
              fill: pal.signal,
              tracking: tracking,
            )
            body
          })
        }
        let period-h = if period-block == none { 0pt } else {
          measure(block(width: text-w, period-block)).height
        }

        // --- Zone 2: classification title, optically centred ------------------------------
        // Built at a shrink factor so the display size can be fitted to the space actually
        // available. All three lines shrink together, preserving the size hierarchy.
        let make-title(f) = {
          if title != none {
            block(width: text-w, {
              set par(leading: thai-leading(k-display))
              set text(size: sz.title * s * f, weight: "bold", tracking: tracking)
              phrased(title)
            })
          }
          if title-en != none {
            block(width: text-w, above: 0.55em, {
              set text(size: sz.title-en * s * f, lang: "en", tracking: 0em)
              title-en
            })
          }
          if subtitle != none {
            block(width: text-w, above: 0.9em, {
              set text(size: sz.subtitle * s * f, fill: pal.brand.lighten(25%))
              phrased(subtitle)
            })
          }
        }

        // The title is centred on the optical anchor, so it grows symmetrically about it and
        // eats twice the distance to whichever neighbour it reaches first: the brand lockup
        // above, or the period + hero + metadata below. A long Thai title at the default 64pt
        // runs to three or four lines and would otherwise crush the hero band out of existence.
        // calc.max keeps the budget positive on very short or landscape pages, where the zones
        // below the anchor can already consume everything. A non-positive budget would otherwise
        // skip the fit loop entirely and let the title overrun the page — the opposite of what
        // a cramped page needs.
        let title-budget = calc.max(
          2
            * calc.min(
              // 3.5 gaps, not 2: the band below the title loses one gap before the period,
              // one after it, and the 1.5 that hero-bottom holds back off the metadata rule.
              // Counting only the first two silently ate into min-hero.
              meta-y - optical * h - period-h - 3.5 * gap - min-hero,
              optical * h - m.top - brand-h - gap,
            ),
          12mm * s,
        )
        let fit-factor = 1.0
        let title-stack = make-title(fit-factor)
        let title-h = measure(block(width: text-w, title-stack)).height
        if fit {
          // Step down until it fits. Bounded: 0.04 per step from 1.0 to the 0.45 floor.
          while title-h > title-budget and fit-factor > 0.45 {
            fit-factor = fit-factor - 0.04
            title-stack = make-title(fit-factor)
            title-h = measure(block(width: text-w, title-stack)).height
          }
        }
        let title-y = optical * h - title-h / 2
        let period-y = title-y + title-h + gap

        if brand-block != none {
          place(top + left, dx: m.left, dy: m.top, brand-block)
        }

        place(top + left, dx: m.left, dy: title-y, block(width: text-w, title-stack))
        if period-block != none {
          place(top + left, dx: m.left, dy: period-y, block(width: text-w, period-block))
        }

        // --- Zone 4: hero abstraction ----------------------------------------------------
        let hero-top = period-y + period-h + gap
        let hero-bottom = meta-y - 1.5 * gap
        let hero-h = hero-bottom - hero-top
        if hero != none and hero-h > 0.5 * min-hero {
          place(top + left, dx: m.left, dy: hero-top, block(width: text-w, height: hero-h, {
            if hero == auto {
              // The Van de Graaf construction lines that generated the page, drawn as
              // near-invisible hairlines, plus a column-aligned bar field reading as a data
              // abstraction. Both land on the same 12-column module as the type above.
              let faint = pal.brand.transparentize(90%)
              place(top + left, line(
                start: (0pt, 0pt),
                end: (text-w, hero-h),
                stroke: 0.3pt + faint,
              ))
              place(top + left, line(
                start: (text-w, 0pt),
                end: (0pt, hero-h),
                stroke: 0.3pt + faint,
              ))
              place(top + left, line(
                start: (0pt, 0pt),
                end: (text-w / 2, hero-h),
                stroke: 0.3pt + faint,
              ))
              place(top + left, line(
                start: (text-w, 0pt),
                end: (text-w / 2, hero-h),
                stroke: 0.3pt + faint,
              ))
              for i in range(columns) {
                let bar-h = cover-hero-heights.at(calc.rem(i, cover-hero-heights.len())) * hero-h
                let fill-colour = if calc.rem(i, 6) == 5 {
                  pal.signal
                } else {
                  pal.brand.transparentize(45% + calc.rem(i * 13, 40) * 1%)
                }
                place(
                  top + left,
                  dx: i * (col-w + g),
                  dy: hero-h - bar-h,
                  rect(width: col-w, height: bar-h, fill: fill-colour, stroke: none),
                )
              }
            } else {
              hero
            }
          }))
        }

        if meta-block != none {
          line-at(meta-y - 0.7em.to-absolute() * s, 0.5pt, pal.brand.transparentize(65%))
          place(top + left, dx: m.left, dy: meta-y, block(width: text-w, meta-block))
        }

        // --- Grid overlay ------------------------------------------------------------------
        if grid-debug {
          let dbg = rgb("#E5006D")
          place(top + left, dx: m.left, dy: m.top, rect(
            width: text-w,
            height: h - m.top - m.bottom,
            stroke: 0.4pt + dbg.transparentize(40%),
          ))
          for i in range(columns) {
            place(top + left, dx: m.left + i * (col-w + g), dy: m.top, rect(
              width: col-w,
              height: h - m.top - m.bottom,
              fill: dbg.transparentize(92%),
              stroke: none,
            ))
          }
          place(top + left, line(start: (0pt, 0pt), end: (w, h), stroke: 0.3pt + dbg))
          place(top + left, line(start: (w, 0pt), end: (0pt, h), stroke: 0.3pt + dbg))
          line-at(optical * h, 0.6pt, dbg)
          place(top + left, dx: m.left, dy: title-y, rect(
            width: text-w,
            height: title-h,
            stroke: 0.4pt + rgb("#00A0B0"),
          ))
          place(top + left, dx: m.left, dy: h - 14pt, text(
            size: 7pt,
            fill: dbg,
            font: "DejaVu Sans Mono",
          )[#canon · s=#calc.round(s, digits: 3) · fit=#calc.round(fit-factor, digits: 2) · col=#col-w.to-absolute() · gut=#g · hero=#calc.round(hero-h / 1mm, digits: 1)mm])
        }
      })
    },
  )

  if counter-reset { counter(page).update(1) }
}

// ===== Helper Functions =====

// thai-outline: Automated Table of Contents
#let thai-outline(
  title: "สารบัญ",
  depth: none,
) = {
  block(above: 1.2em, below: 0.8em)[
    #set align(center)
    #set text(font: "TH Sarabun New", size: 18pt, weight: "bold", fill: black)
    #title
  ]

  show outline.entry: it => link(
    it.element.location(),
    box(width: 100%)[
      #set text(font: "TH Sarabun New", size: 16pt, fill: black)
      #h(it.level * 1.5em - 1.5em)
      #it.body()
      #h(0.3em)
      #box(width: 1fr, repeat[.])
      #h(0.3em)
      #it.page()
    ],
  )

  outline(
    title: none,
    depth: depth,
    indent: 0pt,
  )
}

// signature-line: Signature line block
#let signature-line(
  role: "role = ตำแหน่ง",
  name: "name = ชื่อ",
  line-width: 6cm,
  sign-space: 1.5cm,
) = {
  align(center)[
    #block(above: 1.5em, below: 1.2em, breakable: false)[
      #v(sign-space)
      #grid(
        columns: (auto, line-width, auto),
        column-gutter: 0.4em,
        row-gutter: 0.6em,
        align: (right, center + bottom, left),
        [ลงชื่อ],
        line(length: 100%, stroke: 0.5pt + black),
        if role != none [ (#role)] else [],

        [], if name != none [(#name)] else [], [],
      )
      #v(0.3em)
    ]
  ]
}
