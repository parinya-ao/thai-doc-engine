// thai-doc-engine: Thai captions ("ภาพที่"/"ตารางที่"), numbering "1",
// top caption placement + 14pt for tables, non-justified table-cell text.
#import "../_fixtures.typ": tech-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with()

#tech-paragraphs.at(5)

#figure(
  rect(width: 60%, height: 3cm, stroke: 0.5pt),
  caption: [แผนภาพสถาปัตยกรรมระบบ],
)

#tech-paragraphs.at(6)

#figure(
  table(
    columns: 3,
    [หัวข้อ], [ค่า], [หน่วย],
    [ความเร็ว], [128], [KB/s],
    [ความถี่], [920], [MHz],
  ),
  caption: [ผลการทดสอบระบบ],
)

#tech-paragraphs.at(7)
