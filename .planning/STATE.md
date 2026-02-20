# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Users can load a document and ask natural-language questions about its contents via on-device RAG
**Current focus:** Phase 2 — iOS App RAG Feature

## Current Position

Phase: 2 of 2 (iOS App RAG Feature)
Plan: 1 of TBD in current phase
Status: In progress
Last activity: 2026-02-20 — Completed Plan 01 (iOS app RAG data/logic layer: DocumentService + RAGViewModel)

Progress: [███░░░░░░░] 30%

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: 373s
- Total execution time: 1119s

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-swift-sdk-rag-component | 2 | 803s | 402s |
| 02-ios-app-rag-feature | 1 | 316s | 316s |

**Recent Trend:**
- Last 5 plans: 01-01 (203s), 01-02 (600s), 02-01 (316s)
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

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 02-01-PLAN.md (iOS app RAG data/logic layer: DocumentService + RAGViewModel)
Resume file: None
