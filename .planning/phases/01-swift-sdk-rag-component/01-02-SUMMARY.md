---
phase: 01-swift-sdk-rag-component
plan: 02
subsystem: swift-sdk
tags: [rag, swift, public-api, events, types]
dependency_graph:
  requires: [rag-c-headers, cpp-bridge-rag-actor]
  provides: [rag-public-api, rag-swift-types, rag-events]
  affects: [RunAnywhere, CppBridge.RAG, EventBus]
tech_stack:
  added: []
  patterns: [extension-pattern, event-publishing, actor-safe-swift-types]
key_files:
  created:
    - sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/RAGTypes.swift
    - sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/RunAnywhere+RAG.swift
    - sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/RAGEvents.swift
  modified:
    - sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+RAG.swift
decisions:
  - Swift-typed actor overloads (createPipeline(swiftConfig:), query(swiftOptions:)) added to CppBridge.RAG to contain C string pointer lifetimes within synchronous actor methods — eliminates the async/sync closure mismatch
  - Async withCConfig/withCQuery overloads omitted from RAGTypes as they cannot be implemented safely with Swift's withCString (synchronous only); actor overloads are the correct pattern
  - RAGEvent.destination defaults to publicOnly for most events; error events use .all to reach telemetry
metrics:
  duration: 600s
  completed: 2026-02-20
  tasks_completed: 2
  files_changed: 4
---

# Phase 1 Plan 2: RAG Public API and Swift Types Summary

**One-liner:** Public RAG API on RunAnywhere with Swift-typed configuration, query, result, and event types backed by synchronous CppBridge.RAG actor overloads that safely contain C string pointer lifetimes.

## What Was Built

This plan creates the developer-facing RAG API for the Swift SDK:

1. **RAGTypes.swift** — Four `Sendable` structs wrapping C RAG types:
   - `RAGConfiguration` wraps `rac_rag_config_t` with a `withCConfig` sync bridge
   - `RAGQueryOptions` wraps `rac_rag_query_t` with a `withCQuery` sync bridge
   - `RAGSearchResult` wraps `rac_search_result_t` with `init(from:)`
   - `RAGResult` wraps `rac_rag_result_t` with `init(from:)`

2. **RAGEvents.swift** — `RAGEvent` conforming to `SDKEvent` with factory methods for all lifecycle events: `ingestionStarted`, `ingestionComplete`, `queryStarted`, `queryComplete`, `pipelineCreated`, `pipelineDestroyed`, `error`. All events use `category: .rag` for filtered subscriptions.

3. **RunAnywhere+RAG.swift** — Public extension on `RunAnywhere` with six static methods:
   - `ragCreatePipeline(config:)` — creates the C++ pipeline via actor
   - `ragDestroyPipeline()` — tears down pipeline
   - `ragIngest(text:metadataJSON:)` — ingests text with before/after events
   - `ragClearDocuments()` — clears the vector index
   - `ragDocumentCount` — async computed property
   - `ragQuery(question:options:)` — full RAG query returning `RAGResult`

4. **CppBridge+RAG.swift (modified)** — Added two Swift-typed overloads:
   - `createPipeline(swiftConfig: RAGConfiguration)` — builds C struct inside the synchronous actor method
   - `query(swiftOptions: RAGQueryOptions)` — builds query, calls C, converts result, frees memory

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed actor-isolated call in synchronous nonisolated context**
- **Found during:** Task 2 first build
- **Issue:** Plan called `try await CppBridge.RAG.shared.createPipeline(config:)` inside `config.withCConfig { ... }` — but `withCConfig` accepts a synchronous closure and `String.withCString` has no async overload in Swift stdlib
- **Fix:** Added `createPipeline(swiftConfig:)` and `query(swiftOptions:)` overloads on `CppBridge.RAG` actor so the C struct construction and actor call happen together inside the synchronous actor method; `RunAnywhere+RAG.swift` calls these directly with `await`
- **Files modified:** `CppBridge+RAG.swift`, `RunAnywhere+RAG.swift`
- **Commit:** ff0be21f

## Self-Check: PASSED

- RAGTypes.swift: FOUND
- RAGEvents.swift: FOUND
- RunAnywhere+RAG.swift: FOUND
- CppBridge+RAG.swift: modified with Swift-type overloads CONFIRMED
- swift build: Build complete (no errors)
- Task 1 commit: 635f42c7
- Task 2 commit: ff0be21f
- ragCreatePipeline: public API CONFIRMED
- ragDestroyPipeline: public API CONFIRMED
- ragIngest: public API CONFIRMED
- ragClearDocuments: public API CONFIRMED
- ragDocumentCount: public API CONFIRMED
- ragQuery: public API CONFIRMED
- RAGEvent.category == .rag: CONFIRMED
- EventBus.shared.publish calls: CONFIRMED
