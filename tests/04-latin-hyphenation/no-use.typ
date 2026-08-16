// Raw Typst: text stays lang "th" throughout, so hyphenation (needed by
// the long English word) never kicks in — the word either overflows the
// line or forces a very ragged justified line.
#import "../_fixtures.typ": tech-paragraphs
#set page(paper: "a4", margin: 2.5cm)
#set text(font: "TH Sarabun New", size: 16pt, lang: "th", region: "th", hyphenate: true)
#set par(justify: true)

โครงการนี้ใช้สถาปัตยกรรมแบบ Microservices และปรับใช้ระบบด้วย Kubernetes Container Orchestration เพื่อรองรับการขยายตัวของผู้ใช้งานจำนวนมาก โดยทีมพัฒนาได้อ้างอิงเอกสารจาก https://kubernetes.io/docs/concepts/workloads/controllers/deployment เพื่อออกแบบกลยุทธ์การปรับใช้แบบ Rolling Update อย่างเหมาะสมกับสภาพแวดล้อมการทำงานจริง

ทีมปฏิบัติการยังได้นำกระบวนการ Continuous Integration/Continuous Deployment มาใช้ควบคู่กับการจัดการสิทธิ์ผ่าน Authentication และ Infrastructure-as-a-Code โดยเอกสารประกอบเพิ่มเติมอ้างอิงจาก https://docs.github.com/en/actions/deployment/about-deployments/deploying-with-github-actions ซึ่งครอบคลุมทั้งขั้นตอน Rolling Update และการตรวจสอบสิทธิ์แบบ Microservices Architecture อย่างละเอียด

#tech-paragraphs.at(2)
