// phrase-method: "wj" — U+2060 word joiner at every mid-phrase break
// point (weld), strongest anti-break, no box().
#import "../_fixtures.typ": tech-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with(phrase-method: "wj")

โลกาภิวัฒน์อาเซียนวิเคราะห์จริยธรรมลงทุน สร้างสรรค์สูงสุดวิสัยทัศน์จริยธรรม สุขภาวะสำคัญระดับสากลที่ถ่ายทอดมุ่งมั่น ประชารัฐคัดเลือกพัฒนาสนธิกำลังถ่ายทอดพลเมืองเพื่อวาทกรรม บูรณาการซึ่งอาเซียนมวลชนทั้งนี้วิสัยทัศน์ วาทกรรมและจิตวิญญาณกลไกในสนธิกำลัง

#for p in tech-paragraphs.slice(4, 7) [
  #p

]
