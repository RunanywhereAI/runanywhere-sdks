# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Users can load a document and ask natural-language questions about its contents via on-device RAG
**Current focus:** Phase 2 — iOS App RAG Feature

## Current Position

Phase: 2 of 2 (iOS App RAG Feature)
Plan: 2 of 2 in current phase
Status: Complete
Last activity: 2026-02-20 — Completed Plan 02 (iOS app RAG UI: DocumentRAGView + ContentView navigation wiring)

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: 380s
- Total execution time: 1514s

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-swift-sdk-rag-component | 2 | 803s | 402s |
| 02-ios-app-rag-feature | 2 | 711s | 356s |

**Recent Trend:**
- Last 5 plans: 01-01 (203s), 01-02 (600s), 02-01 (316s), 02-02 (395s)
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Thin wrapper over C++ — C++ already has full RAG pipeline; avoid duplicating logic
- PDF/JSON text extraction in Swift — C++ only takes strings; parsing at app layer keeps C++ layer clean
- Persistent document session — User doesn't want to re-upload per query
- RAG C headers use flattened include paths for SPM CRACommons compatibility
- CppBridge.RAG actor uses OpaquePointer for rac_rag_pipeline_t* (opaque C struct)
- SDKComponent.rag maps to RAC_CAPABILITY_TEXT_GENERATION (no dedicated RAG capability in C++ enum)
- Swift-typed actor overloads on CppBridge.RAG contain C string pointer lifetimes in synchronous actor methods
- Async withCConfig/withCQuery omitted; String.withCString is synchronous-only in Swift stdlib
- DocumentService as static struct — no state or DI needed for a pure extraction utility
- loadDocument accepts RAGConfiguration parameter — view provides model paths at runtime
- MessageRole enum scoped to RAG feature file — avoids polluting shared AppTypes
- [Phase 02-ios-app-rag-feature]: ragConfig uses empty placeholder paths — real model paths wired from model manager in future iteration
- [Phase 02-ios-app-rag-feature]: No clearDocument() on onDisappear — document state preserved across navigation

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 02-02-PLAN.md (iOS app RAG UI: DocumentRAGView + ContentView wiring)
Resume file: None
