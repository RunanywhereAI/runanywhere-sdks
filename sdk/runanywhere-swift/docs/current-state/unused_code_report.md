# RunAnywhere Swift SDK - Unused / Dead Code Report

**Generated:** December 7, 2025
**SDK Version:** 0.15.8

---

## Overview

This document catalogs unused, dead, or redundant code identified during the comprehensive SDK analysis. Items are categorized by confidence level and include recommendations for action.

---

## Summary

| Category | Count | Action Required |
|----------|-------|-----------------|
| Confirmed Dead Code | 12 | Safe to remove |
| Likely Unused (needs confirmation) | 15 | Verify before removal |
| Placeholder/Non-functional | 4 | Implement or remove |
| Duplicate Code | 2 | Consolidate |
| Technical Debt | 8 | Refactor |

---

## Confirmed Dead Code

These items have no references found in the codebase and are safe to remove.

### Components Module

| File | Item | Type | Rationale |
|------|------|------|-----------|
| `Components/LLM/LLMComponent.swift` | `conversationContext` property | Property | Set but never read or used |
| `Components/LLM/LLMComponent.swift` | `modelPath` property | Property | Set but never passed to service |
| `Components/LLM/LLMComponent.swift` | `modelLoadProgress` property | Property | Updated but not exposed |
| `Components/LLM/LLMComponent.swift` | `downloadModel()` method | Method | Simulation code, never called |
| `Components/STT/STTComponent.swift` | `downloadModel()` method | Method | Simulation code, never called |
| `Components/STT/STTComponent.swift` | `STTServiceAudioFormat` enum | Type | Defined but never referenced |
| `Components/TTS/TTSComponent.swift` | `currentVoice` property | Property | Set but never used |
| `Components/VAD/VADComponent.swift` | `lastSpeechState` property | Property | Tracked but not exposed |
| `Components/VoiceAgent/VoiceAgentComponent.swift` | `isProcessing` property | Property | Set but not used for concurrency control |
| `Components/VoiceAgent/VoiceAgentComponent.swift` | `processQueue` property | Property | Created but never used |
| `Components/WakeWord/WakeWordComponent.swift` | `isDetecting` property | Property | Tracked but never exposed |
| `Components/SpeakerDiarization/SpeakerDiarizationComponent.swift` | `isServiceReady` property | Property | Set but never checked |

### Backend Adapters

| File | Item | Type | Rationale |
|------|------|------|-----------|
| `FluidAudioDiarization/FluidAudioDiarization.swift` | `lastProcessedEmbedding` property | Property | Stored but never used |
| `FluidAudioDiarization/FluidAudioDiarization.swift` | `audioAccumulator` property | Property | Defined but accumulation logic not implemented |

---

## Likely Unused (Needs Confirmation)

These items appear unused but may have indirect usage through reflection, protocol conformances, or external callers.

### Components Module

| File | Item | Type | Rationale | Action |
|------|------|------|-----------|--------|
| `Components/VAD/VADComponent.swift` | `VADFrameworkAdapter` protocol | Protocol | Defined but no registry pattern implemented | Verify if planned for future use |
| `Components/SpeakerDiarization/SpeakerDiarizationComponent.swift` | `SpeakerDiarizationFrameworkAdapter` protocol | Protocol | No registry to use it | Verify if planned for future use |
| `Components/SpeakerDiarization/SpeakerDiarizationComponent.swift` | `downloadModel()` method | Method | Simulation code | Verify if needed for model downloads |
| `Components/WakeWord/WakeWordComponent.swift` | `WakeWordServiceProvider` protocol | Protocol | No registry implemented to use it | Verify future plans |

### Public Module

| File | Item | Type | Rationale | Action |
|------|------|------|-----------|--------|
| `Public/Models/ComponentInitializationParameters.swift` | `EmbeddingInitParameters` struct | Type | Embedding component not implemented | Check roadmap |
| `Public/Configuration/PrivacyMode.swift` | `.custom` case | Enum case | Custom mode not fully implemented | Check if planned |
| `Public/Configuration/RoutingPolicy.swift` | `.custom` case | Enum case | Custom policy not implemented | Check if planned |

### Backend Adapters

| File | Item | Type | Rationale | Action |
|------|------|------|-----------|--------|
| `FluidAudioDiarization/FluidAudioDiarizationProvider.swift` | `FluidDiarizationService` class | Class | Entire class is placeholder stub | Should use FluidAudioDiarization instead |

---

## Non-Functional / Placeholder Components

These are complete components or services that exist but don't provide real functionality.

### Critical - Entire Component Non-Functional

| Component | Status | Issue | Recommendation |
|-----------|--------|-------|----------------|
| `Components/VLM/VLMComponent.swift` | Non-functional | `UnavailableVLMService` always throws error | Remove until VLM implementation ready, or implement |
| `Components/WakeWord/WakeWordComponent.swift` | Non-functional | `DefaultWakeWordService` always returns false | Remove until wake word implementation ready, or implement |

### Supporting Types for Non-Functional Components

| File | Items | Recommendation |
|------|-------|----------------|
| `Components/VLM/VLMComponent.swift` | `MockVLMService`, `UnavailableVLMService`, `DefaultVLMAdapter`, `preprocessImage()` | Remove with component |
| `Components/WakeWord/WakeWordComponent.swift` | `DefaultWakeWordService` | Remove with component |

---

## Duplicate Code

### C Bridge Headers

| Files | Issue | Recommendation |
|-------|-------|----------------|
| `CRunAnywhereCore/include/ra_llamacpp_bridge.h` and `CRunAnywhereCore/include/ra_onnx_bridge.h` | Identical API definitions | Consolidate into single `ra_unified_bridge.h` |

---

## Technical Debt Items

These are not strictly dead code but represent areas needing attention.

### Thread Safety Concerns

| File | Issue | Risk |
|------|-------|------|
| Multiple Components | `@unchecked Sendable` without verification | Potential race conditions |
| `Components/TTS/TTSComponent.swift` | `speechContinuation` accessed from multiple threads | Thread safety issue |

### Incomplete Implementations

| File | Item | Issue |
|------|------|-------|
| `WhisperKitTranscription/WhisperKitService.swift` | `streamTranscribe<S>()` | Returns empty result (TODO) |
| `FluidAudioDiarization/FluidAudioDiarization.swift` | `processAudio()` | Returns placeholder (TODO: API needs fixing) |
| `Public/Extensions/RunAnywhere+Voice.swift` | `createVoiceConversation()` | Only initializes, doesn't implement conversation loop |

### Hardcoded / Magic Values

| File | Item | Issue |
|------|------|-------|
| `Components/TTS/TTSComponent.swift` | Telemetry framework | Hardcoded to "ONNX" even for system TTS |
| `Components/LLM/LLMComponent.swift` | Token estimation | Rough `text.count / 4` approximation |
| `ONNXRuntime/ONNXAdapter.swift` | Cache timeout | Hardcoded 5-minute timeout |
| `ONNXRuntime/ONNXSTTService.swift` | Batch threshold | Hardcoded 3-second chunks |

### Mock/Simulation Code in Production

| File | Item | Issue |
|------|------|-------|
| `Components/LLM/LLMComponent.swift` | `downloadModel()` | Simulation with fake progress |
| `Components/STT/STTComponent.swift` | `downloadModel()` | Simulation with fake progress |
| `Components/VLM/VLMComponent.swift` | `MockVLMService` | Mock service in production code |
| `Data/Network/Services/MockNetworkService.swift` | Entire file | Mock service - verify if needed |

---

## Recommendations by Priority

### High Priority (Remove/Fix Now)

1. **Remove non-functional VLMComponent** - Throws errors, provides no value
2. **Remove non-functional WakeWordComponent** - Always returns false
3. **Fix FluidAudioDiarizationProvider** - Replace stub with actual FluidAudioDiarization
4. **Consolidate C bridge headers** - Reduce maintenance burden

### Medium Priority (Address in Next Sprint)

1. **Remove simulation downloadModel() methods** - 3 occurrences
2. **Clean up unused properties in components** - 10+ properties
3. **Implement WhisperKit streaming** - Currently returns empty
4. **Verify thread safety** - Audit `@unchecked Sendable` usage

### Low Priority (Technical Debt Backlog)

1. **Extract hardcoded values to configuration**
2. **Implement custom PrivacyMode and RoutingPolicy**
3. **Complete voice conversation loop**
4. **Move mock services to test targets**

---

## Verification Checklist

Before removing any code, verify:

- [ ] No string-based references (Selectors, KVO paths)
- [ ] No reflection-based usage
- [ ] No external SDK consumers relying on it
- [ ] No planned features depending on it
- [ ] Tests don't require it

---

## Code Removal Script (Suggested)

```bash
# After verification, these files/sections can be safely removed:

# Non-functional components (entire files)
# - Sources/RunAnywhere/Components/VLM/VLMComponent.swift (or implement)
# - Sources/RunAnywhere/Components/WakeWord/WakeWordComponent.swift (or implement)

# Duplicate headers (consolidate first)
# - Sources/CRunAnywhereCore/include/ra_onnx_bridge.h (merge into ra_llamacpp_bridge.h)

# Mock services (move to tests)
# - Sources/RunAnywhere/Data/Network/Services/MockNetworkService.swift
```

---

*This document is part of the RunAnywhere Swift SDK current-state documentation.*
*Last updated after comprehensive file analysis.*
