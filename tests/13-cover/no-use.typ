// Baseline for tests/13-cover/use.typ: the same cover fields set as ordinary
// flow content with no cover(). Shows what the zone geometry, optical centring
// and phrase-safe display breaking are actually buying — in particular the
// long title here breaks mid-phrase.
#import "../_fixtures.typ": tech-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with(
  header-left: "Kasetsart University",
  header-right: "Department of Computer Engineering",
  footer-left: "โครงงานวิศวกรรมคอมพิวเตอร์",
)

#align(center)[
  #text(size: 15pt, weight: "bold")[มหาวิทยาลัยเกษตรศาสตร์]

  #text(size: 64pt, weight: "bold")[รายงานการพัฒนาอย่างยั่งยืนและผลการดำเนินงานประจำปี]

  #text(size: 26pt)[Integrated Sustainability and Performance Report]

  #text(size: 24pt)[ภาควิชาวิศวกรรมคอมพิวเตอร์ คณะวิศวกรรมศาสตร์]

  #text(size: 88pt, weight: "bold")[2568]

  #text(size: 14pt)[ปีการศึกษา 2568 · ฉบับสมบูรณ์ rev. 1.0 · KU · CPE]
]

#pagebreak()

= บทนำ

เนื้อหารายงานเริ่มต้นที่หน้าถัดจากปก พร้อมหัวกระดาษและท้ายกระดาษตามปกติ

#tech-paragraphs.at(0)

#tech-paragraphs.at(1)
