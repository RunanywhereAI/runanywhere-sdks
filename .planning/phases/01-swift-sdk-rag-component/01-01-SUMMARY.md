---
phase: 01-swift-sdk-rag-component
plan: 01
subsystem: swift-sdk
tags: [rag, swift, c-bridge, headers, actors]
dependency_graph:
  requires: []
  provides: [rag-c-headers, cpp-bridge-rag-actor, rag-error-infrastructure]
  affects: [CRACommons, SDKError, SDKComponent, EventCategory, ErrorCategory]
tech_stack:
  added: []
  patterns: [actor-bridge, c-interop, extension-actor]
key_files:
  created:
    - sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/rac_rag_pipeline.h
    - sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/rac_rag.h
    - sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+RAG.swift
  modified:
    - sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/CRACommons.h
    - sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Errors/ErrorCategory.swift
    - sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Errors/SDKError.swift
    - sdk/runanywhere-swift/Sources/RunAnywhere/Core/Types/ComponentTypes.swift
    - sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Events/SDKEvent.swift
    - sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Services.swift
    - sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/RunAnywhere+Frameworks.swift
decisions:
  - RAG C headers copied with flattened include paths (rac/core/rac_types.h -> rac_types.h) to match SPM CRACommons local include pattern
  - CppBridge.RAG actor uses OpaquePointer for rac_rag_pipeline_t* (opaque C struct pointer)
  - SDKComponent.rag maps to RAC_CAPABILITY_TEXT_GENERATION for C++ routing (RAG has no dedicated capability enum value)
  - RAG uses language ModelCategory for framework discovery queries
metrics:
  duration: 203s
  completed: 2026-02-20
  tasks_completed: 2
  files_changed: 10
---

# Phase 1 Plan 1: RAG C API Bridge and Infrastructure Summary

**One-liner:** RAG C headers exposed to Swift via CRACommons umbrella and CppBridge.RAG actor provides thread-safe pipeline lifecycle management using Swift 6 actor concurrency.

## What Was Built

This plan establishes the foundation for Swift SDK RAG support:

1. **RAG C headers in CRACommons** — Copied `rac_rag_pipeline.h` and `rac_rag.h` from `sdk/runanywhere-commons/include/rac/` into `sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/`, flattening `#include` paths from `"rac/core/rac_types.h"` to `"rac_types.h"` for SPM compatibility.

2. **CRACommons umbrella updated** — Added `#include "rac_rag_pipeline.h"` and `#include "rac_rag.h"` to `CRACommons.h` after the Voice Agent section, making all RAG C types and functions importable from Swift via `import CRACommons`.

3. **Error/event/component infrastructure** — Added `.rag` case to `ErrorCategory`, `SDKComponent`, `EventCategory`, and `SDKError.rag()` factory method, following the established patterns for all other SDK components.

4. **CppBridge.RAG actor** — Created `CppBridge+RAG.swift` as an actor nested in a `CppBridge` extension, following the `CppBridge+STT.swift` pattern. Provides: `createPipeline(config:)`, `destroy()`, `addDocument(text:metadataJSON:)`, `clearDocuments()`, `documentCount`, and `query(_:)`. All methods delegate to the C API. Actor provides Swift 6 concurrency safety.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed exhaustive switch in RunAnywhere+Frameworks.swift**
- **Found during:** Task 1 first build
- **Issue:** Adding `.rag` to `SDKComponent` caused `getFrameworks(for:)` switch to be non-exhaustive
- **Fix:** Added `case .rag: relevantCategories = [.language]`
- **Files modified:** `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/RunAnywhere+Frameworks.swift`
- **Commit:** 0e98f9a0

**2. [Rule 1 - Bug] Fixed exhaustive switch in CppBridge+Services.swift**
- **Found during:** Task 1 first build
- **Issue:** `SDKComponent.toC()` switch was non-exhaustive after adding `.rag`
- **Fix:** Added `case .rag: return RAC_CAPABILITY_TEXT_GENERATION` (RAG has no dedicated capability enum in C++)
- **Files modified:** `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Services.swift`
- **Commit:** 0e98f9a0

## Self-Check: PASSED

- rac_rag_pipeline.h: FOUND
- rac_rag.h: FOUND
- CppBridge+RAG.swift: FOUND
- CRACommons.h includes rac_rag_pipeline.h: CONFIRMED
- ErrorCategory.rag: CONFIRMED
- SDKComponent.rag: CONFIRMED
- EventCategory.rag: CONFIRMED
- SDKError.rag() factory: CONFIRMED
- CppBridge.RAG actor: CONFIRMED
- swift build: Build complete (no errors)
- Task 1 commit: 0e98f9a0
- Task 2 commit: 1a2f4f8b
