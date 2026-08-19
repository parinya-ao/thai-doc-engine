// The same cover across paper sizes. Margins come from the ninths canon, which
// is proportional, and type is scaled by the geometric mean of the page against
// A4 — so a4/a5/a3 should be the identical design at 1.0 / 0.707 / 1.414, and
// us-letter (0.983) should not look cramped despite being wider than A4.
//
// The last page is deliberately landscape: width-only scaling would set type at
// 1.33x there and overflow the height.
#import "@local/thai-doc-engine:1.0.0": *

#set text(font: "TH Sarabun New", lang: "th")

#let sheet(..args) = cover(
  counter-reset: false,
  brand: [มหาวิทยาลัยเกษตรศาสตร์],
  title: [รายงานการพัฒนาอย่างยั่งยืนและผลการดำเนินงานประจำปี],
  title-en: [Integrated Sustainability and Performance Report],
  subtitle: [ภาควิชาวิศวกรรมคอมพิวเตอร์ คณะวิศวกรรมศาสตร์],
  period: "2568",
  meta: ([ปีการศึกษา 2568], [rev. 1.0], [KU · CPE]),
  ..args,
)

#[
  #set page(paper: "a4")
  #sheet()
]
#[
  #set page(paper: "a5")
  #sheet()
]
#[
  #set page(paper: "a3")
  #sheet()
]
#[
  #set page(paper: "us-letter")
  #sheet()
]
#[
  #set page(paper: "a4", flipped: true)
  #sheet()
]
