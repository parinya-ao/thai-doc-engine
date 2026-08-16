// phrase-method: "box" (default) — each phrase wrapped in box(), safest
// for PDF text extraction/copy-paste.
#import "../_fixtures.typ": tech-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with(phrase-method: "box")

โลกาภิวัฒน์อาเซียนวิเคราะห์จริยธรรมลงทุน สร้างสรรค์สูงสุดวิสัยทัศน์จริยธรรม สุขภาวะสำคัญระดับสากลที่ถ่ายทอดมุ่งมั่น ประชารัฐคัดเลือกพัฒนาสนธิกำลังถ่ายทอดพลเมืองเพื่อวาทกรรม บูรณาการซึ่งอาเซียนมวลชนทั้งนี้วิสัยทัศน์ วาทกรรมและจิตวิญญาณกลไกในสนธิกำลัง

#for p in tech-paragraphs.slice(4, 7) [
  #p

]
