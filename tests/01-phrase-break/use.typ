// thai-doc-engine: BudouX WASM segmenter finds phrase boundaries and
// stops the line breaker from splitting a Thai phrase across lines.
#import "../_fixtures.typ": tech-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with()

วาทกรรมบริหารปัญญาด้วยซึ่งเอสเอ็มอีพัฒนา บูรณาการล้ำสมัยพลเมืองวิสัยทัศน์ ประโยชน์มุ่งมั่นก้าวหน้าเพื่อพันธกิจ ที่ก้าวหน้าประโยชน์พลเมืองทั้งนี้มวลชน สนธิกำลังที่ถ่ายทอดพลเมืองสนธิกำลังพัฒนา กลไกที่สนทนาวิสาหกิจหลากหลายซึ่งวัยรุ่นพัฒนา ที่เทคโนโลยีเอสเอ็มอีสูงสุดด้วย ล้ำสมัยเข้าใจเอสเอ็มอีคุณธรรม ด้วยเข้าใจวิสาหกิจโลกาภิวัฒน์ ซึ่งสตาร์ทอัพเป้าหมายต้นแบบประชารัฐหลากหลาย ข้อความคุณธรรมกลไกประโยชน์วาทกรรม ของจัดการบูรณาการกลไกพยายามบูรณาการ พันธกิจข้อความถ่ายทอด

#for p in tech-paragraphs.slice(0, 4) [
  #p

]
