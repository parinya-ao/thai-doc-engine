// grid-debug overlay for the cover geometry. Magenta = ninths text block, the
// 12 columns, the page diagonals and the optical-centre rule; cyan = the
// measured title stack, whose centre must sit on the optical rule.
//
// One page per canon so the three margin systems can be compared directly.
#import "@local/thai-doc-engine:1.0.0": *

#set page(paper: "a4")
#set text(font: "TH Sarabun New", lang: "th")

#let probe(canon) = cover(
  canon: canon,
  grid-debug: true,
  counter-reset: false,
  brand: [มหาวิทยาลัยเกษตรศาสตร์],
  title: [รายงานการพัฒนาอย่างยั่งยืนและผลการดำเนินงานประจำปี],
  title-en: [Integrated Sustainability and Performance Report],
  period: "2568",
  meta: ([ปีการศึกษา 2568], [rev. 1.0], [KU · CPE]),
)

#probe("van-de-graaf")
#probe("iso")
#probe("symmetric")

// Golden-ratio optical anchor (0.382H) instead of the 0.45H default.
#cover(
  optical: 0.382,
  grid-debug: true,
  counter-reset: false,
  brand: [มหาวิทยาลัยเกษตรศาสตร์],
  title: [รายงานการพัฒนาอย่างยั่งยืนและผลการดำเนินงานประจำปี],
  title-en: [Integrated Sustainability and Performance Report],
  period: "2568",
  meta: ([ปีการศึกษา 2568], [rev. 1.0], [KU · CPE]),
)
