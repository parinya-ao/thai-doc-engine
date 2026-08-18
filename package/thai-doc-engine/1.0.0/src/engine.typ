// engine.typ — Layer 3: main document template + outline/signature helpers
//
// Core standard template for all documents in docs/ (week-2 to week-6)
// Usage: #import "@local/thai-doc-engine:1.0.0": *
//        #show: thai-document-engine.with(...)

#import "config.typ": load-typography, thai-alternation, thai-wj, thai-glue, thai-weld, thai-chunks, thai-never

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
