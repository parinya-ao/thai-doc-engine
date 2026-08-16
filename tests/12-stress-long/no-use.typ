// Raw Typst: dedicated extreme-stress test. Dense, unbroken compound
// Thai text (technical jargon + celebrity/brand/place-name compounds) —
// no natural word spaces at all, worst case for a naive line breaker.
#import "../_fixtures.typ": stress-paragraphs
#set page(paper: "a4", margin: 2.5cm)
#set text(font: "TH Sarabun New", size: 16pt, lang: "th", region: "th")
#set par(justify: true)

#for p in stress-paragraphs [
  #p

]
