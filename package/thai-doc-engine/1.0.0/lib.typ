// lib.typ
// Advanced Thai-English Document Engine for Typst (Production-Ready)
// Powered by Knuth-Plass Optimization & Hybrid Dynamic Space Distribution
//
// Public API re-export shim. Implementation lives in src/, layered as a DAG:
//   src/config.typ  — Layer 0: plugin binding, phrase-segmenter wrappers, typography config
//   src/metrics.typ — Layer 1: pure font-metric / leading / contrast / page-geometry math
//   src/cover.typ   — Layer 2: cover() component (imports config.typ, metrics.typ)
//   src/engine.typ  — Layer 3: thai-document-engine() template + outline/signature helpers
//
// Usage: #import "@local/thai-doc-engine:1.0.0": *
//        #show: thai-document-engine.with(...)
#import "src/config.typ": *
#import "src/metrics.typ": *
#import "src/cover.typ": *
#import "src/engine.typ": *
