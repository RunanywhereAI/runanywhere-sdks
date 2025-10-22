# Kotlin SDK Master Execution Plan

**Total Issues**: 51 Kotlin SDK issues
**Last Updated**: 2025-10-20
**Priority Levels**: P0 (Critical) → P1 (High) → P2 (Medium) → P3 (Low)

---

## Executive Summary

This document provides a **single source of truth** for Kotlin SDK issue execution order, organized by dependencies and priorities. Issues are grouped into phases that must be completed sequentially, with clear dependencies documented.

**Key Metrics**:
- P0 (Critical): 11 issues - Core blockers, must complete first
- P1 (High): 21 issues - High priority, complete next
- P2 (Medium): 16 issues - Medium priority, complete after P1
- P3 (Low): 3 issues - Nice to have, defer if needed

---

## How to Use This Document

1. **Start with Phase 0** - Critical blockers (P0)
2. **Work down each phase sequentially** - Dependencies are documented
3. **Within each phase**, issues can be worked in parallel unless dependencies are noted
4. **Check "Depends on" section** before starting any issue

---

# PHASE 0: CRITICAL BLOCKERS (P0)

**Must complete these first. Everything else depends on these being stable.**

## 0.1 Core Infrastructure (Parallel OK)

### #142: Fix critical thread safety issues in ModuleRegistry and shared state
**Priority**: P0
**Labels**: bug, kotlin-sdk
**Dependencies**: None
**Why Critical**: Thread safety bugs can cause crashes in production
**Effort**: 2-3 days

### #144: Implement privacy-first logging infrastructure
**Priority**: P0
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Why Critical**: Required for compliance, must be in place before shipping
**Effort**: 1 week

---

## 0.2 Core Services (Can work in parallel)

### #166: Implement functional ConfigurationService with persistence
**Priority**: P0
**Labels**: bug, kotlin-sdk
**Dependencies**: None
**Why Critical**: Configuration service is foundational for all SDK operations
**Effort**: 1 week
**Details**:
- Environment-based configuration
- Secure storage integration
- Fallback chain (Remote → DB → Consumer → Defaults)

### #168: Implement functional MemoryService with accurate tracking
**Priority**: P0
**Labels**: bug, kotlin-sdk
**Dependencies**: None
**Why Critical**: Prevents OOM crashes, critical for stability
**Effort**: 1 week
**Details**:
- Platform-specific memory detection
- Allocation tracking
- Memory pressure detection

### #169: Implement functional AnalyticsService with backend integration
**Priority**: P0
**Labels**: bug, kotlin-sdk
**Dependencies**: None
**Why Critical**: Required for usage metrics and debugging
**Effort**: 1 week
**Details**:
- Event persistence
- Backend integration
- Retry logic and offline support

---

## 0.3 Core Protocol Architecture (Sequential)

### #174: Define core protocol hierarchy (Component, LifecycleManaged, ModelBased)
**Priority**: P0
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Why Critical**: Foundation for all protocol work
**Effort**: 4-5 days
**Details**:
- Base Component interface
- LifecycleManaged interface
- ModelBasedComponent interface
- ServiceComponent interface
- PipelineComponent interface

### #177: Implement framework adapter and service protocols
**Priority**: P0
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #174 (should be completed first)
**Why Critical**: Required for plugin architecture
**Effort**: 1 week
**Details**:
- UnifiedFrameworkAdapter protocol
- ModelRegistry protocol
- AnalyticsService protocol
- ConfigurationServiceProtocol

---

## 0.4 Component Architecture (Critical Decision)

### #173: Refactor ServiceContainer component ownership pattern
**Priority**: P0
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #174, #177 (protocols should be defined first)
**Why Critical**: **ARCHITECTURAL DECISION REQUIRED** - Affects all component work
**Effort**: 1 week
**Decision Needed**: iOS pattern (independent components) vs Kotlin pattern (container ownership)
**⚠️ BLOCKER**: Must decide approach before proceeding with other component work

---

## 0.5 Voice Pipeline Infrastructure (Sequential)

### #153: Implement Audio Capture Infrastructure for Microphone Input
**Priority**: P0
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Why Critical**: Required for all voice features
**Effort**: 1 week

### #152: Implement Voice Capability Service for Platform Voice Feature Detection
**Priority**: P0
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Why Critical**: Required to detect platform voice capabilities
**Effort**: 3-4 days

---

## 0.6 Voice Pipeline Core Components (Depends on Infrastructure)

### #149: Implement TTS Component for Voice Pipeline Completion
**Priority**: P0
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #152, #153
**Effort**: 1 week

### #150: Implement Wake Word Detection Component
**Priority**: P0
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #152, #153
**Effort**: 1 week

---

## 0.7 Voice Pipeline Orchestration (Depends on Components)

### #151: Implement Voice Agent Component for End-to-End Voice Pipeline Orchestration
**Priority**: P0
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #149, #150, #152, #153
**Why Critical**: Orchestrates the complete voice pipeline
**Effort**: 1.5 weeks
**⚠️ Cannot start until prerequisites are complete**

---

**PHASE 0 COMPLETION CHECKPOINT**: After completing Phase 0, you will have:
- ✅ Thread-safe core infrastructure
- ✅ Privacy-first logging
- ✅ Functional core services (Configuration, Memory, Analytics)
- ✅ Core protocol architecture
- ✅ ServiceContainer pattern decided
- ✅ Complete voice pipeline (infrastructure → components → orchestration)

---

# PHASE 1: HIGH PRIORITY CONSOLIDATION (P1)

**Focus**: Clean up duplicated code and establish proper architecture patterns

## 1.1 Storage & Network Consolidation (MUST DO SEQUENTIALLY)

### #130: Consolidate duplicate SecureStorage interfaces
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Effort**: 3-4 days
**Start**: Begin Phase 1 with this

### #132: Consolidate duplicate FileManager implementations
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None (but work after #130 for clean flow)
**Effort**: 4-5 days

### #133: Consolidate duplicate network layer implementations
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None (but work after #132 for clean flow)
**Effort**: 4-5 days

### #134: Remove unused legacy code after network and storage consolidation
**Priority**: P2 (downgraded from consolidation)
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #130, #132, #133 (MUST complete these first)
**Effort**: 2-3 days
**⚠️ BLOCKER**: Cannot start until #130, #132, #133 are complete

---

## 1.2 File Management (SEQUENTIAL - #132 must complete first)

### #117: Implement Unified File Management System in Kotlin SDK
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #132 (Consolidate FileManager implementations)
**Effort**: 2 weeks
**⚠️ BLOCKER**: Must complete #132 first

---

## 1.3 Module Organization (SEQUENTIAL)

### #128: Relocate llama-jni native module to runanywhere-llm-llamacpp module
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Effort**: 1 week

### #129: Relocate whisper-jni native module to runanywhere-whisperkit module
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None (can work parallel with #128)
**Effort**: 1 week

### #137: Fix expect/actual pattern for platform-specific code
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #128, #129 (should relocate modules first)
**Effort**: 1 week
**💡 Recommended**: Complete after JNI relocations

### #136: Organize platform-specific expect declarations in dedicated infrastructure folder
**Priority**: P2 (downgraded)
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #128, #129, #137 (do after expect/actual fixes)
**Effort**: 1 week
**💡 Recommended**: Complete after all module relocations and pattern fixes

---

## 1.4 Model & Component Refactoring (PARALLEL OK)

### #122: Refactor WhisperKit models to eliminate duplication and follow SDK patterns
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Effort**: 1.5 weeks (6 phases)

### #121: Refactor Audio Processing: Extract Platform-Agnostic Interface to Commons
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Effort**: 1 week

---

## 1.5 Component Architecture Alignment (Can start after #174)

### #170: Refactor BaseComponent lifecycle to match iOS patterns
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #174 (core protocols defined)
**Effort**: 3-4 days

### #171: Implement event-driven architecture with EventBus alignment
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #174
**Effort**: 2-3 days

---

## 1.6 Protocol Implementation (Depends on #174)

### #175: Implement model lifecycle protocols (ModelLifecycleManager, Observer)
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #174 (core protocols)
**Effort**: 3-4 days

### #176: Implement resource management protocols (Hardware, Memory, Storage)
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #174 (can work parallel with #175)
**Effort**: 1 week

---

## 1.7 Hardware & Capability Detection (PARALLEL OK)

### #148: Implement DeviceCapability system for hardware detection and monitoring
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Effort**: 1.5 weeks
**Note**: Includes ResourceChecker functionality (merged from #156)

### #156: Implement Resource Checker for Hardware Capability Detection
**Status**: MERGED INTO #148
**Action**: Do not work on this separately, covered by #148

---

## 1.8 Component Implementations (Can start after protocols)

### #154: Implement VLM Component for Vision Language Model Support
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #174 (protocols), #177 (framework adapter)
**Effort**: 2 weeks

### #155: Implement Unified Framework Adapter for Cross-Platform Model Loading
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #177 (adapter protocols)
**Effort**: 2 weeks

---

## 1.9 Voice Pipeline Advanced (After core pipeline works)

### #157: Implement Audio Segmentation for VAD Pipeline
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #151 (Voice Agent working)
**Effort**: 1 week

### #158: Implement Advanced VAD Strategies for Improved Speech Detection
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #151 (Voice Agent working)
**Effort**: 1 week

---

## 1.10 Production Readiness (Can work in parallel)

### #113: Fix IntelliJ Run Configurations for Kotlin SDK and Sample Projects
**Priority**: P1
**Labels**: enhancement, kotlin-sample, kotlin-sdk
**Dependencies**: None
**Effort**: 4-6 hours

### #127: Establish Proper Release Process with JitPack for Kotlin SDK Multi-Module Distribution
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #128, #129 (modules should be organized first)
**Effort**: 1 week

### #140: Replace non-null assertions (!!) with safe null handling
**Priority**: P1
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Effort**: 1 week (codebase-wide)

---

**PHASE 1 COMPLETION CHECKPOINT**: After completing Phase 1, you will have:
- ✅ Consolidated storage, network, and file management
- ✅ Properly organized module structure
- ✅ Refactored components following iOS patterns
- ✅ Complete protocol architecture
- ✅ Hardware capability detection
- ✅ Advanced voice features
- ✅ Production-ready build and release process

---

# PHASE 2: MEDIUM PRIORITY ENHANCEMENTS (P2)

**Focus**: Architecture improvements, code quality, and advanced features

## 2.1 Architecture & Code Quality (PARALLEL OK)

### #138: Align Kotlin SDK package structure with iOS SDK architecture
**Priority**: P2
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #130-#137 (consolidation should be done)
**Effort**: 1-2 weeks

### #139: Remove mock implementations from production code
**Priority**: P2
**Labels**: enhancement, kotlin-sdk
**Dependencies**: Real implementations should exist first
**Effort**: 1 week

### #172: Align provider pattern with iOS ModuleRegistry
**Priority**: P2
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #171 (EventBus), #174 (protocols)
**Effort**: 2-3 days

---

## 2.2 Configuration & Module Cleanup (PARALLEL OK)

### #120: Remove hard-coded sampling and chat template parameters from Llama CPP module
**Priority**: P2
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Effort**: 1 week

### #123: Extract Hardcoded Configuration Values in Llama CPP Module
**Status**: MERGED INTO #120
**Action**: Do not work on separately, covered by #120

### #131: Consolidate duplicate SDKConstants into single location
**Priority**: P2
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Effort**: 2-3 days

---

## 2.3 Advanced Voice Features (After core pipeline)

### #159: Implement Voice Analytics for Usage Tracking and Insights
**Priority**: P2
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #151 (Voice Agent working), #169 (AnalyticsService)
**Effort**: 1 week

### #160: Implement Speaker Diarization for Multi-Speaker Detection
**Priority**: P2
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #151 (Voice Agent)
**Effort**: 2 weeks

---

## 2.4 Advanced SDK Features (PARALLEL OK)

### #161: Implement Routing Policy Engine for Model Selection Optimization
**Priority**: P2
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #166 (ConfigurationService), #168 (MemoryService)
**Effort**: 1.5 weeks

### #162: Implement Conversation Helper API for Multi-Turn Dialogue Management
**Priority**: P2
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #168 (MemoryService)
**Effort**: 1 week

### #118: Move ConversationStore to SDK with proper database persistence
**Priority**: P2
**Labels**: enhancement, ios-sdk, kotlin-sdk
**Dependencies**: #117 (File Management), #164 (Database Migrations)
**Effort**: 2 weeks
**Note**: Cross-platform feature (iOS + Android)

---

**PHASE 2 COMPLETION CHECKPOINT**: After completing Phase 2, you will have:
- ✅ Clean, iOS-aligned architecture
- ✅ No mock/hardcoded implementations
- ✅ Advanced voice analytics and diarization
- ✅ Routing and conversation management
- ✅ Production-quality codebase

---

# PHASE 3: LOW PRIORITY / FUTURE (P3 or No Priority)

**Focus**: Nice-to-have features, can defer if needed

## 3.1 Infrastructure Enhancements (PARALLEL OK)

### #163: Implement Public API Utilities and Helper Functions
**Priority**: P3 (no label in repo)
**Labels**: enhancement, kotlin-sdk
**Dependencies**: None
**Effort**: 1 week
**Note**: Needs detailed scope definition

### #164: Implement Database Migration System for Schema Evolution
**Priority**: P3 (no label in repo)
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #118 (ConversationStore)
**Effort**: 1 week

### #165: Implement Network Reachability Monitoring for Offline Handling
**Priority**: P3 (no label in repo)
**Labels**: enhancement, kotlin-sdk
**Dependencies**: #133 (Network consolidation)
**Effort**: 3-4 days

---

**PHASE 3 COMPLETION CHECKPOINT**: After completing Phase 3, you will have:
- ✅ Complete SDK with all planned features
- ✅ Database migration support
- ✅ Offline-first capabilities
- ✅ Comprehensive public API

---

# DEPENDENCY VISUALIZATION

```
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 0: CRITICAL BLOCKERS (P0)                                 │
└─────────────────────────────────────────────────────────────────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
                    ▼            ▼            ▼
          ┌─────────────┐  ┌─────────┐  ┌─────────────┐
          │   Core      │  │ Core    │  │  Protocol   │
          │Infrastructure│  │Services │  │Architecture │
          │#142,#144    │  │#166-169 │  │#174,#177    │
          └─────────────┘  └─────────┘  └──────┬──────┘
                                               │
                    ┌──────────────────────────┤
                    │                          │
                    ▼                          ▼
          ┌─────────────────┐        ┌─────────────────┐
          │ServiceContainer │        │Voice Pipeline   │
          │   Decision      │        │#149-153         │
          │     #173        │        │   Sequential    │
          └────────┬────────┘        └────────┬────────┘
                   │                          │
                   │                          ▼
                   │                 ┌─────────────────┐
                   │                 │  Voice Agent    │
                   │                 │Orchestration    │
                   │                 │     #151        │
                   │                 └─────────────────┘
                   │
┌──────────────────┴──────────────────────────────────────────────┐
│ PHASE 1: HIGH PRIORITY (P1)                                     │
└─────────────────────────────────────────────────────────────────┘
                   │
      ┌────────────┼────────────┬─────────────┐
      │            │            │             │
      ▼            ▼            ▼             ▼
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐
│Storage & │ │  Module  │ │Component │ │  Advanced    │
│ Network  │ │  Reorg   │ │Refactor  │ │  Features    │
│#130-134  │ │#128-137  │ │#170-176  │ │#154-158      │
│Sequential│ │Sequential│ │ Parallel │ │  Parallel    │
└──────────┘ └──────────┘ └──────────┘ └──────────────┘
      │            │            │             │
      └────────────┴────────────┴─────────────┘
                   │
┌──────────────────┴──────────────────────────────────────────────┐
│ PHASE 2: MEDIUM PRIORITY (P2)                                   │
└─────────────────────────────────────────────────────────────────┘
                   │
      ┌────────────┼────────────┐
      │            │            │
      ▼            ▼            ▼
┌──────────┐ ┌──────────┐ ┌──────────────┐
│Arch      │ │Advanced  │ │  Advanced    │
│Cleanup   │ │  Voice   │ │  SDK         │
│#138-139  │ │#159-160  │ │#161-162,#118 │
│ Parallel │ │ Parallel │ │  Parallel    │
└──────────┘ └──────────┘ └──────────────┘
      │            │            │
      └────────────┴────────────┘
                   │
┌──────────────────┴──────────────────────────────────────────────┐
│ PHASE 3: LOW PRIORITY (P3/Future)                               │
└─────────────────────────────────────────────────────────────────┘
                   │
            #163, #164, #165
           (Nice-to-have features)
```

---

# QUICK REFERENCE: START HERE

## Week 1-2: Critical Blockers
1. Start with #142 (Thread safety) + #144 (Privacy logging) in parallel
2. Start #166, #168, #169 (Core services) in parallel
3. Start #174 (Core protocols)

## Week 3-4: Voice Pipeline Foundation
1. Complete #177 (Framework protocols) - depends on #174
2. Complete #173 (ServiceContainer decision) - **CRITICAL DECISION**
3. Start #153, #152 (Voice infrastructure) in parallel

## Week 5-6: Voice Pipeline Components
1. Complete #149, #150 (TTS, Wake Word) - depends on #152, #153
2. Complete #151 (Voice Agent) - depends on all above

## Week 7-10: Consolidation & Module Cleanup
1. Sequential: #130 → #132 → #133 → #134
2. Parallel: #128, #129 (JNI relocations)
3. Sequential after JNI: #137 → #136
4. Complete #117 after #132

## Week 11-14: Component Refactoring
1. #170, #171 (Component lifecycle, EventBus)
2. #175, #176 (Protocol implementations)
3. #122, #121 (WhisperKit, Audio refactoring)
4. #148 (DeviceCapability)

## Week 15-18: Advanced Features
1. #154, #155 (VLM, Framework Adapter)
2. #157, #158 (Advanced VAD)
3. #113, #127, #140 (Production readiness)

## Week 19+: P2 and Beyond
1. Architecture cleanup (#138, #139)
2. Configuration cleanup (#120, #131)
3. Advanced voice (#159, #160)
4. Advanced SDK (#161, #162, #118)
5. Future features (#163, #164, #165)

---

# ISSUES CLOSED/MERGED

The following issues were duplicates or merged:

- ❌ #124: Duplicate of #122 (WhisperKit refactoring)
- ❌ #141: Split into #166, #168, #169 (Core services)
- ❌ #143: Split into #174, #175, #176, #177 (Protocols)
- ❌ #135: Split into #170, #171, #172, #173 (Component architecture)
- ❌ #145: Duplicate of #148 (DeviceCapability)
- ❌ #146: Duplicate of #141 (Core services)
- ❌ #147: Duplicate of #144 (Privacy logging)
- ❌ #156: Merged into #148 (ResourceChecker is part of DeviceCapability)
- ❌ #167: Duplicate of #168 (MemoryService)

**Total Issues**: 51 active Kotlin SDK issues (after cleanup)

---

# CRITICAL DECISIONS NEEDED

## Decision #1: ServiceContainer Component Ownership (#173)
**When**: Before starting Phase 1 component work
**Options**:
- A: Keep Kotlin pattern (ServiceContainer owns components)
- B: Adopt iOS pattern (Independent components)

**Recommendation**: Option B (iOS pattern) for consistency

**Impact**: Affects #170, #171, #173, and all component implementations

---

# COMPLETION TRACKING

Use this checklist to track phase completion:

## Phase 0: Critical Blockers
- [ ] 0.1 Core Infrastructure (#142, #144)
- [ ] 0.2 Core Services (#166, #168, #169)
- [ ] 0.3 Core Protocols (#174, #177)
- [ ] 0.4 ServiceContainer Decision (#173)
- [ ] 0.5 Voice Infrastructure (#152, #153)
- [ ] 0.6 Voice Components (#149, #150)
- [ ] 0.7 Voice Orchestration (#151)

## Phase 1: High Priority
- [ ] 1.1 Storage/Network (#130, #132, #133, #134)
- [ ] 1.2 File Management (#117)
- [ ] 1.3 Module Organization (#128, #129, #137, #136)
- [ ] 1.4 Model Refactoring (#122, #121)
- [ ] 1.5 Component Architecture (#170, #171)
- [ ] 1.6 Protocol Implementation (#175, #176)
- [ ] 1.7 Hardware Detection (#148)
- [ ] 1.8 Component Implementations (#154, #155)
- [ ] 1.9 Voice Advanced (#157, #158)
- [ ] 1.10 Production Readiness (#113, #127, #140)

## Phase 2: Medium Priority
- [ ] 2.1 Architecture (#138, #139, #172)
- [ ] 2.2 Configuration (#120, #131)
- [ ] 2.3 Advanced Voice (#159, #160)
- [ ] 2.4 Advanced SDK (#161, #162, #118)

## Phase 3: Low Priority
- [ ] 3.1 Infrastructure (#163, #164, #165)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-20
**Next Review**: After Phase 0 completion

**Use this as your single source of truth for Kotlin SDK issue execution order.**
