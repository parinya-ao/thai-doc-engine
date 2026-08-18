// metrics.typ — Layer 1 (pure): font metrics, leading, numerals, contrast, page-geometry math
//
#import "config.typ": thai-alternation
//
// Implements the numeric backbone of the "Corporate Clean" cover system described in
// docs/cover.md: Van de Graaf ninths page geometry, WCAG-checkable contrast, and phrase-safe
// Thai display typesetting metrics.
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
