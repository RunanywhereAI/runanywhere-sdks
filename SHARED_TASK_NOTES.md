# Shared Task Notes - Core Migration Feasibility Audit

## Status: AUDIT COMPLETE ✅

All 10 deliverable documents have been created and verified in `docs/core-migration/`.

## For Next Developer: What to Do

### If You're Starting Implementation (Phase 0)
1. Read `MIGRATION_SEQUENCE.md` - Start with Phase 0 (Foundation, weeks 1-3)
2. First task: Create `include/ra_core.h` header based on `CORE_API_BOUNDARY_SPEC.md`
3. Set up CMake build for XCFramework + Android .so
4. Use Flutter's existing FFI (`lib/backends/native/native_backend.dart`) as reference pattern

### If You're Reviewing the Audit
Key docs to review in order:
1. `CORE_MIGRATION_OVERVIEW.md` - Executive summary (10 min read)
2. `CORE_PORTABILITY_RULES.md` - Decision framework for what moves to core
3. `IOS_CORE_FEASIBILITY.md` - iOS is source of truth, has detailed component tables

### Critical Architectural Decisions Made
- **C++ core with C ABI** (NOT Python/Go for mobile runtime)
- **Core = decisions + transforms, Wrappers = side effects**
- **Platform adapters for HTTP, FileSystem, SecureStorage, Logger**
- **Batched streaming** to minimize FFI overhead (10-50 tokens per callback)

## Quick Reference

### Move to Core (High Priority)
| Component | Why | Effort |
|-----------|-----|--------|
| RoutingDecisionEngine | KMP only, backport to iOS | M |
| SimpleEnergyVAD | Pure math, duplicated 4x | S |
| ModelLifecycleManager | State machine, duplicated 4x | S |
| EventPublisher | Event routing | S |
| ModuleRegistry | Plugin architecture | M |

### Keep in Wrappers
AudioCaptureManager, AudioPlaybackManager, SystemTTS, KeychainManager, DeviceIdentity, SentryManager

### Measurements Needed Before Starting
- SDK size (MB) per platform
- Init time (ms) per platform
- Memory with model loaded
- STT/LLM/TTS latencies

## Document Locations
All docs in `docs/core-migration/`:
- Overview + rules: `CORE_MIGRATION_OVERVIEW.md`, `CORE_PORTABILITY_RULES.md`
- Per-SDK analysis: `IOS_CORE_FEASIBILITY.md`, `ANDROID_CORE_FEASIBILITY.md`, `FLUTTER_CORE_FEASIBILITY.md`, `RN_CORE_FEASIBILITY.md`
- Unified plan: `CORE_COMPONENT_CANDIDATES.md`, `CORE_API_BOUNDARY_SPEC.md`, `BINDINGS_AND_PACKAGING_PLAN.md`, `MIGRATION_SEQUENCE.md`

---
*Last updated: December 2025*
