# Requirements: RAG for Swift SDK & iOS Example App

**Defined:** 2026-02-20
**Core Value:** Users can load a document and ask natural-language questions about its contents via on-device RAG

## v1 Requirements

### Swift SDK — RAG Component

- [x] **SDK-01**: RAG component wrapper following CppBridge + RunAnywhere extension pattern (matching STT/LLM/TTS)
- [x] **SDK-02**: Document ingestion API that passes text strings to C++ RAG backend
- [x] **SDK-03**: Query API that sends questions to C++ and returns RAG-augmented answers
- [x] **SDK-04**: RAG event types published on EventBus for status and results

### iOS Example App — RAG Feature

- [x] **APP-01**: User can pick PDF or JSON files via document picker
- [x] **APP-02**: App extracts text from PDF and JSON documents before passing to C++
- [x] **APP-03**: User can type questions and receive RAG-augmented answers
- [x] **APP-04**: Document stays loaded across multiple queries (persistent session)

## v2 Requirements

### Enhanced UX

- **UX-01**: Document preview before querying
- **UX-02**: Query history within session
- **UX-03**: Multiple document session support
- **UX-04**: Pipeline progress events (chunking, embedding status)

## Out of Scope

| Feature | Reason |
|---------|--------|
| C++ RAG backend changes | Already implemented, not modifying |
| Kotlin/Android RAG | Separate effort |
| Web SDK RAG | Separate effort |
| HTML/rich text documents | C++ only accepts plain text strings |
| Cloud RAG fallback | On-device only for now |
| Document chunking UI | Handled internally by C++ backend |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SDK-01 | Phase 1 | Complete (Plan 01) |
| SDK-02 | Phase 1 | Complete |
| SDK-03 | Phase 1 | Complete |
| SDK-04 | Phase 1 | Complete |
| APP-01 | Phase 2 | Complete |
| APP-02 | Phase 2 | Complete |
| APP-03 | Phase 2 | Complete |
| APP-04 | Phase 2 | Complete |

**Coverage:**
- v1 requirements: 8 total
- Mapped to phases: 8
- Unmapped: 0

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 after roadmap creation*
