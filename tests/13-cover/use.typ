// thai-doc-engine: the `cover()` page — Van de Graaf ninths geometry, five
// zones, optically-centred title, generated hero geometry, and phrase-safe
// Thai display type. Body content follows on a fresh page with the normal
// header/footer furniture intact.
#import "../_fixtures.typ": tech-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with(
  header-left: "Kasetsart University",
  header-right: "Department of Computer Engineering",
  footer-left: "โครงงานวิศวกรรมคอมพิวเตอร์",
)

#cover(
  brand: [มหาวิทยาลัยเกษตรศาสตร์],
  title: [รายงานการพัฒนาอย่างยั่งยืนและผลการดำเนินงานประจำปี],
  title-en: [Integrated Sustainability and Performance Report],
  subtitle: [ภาควิชาวิศวกรรมคอมพิวเตอร์ คณะวิศวกรรมศาสตร์],
  period: "2568",
  meta: (
    [ปีการศึกษา 2568],
    [ฉบับสมบูรณ์ · rev. 1.0],
    [KU · CPE],
  ),
)

= บทนำ

เนื้อหารายงานเริ่มต้นที่หน้าถัดจากปก พร้อมหัวกระดาษและท้ายกระดาษตามปกติ

#tech-paragraphs.at(0)

#tech-paragraphs.at(1)
