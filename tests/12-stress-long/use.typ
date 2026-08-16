// thai-doc-engine: same extreme-stress paragraphs, run through the
// BudouX WASM segmenter. Every phrase should stay intact even at this
// vocabulary density (out-of-dictionary compounds included).
#import "../_fixtures.typ": stress-paragraphs
#import "@local/thai-doc-engine:1.0.0": *

#show: thai-document-engine.with()

#for p in stress-paragraphs [
  #p

]
