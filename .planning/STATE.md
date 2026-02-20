# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Users can load a document and ask natural-language questions about its contents via on-device RAG
**Current focus:** Phase 1 — Swift SDK RAG Component

## Current Position

Phase: 1 of 2 (Swift SDK RAG Component)
Plan: 2 of TBD in current phase
Status: In progress
Last activity: 2026-02-20 — Completed Plan 02 (RAG public API and Swift types)

Progress: [██░░░░░░░░] 20%

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: 402s
- Total execution time: 803s

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-swift-sdk-rag-component | 2 | 803s | 402s |

**Recent Trend:**
- Last 5 plans: 01-01 (203s), 01-02 (600s)
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

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 01-02-PLAN.md (RAG public API and Swift types)
Resume file: None
