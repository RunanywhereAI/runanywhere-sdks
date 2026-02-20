# Roadmap: RAG for Swift SDK & iOS Example App

## Overview

Two natural delivery boundaries drive this project. First, the Swift SDK gets a RAG component — a thin wrapper over the existing C++ backend following the established CppBridge + Extension pattern. Second, the iOS example app gets a document-aware Q&A feature that uses that component, giving users the ability to load a PDF or JSON file and ask questions about it. The SDK phase must complete before the app phase can begin.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Swift SDK RAG Component** - Expose RAG as a first-class SDK component via CppBridge + extension pattern
- [x] **Phase 2: iOS App RAG Feature** - User-facing document upload and natural-language Q&A over loaded documents (completed 2026-02-20)

## Phase Details

### Phase 1: Swift SDK RAG Component
**Goal**: The Swift SDK exposes a RAG component that developers can call to ingest documents and query them via the C++ backend
**Depends on**: Nothing (first phase)
**Requirements**: SDK-01, SDK-02, SDK-03, SDK-04
**Success Criteria** (what must be TRUE):
  1. Calling the SDK ingest API with a text string sends it to the C++ RAG backend without error
  2. Calling the SDK query API with a question string returns a RAG-augmented answer string
  3. RAG events (ingestion started, ingestion complete, query result) appear on the EventBus
  4. The component follows the same CppBridge + RunAnywhere extension file structure as STT/LLM/TTS
**Plans:** 2/2 plans complete

Plans:
- [x] 01-01-PLAN.md — RAG C headers in CRACommons, error/event/component enums, CppBridge.RAG actor
- [x] 01-02-PLAN.md — RAGTypes, RunAnywhere+RAG public API, RAGEvents

### Phase 2: iOS App RAG Feature
**Goal**: Users can pick a PDF or JSON document in the iOS app, load it once, and ask multiple natural-language questions about it
**Depends on**: Phase 1
**Requirements**: APP-01, APP-02, APP-03, APP-04
**Success Criteria** (what must be TRUE):
  1. User can open the system document picker and select a PDF or JSON file
  2. App extracts plain text from the selected file and passes it to the SDK ingest API
  3. User can type a question and receive an answer grounded in the loaded document
  4. User can ask follow-up questions without re-uploading the document (document stays loaded)
**Plans:** 2/2 plans complete

Plans:
- [ ] 02-01-PLAN.md — DocumentService (PDF/JSON extraction) + RAGViewModel (orchestration logic)
- [ ] 02-02-PLAN.md — DocumentRAGView (SwiftUI Q&A interface) + ContentView wiring

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Swift SDK RAG Component | 2/2 | Complete    | 2026-02-20 |
| 2. iOS App RAG Feature | 2/2 | Complete   | 2026-02-20 |
