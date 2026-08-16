// thai-doc-engine: runs of >=4 Latin characters are switched to lang
// "en" via a show-regex rule, so English words/URLs hyphenate correctly
// while surrounding Thai text (which has no hyphenation) is untouched.
#import "../_fixtures.typ": tech-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with()

โครงการนี้ใช้สถาปัตยกรรมแบบ Microservices และปรับใช้ระบบด้วย Kubernetes Container Orchestration เพื่อรองรับการขยายตัวของผู้ใช้งานจำนวนมาก โดยทีมพัฒนาได้อ้างอิงเอกสารจาก https://kubernetes.io/docs/concepts/workloads/controllers/deployment เพื่อออกแบบกลยุทธ์การปรับใช้แบบ Rolling Update อย่างเหมาะสมกับสภาพแวดล้อมการทำงานจริง

ทีมปฏิบัติการยังได้นำกระบวนการ Continuous Integration/Continuous Deployment มาใช้ควบคู่กับการจัดการสิทธิ์ผ่าน Authentication และ Infrastructure-as-a-Code โดยเอกสารประกอบเพิ่มเติมอ้างอิงจาก https://docs.github.com/en/actions/deployment/about-deployments/deploying-with-github-actions ซึ่งครอบคลุมทั้งขั้นตอน Rolling Update และการตรวจสอบสิทธิ์แบบ Microservices Architecture อย่างละเอียด

#tech-paragraphs.at(2)
