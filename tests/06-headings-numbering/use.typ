// thai-doc-engine: headings auto-numbered "1.1" style, bold TH Sarabun
// New, level-1 18pt / level-2 16pt (numbering-style is configurable).
#import "../_fixtures.typ": tech-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with()

= บทนำ
เนื้อหาส่วนบทนำของรายงาน

#tech-paragraphs.at(0)

== ที่มาและความสำคัญของปัญหา
เนื้อหาส่วนที่มาและความสำคัญ

#tech-paragraphs.at(1)

= วิธีการดำเนินงาน
เนื้อหาส่วนวิธีการดำเนินงาน

#tech-paragraphs.at(2)

== การเก็บรวบรวมข้อมูล
เนื้อหาส่วนการเก็บรวบรวมข้อมูล

#tech-paragraphs.at(3)

== การวิเคราะห์ข้อมูล
เนื้อหาส่วนการวิเคราะห์ข้อมูล

#tech-paragraphs.at(4)
