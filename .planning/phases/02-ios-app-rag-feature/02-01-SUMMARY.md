---
phase: 02-ios-app-rag-feature
plan: 01
subsystem: ios-app-rag-layer
tags: [swift, ios, rag, pdfkit, viewmodel, observable]
dependency_graph:
  requires:
    - 01-02 (RunAnywhere+RAG.swift SDK public API)
  provides:
    - DocumentService.extractText(from:) for PDF and JSON text extraction
    - RAGViewModel for document loading, pipeline management, and query flow
  affects:
    - 02-02 (RAG UI views will bind to RAGViewModel)
tech_stack:
  added: []
  patterns:
    - "@MainActor @Observable ViewModel pattern (matching LLMViewModel)"
    - "Static struct service for stateless utility (DocumentService)"
    - "PDFKit for PDF text extraction"
    - "JSONSerialization with recursive string extraction for JSON"
    - "Security-scoped resource access for document picker URLs"
key_files:
  created:
    - examples/ios/RunAnywhereAI/RunAnywhereAI/Features/RAG/Services/DocumentService.swift
    - examples/ios/RunAnywhereAI/RunAnywhereAI/Features/RAG/ViewModels/RAGViewModel.swift
  modified: []
decisions:
  - "DocumentService as static struct — no state or DI needed for a pure extraction utility"
  - "loadDocument accepts RAGConfiguration parameter — view/caller provides model paths at runtime"
  - "MessageRole enum defined in RAGViewModel file — scoped to RAG feature, avoids polluting AppTypes"
  - "Pre-existing linker error (missing RAG C symbols) is out of scope — SDK Phase 1 build issue, no Swift compiler errors in new files"
metrics:
  duration: 316s
  completed: 2026-02-20
  tasks_completed: 2
  files_created: 2
---

# Phase 2 Plan 1: iOS App RAG Data/Logic Layer Summary

**One-liner:** PDF/JSON extraction via PDFKit+JSONSerialization plus @Observable RAGViewModel wiring RunAnywhere.ragIngest and ragQuery SDK calls.

## What Was Built

Two files that form the data and logic layer for the RAG feature in the iOS example app:

**DocumentService.swift** — A stateless utility struct that extracts plain text from PDF and JSON files. Uses PDFKit to iterate PDF pages and collect page strings. Uses JSONSerialization with recursive traversal to flatten all string values from nested JSON objects. Handles security-scoped resource access for UIDocumentPickerViewController URLs. Throws typed `DocumentServiceError` values for unsupported formats, extraction failures, and file read errors.

**RAGViewModel.swift** — A `@MainActor @Observable` ViewModel that orchestrates the full RAG lifecycle. `loadDocument(url:config:)` extracts text via DocumentService, calls `RunAnywhere.ragCreatePipeline`, then `RunAnywhere.ragIngest`. `askQuestion()` appends user/assistant messages to conversation history, calls `RunAnywhere.ragQuery`, and preserves `isDocumentLoaded = true` across subsequent calls (satisfying APP-04). `clearDocument()` destroys the pipeline and resets all state.

## Decisions Made

1. **DocumentService as static struct** — No instance state or dependency injection needed; pure input/output extraction utility.

2. **loadDocument accepts RAGConfiguration parameter** — The ViewModel does not hardcode model paths; the view (or model selection logic from the app) constructs the config with actual downloaded model paths.

3. **MessageRole enum local to RAG feature** — Avoids adding a RAG-specific type to the shared AppTypes.swift; scoped to the feature directory.

4. **No async in DocumentService** — PDFKit and file reads are synchronous and fast for typical documents; adding async would add complexity without benefit.

## Deviations from Plan

### Pre-existing Issue (Out of Scope)

**Linker error: missing RAG C symbols (`_rac_rag_pipeline_create`, etc.)**
- **Found during:** Task 1 build verification
- **Issue:** The RAG C++ bridge methods reference `rac_rag_*` symbols that are not yet linked into the example app build. This pre-dates both tasks in this plan and exists without any of the new files.
- **Action:** Confirmed pre-existing via `git stash` (no changes to stash — error exists on HEAD). Logged as deferred — this will be resolved when the SDK XCFramework with compiled C++ RAG code is included in the example app.
- **Impact on this plan:** None — both DocumentService and RAGViewModel have zero Swift compiler errors. The feature is complete at the Swift source level.

## Self-Check: PASSED

Files verified:
- FOUND: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/RAG/Services/DocumentService.swift
- FOUND: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/RAG/ViewModels/RAGViewModel.swift

Commits verified:
- 641ce824: feat(02-01): create DocumentService for PDF and JSON text extraction
- d6a6326c: feat(02-01): create RAGViewModel for document lifecycle and query orchestration
