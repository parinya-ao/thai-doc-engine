// Raw Typst: no header, no footer, no title block — just body text.
#import "../_fixtures.typ": place-paragraphs
#set page(paper: "a4", margin: 2.5cm)
#set text(font: "TH Sarabun New", size: 16pt, lang: "th", region: "th")
#set par(justify: true)

เนื้อหารายงานเริ่มต้นที่นี่โดยไม่มีหัวกระดาษ ท้ายกระดาษ หรือหน้าปกส่วนหัวเรื่องใด ๆ กำกับไว้

#place-paragraphs.at(0)

#place-paragraphs.at(1)
#pagebreak()
หน้าที่สองของเอกสารก็ยังคงไม่มีส่วนหัวหรือท้ายกระดาษเช่นเดียวกัน

#place-paragraphs.at(2)

#place-paragraphs.at(3)
