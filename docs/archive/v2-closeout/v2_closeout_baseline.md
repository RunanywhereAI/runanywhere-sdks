# v2 close-out — baseline LOC snapshot

_Captured at the start of Phase 0, before any deletes. Used by Phase 16 to compute the actual LOC delta delivered._

Branch: `feat/v2-architecture` @ `05fbe602` (`docs(v2-audit): post-Wave-F reality check + prioritized remaining work`).

| # | File | Baseline LOC | Spec target |
|---|------|--------------|-------------|
| 1 | `sdk/runanywhere-kotlin/.../public/extensions/RunAnywhere+VoiceAgent.jvmAndroid.kt` | 494 | ~150 (delete orchestration) |
| 2 | `sdk/runanywhere-kotlin/.../foundation/bridge/extensions/CppBridgeAuth.kt` | 567 | 0 (delete file) |
| 3 | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+TextGeneration.swift` | 554 | ~400 (delete `ThinkingContentParser`) |
| 4 | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/RunAnywhere+VoiceSession.swift` | 396 | ~120 (delete orchestration) |
| 5 | `sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Download/Services/AlamofireDownloadService.swift` | 470 | ~290 (delete retry/progress) |
| 6 | `sdk/runanywhere-flutter/packages/runanywhere/lib/public/runanywhere.dart` | **2,688** | **≤ 500** (GAP 08 #4) |
| 7 | `sdk/runanywhere-flutter/packages/runanywhere/lib/capabilities/voice/models/voice_session_handle.dart` | 472 | ~100 (delete orchestration) |
| 8 | `sdk/runanywhere-react-native/packages/core/src/Features/VoiceSession/VoiceSessionHandle.ts` | 636 | **≤ 250** (GAP 08 #5) |
| 9 | `sdk/runanywhere-web/packages/llamacpp/src/Extensions/RunAnywhere+TextGeneration.ts` | 609 | ~430 (delete tokenQueue) |
| 10 | `sdk/runanywhere-web/packages/core/src/Foundation/EventBus.ts` | 203 | ~125 (delete legacy block) |
| **Total target files** | | **7,089** | **~2,165** |

**Expected delete budget:** ~7,089 - 2,165 = **~4,924 LOC** (matches the v2_remaining_work.md estimate of ~4,860).

## Notes

- The lightweight `lib/runanywhere.dart` (40 LOC) is a re-export shim; the actual large file is `lib/public/runanywhere.dart` (2,688 LOC). This doc tracks the latter (the spec target).
- `CppBridgeAuth.kt` is a **full file delete** (`git rm`), not a shrink — that's why the "spec target" column reads `0`.
- The **Kotlin orphan native declarations** (P2-3) are not in this table because they live across 14 different `CppBridge*.kt` files; they're tracked separately in [`gap08_kotlin_orphan_natives.md`](gap08_kotlin_orphan_natives.md). Today's count: 88 declarations across the 14 files.

## How Phase 16 closes the loop

After all deletes land, Phase 16 re-runs the `wc -l` against this same list and produces a delta table in `docs/v2_closeout_results.md`. Each row gets one of three statuses:
- **MET** — actual ≤ spec target
- **PARTIAL** — actual < baseline but > spec target (still a win, but flag for follow-up)
- **MISSED** — file unchanged or grew

That table flips `gap08_final_gate_report.md` rows from PARTIAL/MISSING to OK.
