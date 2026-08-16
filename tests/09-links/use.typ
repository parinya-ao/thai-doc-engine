// thai-doc-engine: links rendered black + underlined, matching academic
// print convention instead of Typst's default blue.
#import "../_fixtures.typ": tech-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with()

#tech-paragraphs.at(8)

อ่านเอกสารเพิ่มเติมได้ที่ #link("https://typst.app")[typst.app] และ #link("https://kasetsart.ac.th")[เว็บไซต์มหาวิทยาลัย] นอกจากนี้ยังสามารถศึกษาเพิ่มเติมได้จาก #link("https://kubernetes.io")[เอกสารประกอบ Kubernetes] และ #link("https://github.com")[คลังซอร์สโค้ดบน GitHub]

#tech-paragraphs.at(9)
