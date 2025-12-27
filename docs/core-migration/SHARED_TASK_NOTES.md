# Shared Task Notes - Core Migration Audit

## Current State
The core migration feasibility audit is **COMPLETE**. All 9 deliverable documents have been created in `docs/core-migration/`.

## Documents Created
1. `CORE_MIGRATION_OVERVIEW.md` - Executive summary and recommendations
2. `CORE_PORTABILITY_RULES.md` - Decision framework for what moves to core
3. `IOS_CORE_FEASIBILITY.md` - iOS SDK analysis (source of truth)
4. `ANDROID_CORE_FEASIBILITY.md` - Kotlin KMP SDK analysis
5. `FLUTTER_CORE_FEASIBILITY.md` - Flutter SDK analysis (already has FFI)
6. `RN_CORE_FEASIBILITY.md` - React Native SDK analysis (already has Nitrogen/JSI)
7. `CORE_COMPONENT_CANDIDATES.md` - Unified component list by category
8. `CORE_API_BOUNDARY_SPEC.md` - Concrete C API specification
9. `BINDINGS_AND_PACKAGING_PLAN.md` - Platform packaging details
10. `MIGRATION_SEQUENCE.md` - Phased implementation plan

## Key Findings

### Architecture Alignment
All 4 SDKs follow remarkably similar patterns:
- Component architecture (BaseComponent → STT/LLM/TTS/VAD/VoiceAgent)
- ModuleRegistry for plugin architecture
- EventBus for events
- ServiceContainer for DI
- 8-step initialization sequence

### Portability Assessment
- **~70-80% of business logic is portable** to C++ core
- **~20-30% must stay in platform wrappers** (audio I/O, keychain, permissions)

### Existing Core Usage
- **Flutter**: Already uses dart:ffi with 1,100+ line NativeBackend
- **React Native**: Already uses Nitrogen/JSI with C++ HybridRunAnywhere
- **iOS**: Uses CRunAnywhereCore headers for ONNX/LlamaCpp backends
- **KMP**: Uses JNI modules for native backends

### Unique Findings
- **RoutingDecisionEngine** exists only in KMP - should be backported to iOS and moved to core
- **SimpleEnergyVAD** is duplicated in iOS and KMP with identical algorithms

## Next Steps for Implementation (Not Part of This Audit)

If the team decides to proceed with migration:

1. **Phase 0 (3 weeks)**: C API skeleton, build infrastructure, golden tests
2. **Phase 1 (4 weeks)**: Routing, VAD, Lifecycle, Events
3. **Phase 2 (4 weeks)**: ModuleRegistry, ServiceContainer, Components
4. **Phase 3 (5 weeks)**: Analytics, Download, Voice Pipeline

Total estimated effort: ~16 weeks

## Unknowns Requiring Measurement
- Baseline performance metrics per SDK (latency, memory, battery)
- FFI overhead for streaming (need to prototype batched callbacks)
- Actual size reduction from removing duplicated code

## Files to Reference
- iOS source of truth: `sdk/runanywhere-swift/Sources/RunAnywhere/`
- KMP routing engine: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/routing/`
- Flutter FFI: `sdk/runanywhere-flutter/lib/backends/native/native_backend.dart`
- RN JSI: `sdk/runanywhere-react-native/cpp/HybridRunAnywhere.cpp`

---
*Last updated: December 2025*
*Status: Audit Complete - Implementation Not Started*
