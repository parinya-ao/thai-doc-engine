// thai-doc-engine: header-left/header-right + rule, footer-left + "Page
// X / Y" + rule, and a centered bold `topic` title block — all wired up
// via with(...) params, no manual page-furniture code needed.
#import "../_fixtures.typ": place-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with(
  topic: "รายงานฉบับสมบูรณ์",
  header-left: "Kasetsart University",
  header-right: "Department of Computer Engineering",
  footer-left: "โครงงานวิศวกรรมคอมพิวเตอร์",
)

เนื้อหารายงานเริ่มต้นที่นี่พร้อมหัวกระดาษ ท้ายกระดาษ และหน้าปกส่วนหัวเรื่องที่กำกับไว้โดยอัตโนมัติ

#place-paragraphs.at(0)

#place-paragraphs.at(1)
#pagebreak()
หน้าที่สองของเอกสารยังคงแสดงหัวกระดาษ ท้ายกระดาษ และเลขหน้าอัตโนมัติต่อเนื่อง

#place-paragraphs.at(2)

#place-paragraphs.at(3)
