# Migration Sequence

## Overview

This document outlines a staged, incremental plan for migrating shared business logic from the platform SDKs (iOS, Android/KMP, Flutter, React Native) to a unified C++ core.

---

## Phase 0: Foundation (Weeks 1-3)

### Objectives
- Establish C API skeleton with stable ABI
- Create build infrastructure
- Set up golden tests
- Define platform adapter interface

### Tasks

| Task | Description | Acceptance Criteria | Effort |
|------|-------------|---------------------|--------|
| **0.1 C API Header Design** | Create `ra_core.h` and sub-headers | Headers compile on all platforms | 3 days |
| **0.2 Build Infrastructure** | CMake + CI for iOS XCFramework, Android .so | Artifacts build successfully | 5 days |
| **0.3 Platform Adapter Interface** | Define `ra_platform_adapter_t` | Interface covers HTTP, FileSystem, SecureStorage, Logger | 2 days |
| **0.4 Error Handling** | Implement error codes and `ra_get_last_error()` | Errors propagate to all platforms | 2 days |
| **0.5 Golden Tests** | Core C++ unit tests for API | >80% coverage of API | 3 days |

### Deliverables
- `include/ra_*.h` header files
- `CMakeLists.txt` for cross-platform build
- `.github/workflows/build-core.yml`
- `tests/` directory with unit tests
- Platform adapter stub implementations

### Definition of Done
- [ ] Headers compile on iOS (Xcode), Android (NDK), macOS, Linux, Windows
- [ ] XCFramework and AAR artifacts build in CI
- [ ] Platform adapter compiles as stub
- [ ] 10+ unit tests pass

### Rollback Strategy
- Headers are additive; no breaking changes to existing SDK code
- Build infrastructure is standalone; SDKs continue using existing binaries

---

## Phase 1: High-ROI Stable Logic (Weeks 4-7)

### Objectives
Move the highest ROI components with lowest risk:
- RoutingDecisionEngine (consistent routing across all SDKs)
- SimpleEnergyVAD (pure math, duplicated 4x)
- ModelLifecycleManager (state machine, duplicated 4x)
- EventPublisher (event routing, analytics integration)

### Tasks

| Task | Description | Acceptance Criteria | Effort |
|------|-------------|---------------------|--------|
| **1.1 RoutingDecisionEngine** | Port KMP `RoutingDecisionEngine.kt` to C++ | Same scoring as KMP, test cases pass | 5 days |
| **1.2 SimpleEnergyVAD** | Port iOS `SimpleEnergyVADService.swift` to C++ | Same RMS/hysteresis behavior | 3 days |
| **1.3 ModelLifecycleManager** | Port iOS `ManagedLifecycle.swift` to C++ | State transitions match iOS | 3 days |
| **1.4 EventPublisher** | Implement `ra_event_*()` API | Events flow to subscribers and analytics | 4 days |
| **1.5 iOS Integration** | Update iOS SDK to use core routing, VAD, lifecycle | iOS tests pass | 5 days |
| **1.6 KMP Integration** | Update KMP SDK to use core via JNI | KMP tests pass | 5 days |
| **1.7 Flutter Integration** | Update Flutter SDK (already FFI) | Flutter tests pass | 3 days |
| **1.8 RN Integration** | Update RN SDK via Nitrogen | RN tests pass | 4 days |

### Deliverables
- `src/routing/routing_decision_engine.cpp`
- `src/vad/simple_energy_vad.cpp`
- `src/lifecycle/model_lifecycle_manager.cpp`
- `src/events/event_publisher.cpp`
- Updated bindings in each SDK

### Definition of Done
- [ ] Routing decisions identical across all SDKs (compare logs)
- [ ] VAD behavior matches iOS golden tests
- [ ] Lifecycle state transitions logged consistently
- [ ] Events received in all SDK wrappers
- [ ] All SDK unit tests pass
- [ ] Example apps work on iOS, Android

### Rollback Strategy
- Feature flags in each SDK: `useNativeRouting`, `useNativeVAD`
- Can revert to SDK-native implementation if issues found
- Binaries versioned; can pin to pre-migration version

---

## Phase 2: Pipelines & State Machines (Weeks 8-11)

### Objectives
Move orchestration logic:
- ModuleRegistry (plugin architecture)
- ServiceContainer (DI and initialization)
- Component state machines (STT, LLM, TTS, VAD component wrappers)
- MemoryPressureHandler

### Tasks

| Task | Description | Acceptance Criteria | Effort |
|------|-------------|---------------------|--------|
| **2.1 ModuleRegistry** | Port iOS `ModuleRegistry.swift` to C++ | Provider registration and lookup works | 5 days |
| **2.2 ServiceContainer** | Port iOS `ServiceContainer.swift` to C++ | 8-step initialization matches iOS | 5 days |
| **2.3 Component State Machines** | Implement `ra_stt_component_*`, `ra_llm_component_*` | Component lifecycle managed in core | 8 days |
| **2.4 MemoryPressureHandler** | Port KMP `MemoryManager` to C++ | Eviction decisions match KMP | 4 days |
| **2.5 iOS Integration** | Update iOS SDK components | iOS sample app works | 5 days |
| **2.6 KMP Integration** | Update KMP SDK components | KMP sample app works | 5 days |
| **2.7 Flutter Integration** | Update Flutter SDK components | Flutter sample app works | 4 days |
| **2.8 RN Integration** | Update RN SDK components | RN sample app works | 4 days |

### Deliverables
- `src/registry/module_registry.cpp`
- `src/container/service_container.cpp`
- `src/components/stt_component.cpp`, `llm_component.cpp`, etc.
- `src/memory/memory_pressure_handler.cpp`
- Updated bindings in each SDK

### Definition of Done
- [ ] ModuleRegistry discovers providers correctly on all platforms
- [ ] ServiceContainer 8-step initialization logged identically
- [ ] Components load/unload models via core
- [ ] Memory pressure triggers model eviction
- [ ] All SDK integration tests pass
- [ ] Example apps demonstrate full workflow

### Rollback Strategy
- Keep SDK-native component wrappers alongside core versions
- Toggle via config: `useNativeComponents: true/false`
- Gradual rollout per component

---

## Phase 3: Remaining Compute & Transform Logic (Weeks 12-16)

### Objectives
Move remaining portable logic:
- AnalyticsQueueManager (batching, redaction)
- DownloadOrchestrator (retry, checksum, progress)
- StructuredOutputParser (JSON schema validation)
- VoiceAgentPipeline (VAD→STT→LLM→TTS orchestration)

### Tasks

| Task | Description | Acceptance Criteria | Effort |
|------|-------------|---------------------|--------|
| **3.1 AnalyticsQueueManager** | Port telemetry batching to C++ | Analytics events batched and sent | 4 days |
| **3.2 DownloadOrchestrator** | Port download logic (calls HTTP adapter) | Downloads with retry, checksum | 6 days |
| **3.3 StructuredOutputParser** | Port JSON schema validation to C++ | Structured output parsing works | 4 days |
| **3.4 VoiceAgentPipeline** | Port orchestration logic | Full voice pipeline works | 8 days |
| **3.5 Streaming Optimization** | Implement batched streaming callbacks | Reduced FFI crossings | 4 days |
| **3.6 Full Integration Testing** | End-to-end tests across all SDKs | All scenarios pass | 6 days |
| **3.7 Performance Benchmarking** | Measure latency, memory, battery | Within 10% of native baseline | 4 days |
| **3.8 Documentation** | Update SDK docs, migration guide | Docs complete | 4 days |

### Deliverables
- `src/analytics/analytics_queue.cpp`
- `src/download/download_orchestrator.cpp`
- `src/parsing/structured_output_parser.cpp`
- `src/voice/voice_agent_pipeline.cpp`
- Performance benchmark results
- Updated SDK documentation

### Definition of Done
- [ ] Analytics events reach backend correctly
- [ ] Model downloads resume after interruption
- [ ] Structured output parsing matches iOS behavior
- [ ] Voice pipeline (VAD→STT→LLM→TTS) works end-to-end
- [ ] Streaming latency < 100ms per batch
- [ ] Memory usage within 10% of pre-migration
- [ ] All SDK example apps work
- [ ] Documentation complete

### Rollback Strategy
- Full SDK-native fallback path preserved
- Feature flags disable core logic selectively
- Binary versioning allows rollback

---

## Phase Summary

| Phase | Duration | Components | Risk Level |
|-------|----------|------------|------------|
| Phase 0 | 3 weeks | Foundation, ABI, Tests | LOW |
| Phase 1 | 4 weeks | Routing, VAD, Lifecycle, Events | LOW |
| Phase 2 | 4 weeks | Registry, Container, Components | MEDIUM |
| Phase 3 | 5 weeks | Analytics, Download, Voice Pipeline | MEDIUM |

**Total Duration**: 16 weeks (~4 months)

---

## Measurements Needed

### Before Migration (Baseline)

| Metric | iOS | Android | Flutter | RN |
|--------|-----|---------|---------|-----|
| SDK size (MB) | Measure | Measure | Measure | Measure |
| Init time (ms) | Measure | Measure | Measure | Measure |
| Memory (model loaded) | Measure | Measure | Measure | Measure |
| STT latency (ms) | Measure | Measure | Measure | Measure |
| LLM TTFT (ms) | Measure | Measure | Measure | Measure |
| TTS latency (ms) | Measure | Measure | Measure | Measure |
| Battery (1hr use) | Measure | Measure | Measure | Measure |

### After Each Phase

Re-measure all metrics and compare:
- SDK size should decrease (less duplicated code)
- Init time should be similar or faster
- Memory should be similar or lower
- Latencies should be within 10%
- Battery should be within 10%

---

## Risk Register

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| ABI breaking changes | HIGH | MEDIUM | Struct versioning, deprecation policy |
| Memory leaks in C++ | HIGH | MEDIUM | ASAN/MSAN in CI, code review |
| Thread safety issues | HIGH | MEDIUM | Clear ownership rules, mutex patterns |
| FFI performance overhead | MEDIUM | LOW | Batching, pull model for streaming |
| Build complexity | MEDIUM | HIGH | Comprehensive CI, documentation |
| Platform divergence | MEDIUM | LOW | Shared tests, cross-platform CI |
| Team learning curve | LOW | MEDIUM | Training, pair programming |

---

## Success Criteria

### Technical
- [ ] All 4 SDKs use shared core for routing, VAD, lifecycle, events
- [ ] Feature parity with pre-migration SDKs
- [ ] Performance within 10% of baseline
- [ ] Zero regressions in existing functionality

### Operational
- [ ] CI builds all artifacts automatically
- [ ] Binary distribution working (CocoaPods, Maven, pub.dev, npm)
- [ ] Documentation updated
- [ ] Team can extend core independently

### Business
- [ ] Reduced time-to-ship for new features (implement once)
- [ ] Reduced bug count from SDK divergence
- [ ] Consistent behavior across platforms

---

## Post-Migration Maintenance

### Ongoing Tasks
1. **Version management**: Semantic versioning for core API
2. **ABI stability**: No breaking changes without major version bump
3. **Platform testing**: CI tests all platforms for each core change
4. **Documentation**: Keep API docs current
5. **Performance monitoring**: Track metrics per release

### Extension Points
1. **New capabilities**: Add to core, bind to all SDKs
2. **New platforms**: Add new bindings (e.g., desktop, wasm)
3. **New backends**: Register via ModuleRegistry
4. **Custom routing**: Extend RoutingDecisionEngine

---

*Document generated: December 2025*
