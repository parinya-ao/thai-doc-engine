// Assertions for the cover's numeric helpers. This is the one test in the repo
// that actually fails loudly rather than needing to be eyeballed: a broken
// assert() aborts compilation with a message.
#import "@local/thai-doc-engine:1.0.0": *

#set page(paper: "a4")
#set text(font: "TH Sarabun New", lang: "th", size: 14pt)

= cover helper assertions

// --- WCAG contrast, docs/cover.md § Color Science -------------------------------
#let aaa(fg, bg) = {
  let cr = contrast-ratio(fg, bg)
  assert(cr >= 7, message: "expected WCAG AAA (>= 7:1), got " + repr(cr) + " for " + repr(fg))
  cr
}
// Known reference values: white on black is exactly 21:1, and a colour against
// itself is exactly 1:1.
#assert(
  calc.abs(contrast-ratio(rgb("#FFFFFF"), rgb("#000000")) - 21.0) < 0.001,
  message: "white-on-black must be 21:1",
)
#assert(
  calc.abs(contrast-ratio(rgb("#8C1220"), rgb("#8C1220")) - 1.0) < 0.001,
  message: "a colour against itself must be 1:1",
)
// The palette defaults must clear AAA on the default base.
- brand #rgb("#0F1D33").to-hex() on base: #calc.round(aaa(rgb("#0F1D33"), rgb("#FFFFFF")), digits: 2) : 1
- signal #rgb("#8C1220").to-hex() on base: #calc.round(aaa(rgb("#8C1220"), rgb("#FFFFFF")), digits: 2) : 1

// --- Ninths geometry, docs/cover.md § Classical Canons ---------------------------
#let m = cover-margins(210mm, 297mm, "van-de-graaf")
#assert(calc.abs(m.left / 1mm - 210 / 9) < 0.01, message: "inner margin must be W/9")
#assert(calc.abs(m.top / 1mm - 297 / 9) < 0.01, message: "top margin must be H/9")
#assert(calc.abs(m.right / 1mm - 2 * 210 / 9) < 0.01, message: "outer margin must be 2W/9")
#assert(calc.abs(m.bottom / 1mm - 2 * 297 / 9) < 0.01, message: "bottom margin must be 2H/9")
// The 12-column grid closes exactly on A4 at a 4mm gutter: W_active = 12w + 11g.
#let text-w = 210mm - m.left - m.right
#let col-w = (text-w - 11 * 4mm) / 12
#assert(calc.abs(col-w / 1mm - 8) < 0.001, message: "A4 columns must come out at exactly 8mm")
- A4 ninths: #calc.round(m.left / 1mm, digits: 2) / #calc.round(m.top / 1mm, digits: 2) / #calc.round(m.right / 1mm, digits: 2) / #calc.round(m.bottom / 1mm, digits: 2) mm
- text block #calc.round(text-w / 1mm, digits: 1) mm wide, column #calc.round(col-w / 1mm, digits: 3) mm

// --- Thai leading ----------------------------------------------------------------
// leading is the gap *between* line boxes, so baseline-to-baseline is
// line-box + leading and must land back on k.
#for k in (1.2, 1.35, 1.5, 1.8) {
  let total = sarabun-metrics.line-box + thai-leading(k) / 1em
  assert(calc.abs(total - k) < 0.0001, message: "thai-leading(" + repr(k) + ") is off")
}
// Every k the cover uses by default must clear the measured collision point.
#let touch = sarabun-metrics.ink-top - sarabun-metrics.ink-bottom
#assert(calc.abs(touch - 1.083) < 0.001, message: "ink envelope should be 1.083em")
#for k in (1.35, 1.55) {
  assert(k > touch, message: "default k=" + repr(k) + " collides")
}
- ink envelope #calc.round(touch, digits: 3) em; clearance at k=1.35 is #calc.round(1.35 - touch, digits: 3) em, at k=1.55 is #calc.round(1.55 - touch, digits: 3) em

// --- Thai numerals ---------------------------------------------------------------
#assert(thai-numerals(2568) == "๒๕๖๘", message: "2568 must map to ๒๕๖๘")
#assert(thai-numerals("rev 1.0") == "rev ๑.๐", message: "non-digits must pass through")
- #thai-numerals(2568) / #thai-numerals("rev 1.0")

// --- Keep-phrase boundary merging -------------------------------------------------
// BudouX cuts ยั่งยืน into ยั่ง|ยืน and ดำเนินงาน into ดำเนิน|งาน at the default min-chunk.
#let sample = "รายงานการพัฒนาอย่างยั่งยืนและผลการดำเนินงานประจำปี"
#let keeps = ("อย่างยั่งยืน", "ยั่งยืน", "ผลการดำเนินงาน", "ดำเนินงาน", "การพัฒนา")
#let raw-chunks = thai-chunks(sample, 4)
#let merged = thai-merge-keeps(raw-chunks, keeps)

// Merging must never lose, reorder or duplicate a single character.
#assert(merged.join() == sample, message: "thai-merge-keeps must be lossless")
#assert(raw-chunks.join() == sample, message: "thai-chunks must be lossless")
// It can only ever remove boundaries, never add them.
#assert(
  merged.len() <= raw-chunks.len(),
  message: "merging must not introduce new boundaries",
)
// No curated word may straddle a boundary any more: every keep-phrase present in the
// source must sit wholly inside exactly one chunk.
#for w in keeps {
  if sample.contains(w) {
    assert(
      merged.any(c => c.contains(w)),
      message: "keep-phrase " + w + " is still split across chunks",
    )
  }
}
// The two the model actually broke:
#assert(merged.any(c => c.contains("ยั่งยืน")), message: "ยั่งยืน still split")
#assert(merged.any(c => c.contains("ดำเนินงาน")), message: "ดำเนินงาน still split")
// Empty keep list is the identity.
#assert(
  thai-merge-keeps(raw-chunks, ()) == raw-chunks,
  message: "an empty keep list must be a no-op",
)
- raw: #raw-chunks.join(" | ")
- merged: #merged.join(" | ")

// --- Canon validation ------------------------------------------------------------
#for c in ("van-de-graaf", "iso", "symmetric") {
  let mm-c = cover-margins(210mm, 297mm, c)
  assert(mm-c.left > 0mm and mm-c.bottom > 0mm, message: "canon " + c + " produced junk")
}

All assertions passed.
