// Raw Typst, no thai-doc-engine. Thai text has no explicit word spaces,
// so Typst's line breaker can split anywhere — including mid-phrase.
#import "../_fixtures.typ": tech-paragraphs
#set page(paper: "a4", margin: 2.5cm)
#set text(font: "TH Sarabun New", size: 16pt, lang: "th", region: "th")
#set par(justify: true)

วาทกรรมบริหารปัญญาด้วยซึ่งเอสเอ็มอีพัฒนา บูรณาการล้ำสมัยพลเมืองวิสัยทัศน์ ประโยชน์มุ่งมั่นก้าวหน้าเพื่อพันธกิจ ที่ก้าวหน้าประโยชน์พลเมืองทั้งนี้มวลชน สนธิกำลังที่ถ่ายทอดพลเมืองสนธิกำลังพัฒนา กลไกที่สนทนาวิสาหกิจหลากหลายซึ่งวัยรุ่นพัฒนา ที่เทคโนโลยีเอสเอ็มอีสูงสุดด้วย ล้ำสมัยเข้าใจเอสเอ็มอีคุณธรรม ด้วยเข้าใจวิสาหกิจโลกาภิวัฒน์ ซึ่งสตาร์ทอัพเป้าหมายต้นแบบประชารัฐหลากหลาย ข้อความคุณธรรมกลไกประโยชน์วาทกรรม ของจัดการบูรณาการกลไกพยายามบูรณาการ พันธกิจข้อความถ่ายทอด

#for p in tech-paragraphs.slice(0, 4) [
  #p

]
