// Raw Typst: default figure captions ("Figure 1"/"Table 1", English,
// bottom placement for figures) and default table styling.
#import "../_fixtures.typ": tech-paragraphs
#set page(paper: "a4", margin: 2.5cm)
#set text(font: "TH Sarabun New", size: 16pt, lang: "th", region: "th")
#set par(justify: true)

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
