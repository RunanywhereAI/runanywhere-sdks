# API Realignment 2026-08: change log

Mechanically generated from the review's own source-of-truth JSON (`proposals.json`, `seed.json`, care plans, edit records) against commit [`07907b273`](https://github.com/RunanywhereAI/runanywhere-sdks/commit/07907b273) (`idl: apply 194 approved API simplification decisions across 37 proto files`). Do not hand-edit this file — regenerate it from `gen_api_changes_audit.py` if the source data changes.

## Summary

| Bucket | Count |
|---|---:|
| Approved, real proto edit | 194 |
| Approved anti-proposals (decision NOT to change the proto) | 10 |
| Declined | 33 |
| **Total reviewed** | 243 |


## Changes by domain


<details>
<summary><strong>core</strong> (10 changes)</summary>

### `core-delete-public-api-v4` — Delete public_api_v4.proto entirely; move AcceleratorPolicy into model_types.proto

**Proto location:** [public_api_v4.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/public_api_v4.proto#L1), [public_api_v4.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/public_api_v4.proto#L8), [public_api_v4.proto (AcceleratorPolicy)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/public_api_v4.proto#L33), [model_types.proto (ModelLoadRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L561)

**Why:** A newcomer opening idl/ finds a file whose own header calls it the public stream contract ("Public stream consumers project these Public* messages") and reasonably builds against it. Nothing reads it: 16 messages and 4 enums are code-generated into eight SDKs with zero hand-written consumers, and the facades that were meant to project it hand-rolled divergent copies instead. The only live thing in the file is AcceleratorPolicy, and model_types.proto refers to it as an untyped int32 to dodge a circular import.

**Skeptic verdict:** `risky` — Dropping 'optional' on accelerator_policy deletes has_accelerator_policy(), which commons calls at model_lifecycle.cpp:659-660 to decide whether to report the knob as unsupported; the proposal is labelled breaking:false. Enum count is 5, not 4.

**What changed:** Deleted idl/public_api_v4.proto outright (all 16 messages and 5 enums) and moved AcceleratorPolicy into idl/model_types.proto immediately above ModelLoadRequest, keeping values 0-4 and adding the rac_wire_string annotations (model_types.proto already imported rac_options.proto). Retyped ModelLoadRequest.accelerator_policy = 10 from `optional int32` to `optional AcceleratorPolicy`, keeping the `optional` keyword per carePlan.correctionNeeded, and deleted the now-false comment that said AcceleratorPolicy lives in public_api_v4.proto.

**Files touched:** `model_types.proto`, `public_api_v4.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** 1) Explicit presence: `has_accelerator_policy()` is called at three sites, not the one the skeptic named — sdk/runanywhere-commons/src/core/model_lifecycle.cpp:659 (decides whether to report the knob as unsupported), sdk/runanywhere-commons/src/core/model_lifecycle.cpp:862 (NPU-requested-but-engine-cannot warning), and sdk/runanywhere-commons/src/core/model_lifecycle_translation.cpp:435 (emits it into load_options_json). Dropping `optional` deletes the accessor at all three and they stop compiling. 2) commons never includes public_api_v4.pb.h; it hardcodes the enum values as local constants a…

**Wire safety:** AcceleratorPolicy values 0-4 are preserved verbatim, and an enum field and an int32 field are both varint on the wire, so relocating the enum and retyping ModelLoadRequest.accelerator_policy = 10 is wire-neutral. The ONE wire/API detail that is not neutral: the after-text drops `optional`. Field 10 must stay `optional AcceleratorPolicy accelerator_policy = 10;` or explicit presence disappears. pu…

**Do first:**
  1. Fix the item's own arithmetic first: `rg -c '^enum ' idl/public_api_v4.proto` returns 5, not 4. Correct the count before the commit message quotes it.
  1. Move the enum into idl/model_types.proto next to ModelLoadRequest, keeping values 0-4 and adding the rac_wire_string annotations. model_types.proto already imports rac_options.proto for SDKEnvironment's annotations (idl/model_types.proto:124-126), so no new import is needed there.
  1. Retype field 10 as `optional AcceleratorPolicy accelerator_policy = 10;` — KEEP the `optional` keyword. Do not drop it.
  1. In the same commit, replace the local constants at sdk/runanywhere-commons/src/core/model_lifecycle.cpp:161-162 with the real enum values (::runanywhere::v1::ACCELERATOR_POLICY_UNSPECIFIED / _NPU) and fix the now-stale file references in the comments at model_lifecycle.cpp:156-157, :641, :859, :1025 and model_lifecycle_internal.h:212.
  1. Regenerate all eight SDKs and delete the orphaned generated artifacts by hand: sdk/runanywhere-swift/Sources/RunAnywhere/Generated/public_api_v4.pb.swift, sdk/shared/proto-ts/src/public_api_v4.ts, and the ~20 files under sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/ai/runanywhere/proto/v1/ that came only from this file. Stale generated files do not delete themselves.
  1. Land this BEFORE core-capabilities-shrink, which re-declares the one message worth keeping.


### `core-delete-unused-knobs` — Delete two never-read knobs: mic_tap_buffer_frames and rac_analytics_key

**Proto location:** [sdk_defaults.proto (AudioCaptureDefaults)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_defaults.proto#L164), [sdk_defaults.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_defaults.proto#L3), [rac_options.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rac_options.proto#L49), [rac_options.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rac_options.proto#L46)

**Why:** Both are exactly what the default pool is meant to prevent. mic_tap_buffer_frames is emitted into six generated pools (Swift, Kotlin, Dart, TS, Python, C) and read by no commons or SDK source, so an author tuning capture latency finds it, sets it, and observes nothing. rac_analytics_key is declared as extension 50011 and applied by no .proto file in the repo — a concept in the annotation vocabulary with no instances (unlike rac_display_name, which logging.proto does use).

**Skeptic verdict:** `risky` — 'reserved 50011;' inside an extend block is a protoc syntax error (verified with protoc 35.1), and rac_analytics_key is consumed by five codegen files plus the design doc, not by zero consumers.

**What changed:** Half A only: deleted AudioCaptureDefaults.mic_tap_buffer_frames from idl/sdk_defaults.proto outright (no `reserved`, per the no-backwards-compat rule) and renumbered tts_sample_rate_hz from 5 to 4 to keep the pool dense. Half B (rac_analytics_key) was NOT applied - see note.

**Files touched:** `sdk_defaults.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** Half A: nothing found — and here are the greps that came back empty. `rg -n "mic_tap_buffer_frames|micTapBufferFrames|MIC_TAP_BUFFER_FRAMES|MicTapBufferFrames" sdk idl examples starters` returns ten hits and every single one is a generated constant or the proto declaration itself: idl/sdk_defaults.proto:164; sdk/runanywhere-commons/include/rac/rac_defaults_generated.h:110; sdk/runanywhere-swift/Sources/RunAnywhere/Generated/RADefaultsPool.swift:33; sdk/runanywhere-kotlin/.../generated/RADefaultsPool.kt:35; sdk/runanywhere-flutter/.../generated/RADefaultsPool.kt:35 and lib/generated/ra_default…

**Wire safety:** Half A (mic_tap_buffer_frames): AudioCaptureDefaults is an annotation-carrier pool, not a serialised type, so `reserved 4; reserved "mic_tap_buffer_frames";` is belt-and-braces and costs nothing. Half B (rac_analytics_key): NOT wire-safe as written — `reserved 50011;` inside an `extend google.protobuf.EnumValueOptions` block is a protoc syntax error (skeptic reproduced it on protoc 35.1). Extensi…

**Do first:**
  1. Split the item into two commits. They share nothing but a severity label.
  1. Commit A (mic_tap_buffer_frames) — this one is genuinely routine. Apply `reserved 4; reserved "mic_tap_buffer_frames";` to AudioCaptureDefaults (idl/sdk_defaults.proto:164), regenerate, and delete the ten stale generated constants listed above. Note two of them live in vendored copies under sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include/ and sdk/runanywhere-flutter/.../android/src/main/kotlin/.../generated/ — those get refreshed from commons, not from a local codegen run, so check they actually change.
  1. Commit B (rac_analytics_key) — do NOT ship it this pass. It requires deleting the annotation handling from five codegen files, the fixture usages at idl/codegen/tests/fixtures/test_options.proto:47,52, the golden expectations, the design doc rows at CONVENIENCE_CODEGEN_DESIGN.md:46,56,211, and three generated public bindings. That is a codegen-vocabulary change, not a dead-field deletion, and the item's own framing ('applied by no .proto file in the repo') is factually wrong.
  1. If commit B does go ahead later: the retirement marker must be a comment, not `reserved` — e.g. `// 50011 retired (was rac_analytics_key); do not reuse.` inside the extend block.


### `core-error-category-wire-string` — Give ErrorCategory's 9 values a rac_wire_string so eight SDKs print the same word

**Proto location:** [errors.proto (ErrorCategory)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/errors.proto#L20), [errors.proto (ErrorCategory)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/errors.proto#L25), [rac_options.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rac_options.proto#L53), [model_types.proto (SDKEnvironment)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L124)

**Why:** ErrorCategory is the enum an app is most likely to render in a crash report or a log line, and it is the only major enum in the repo with neither a wire string nor a display name — so the three SDKs whose native idiom is JSON each pick their own form (a raw int, the SCREAMING_SNAKE constant, or a hand-written map) and two SDKs then disagree about what to write for the same failure. The annotation already exists and is already applied in logging.proto and model_types.proto.

**Skeptic verdict:** `sound` — The after-text omits the required 'import "rac_options.proto";' in errors.proto, which today has no imports at all.

**What changed:** Annotated all 9 ErrorCategory values in idl/errors.proto with the approved rac_wire_string values (unspecified, network_error, invalid_request_error, model_error, component_error, io_error, authentication_error, internal_error, configuration_error) and added the `import "rac_options.proto";` errors.proto lacked. Kept the per-value trailing comments and applied the after-text's corrected header comment.

**Files touched:** `errors.proto`

**Status:** `applied`


### `core-error-component-honest` — Make SDKError.component's documented lowercase form real via rac_wire_string

**Proto location:** [errors.proto (SDKError)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/errors.proto#L270), [errors.proto (SDKError)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/errors.proto#L274), [sdk_events.proto (SDKComponent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L91)

**Why:** The proto says component is "a stable lowercase key (\"llm\", \"stt\", \"rag\", \"download\")" and commons writes SDKComponent_Name(component), which yields SDK_COMPONENT_LLM. Any consumer that follows the comment and matches on "llm" never matches, on every platform, silently — and this is the field an app uses to route an error to a feature area, so the failure mode is a diagnostics screen that buckets everything as unknown. The comment is also misplaced: it sits above timestamp_ms, three fields from the field it describes.

**Skeptic verdict:** `sound` — Only omission: sdk_events.proto must gain 'import "rac_options.proto";' or the rac_wire_string options are undeclared; and the commons fix (two SDKComponent_Name call sites) must land in the same commit or the comment is still a lie.

**What changed:** Added `import "rac_options.proto";` to idl/sdk_events.proto (it had no such import, so the after-text would not have compiled) and annotated all 14 SDKComponent values with rac_wire_string, not just the five shown. In idl/errors.proto I moved the misplaced comment off timestamp_ms and onto SDKError.component where it belongs, and rewrote it to require the wire string.

**Files touched:** `errors.proto`, `sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Two producers, both in commons, both confirmed: sdk/runanywhere-commons/src/infrastructure/events/event_publisher.cpp:179 (`error->set_component(runanywhere::v1::SDKComponent_Name(component))`) and sdk/runanywhere-commons/src/core/model_lifecycle_translation.cpp:397 (`event.mutable_error()->set_component(runanywhere::v1::SDKComponent_Name(component))`). Those are the only two — `rg -n 'SDKComponent_Name' sdk idl --glob '!**/generated/**' --glob '!**/*.pb.*'` returns exactly those two lines. The complication the item does not name: the facades already write a THIRD vocabulary into the same fie…

**Wire safety:** No field-number change; SDKError.component stays `string` at tag 9. The wire VALUE changes from "SDK_COMPONENT_LLM" to "llm" — a content break, not a schema break, so protobuf will not warn anyone. rac_wire_string is an EnumValueOption (extension 50012 per idl/rac_options.proto), so adding it to SDKComponent changes no bytes of sdk_events.proto's own encoding.

**Do first:**
  1. Add `import "rac_options.proto";` to idl/sdk_events.proto before adding any rac_wire_string option — it is not imported today.
  1. Annotate all 14 SDKComponent values (idl/sdk_events.proto:91 onward), not just the five shown in the after-text. A partially annotated enum makes SDKComponent_wire_string() return empty for the rest, which is worse than SCREAMING_SNAKE.
  1. In the SAME commit, change both producers — event_publisher.cpp:179 and model_lifecycle_translation.cpp:397 — from SDKComponent_Name(component) to the wire-string lookup. Landing the annotation without the producer change leaves the comment a lie, which is the entire defect.
  1. Decide what to do about Web's parallel vocabulary at SDKException.ts:81-97 (componentForCode) in the same pass, or say explicitly in the field comment that platform-constructed errors may carry a non-SDKComponent key. Do not leave the comment claiming a single vocabulary that two producers disagree on.
  1. Move the comment: it currently sits at idl/errors.proto:270-271 above timestamp_ms (272), two fields away from component (274).


### `core-init-result-shrink` — Shrink SdkInitResult 10 fields to 5, delete SdkInitPhase, add the missing reserved 2

**Proto location:** [sdk_init.proto (SdkInitPhase)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_init.proto#L23), [sdk_init.proto (SdkInitResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_init.proto#L65), [sdk_init.proto (SdkInitResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_init.proto#L71)

**Why:** Six of ten fields are noise an SDK author must read the C++ to discount: phase, device_registered, discovered_orphans and duration_ms are written by commons and read by no SDK, and three overlapping booleans encode network readiness (Swift ORs two of them together on every read). discovered_orphans is actively misleading — commons hardcodes it to 0, so a storage-cleanup screen built on it always says zero. Tag 2 was retired without a `reserved`, so it can be silently reused.

**Skeptic verdict:** `risky` — Two of the six 'write-only' fields have hand-written readers (Kotlin reads .phase; Swift/Kotlin/Web all read http_configured), so the blast radius is not 'commons' producer code plus generated accessors'.

**What changed:** Deleted enum SdkInitPhase from idl/sdk_init.proto and cut SdkInitResult from 10 fields to 5, removing phase, http_configured, device_registered, discovered_orphans and duration_ms. Rather than the after-text's `reserved 1, 2, 4, 5, 7, 9;` block I deleted them outright and renumbered the survivors densely 1-5 (error=1, linked_models_count=2, warning=3, has_completed_http_setup=4, http_applicable=5), which also closes the never-reserved tag-2 hole the item flagged. Fixed the SdkInitResult header comment, which cited the deleted http_configured.

**Files touched:** `sdk_init.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Four of the six 'write-only' fields have live hand-written readers. phase: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeSdkInit.kt:126 interpolates `result.phase` into the failure message. http_configured, which is on the delete list, is read on SIX platforms: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift:467 and :564 (`phase2Result.hasCompletedHTTPSetup_p || phase2Result.httpConfigured`), sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt:696 and :841, sdk/runanywhere-web/packages/core/src/…

**Wire safety:** Wire-breaking by design. `reserved 1, 2, 4, 5, 7, 9;` plus the name reservations is correct and the missing `reserved 2` is genuinely free (tag 2 is absent today with no reserved — verified by reading idl/sdk_init.proto:65-84). Add "has_completed_http_setup" NOWHERE — tags 10 and 11 survive unchanged. One extra hazard the proposal misses: sdk/runanywhere-react-native/packages/core/cpp/bridges/Ini…

**Do first:**
  1. Commit 1 (commons, no proto change): make has_completed_http_setup true at every site where http_configured is set true today — sdk_init.cpp:267/268, :309/310, :343/344, :355/356, :376/377 already do both, so the only real work is confirming the false-paths (:293, :316, :321, :329, :338, :362, :371) leave the latched bit correct on a retryHTTP. Ship and let it soak one release, so the OR-fallback in every facade is provably redundant.
  1. Commit 2 (facades, still no proto change): collapse every `X || httpConfigured` read to the latched bit alone at RunAnywhere.swift:467 and :564, RunAnywhere.kt:696 and :841, SDKCore.ts:891 and :1232, runanywhere.dart:478 and dart_bridge.dart:336, RunAnywhere.ts:124, bootstrap.cpp:456. Drop deviceRegistered/discoveredOrphans/durationMs from the Flutter log map at dart_bridge.dart:337,339,341 and drop `device_registered()` from bootstrap.cpp:457-458.
  1. Commit 2 also: replace the Kotlin `result.phase` interpolation at CppBridgeSdkInit.kt:126 with a static string, or the SdkInitPhase deletion will not compile.
  1. Commit 3 (proto): apply the reserved block, delete enum SdkInitPhase, remove the six producer calls in sdk_init.cpp, regenerate all eight SDKs.
  1. Do NOT collapse commits 1 and 3. Between them, an SDK built against the new proto and an older commons binary is exactly the configuration where 'http_configured was the only true bit' would silently report the SDK as offline.


### `core-init-timeout-retries` — Add request_timeout_ms and max_retries to init - the two knobs every client has

**Proto location:** [sdk_init.proto (SdkInitPhase1Request)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_init.proto#L40), [sdk_defaults.proto (NetworkDefaults)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_defaults.proto#L55), [sdk_defaults.proto (NetworkDefaults)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_defaults.proto#L94), [sdk_defaults.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_defaults.proto#L4)

**Why:** This is the one place the domain is missing something rather than carrying too much. Timeout and retry count exist only as build-time constants in a pool whose own header says the messages are not wire types, so an app downloading a 4 GB model over a weak link cannot raise the timeout, and an app that wants to fail fast at a splash screen cannot lower it. Tuning them today means a proto edit, a codegen run and eight SDK releases.

**Skeptic verdict:** `risky` — The proposed snippet does not compile: sdk_init.proto never imports rac_options.proto, so the rac_min options are undeclared, and the snippet also presumes core-one-environment-enum has already landed.

**What changed:** Added `optional int32 request_timeout_ms = 7 [(rac_min) = 1000]` and `optional int32 max_retries = 8 [(rac_min) = 0, (rac_max) = 10]` to SdkInitPhase1Request in idl/sdk_init.proto, and added the `import "rac_options.proto";` the options require (sdk_init.proto imported only errors.proto before, which is why the after-text as written would not have compiled). Per carePlan.correctionNeeded I dropped the after-text's `SDKEnvironment environment = 1;` line from this item (it belongs to core-one-environment-enum, which I landed first) and dropped the claim 'Commons is the single place that applies it' from the field comment, since grep found zero commons consumers of max_retries. sdk_defaults.proto keeps NetworkDefaults.request_timeout_ms and .max_retries unchanged as the default declaration.

**Files touched:** `sdk_init.proto`

**Status:** `applied`

**Care level:** `blocked`

**What could break:** Nothing breaks — the change is additive — but it does not WORK either, and that is the real finding. No commons translation unit reads the timeout or the retry budget today: `rg -n 'RAC_DEFAULT_NETWORK_REQUEST_TIMEOUT_MS|RAC_DEFAULT_NETWORK_MAX_RETRIES|request_timeout_ms|max_retries' sdk/runanywhere-commons/src sdk/runanywhere-commons/include --glob '!**/generated/**'` returns exactly three hits, and none of them is a consumer: sdk/runanywhere-commons/include/rac/rac_defaults_generated.h:93 and :99 are the generated macro definitions, and sdk/runanywhere-commons/src/features/llm/structured_ou…

**Wire safety:** Additive only. Tags 7 and 8 are free on SdkInitPhase1Request (existing fields are 1-6 at idl/sdk_init.proto:40-47). `optional` on both is the right call and matches the presence trap the brief flags. No reserved needed. One hazard: sdk/runanywhere-react-native/packages/core/cpp/bridges/InitBridge.cpp:985-993 hand-writes the phase-1 request bytes field by field, so RN will simply never send tags 7…

**Do first:**
  1. PREREQUISITE (this is why the item is blocked): write the commons consumer first. A commit that makes rac_http_transport honour a per-client timeout and a per-client retry budget, defaulting to RAC_DEFAULT_NETWORK_REQUEST_TIMEOUT_MS (60000) and RAC_DEFAULT_NETWORK_MAX_RETRIES (3) from rac_defaults_generated.h:93,99. Until that exists there is nothing for the field to feed.
  1. Add `import "rac_options.proto";` to idl/sdk_init.proto (it currently imports errors.proto only, line 12) or the rac_min/rac_max options will not compile.
  1. Strip the `SDKEnvironment environment = 1;` line out of this proposal's diff — it belongs to core-one-environment-enum. As written the two items conflict on the same line of the same message. Land core-one-environment-enum first, then this one, and this diff becomes purely additive.
  1. Extend sdk/runanywhere-react-native/packages/core/cpp/bridges/InitBridge.cpp:985-999 (makePhase1RequestBytes) to append tags 7 and 8, or RN silently ignores both knobs.


### `core-one-environment-enum` — Delete SdkInitEnvironment and use SDKEnvironment; unset today silently means dev

**Proto location:** [sdk_init.proto (SdkInitEnvironment)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_init.proto#L30), [sdk_init.proto (SdkInitPhase1Request)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_init.proto#L41), [model_types.proto (SDKEnvironment)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L123)

**Why:** Two enums express one concept with three different wire numbers for the two real values, so every SDK hand-writes a mapper between them. Worse for a newcomer: SdkInitEnvironment's proto3 zero is DEVELOPMENT, not UNSPECIFIED, so an omitted field means "talk to the development control plane", and Swift's mapper has a `default:` arm that fails in the same direction. A production build can fall through to development without a compile error.

**Skeptic verdict:** `risky` — An 'approve' on a change that retires a wire value already emitted by shipped binaries, and that drags model_types.proto's four-deep import graph into sdk_init.proto for one enum. The two-release compat shim is a hard prerequisite, not a note.

**What changed:** Deleted enum SdkInitEnvironment from idl/sdk_init.proto, added `import "model_types.proto";`, and retyped SdkInitPhase1Request.environment = 1 to SDKEnvironment. model_types.proto's SDKEnvironment is untouched and remains the single declaration. I did NOT write the after-text's 'commons accepts the retired value 2 as PRODUCTION for one release' comment: no backwards compatibility is required this wave, and that comment would describe commons behaviour that does not exist. The comment I wrote instead states the real, checkable fact that the zero value is now UNSPECIFIED, so unset no longer silently means development.

**Files touched:** `sdk_init.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** 1) commons: sdk/runanywhere-commons/src/lifecycle/sdk_init.cpp:59 (`using ::runanywhere::v1::SdkInitEnvironment`), :66 (`rac_environment_t to_rac_environment(SdkInitEnvironment env)`), :527 (`to_rac_environment(request.environment())`). 2) CLI: sdk/runanywhere-cli/src/bootstrap.cpp:184-190 declares a function returning `::runanywhere::v1::SdkInitEnvironment` and returns SDK_INIT_ENVIRONMENT_PRODUCTION / SDK_INIT_ENVIRONMENT_DEVELOPMENT — a compile break. 3) The one the proposal does not mention and that no recompile will catch: sdk/runanywhere-react-native/packages/core/cpp/bridges/InitBridge…

**Wire safety:** The dangerous one. Today SdkInitEnvironment is {DEVELOPMENT=0, PRODUCTION=2}; SDKEnvironment is {UNSPECIFIED=0, DEVELOPMENT=1, PRODUCTION=3} with 2 reserved (idl/model_types.proto:120-126). Every shipped binary that sends 2 means PRODUCTION; after the swap 2 is a reserved hole and 0 flips meaning from DEVELOPMENT to UNSPECIFIED. Both directions of that are silent. Commons MUST accept 2 as product…

**Do first:**
  1. Release N-1, commons only, no proto change: rewrite to_rac_environment (sdk/runanywhere-commons/src/lifecycle/sdk_init.cpp:66) so it switches on the raw int and maps {2, 3} -> production, {1} -> development, and {0} -> a hard failure returning an SDKError, NOT a silent development fallback. Ship it. The compat shim must be in the field BEFORE the enum swap, not alongside it.
  1. Same release: audit every `default:` arm on an environment switch and make it fail closed. `rg -n 'SDK_ENVIRONMENT_|SDK_INIT_ENVIRONMENT_' sdk --glob '!**/generated/**'` is the list; sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/infrastructure/logging/SDKLogger.kt:55-58 is one to check.
  1. Release N: swap the proto. Add `import "model_types.proto";` to idl/sdk_init.proto, delete enum SdkInitEnvironment, retype field 1. Fix sdk/runanywhere-cli/src/bootstrap.cpp:184-190 in the same commit.
  1. Release N, same commit: remap RN's hand-rolled encoder at sdk/runanywhere-react-native/packages/core/cpp/bridges/InitBridge.cpp:993 from `static_cast<uint64_t>(environment)` to an explicit rac_environment_t -> SDKEnvironment table. This will not fail to compile if you forget it — it will just keep shipping the old numbers.
  1. Release N+1 at the earliest: drop the value-2 acceptance from to_rac_environment. Not before.


### `core-phase2-one-field` — Reduce SdkInitPhase2Request to build_token alone; callers already pass literals

**Proto location:** [sdk_init.proto (SdkInitPhase2Request)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_init.proto#L49), [sdk_init.proto (SdkInitPhase2Request)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_init.proto#L54)

**Why:** Five fields exist to parameterise a call no app is supposed to make: the only caller passes literals (false, true, true, true) with build_token empty. The IDL is what keeps a second startup phase alive — Web's facade already says there is no second phase and Swift marks completeServicesInitialization deprecated. flush_telemetry is also a proto3 presence trap: its zero is false while the only caller wants true.

**Skeptic verdict:** `sound` — Only gap: the after-text's comment implies commons 'always' does the work, but force_refresh_assignments must be pinned false (not true) to preserve behaviour, and four public bridge parameters disappear from Swift/Kotlin/Python call sites in the same commit.

**What changed:** Reduced SdkInitPhase2Request in idl/sdk_init.proto to `string build_token = 1;` alone, deleting force_refresh_assignments, flush_telemetry, discover_downloaded_models and rescan_local_models outright with no `reserved` block (no backwards compatibility required this wave). Per carePlan.doFirst I did not write the after-text's 'Commons always flushes telemetry and always reconciles...; every caller already passed those literals' comment, because that literals claim is false for React Native and Flutter; the comment now only says telemetry flushing and reconciliation are commons behaviour rather than per-call hints.

**Files touched:** `sdk_init.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** 1) Compile break in the CLI: sdk/runanywhere-cli/src/bootstrap.cpp:424-426 calls set_flush_telemetry(true), set_discover_downloaded_models(true), set_rescan_local_models(true). 2) React Native carries the four booleans all the way up to its PUBLIC config surface: sdk/runanywhere-react-native/packages/core/src/types/models.ts:29-41 declares buildToken/forceRefreshAssignments/flushTelemetry/discoverDownloadedModels/rescanLocalModels as optional config fields; sdk/runanywhere-react-native/packages/core/cpp/HybridRunAnywhereCore.cpp:86-90 reads them out of configJson with defaults (false, true, t…

**Wire safety:** `reserved 2, 3, 4, 5;` plus names is correct and necessary — more necessary than usual, because sdk/runanywhere-react-native/packages/core/cpp/bridges/InitBridge.cpp:1002-1012 writes those four tags as raw bytes (`appendBoolField(bytes, 2, forceRefreshAssignments)` … `appendBoolField(bytes, 5, rescanLocalModels)`) and will keep doing so until someone edits that function. Reserved tags turn RN's s…

**Do first:**
  1. Before writing any proto, confirm the behaviour you are pinning. force_refresh_assignments must be hardcoded FALSE in commons (every caller passes false: Swift's default, RN's HybridRunAnywhereCore.cpp:88 default, RunAnywhere.ts:298). flush_telemetry / discover_downloaded_models / rescan_local_models pin to TRUE. The after-text's comment says commons 'always' does the work — write it so it does not imply force_refresh is now always on.
  1. Grep the downstream app repos, not just this one, for the RN config keys: `rg -n 'forceRefreshAssignments|flushTelemetry|discoverDownloadedModels|rescanLocalModels' <app repos>`. They are typed public config at types/models.ts:29-41, so an app may be setting them.
  1. Commit 1 (commons): hardcode the four behaviours, keep reading the fields but ignore them, ship. This makes the proto fields inert without any caller changing.
  1. Commit 2 (callers): delete the four parameters from sdk/runanywhere-cli/src/bootstrap.cpp:424-426, RN's InitBridge.hpp:65-67 + InitBridge.cpp:1002-1012,1645-1647,1726-1729 + HybridRunAnywhereCore.cpp:86-90 + types/models.ts:29-41 + RunAnywhere.ts:297-301, Flutter dart_bridge.dart:325-330 and its callers, Swift CppBridge+SdkInit.swift:100-103 + RunAnywhere.swift:462-465, Python _runtime.py:222-225. RN and Flutter are the two that need a deprecation note in the package CHANGELOG because the knobs were public.
  1. Commit 3 (proto): reserve 2-5, delete the four fields, regenerate.


### `core-sdk-error-four-fields` — Delete ErrorContext and remediation_hint; flatten field_path to param on SDKError

**Proto location:** [errors.proto (ErrorContext)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/errors.proto#L235), [errors.proto (SDKError)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/errors.proto#L256), [errors.proto (SDKError)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/errors.proto#L276), [errors.proto (SDKError)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/errors.proto#L277)

**Why:** SDKError is the one type every app writes a catch block against, and a third of it is guaranteed empty on every platform: remediation_hint and correlation_id have no producer anywhere (Web writes "" into both at seven construction sites), and four of ErrorContext's five fields have no producer either. A developer reading `remediation_hint` assumes there is a hint to show a user. ErrorContext costs a nested message and a null-check on every error path to deliver one string that OpenAI puts flat on the error object as `param`.

**Skeptic verdict:** `risky` — ErrorContext is not dead surface: 3 facade SDKException factories and 4 convenience-codegen generators construct it today, and the risk section lists none of them. The correlation_id->request_id rename is a silent JSON wire-name change.

**What changed:** In idl/errors.proto: deleted message ErrorContext entirely, deleted SDKError.remediation_hint, renamed correlation_id to request_id, and added `optional string param` carrying the flattened field_path. Deleted rather than reserved tags 4 and 11, and renumbered SDKError densely 1-11. Folded ErrorContext's surviving 'stack traces are deliberately absent' rationale into the SDKError header comment, and fixed the ErrorCategory comment that cited the deleted ErrorContext.operation.

**Files touched:** `errors.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** ErrorContext is NOT dead surface. Four facades construct it by hand today: sdk/runanywhere-flutter/packages/runanywhere/lib/foundation/errors/sdk_exception.dart:69 (`err.context = pb.ErrorContext(fieldPath: fieldPath)`), sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/errors/SDKException.kt:18,237 (`ProtoErrorContext(...)`), sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Errors/SDKException.swift:209 (`var context = RAErrorContext()`), sdk/runanywhere-react-native/packages/core/src/Foundation/Errors/SDKException.ts:16,51,118,237,245 (getter + construction). Two of …

**Wire safety:** `reserved 4, 11;` + name reservations is right. Two things the after-text does not say: (a) tag 12 is being REUSED with a new name — correlation_id -> request_id at idl/errors.proto:277. The binary wire is unchanged (both are string, tag 12) but proto3-JSON emits a different key, so any JSON-transport consumer silently loses the value; if you want that to be safe, reserve 12 and use a fresh tag i…

**Do first:**
  1. Commit 1 (proto, additive only): add `optional string param = 13;` (or field_path under whatever name wins) and `string request_id = 12` as a NEW tag if you take the safe route — do not delete anything yet.
  1. Commit 2 (generators): update all four convenience generators to emit the flat field instead of `context.metadata["field_path"]` — generate_kotlin_convenience.py:236-242, generate_swift_convenience.py:252-265, generate_ts_convenience.py:501-507, generate_dart_convenience.py:549-621 — and regenerate idl/codegen/tests/golden/*.expected. `python -m pytest idl/codegen/tests/test_convenience_generators.py` is the gate.
  1. Commit 3 (facades): rewrite the four SDKException constructors (sdk_exception.dart:69, SDKException.kt:237, SDKException.swift:209, SDKException.ts:237-245) to set the flat field, and delete the public re-exports at runanywhere-web/src/index.ts:142, runanywhere-web/src/internal.ts:130, runanywhere-react-native/src/index.ts:207 with a deprecation note in each package's CHANGELOG.
  1. Commit 4 (proto, destructive): reserve 4 and 11, delete message ErrorContext, and fix the stale ErrorCategory comment at idl/errors.proto:20-22 that still cites ErrorContext.operation — same commit, non-negotiable.
  1. Decide request_id before commit 1, not after: if no producer will populate it this pass, leave it out. A second guaranteed-empty field is exactly the defect this item is removing.


### `core-token-usage-one-timing-block` — Rename tokens_per_second to decode_tokens_per_second; one home for TTFT

**Proto location:** [token_usage.proto (TokenUsage)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/token_usage.proto#L19), [token_usage.proto (TokenUsage)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/token_usage.proto#L23), [llm_options.proto (LLMGenerationResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L82), [llm_service.proto (LLMStreamFinalResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L41)

**Why:** tokens_per_second is the headline number of the whole SDK and its definition is unstated: nothing says whether it counts output only or input plus output, or whether prefill time is included, so the value is not comparable between two backends or two releases. Meanwhile time-to-first-token is spelled three ways in two integer widths across three protos (llm_options.ttft_ms as double, llm_service and vlm_options as int64 time_to_first_token_ms), so a cross-modality metrics screen needs three code paths.

**Skeptic verdict:** `risky` — Renaming the single most-consumed metric in the repo (188 hand-written references) plus a silent proto3-JSON key change, to buy a semantics statement that a comment on tag 4 delivers for free.

**What changed:** In idl/token_usage.proto renamed TokenUsage.tokens_per_second to decode_tokens_per_second (tag 4, still double) with the llama.cpp-referenced definition, and added `int64 prefill_ms = 5` and `int64 ttft_ms = 6`. Deleted the three duplicate TTFT spellings: llm_options.proto LLMGenerationResult.ttft_ms (tag 7), llm_service.proto LLMStreamFinalResult.time_to_first_token_ms (tag 7), vlm_options.proto VLMResult.time_to_first_token_ms (tag 8). All three messages already embed TokenUsage, so TTFT has a home. Deleted outright with no `reserved`, and left the surrounding already-sparse tag numbering alone rather than renumbering unrelated fields.

**Files touched:** `token_usage.proto`, `llm_options.proto`, `llm_service.proto`, `vlm_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The rename touches the single most-referenced metric in the repo. commons producers: sdk/runanywhere-commons/src/features/llm/llm_module.cpp:207,1477,1751,1766,2162; features/llm/tool_calling_generation_internal.h:162,211,238; features/vlm/vlm_module.cpp:1060,1101,1299,1414; core/events.cpp:125; foundation/rac_proto_adapters.cpp:527; infrastructure/telemetry/telemetry_manager.cpp:1059. Hand-written facades, by file and hit count: sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Results.swift (11), sdk/runanywhere-cli/src/commands/cmd_bench.cpp (11), sdk/runanywhere-react-native/packages/c…

**Wire safety:** Tag 4 keeps its number and type (double), so binary payloads are unaffected — but proto3-JSON emits `decodeTokensPerSecond` instead of `tokensPerSecond`, so any JSON-transport or persisted-telemetry consumer silently reads undefined. New tags 5 and 6 on TokenUsage do not collide (existing 1-4, verified at idl/token_usage.proto:19-24). Deleting llm_options.ttft_ms=7, llm_service.time_to_first_toke…

**Do first:**
  1. Split the item. Ship the cheap, uncontested half alone first: add prefill_ms = 5 and ttft_ms = 6 to TokenUsage, and add the defining comment to tag 4 WITHOUT renaming it. That captures the 'unstated definition' fix — the actual stated motivation — at zero blast radius.
  1. Only then, as a separate coordinated change, decide the rename. If it goes ahead: get sign-off from the owners of llm_options.proto, llm_service.proto, vlm_options.proto AND sdk_events.proto (the fourth file the proposal omits).
  1. Before deleting any TTFT field, add `reserved` for llm_options tag 7, llm_service tag 7 and vlm_options tag 8 — the after-text has none.
  1. Decide the sdk_events.proto question explicitly: either rename idl/sdk_events.proto:422 and :1107 and :423 in the same commit, or state in the TokenUsage comment that the event stream keeps the legacy spelling. Silently leaving both is the failure mode.
  1. Write the codemod, do not hand-edit ~40 files. Separate passes per language: `tokensPerSecond` -> `decodeTokensPerSecond` in TS/Swift/Kotlin/Dart facades, `tokens_per_second()` -> `decode_tokens_per_second()` in commons C++, and leave the C ABI struct member `tokens_per_second` alone (rac_llm_metrics.h, rac_api_types.h, rac_vlm_types.h are shipped headers).


</details>


<details>
<summary><strong>cua</strong> (6 changes)</summary>

### `cua-document-the-three-unwritten-contracts` — Write the three unwritten contracts into the CuaAction comment: pixel space, drag destination, 2047-byte cap

**Proto location:** [cua.proto (CuaAction)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/cua.proto#L47), [cua.proto (CuaAction)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/cua.proto#L55), [cua.proto (CuaActionType)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/cua.proto#L32), [cua.proto (CuaAction)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/cua.proto#L59)

**Why:** Three things an app must know are folklore today: whether the viewport is physical pixels or logical points (get it wrong on a DPR-3 phone and every click is off by 3x, silently — the iOS example has to work it out itself with `image.size.width * image.scale`), that LEFT_CLICK_DRAG carries only a destination so the host must supply the press point, and that text/reasoning are truncated at 2047 bytes with nothing recording it — including a TERMINATE final answer.

**Skeptic verdict:** `risky` — The COORDINATE CONTRACT paragraph is not documentation of existing behavior -- it invents a rule, and the rule is wrong. rac_cua_parse_action only rescales 1000x1000 into whatever viewport_w/viewport_h the caller passed; commons cannot know or enforce whether those are physical pixels, so 'x/y are integer PHYSICAL device pixels ... not a downscaled copy' is unenforceable and, worse, is contradicted by the proposal's own cited precedent. The same Anthropic page says at line 1753 'Either downscale the screenshot by 2x before sending, or halve the coordinates Claude returns' and at 1552 warns that oversized screenshots are downscaled server-side -- so sending a downscaled screenshot and declaring its downscaled size is CORRECT, common practice, and required to stay inside image limits. The proposed comment tells that app it is wrong and pushes it toward sending full-resolution Retina images. The correct, DPR-agnostic invariant is 'the viewport MUST be the pixel dimensions of the exact image you sent the model' -- which is what Anthropic's table actually says. Two of the three precedent legs also failed verification against the current doc: `grep -n start_coordinate` on the fetched computer-use page returns ZERO hits (it describes left_click_drag only as 'Click and drag between coordinates'), and `max_characters` likewise returns zero. Keep the 2047-byte and drag-destination paragraphs as written; rewrite the coordinate paragraph and drop the two unverified precedent claims.

**What changed:** Added the COORDINATE CONTRACT / LEFT_CLICK_DRAG / LENGTH comment block to CuaAction, using the corrected coordinate-contract wording from the care plan (states the invariant commons can actually hold -- same pixel space as the passed viewport -- rather than the incorrect 'always physical pixels, never downscaled' claim).

**Files touched:** `idl/cua.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** 'Comment-only' is not 'file-only' in this repo: leading proto comments are propagated verbatim into four generated bindings, so this edit dirties them and `idl/codegen/ci-drift-check.sh` FAILS until they are regenerated. Verified: the current CuaAction leading block appears at sdk/shared/proto-ts/src/cua.ts:154-157, sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/ai/runanywhere/proto/v1/CuaAction.kt:35-38, and sdk/runanywhere-swift/Sources/RunAnywhere/Generated/cua.pb.swift:139-141 (plus flutter cua.pb.dart). The committed sdk/shared/proto-ts/dist/ carries the comment too…

**Wire safety:** No wire change -- comment only.

**Do first:**
  1. Rewrite the COORDINATE CONTRACT paragraph to state the invariant commons can actually hold (see correctionNeeded) before writing anything.
  1. Land this LAST, after cua-drop-coordinate-valid and cua-scroll-x-y. The block describes x/y presence and the scroll axes, both of which those two items change; writing it first means rewriting it twice and paying two codegen sweeps.
  1. Run idl/codegen/generate_all.sh in the same commit and rebuild sdk/shared/proto-ts -- otherwise CI's idl-drift-check.yml fails on a change that 'only touched a comment'.


### `cua-drop-coordinate-valid` — Delete coordinate_valid and use proto3 `optional` on x/y for real field presence

**Proto location:** [cua.proto (CuaAction)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/cua.proto#L54), [model_types.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L327)

**Why:** coordinate_valid is a hand-rolled presence flag in a file that could just write `optional`, and it is applied to only one of the three conditional fields: an app can tell 'no coordinate' from 'coordinate (0,0)' but cannot tell 'scroll by 0' from 'not a scroll' without also switching on `type`. The message is inconsistent with itself, and this repo already uses `optional` next door (model_types.proto:327).

**Skeptic verdict:** `risky` — The claim 'The five SDK facades each lose their coordinateValid mapping (a deletion, not a rewrite)' is verifiably false. runanywhere-web/.../RunAnywhere+CUA.ts:232 reads `coordinate: proto.coordinateValid ? { x: proto.x, y: proto.y } : null` and Swift RunAnywhere+CUA.swift:91 reads `let coordinate = proto.coordinateValid ? (x: Int(proto.x), y: Int(proto.y)) : nil` -- those ternaries are rewritten to a different predicate (`hasX`), not deleted, and under `optional` ts-proto regenerates `x?: number` so every downstream read changes type. A third consumer the proposal never mentions: commons' own test at tests/test_cua.cpp:365 `ASSERT_TRUE(action.coordinate_valid(), "has coordinate")`. A fourth: the hand-checked-in sdk/shared/proto-ts/src/cua.ts:162 `coordinateValid: boolean`. Worse is the silent cross-version failure: idl/buf.yaml declares `breaking: use: WIRE`, and reserving tag 2 passes WIRE, so nothing gates the real hazard -- an already-shipped Swift/Web/Flutter SDK decoding a NEW commons payload sees field 2 absent, defaults coordinateValid to false, and returns `coordinate = nil` for EVERY click, with no error anywhere. These are independently versioned artifacts (vendored xcframeworks, npm, maven), so that skew will happen. Finally the concept is not actually removed from the stack: rac_cua.h:73 `int32_t has_coordinate` stays, so cua.cpp:599 just changes from `set_coordinate_valid(...)` to a conditional `set_x/set_y` -- the hand-rolled flag survives in the C ABI and the '9 fields -> 8' win is confined to the proto.

**What changed:** coordinate_valid deleted (no-backcompat: field removed outright, tag 2 reused as optional int32 x since the whole message was rewritten in one pass, not incrementally reserved). x/y made optional int32 (2,3) for real presence.

**Files touched:** `idl/cua.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Nine live consumers, not five, and none of them is a pure deletion. WRITER: sdk/runanywhere-commons/src/features/cua/cua.cpp:599 `proto.set_coordinate_valid(action.has_coordinate != 0);` is the only writer -- it becomes a conditional `if (action.has_coordinate) { proto.set_x(...); proto.set_y(...); }`, because with `optional` you must NOT call set_x/set_y unconditionally or every action gets a phantom (0,0). COMMONS TEST: sdk/runanywhere-commons/tests/test_cua.cpp:365 `ASSERT_TRUE(action.coordinate_valid(), "has coordinate")` -> `action.has_x()`. FIVE FACADES, all rewritten to a different pre…

**Wire safety:** Tag 2 is DELETED and reserved. `reserved 2;` PASSES buf's `breaking: use: WIRE` ruleset (idl/buf.yaml lines 13-17) -- buf will NOT flag this, so CI gives you no loud signal; the only signal is the compile break in the five facades. Second, subtler wire change nobody named: `optional int32 x = 3` does not move the tag but it DOES add a hasbit, so a new writer now emits an explicit 0 for x where th…

**Do first:**
  1. Confirm the toolchain already emits proto3 `optional` cleanly before you rely on it -- it does: model_types.proto:327 `optional string cua_profile = 38` produces `hasCuaProfile` in runanywhere-swift/Sources/RunAnywhere/Generated/model_types.pb.swift:1289 and a nullable ctor arg in flutter model_types.pb.dart:237. So `optional` is proven in this codegen, on this repo, today. No spike needed.
  1. Land in EXACTLY this order, in ONE commit per step but ONE release: (1) edit idl/cua.proto:54-56; (2) run idl/codegen/generate_all.sh (regenerates commons cua.pb.*, kotlin CuaAction.kt, swift cua.pb.swift, flutter cua.pb.dart, sdk/shared/proto-ts/src/cua.ts); (3) rebuild sdk/shared/proto-ts so dist/cua.js + dist/cua.d.ts match -- codegen does NOT touch dist and it is committed; (4) commons cua.cpp:599 -> guard set_x/set_y on action.has_coordinate; (5) commons test_cua.cpp:365 -> action.has_x(); (6) the five facades; (7) CuaActionMappingTest.kt:31/:53; (8) rebuild and refresh the RACommons prebuilts (the serializer lives in the binary, and 12 vendored trees ship it).
  1. Do NOT ship step 1-3 without steps 4-8 in the same release: the Web build and the Kotlin build compile against `coordinateValid` / non-null `proto.x` that are gone.


### `cua-rename-parse-ok` — Rename parse_ok to is_valid — the word all five shipping SDKs already publish

**Proto location:** [cua.proto (CuaAction)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/cua.proto#L61)

**Why:** The wire name describes the SDK's internal parser, not anything the app cares about, so all five facades rename it on the way out (Swift/Kotlin/Web/RN/Flutter all publish `isValid`). Python, Electron and CLI consumers read the generated type directly and will see a sixth, different word.

**Skeptic verdict:** `sound` — One overreach to strike from the rationale, and one omitted edit. The 'why' asserts 'Python, Electron and CLI consumers read the generated type directly and will see a sixth, different word' -- there is no CuaAction in sdk/runanywhere-electron/src/proto/ (only tool_calling.ts has an unrelated isValid) and `find` turns up no python or CLI cua consumer at all. The urgency is therefore weaker than claimed; the case rests entirely on the five verified facades, which is enough on its own. Omitted from the edit list: tests/test_cua.cpp:368 `ASSERT_TRUE(action.parse_ok(), ...)`, the header prose at rac_cua.h:105 and :123 that tells callers to 'inspect out_action->parse_ok', and the same struct field mirrored into 15 vendored xcframework/jniLibs copies of rac_cua.h -- so renaming the C field must ship with the prebuilt binaries or leave header/doc drift.

**What changed:** parse_ok renamed to is_valid (tag 9, same, name-only wire-safe rename).

**Files touched:** `idl/cua.proto`

**Status:** `applied`


### `cua-scroll-x-y` — Replace scroll_pixels with signed scroll_x/scroll_y, positive = right/down (OpenAI's convention)

**Proto location:** [cua.proto (CuaAction)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/cua.proto#L57), [cua.proto (CuaActionType)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/cua.proto#L36)

**Why:** One field carries two axes with a documented sign (+up) that is the inverse of every scroll API an app will call, and the horizontal sign is defined nowhere in the repo. An app that forwards the value into scrollBy, a wheel event or a swipe scrolls backwards; for HSCROLL it has a signed number and no stated meaning at all.

**Skeptic verdict:** `risky` — The proposal's core action item -- 'Commons must negate Fara's up-positive value in exactly one place' -- rests on a premise with zero support in the repo. The `+up / -down` text is an unverified assertion in a hand-written comment (cua.proto:57 and rac_cua.h:76); the prompt Fara actually receives declares no sign, commons never negates, and no test pins it. If the comment is simply wrong (i.e. Fara already emits down-positive, matching every platform API), this change silently INVERTS every scroll in every SDK -- the exact failure it claims to fix, in the opposite direction, with no test to catch it. The premise must be settled by running the model on device before any negation lands. Separately, the migration is silent in the same way as cua-drop-coordinate-valid: reserving 5 and moving to 11/12 passes buf's WIRE ruleset (idl/buf.yaml), so an already-shipped SDK reading a new payload gets scroll = 0 and every scroll becomes a no-op with no error. Also a small misquote: the OpenAI doc's reference handler is `page.mouse.wheel(action.scroll_x, action.scroll_y)`, not the `window.scrollBy({left, top})` the proposal attributes to it (semantics agree, the cited code does not).

**What changed:** scroll_pixels replaced with scroll_x(4)/scroll_y(5), value copied verbatim from the model's raw pixels per axis. Per care plan's finding that no sign convention is verified on device, did NOT assert a '+up/-down inverted vs OpenAI' claim -- comment states the sign is unverified.

**Files touched:** `idl/cua.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** The blocker is not a consumer, it is the PREMISE. I read the actual prompt Fara receives -- it is the tool JSON literal at sdk/runanywhere-commons/src/features/cua/cua.cpp:47, and its `pixels` parameter reads verbatim: "The amount of scrolling to perform. Required only by `action=scroll` and `action=hscroll`." NO SIGN IS DECLARED, in either axis. `hscroll` is described only as "Performs a horizontal scroll (mapped to regular scroll)". So the `+up / -down` text at idl/cua.proto:57 and sdk/runanywhere-commons/include/rac/features/cua/rac_cua.h:76 is asserted nowhere the model can see it, common…

**Wire safety:** Tag 5 deleted + reserved, new tags 11/12 (both free -- CuaAction's max tag is 9 at idl/cua.proto:61). Not reusing tag 5 is the right call and must be kept. But note `reserved 5;` PASSES buf `breaking: use: WIRE` (idl/buf.yaml), so CI stays green while an already-shipped SDK reading a new payload silently sees scroll==0 forever. `optional int32` on 11/12 also carries the hasbit-vs-elided-zero asym…

**Do first:**
  1. SETTLE THE SIGN ON DEVICE FIRST. This is the hard prerequisite and it does not exist in the repo. Run Fara on a real screen: show it a page scrolled to the top with content below, ask it to scroll down, and record the raw `pixels` value the model emits (log it at sdk/runanywhere-commons/src/features/cua/cua.cpp:524 before the lround). Repeat for scroll-up and for hscroll left/right. Write the four observed signs into a comment on the same line. Nothing about negation may be written until those four numbers exist.
  1. SPLIT THE FIELD AND NEGATE AS TWO SEPARATE COMMITS. Commit A: pure axis split -- scroll_x/scroll_y at tags 11/12, value copied VERBATIM from `pixels` (SCROLL -> scroll_y, HSCROLL -> scroll_x, per the type at cua.proto:36), zero sign change, zero semantic claim in the comment. This is safe today and delivers the axis win. Commit B: the negation plus the 'positive y scrolls DOWN' comment, gated on the device observation from step 1. If the observation shows Fara is already down-positive, commit B is deleted, not written.
  1. Before Commit B lands, replace CuaActionMappingTest.kt:84/:90 with a test that asserts the SIGN against a named real-world meaning ('scroll down 3' -> scrollY == +3), not just that -3 round-trips. As written that test passes under either convention and will not catch the inversion.
  1. rac_cua.h changes here, so the 12 vendored copies under sdk/runanywhere-swift/Binaries/RACommons.xcframework/, sdk/runanywhere-flutter/.../Frameworks/RACommons.xcframework/, sdk/runanywhere-react-native/packages/core/ios/Binaries/RACommons.xcframework/ and .../android/src/main/jniLibs/include/ must be refreshed together with the prebuilt binaries -- header and binary in the same commit or the link/ABI silently disagrees.


### `cua-systemprompt-drop-display` — Delete display_w/display_h from systemPrompt — they cannot change the output and hardcode Fara's 1000x1000

**Proto location:** [rac_cua.h](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rac_cua.h#L99)

**Why:** systemPrompt takes three parameters, two of which are rejected unless they equal the profile's own space, after which the prompt is returned unmodified — the header says so outright ('The parameter remains for a future profile whose space is genuinely negotiable'). A newcomer reads two required-looking dimensions on the domain's primary verb and reasonably assumes they steer the coordinate space. They cannot.

**Skeptic verdict:** `sound` — Reasoning holds, but two caveats the proposal understates. (1) effort 'M' is wrong: this is not a proto change at all, it is a C-ABI arity change that also rewrites the JNI entry point (runanywhere_commons_jni.cpp:8325-8342 takes displayW/displayH), the WASM export declaration (EmscriptenModule.ts:669 and the CMakeLists.txt:410 export list for `_rac_cua_system_prompt`), the Dart FFI binding, and 15 vendored copies of rac_cua.h inside checked-in RACommons.xcframework/jniLibs trees -- header and prebuilt binary must land together or the link fails. (2) It deletes the three tests that exist only to validate the parameter's rejection behavior (test_cua.cpp:71 zero-space accepted, :73 UINT32_MAX rejected, :83 1440x900 rejected). Both are acceptable costs, but 'Cheap now' should read 'cheap in the IDL, a coordinated multi-language ABI release in practice'.

**What changed:** 

**Status:** `skipped`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Eleven call/declaration sites plus 12 vendored headers, across five languages and three FFI mechanisms. C: definition sdk/runanywhere-commons/src/features/cua/cua.cpp:436, declaration sdk/runanywhere-commons/include/rac/features/cua/rac_cua.h:99, and 12 vendored copies of rac_cua.h (I counted 12, not 15: 3 under runanywhere-swift/Binaries/RACommons.xcframework/, 3 under runanywhere-flutter/.../ios/runanywhere/Frameworks/RACommons.xcframework/, 3 under runanywhere-react-native/packages/core/ios/Binaries/RACommons.xcframework/, 1 under runanywhere-react-native/packages/core/android/src/main/jni…

**Wire safety:** No wire change -- this is not a proto edit at all. It is a C-ABI arity change on an exported symbol whose NAME does not change (`_rac_cua_system_prompt` stays in sdk/runanywhere-commons/exports/RACommons.exports:351 and in sdk/runanywhere-web/wasm/CMakeLists.txt:410). That is the danger: the symbol still resolves, so nothing fails at link time. On Android the mismatch surfaces as a runtime Unsati…

**Do first:**
  1. Treat this as a multi-language ABI release, not an IDL edit. Order: (1) cua.cpp:436 + rac_cua.h:99; (2) JNI runanywhere_commons_jni.cpp:8326-8342 and RunAnywhereBridge.kt:1462 IN THE SAME COMMIT -- a Kotlin `external fun` whose arity disagrees with the JNI entry point still builds and fails only when a user opens the CUA screen; (3) rebuild the commons binaries AND copy the new rac_cua.h into all 12 vendored trees in the same commit -- a stale vendored header plus a new binary is a silent calling-convention mismatch; (4) re-run nitrogen for RN (nitrogen/generated/ is NOT produced by idl/codegen/generate_all.sh) then update HybridRunAnywhereCore+CUA.cpp; (5) rebuild the WASM bundle -- CMakeLists.txt:410 keeps the same export name, so a stale .wasm silently takes two extra ignored args; (6) the five facades; (7) delete tests/test_cua.cpp:69/:71/:73/:83 and drop the args at :26/:41/:85.
  1. Keep the rejection LOGIC even though the parameter goes: cua.cpp:475's neighbouring range check on viewport is a different guard and must not be swept up. Only the display_w/display_h block at cua.cpp:445-456 is deleted.
  1. Do NOT relabel this as effort M. Correct the effort field to L before the change ships -- it touches 3 FFI mechanisms (JNI, Emscripten, Dart FFI) plus a nitrogen codegen pass plus a prebuilt-binary refresh.


### `cua-wait-cap-100s` — Cap wait_seconds at 100s and declare the bound in the IDL

**Proto location:** [cua.proto (CuaAction)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/cua.proto#L58), [cua.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/cua.proto#L10), [rac_options.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rac_options.proto)

**Why:** wait_seconds is an unbounded double copied straight out of untrusted model output, so a garbled "time": 1e9 wedges the agent loop for 31 years while holding a wake-lock, and the SDK hands it to the app without comment. It is also the only scalar in this IDL with no declared bound while every other options message uses the rac_options annotations.

**Skeptic verdict:** `sound` — Three corrections, none fatal. (1) The `after` block writes the options UNQUALIFIED -- `[(rac_min_float) = 0.0, (rac_max_float) = 100.0]` -- while every existing site in this IDL fully qualifies them: diarization.proto:42 is `(runanywhere.v1.rac_min_float)`. Match the convention. (2) The precedent is softer than stated: the fetched Anthropic computer-use doc mentions hold_key duration in seconds but states no maximum anywhere, so 'a hard maximum of 100' comes from the anthropic-quickstarts reference harness, not from the API contract -- and the 'OpenAI's wait ms defaults to 1000' and 'mobile-mcp caps at 10000 ms' legs I could not verify at all. Cite the quickstart precisely or drop the number to a locally chosen bound. (3) The proposal's own hesitation is the right call: annotate nothing. The rac_* annotations are consumed by field NUMBER in idl/codegen/_convenience_common.py:100-101 for request/options clamping, and `grep -rn cua idl/codegen/*.sh idl/codegen/*.py` returns nothing -- cua.proto is in no codegen path today, so the annotation buys zero enforcement while risking a generator emitting a validator that REJECTS a legitimately parsed model value. The comment plus the clamp at cua.cpp:528 is the whole win, with no new import.

**What changed:** wait_seconds comment updated to state the 100s ceiling is RunAnywhere-chosen, not inherited from Anthropic (dropping the fabricated 'matches Anthropic's reference implementation' claim the skeptic flagged). Kept as plain double per care plan's routine-level correction -- did NOT add rac_min_float/rac_max_float annotations or make it optional (that would ripple into 20+ facade call sites for a clamp that's actually enforced in C++, not the wire).

**Files touched:** `idl/cua.proto`

**Status:** `applied`

**Care level:** `routine`

**What could break:** Nothing breaks from the comment or the clamp. What breaks from the `optional` in the `after` block -- unconditional `waitSeconds` reads in every facade: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/extensions/CUA/RunAnywhereCUA.kt (2 hits, the field decl and the `waitSeconds = proto.wait_seconds` mapping), sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/CUA/RunAnywhere+CUA.swift:30 `public let waitSeconds: Double` and :98 `waitSeconds: proto.waitSeconds`, sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+CUA.ts (2), sdk/runanywhere-react-nati…

**Wire safety:** No wire change IF you ship the corrected shape (plain `double wait_seconds = 6` + comment + a C++ clamp). If you ship the `after` block verbatim, it is NOT a no-op and it is NOT non-breaking: `optional double` adds a hasbit and regenerates the accessor as nullable in every SDK (`waitSeconds?: number` in ts-proto, `Double?` under wire, `hasWaitSeconds` in SwiftProtobuf -- exactly the pattern alrea…

**Do first:**
  1. Ship the reduced shape the proposer already offered as the fallback: keep `double wait_seconds = 6;` (no `optional`, no rac_min_float/rac_max_float), add the comment, and put the real clamp in commons. That is a strict no-op for all 20+ consumer sites above while still delivering the whole win. Rationale beyond the skeptic's: idl/cua.proto has zero imports (`grep -c '^import' idl/cua.proto` = 0), and idl/codegen/_convenience_common.py:95-101 keys the rac_* annotations by extension field number for OPTIONS messages -- pointing them at a parsed-output field buys a codegen risk for an advisory that the clamp already enforces.
  1. Write the clamp at sdk/runanywhere-commons/src/features/cua/cua.cpp:527-528, not in the SDKs: `out->wait_seconds = std::clamp(num, 0.0, 100.0);` (guard NaN explicitly -- std::clamp on NaN is UB-adjacent; prefer an explicit `if (!(num > 0.0)) num = 0.0;` then `if (num > 100.0) num = 100.0;`). One place, applies to all eight SDKs for free.
  1. Add the tests that do not exist: parse `{"action":"wait","time":1e9}` -> wait_seconds == 100.0; `{"action":"wait","time":-5}` -> 0.0; `{"action":"wait","time":2.5}` -> 2.5 unchanged. There is currently NO test on wait_seconds at all, so without these the clamp is unverified and a future refactor silently removes it.
  1. If you do want the `optional` + annotations anyway, this stops being routine: it becomes the same five-facade, two-build-artifact sweep as cua-drop-coordinate-valid and must land in that same release.


</details>


<details>
<summary><strong>diarization</strong> (3 changes)</summary>

### `diar-P1` — Add num_speakers and max_speakers hints to DiarizationOptions

**Proto location:** [diarization.proto (DiarizationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diarization.proto)

**Why:** DiarizationOptions carries zero of the domain's universal request knobs: there is no speaker-count field anywhere in diarization.proto, yet this SDK already agrees the capability is needed because STTOptions.max_speakers exists. Adding it is the one case where new surface buys legibility rather than costing it: it is the first thing a reader looks for, its absence makes the SDK answer 'can I hint the speaker count?' differently depending on which verb you picked, and the shipped ONNX Sortformer provider already densely remaps its 4 active speaker slots, so honouring the hint is post-processing on an existing code path. I dropped min_speakers from the review's trio (see droppedAsNoise): no on-device engine in the industry honours a lower bound, and two fields need no precedence table beyond 'num_speakers wins'.

**Skeptic verdict:** `risky` — Before-text, tags and precedent all check out, but the load-bearing feasibility claim is false. 'the shipped ONNX Sortformer provider already densely remaps its 4 active speaker slots, so honouring the hint is post-processing on an existing code path' -- the remap at onnx_diarization_provider.cpp:895-903 only relabels whichever slots happened to activate into a contiguous 0..k-1 range. It cannot force an exact count: Sortformer is a fixed-4-slot end-to-end sigmoid model with no clustering step and no speaker embeddings, so collapsing 3 detected speakers into num_speakers=2 would require a similarity/merge step that does not exist in this provider. max_speakers is honourable (drop the weakest slots); num_speakers is not. Second, this is not a proto-only change: rac_diarization_options_t (rac_diarization_types.h:21-27) has no speaker-count field, so the hint needs a C-ABI struct addition plus plumbing through diarization_module.cpp:293-341, rac_diarization_stream.cpp:659, sdk/runanywhere-electron/native/addon.cpp:2348 and sdk/runanywhere-python/native/module.cpp:1556 -- effort 'medium' and 'ship the engine honouring in the same change' cannot both hold. Third, the justification 'this SDK already agrees the capability is needed because STTOptions.max_speakers exists' cites dead surface as precedent: engines/sherpa/rac_stt_sherpa.cpp:136 lists max_speakers among the options it DROPS, and sdk/runanywhere-python/runanywhere/_options_bridge.py:122 raises not_implemented for it. So the proposal risks shipping exactly the advertised-but-ignored field it used to justify dropping diarization-5 and diarization-6.

**What changed:** Added `optional int32 max_speakers = 8 [(runanywhere.v1.rac_min) = 1];` to DiarizationOptions in diarization.proto, documented as an upper bound whose overflow is resolved by ranking active speakers by total active duration, dropping the weakest and re-densifying indices. Per carePlan.doFirst I did NOT land `num_speakers`; tag 7 is left unallocated (no `reserved` statement) behind a one-line marker comment so the field can land at its approved number later.

**Files touched:** `diarization.proto`

**Status:** `applied`

**Care level:** `blocked`

**What could break:** The proto edit alone breaks nothing, and I verified no name collision: `num_speakers`/`numSpeakers` does not exist as a field ANYWHERE in the repo — the only hits are engines/sherpa/sherpa_backend.cpp:2046 (an unrelated TTS-local `int num_speakers`) and the compile-time constant kNumSpeakers in engines/onnx/onnx_diarization_provider.cpp + sdk/runanywhere-commons/tests/test_diarization_onnx.cpp. What breaks is everything below the proto.

(1) ABI, the sharp edge. To honour the hint you must add a member to rac_diarization_options_t at sdk/runanywhere-commons/include/rac/features/diarization/ra…

**Wire safety:** Additive only. idl/diarization.proto:25-48 DiarizationOptions ends at merge_gap_ms = 6, and `rg -n 'reserved' idl/diarization.proto` returns NOTHING, so tags 7 and 8 are free and have never been used. No field-number change, no enum renumbering, no oneof arm removed, no tag reuse. Proto3 `optional` adds a synthetic oneof for presence only — wire-identical. The wire is safe; the ABI is not (see wh…

**Do first:**
  1. Delete the fabricated feasibility sentence from the rationale before anything is written down — see correctionNeeded. It must not be pasted into the proto comment or the PR description.
  1. SPLIT the item. Land `optional int32 max_speakers = 8 [(runanywhere.v1.rac_min) = 1];` only. Leave tag 7 unallocated with a one-line comment ('// 7 reserved for num_speakers once the ONNX provider gains a slot-merge step') so the eventual field lands exactly where the approved diff says. Do NOT emit `reserved 7;` — that would have to be un-reserved later.
  1. Add `int32_t max_speakers;` to rac_diarization_options_t (sdk/runanywhere-commons/include/rac/features/diarization/rac_diarization_types.h:21-27) and `.max_speakers = 0,` (0 = auto) to RAC_DIARIZATION_OPTIONS_DEFAULT at :29-35. Append it LAST in the struct so existing member offsets are unchanged.
  1. In the SAME commit, rebuild RACommons and re-vendor all 11 header copies listed by `rg -uu --files --glob 'rac_diarization_types.h' .`, including the 9 inside the Swift / Flutter / React Native RACommons.xcframework slices. A header copy that is newer than its sibling binary is the silent-corruption case, and it will not fail to link.
  1. Copy and clamp in sdk/runanywhere-commons/src/features/diarization/diarization_module.cpp: extend the block at :302-311 with a presence-guarded `if (proto->has_max_speakers()) out_options->max_speakers = proto->max_speakers();`, and extend the validation at :317-320 to reject max_speakers < 0. Clamp to the loaded model's capacity here, not in the engine, so every engine inherits the clamp.
  1. Honour it in engines/onnx/onnx_diarization_provider.cpp: after the dense remap at :889-903, when max_speakers > 0 and speaker_count > max_speakers, rank the active slots by total active duration, drop the weakest, re-densify dense_index, and recompute out->speaker_count BEFORE the write-back at :913-921.
  1. Add a case to sdk/runanywhere-commons/tests/test_diarization_onnx.cpp beside the existing RAC_DIARIZATION_OPTIONS_DEFAULT cases (:324, :336, :355, :534, :565, :601) asserting a 3-active-slot prediction with max_speakers=2 yields speaker_count == 2 and contiguous indices.
  1. Surface the knob in every public options struct in the same release (Swift Options.swift:439-449 first, since it is the declared source of truth), then Kotlin Options.kt:223-227, Web Options.ts:177, RN Types.ts:214-217 + Options.ts:325-333, Flutter options.dart:598-618, CLI cmd_diarize.cpp:174-181 (`--max-speakers`), and Python — which needs BOTH runanywhere/options.py and the pybind signature at sdk/runanywhere-python/native/module.cpp:1553-1556, or Python silently ignores it.
  1. Run ./idl/codegen/generate_all.sh, then ./idl/codegen/ci-drift-check.sh.
  1. HARD PREREQUISITE for the num_speakers half (this is why careLevel is blocked): a speaker-merge step in engines/onnx/onnx_diarization_provider.cpp — cosine similarity over Sortformer's speaker-cache embeddings, or a post-hoc merge of the two most-overlapping slots. Until that exists, num_speakers = 7 would be advertised-but-ignored, the exact failure the proposer's own risk note forbids. Do not land tag 7 before it.


### `diar-P2` — Make STTOptions.max_speakers optional and drop the 0 sentinel

**Proto location:** [stt_options.proto (STTOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto)

**Why:** Split out of diarization-1, because it touches another domain's message and the owner may answer it separately. diarization-1's recommendation bundled it: if diarization gains optional-presence hints while STTOptions keeps int32 max_speakers = 4 with rac_default "0" // 0 = auto, the SDK ships two conventions for one concept, which is exactly the kind of thing that makes a small API feel large. The industry expresses auto-detect as null/unset everywhere except C structs that have no null.

**Skeptic verdict:** `sound` — The claim holds and the risk section is honest, but it overstates the break in one direction and understates a dependency in the other. Overstated: the two public SDKs it worries about already model this as null (Swift Options.swift:239, Python options.py:150), so the surviving breakage is the generated proto layer plus dropping 'r.maxSpeakers = 0' from RAConvenience.swift:748 -- both regeneration, not app rewrites. Understated: the entire justification is convention-parity with diar-P1, so if P1 is deferred (and per my P1 finding it should at least be split), P2 becomes a source-breaking retype for zero legibility gain. Keep the declared dependsOn as a hard gate, and note that STTOptions.max_speakers is currently unimplemented anyway (engines/sherpa/rac_stt_sherpa.cpp:136 drops it; _options_bridge.py:122 raises not_implemented), which is the stronger argument for touching it now while nothing depends on the sentinel.

**What changed:** Originally changed STTOptions.max_speakers to optional int32, unset=auto. SUPERSEDED (found by gate_a.py): the later stt-diarization-decide edit (stt domain), which explicitly names this item as its predecessor ('split out of diarization-1... touches another domain's message'), renamed the field to speakers_expected as the final resolution -- chosen together with the response-side decision (WordTimestamp.speaker_id kept live, STTOutput.speaker_ids deleted) so both halves of the diarization story are consistent. The presence semantics (optional, unset = auto) this item wanted are preserved under the new name.

**Files touched:** `stt_options.proto`

**Status:** `superseded`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** The C++ commons — the authoritative consumer — does NOT break. sdk/runanywhere-commons/src/foundation/rac_proto_adapters.cpp:160 (`out->max_speakers = in.max_speakers();`), sdk/runanywhere-commons/src/features/stt/stt_module.cpp:386 (`options.max_speakers = proto.max_speakers();`) and sdk/runanywhere-commons/src/features/stt/rac_stt_stream.cpp:1023 (`s.max_speakers = parsed.max_speakers();`) all call the scalar getter, which protoc still generates for a proto3-optional field (returns 0 when unset). They compile untouched and keep identical meaning, because the C struct rac_stt_options_t keeps…

**Wire safety:** Wire-safe. Tag stays 4 and the type stays int32 at idl/stt_options.proto:52; no reuse, no reserved range touched, no renumbering. Proto3 `optional` only adds a synthetic oneof for presence. One behavior delta worth stating in the migration note: with `optional`, an explicitly-assigned 0 now SERIALIZES where before it was skipped as the default — an old-schema peer decodes it as 0, which still mea…

**Do first:**
  1. Gate on diar-P1. The entire justification is convention-parity, so if the diarization side does not ship an unset-means-auto speaker hint, this is a source-breaking retype for zero legibility gain. The gate is satisfied by the max_speakers-only SUBSET of diar-P1 (see that plan) — it does not require the blocked num_speakers half.
  1. Write the migration note BEFORE the edit: for one release, 0 and unset both mean auto on the wire; the native C ABI keeps 0 = auto permanently (rac_stt_types.h:144 / :159 in all 8 vendored copies) so nothing on the native side changes. Say plainly that Kotlin Wire consumers of the raw proto see Int? and must adjust.
  1. Edit idl/stt_options.proto:52 exactly to the approved `after` line. Do not also change the tag or the type.
  1. Run ./idl/codegen/generate_all.sh. It MUST delete all four sentinel assignments: sdk/runanywhere-swift/Sources/RunAnywhere/Generated/RAConvenience.swift:748, sdk/runanywhere-kotlin/.../generated/convenience/RAConvenience.kt:642, sdk/runanywhere-flutter/packages/runanywhere/lib/generated/convenience/ra_convenience.dart:790, sdk/shared/proto-ts/src/convenience/stt_options_convenience.ts:44. If any survives, the defaults helper now SETS presence and every STT request ships an explicit max_speakers=0 — auto masquerading as a caller's choice. Stop and fix the generator, do not hand-edit the generated file.
  1. Fix the two hand-written mappers that fold null into the sentinel: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/MappingOptions.kt:130 `max_speakers = maxSpeakers ?: 0` -> `max_speakers = maxSpeakers`; sdk/runanywhere-web/packages/core/src/Public/API/Mapping.ts:342 `maxSpeakers: options?.maxSpeakers ?? defaults.maxSpeakers` -> `maxSpeakers: options?.maxSpeakers`. The Web one still typechecks after the change, so it will not be caught by the build — it is the one you have to fix by hand.
  1. Leave the C++ commons readers alone: rac_proto_adapters.cpp:160, stt_module.cpp:386, rac_stt_stream.cpp:1023 keep calling .max_speakers(). Do not 'improve' them into has_max_speakers() in this change — the C struct has no presence bit, so there is nowhere for the extra information to go, and touching them turns a codegen-only diff into a behavior diff.
  1. Rebuild the committed RN JS artifact sdk/runanywhere-react-native/packages/core/lib/Public/Extensions/STT/RunAnywhere+STT.js:38, which still carries `maxSpeakers: 0`.


### `diar-P3` — Advertise only the audio formats diarization actually accepts

**Proto location:** [diarization.proto (DiarizationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diarization.proto), [diarization.proto (DiarizationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diarization.proto)

**Why:** One decision, two sites: stop documenting formats the engine cannot honour. sample_rate advertises rac_min 8000 / rac_max 48000 while commons hard-rejects everything except 16000 — the commons source itself carries the comment 'Do not advertise a validated range the engine cannot honor.' The generated validate() happily passes 44100, so the annotation actively misleads the one tool meant to catch this. Same defect one field lower: encoding is typed with the shared 4-member AudioEncoding enum but only PCM_F32_LE and PCM_S16_LE are accepted, and nothing in the IDL says so. Narrowing the annotation makes sample_rate exactly as honest as `channels` already is (rac_min = rac_max = 1). Comment/annotation-only: no field, message, or tag changes.

**Skeptic verdict:** `sound` — Substantively correct; two small caveats that do not change the verdict. effort 'trivial' undercounts the regeneration: the annotations feed generated validate() in at least Swift/Kotlin/Flutter plus the golden fixtures under idl/codegen/tests/golden, so idl/codegen/ci-drift-check.sh must be re-run. And breaking:false is true for wire and source but not for behaviour -- an app that today calls validate() with sample_rate 44100 starts throwing client-side instead of failing at runtime, which is the intent but should be in the migration note. Also worth aligning diarization_module.cpp:317, which still range-checks 8000..48000 before the 16000 check, so the C++ keeps a bound the IDL no longer advertises.

**What changed:** In diarization.proto DiarizationOptions, narrowed sample_rate's advertised range from rac_min 8000 / rac_max 48000 to rac_min 16000 / rac_max 16000 (rac_default unchanged at 16000) and added a comment saying only 16 kHz is accepted because the engine does not resample. Rewrote the encoding comment to state that only AUDIO_ENCODING_PCM_F32_LE and AUDIO_ENCODING_PCM_S16_LE are accepted and that AUDIO_ENCODING_CONTAINER and AUDIO_ENCODING_UNSPECIFIED are rejected with RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED. No field, tag, type or message changed.

**Files touched:** `diarization.proto`

**Status:** `applied`


</details>


<details>
<summary><strong>embeddings</strong> (9 changes)</summary>

### `E1` — Add input_type (query vs document) to EmbeddingsOptions

**Proto location:** [embeddings_options.proto (EmbeddingsOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto)

**Why:** This is the one thing in the domain that is silently WRONG rather than merely verbose. Every modern asymmetric embedder (bge-*, e5-*, nomic-embed-text, gte, EmbeddingGemma) is trained with a different literal prefix on the query side than the document side, the prefix table ships inside the model bundle, and the SDK owns tokenization — so today the app physically cannot apply it. The failure mode is no error, valid-looking unit vectors, measurably worse recall. Two enum values plus one field buys back correctness for the single most common on-device embedding use case; UNSPECIFIED keeps symmetric models untouched.

**Skeptic verdict:** `risky` — The field is honorable by nobody. There is no prompt/prefix table in any proto (model_types.proto has none) and no field in the C ABI options struct, so merging input_type ships a knob that commons silently drops - reproducing the exact 'normalize is a lie' defect this report opens with, at CRITICAL severity. The claim 'the prefix table ships inside the model bundle' is not true of this repo: it ships in one Android instrumentation-test JSON. Landing it needs (a) a prefix/prompt field on the model manifest, (b) a rac_embeddings_options_t ABI change or a commons-side prepend before tokenization, in the SAME change - none of which is in the proposal's effort estimate of 'medium'.

**What changed:** Added `EmbeddingsInputType input_type = 7;` to EmbeddingsOptions plus a new top-level `enum EmbeddingsInputType { UNSPECIFIED=0, QUERY=1, DOCUMENT=2 }` immediately after the message. Per carePlan.correctionNeeded I did NOT write the false claim 'the prefix table ships in the model bundle'; the comment says the prefix table must be added to the model manifest as part of honouring this field and does not exist today, and it states the no-table contract explicitly (a bundle declaring no prompts ignores input_type and returns the identical vector for QUERY and DOCUMENT, never erroring).

**Files touched:** `embeddings_options.proto`

**Status:** `applied`

**Care level:** `blocked`

**What could break:** Nothing breaks. Nothing honours it either, and there are two hard prerequisites that do not exist in this checkout. (1) NO ABI SLOT: `rac_embeddings_options_t` at sdk/runanywhere-commons/include/rac/features/embeddings/rac_embeddings_types.h:102-123 has exactly five members - normalize, pooling, n_threads, truncate, batch_size - and RAC_EMBEDDINGS_OPTIONS_DEFAULT at :127-128 initialises all five positionally (`.normalize = -1, .pooling = -1, .n_threads = 0, .truncate = -1, .batch_size = 0`). There is no input_type, no prompt, no prefix member anywhere in that header. (2) THE STRUCT IS VENDORE…

**Wire safety:** The schema edit itself is safe and additive: tag 7 is free in EmbeddingsOptions (2,3,4,5,6 in use), the new EmbeddingsInputType enum collides with nothing (`rg -n 'EmbeddingsInputType|EMBEDDINGS_INPUT_TYPE|input_type' idl/` returns zero), and it does not clash with EMBEDDINGS_POOLING_STRATEGY_* in the same package. E4 wants tag 8, so the two are compatible. No wire risk - the risk is entirely tha…

**Do first:**
  1. PREREQUISITE 1 - a data source. Add the prefix table to the model manifest (idl/model_types.proto) or to the bundle metadata commons already parses, e.g. `optional string embeddings_query_prompt` / `optional string embeddings_document_prompt`. Until a bundle can declare these strings, input_type cannot resolve to anything and must not merge.
  1. PREREQUISITE 2 - a honouring seam. Prefer prepending in commons BEFORE tokenization, in sdk/runanywhere-commons/src/features/embeddings/embeddings_module.cpp (it already owns the `texts` vector - see :256 and :425 where it echoes them back) rather than widening rac_embeddings_options_t. This keeps the C ABI and all vendored header copies untouched. Only widen the struct if a backend genuinely needs the enum.
  1. IF you widen the struct anyway: append the new member at the END of rac_embeddings_options_t, bump whatever ABI/version marker exists, update sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/rac_embeddings_types.h and the three sdk/runanywhere-swift/Binaries/RACommons.xcframework/*/Headers/ copies plus the flutter and react-native vendored trees, and rebuild every prebuilt .xcframework/jniLibs before shipping. A stale copy silently misreads every field after the insertion point.
  1. Define the no-table behaviour explicitly in the proto comment AND in a commons test: a bundle with no prompt table must IGNORE input_type and return the identical vector for QUERY and DOCUMENT, never error. Write that test before the field.
  1. Re-scope the effort estimate. 'medium' does not cover a manifest field + a commons prepend path + a no-table test; if the ABI route is chosen, add a full re-vendor of every prebuilt binary.


### `E10` — Document truncate's default as true

**Proto location:** [embeddings_options.proto (EmbeddingsOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto)

**Why:** Today the documented behaviour is not a default but a dispatch: the proto itself says 'Unset = backend default, currently truncate-on-overflow for ONNX and sliding-window for llama.cpp'. Those produce DIFFERENT vectors, and onnx, llamacpp, mlx and qhexrt all publish a non-null embedding_ops slot, so an app that indexes on one engine and queries on another gets silently mismatched embeddings. Vendors disagree loudly on this default (Ollama and Voyage true, Jina false, Cohere END, OpenAI hard-errors), which is exactly why it must be stated rather than inherited. Picking true is the on-device-correct choice: failing a long chunk on a phone is hostile.

**Skeptic verdict:** `risky` — rac_default is not a comment - it is codegen input. Putting rac_default="true" on an `optional bool` makes every generated defaults()/convenience constructor SET the field, so has_truncate() becomes true and rac_proto_adapters.cpp:867 stops producing the -1 sentinel. That silently switches llama.cpp from sliding-window aggregation to tail-discarding truncation for every caller who starts from defaults - precisely the outcome this proposal's own risk note says must not happen. Land the comment (the 90% of the value) and either omit the annotation or make commons map unset->truncate explicitly instead of -1.

**What changed:** Replaced truncate's comment with the four approved lines (true = clip and embed, false = fail the call, unset = true, a backend may instead aggregate over a sliding window). Per carePlan.correctionNeeded I shipped the comment ONLY: the field stays `optional bool truncate = 2;` with NO `(runanywhere.v1.rac_default) = "true"` annotation, because rac_default is codegen input that would make generated defaults() set the field, kill the unset sentinel that rac_proto_adapters.cpp maps to -1, and silently switch llama.cpp from sliding-window aggregation to tail truncation.

**Files touched:** `embeddings_options.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** The annotation flips llama.cpp's long-input behaviour for every defaults-constructed caller. The unset sentinel is real and load-bearing: sdk/runanywhere-commons/include/rac/features/embeddings/rac_embeddings_types.h:112-118 documents `truncate` as "-1 = backend default, 0 = reject overflow, 1 = truncate to the backend context window" and states outright "llama.cpp's backend default is sliding-window aggregation"; RAC_EMBEDDINGS_OPTIONS_DEFAULT at :127-128 initialises `.truncate = -1`. rac_proto_adapters.cpp:867 is what maps proto-unset to that -1. If generated defaults() start setting trunca…

**Wire safety:** No wire change to the field: `optional bool truncate = 2` keeps its tag, type and presence. But `(runanywhere.v1.rac_default) = "true"` is NOT a comment - it is codegen input read by idl/codegen/generate_defaults_pool.py, which emits the generated defaults() constructors (the same machinery that produced sdk/runanywhere-swift/Sources/RunAnywhere/Generated/RAConvenience.swift:428-437 and the Kotli…

**Do first:**
  1. SPLIT THE EDIT. Land the four comment lines now - they are 90% of the value, carry zero behavioural risk, and stop the cross-engine index/query mismatch by documenting it.
  1. Do NOT add `(runanywhere.v1.rac_default) = "true"` in the same breath. First read idl/codegen/generate_defaults_pool.py and confirm whether it emits a set for `optional` scalars; if it does, the annotation changes has_truncate() and therefore engine behaviour.
  1. If you want the default to be real, make commons own it instead: change the unset mapping at sdk/runanywhere-commons/src/foundation/rac_proto_adapters.cpp:867 from proto-unset -> -1 to proto-unset -> 1, and update rac_embeddings_types.h:112-118 so the header and the proto agree. That is a deliberate, reviewable behaviour change with one diff site, not an emergent side effect of a codegen annotation.
  1. Either way, keep the sentence that a backend MAY aggregate over a sliding window - rac_embeddings_types.h:112-118 documents it as deliberate and banning it makes long-document embedding strictly worse.


### `E2` — Make EmbeddingsOptions.normalize the one honored normalize flag

**Proto location:** [embeddings_options.proto (EmbeddingsOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto), [embeddings_options.proto (EmbeddingsConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto)

**Why:** Today normalize is a documented, public lie. Swift (EmbedOptions.normalize: Bool = true), Kotlin (NormalizeMode.NONE) and Web (normalize: 'none' | 'l2') all serialize it faithfully onto the wire, and rac_proto_adapters.cpp:844 then does out->normalize = RAC_EMBEDDINGS_NORMALIZE_L2 and never calls in.normalize(). An app asking for unnormalized vectors gets unit vectors with no error and no warning. The wiring is nearly free: RAC_EMBEDDINGS_NORMALIZE_NONE already exists in rac_embeddings_types.h and MLX already implements the NONE branch. Making it `optional` gives unset-vs-explicit-false, which is what lets the default be stated instead of inherited.

**Skeptic verdict:** `sound`

**What changed:** Changed `bool normalize = 4;` to `optional bool normalize = 4 [(runanywhere.v1.rac_default) = "true"];` in EmbeddingsOptions and documented it (unit-length L2 for cosine search; unset = true; false returns the raw pooled vector). Because E3 deleted EmbeddingsConfiguration.normalize in the same wave, `normalize` is now declared exactly once in the file.

**Files touched:** `embeddings_options.proto`

**Status:** `applied`


### `E3` — Delete EmbeddingsConfiguration and CreateRequest.configuration

**Proto location:** [embeddings_options.proto (EmbeddingsConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto), [embeddings_options.proto (EmbeddingsCreateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto)

**Why:** The whole message is inert. There is no rac_embeddings_config_from_proto anywhere in commons — only a forward declaration at rac_embeddings_proto_adapters.h:23 — and rac_embeddings_create_proto reads only model_id() and config_json(). Its normalize and pooling duplicate EmbeddingsOptions tags 4 and 5, so this is the classic Configuration-AND-Options overlap anti-shape with the Configuration half dead. It is also where all the documented rac_default values live, so the generated RAEmbeddingsConfiguration.defaults() and the RAC_DEFAULT_EMBEDDINGS_CONFIGURATION_* macros in rac_defaults_generated.h describe behaviour no code implements and have zero consumers repo-wide. embedding_dimension and max_sequence_length are model FACTS that EmbeddingsCreateResult.dimension / .max_tokens already report from the backend; preferred_framework belongs on the model-load path. Seven fields and a two-message split disappear in one edit.

**Skeptic verdict:** `risky` — Same failure mode as the VADConfiguration mistake: 'zero consumers repo-wide' was asserted, and the Kotlin defaults test at GeneratedConfigurationDefaultsTest.kt:33 is a hard third consumer that breaks the build. The migration list must add: delete that assertion, regenerate Swift RAConvenience (loses three validators), regenerate the four vendored xcframework rac_defaults_generated.h copies, and drop the now-unused `import "model_types.proto"`. The deletion itself is defensible; the risk accounting is not.

**What changed:** Deleted the whole `message EmbeddingsConfiguration` (model_id, embedding_dimension, max_sequence_length, preferred_framework, normalize, pooling, config_json) and deleted `EmbeddingsCreateRequest.configuration`. Per the no-backwards-compatibility ground rule I deleted outright with no `reserved` tombstone and renumbered `EmbeddingsCreateRequest.config_json` from 3 to 2 so the message is dense (1,2). InferenceFramework was the file's only model_types.proto user, so I also dropped `import "model_types.proto"`. I did NOT move EmbeddingsConfiguration.pooling's rac_default of EMBEDDINGS_POOLING_STRATEGY_MEAN onto EmbeddingsOptions.pooling as carePlan.doFirst suggests: that default contradicts E9's approved enum comment 'UNSPECIFIED = inherit the bundle's pooling', and on a non-optional proto3 enum it would make every generated defaults() serialize MEAN and override the bundle, which is the same silent-override defect E10's correctionNeeded forbids.

**Files touched:** `embeddings_options.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** The 'zero consumers repo-wide' claim is FALSE - there are two source consumers and eleven vendored header copies. (1) HARD BUILD BREAK, Kotlin: sdk/runanywhere-kotlin/src/test/kotlin/com/runanywhere/sdk/public/extensions/GeneratedConfigurationDefaultsTest.kt:8 `import ai.runanywhere.proto.v1.EmbeddingsConfiguration`, :24 `assertNull(configuration.embedding_dimension)`, :33 `assertEquals(384, EmbeddingsConfiguration.defaults().embedding_dimension)`. Three lines, and the file will not compile after regeneration. (2) Swift generated convenience, regenerated away: sdk/runanywhere-swift/Sources/Ru…

**Wire safety:** EmbeddingsCreateRequest field 2 is retired -> the proposed `reserved 2; reserved "configuration";` is correct and mandatory. The EmbeddingsConfiguration message itself is deleted whole, so its internal tags (1,2,3,5,7,8,9 plus the 4/6 gaps) need no reservation - they vanish with the type. No surviving field is renumbered. Merge the `reserved 2;` into whatever reserved statement E8 already put in …

**Do first:**
  1. Land E8 first so the `reserved 2;` merges into an existing statement.
  1. Decide where the defaults go BEFORE deleting: move `pooling`'s EMBEDDINGS_POOLING_STRATEGY_MEAN default onto EmbeddingsOptions.pooling (tag 5) as a rac_default, and land the normalize default (E2) - otherwise rac_defaults_generated.h loses the only nominal off-switch for both.
  1. Edit sdk/runanywhere-kotlin/src/test/kotlin/com/runanywhere/sdk/public/extensions/GeneratedConfigurationDefaultsTest.kt: delete line 8's import and lines 24 and 33, or repoint them at EmbeddingsOptions once the defaults have moved. Do this in the SAME commit as the proto edit.
  1. Edit the proto (delete EmbeddingsConfiguration, add `reserved 2; reserved "configuration";` to EmbeddingsCreateRequest), then check whether model_types.proto is still needed: `rg -n 'InferenceFramework|ModelInfo|model_types' idl/embeddings_options.proto` - drop the import only if it comes back empty.
  1. Delete rac_embeddings_proto_adapters.h:23 in sdk/runanywhere-commons/include/ AND in the three sdk/runanywhere-swift/Binaries/RACommons.xcframework/*/Headers/ copies.
  1. Regenerate, then re-vendor ALL ELEVEN rac_defaults_generated.h copies listed above (flutter 3, swift 3, react-native ios 3, react-native android jniLibs 1, plus canonical) - a partial re-vendor leaves three prebuilt SDKs shipping a header that names a message that no longer exists.


### `E4` — Add dimensions (Matryoshka width) to EmbeddingsOptions

**Proto location:** [embeddings_options.proto (EmbeddingsOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto), [embeddings_options.proto (EmbeddingsConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto)

**Why:** On-device vector stores are RAM- and flash-bound, and this is the biggest storage lever in the domain: EmbeddingGemma-300m is MRL-trained at 768/512/256/128, so a 100k-chunk local index is ~1.2 GB or ~200 MB depending on one field. The only dimension-shaped input we have today is EmbeddingsConfiguration.embedding_dimension, whose own comment says it 'must match the loaded model's hidden size' — that is an assertion you can get wrong, not a request, and E3 deletes it. Unlike the output-dtype gap this can be honoured entirely inside commons (truncate the float array, then re-normalize), so it does not repeat the E2 trap.

**Skeptic verdict:** `sound` — Two care items, not blockers. (1) `grep -rni 'matryoshka|\bmrl\b'` over the whole tree returns ZERO - there is no bundle-declared MRL width list anywhere, so the risk note's 'validate against the widths the bundle declares' has no data source today; the field must therefore accept any width <= native or it cannot ship. (2) EmbeddingsOptions.dimensions sitting beside EmbeddingsResult.dimension and EmbeddingVector.dimension in the same 137-line file is a plural/singular footgun for exactly the newcomer this review is optimizing for.

**What changed:** Added `optional int32 dimensions = 8 [(runanywhere.v1.rac_min) = 1];` to EmbeddingsOptions for Matryoshka output width. Per carePlan.correctionNeeded I dropped the fabricated 'must be one of the MRL widths the bundle declares' contract (no such declaration exists anywhere in idl/) and wrote 'accepts any width in [1, the native width]; a width the model was not MRL-trained at is silently worse'. I kept the approved name `dimensions` and, per the doFirst alternative, disambiguated it in the comment against the surviving `dimension` fields: it is the request-side width, EmbeddingsResult.dimension reports the produced width.

**Files touched:** `embeddings_options.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** Nothing breaks by adding the field; the danger is entirely in the honouring path being half-done. Truncation has to happen at rac_embedding_vector_to_proto (sdk/runanywhere-commons/src/foundation/rac_proto_adapters.cpp:877-886, five lines that copy only `values` out of `rac_embedding_vector_t`, whose members are `float* data; size_t dimension;` at rac_embeddings_types.h:137-142), driven from rac_embeddings_result_to_proto which loops `add_vectors()` at rac_proto_adapters.cpp:909 and sets the result-level width at :911 (`out->set_dimension(static_cast<int32_t>(in->dimension))`). If you truncat…

**Wire safety:** Purely additive: new optional int32 at tag 8 in EmbeddingsOptions (2,3,4,5,6 in use; 7 goes to E1). No tag reuse, no renumbering, no enum change. Old clients that never set it get native width. If E8 lands `reserved 1;` in EmbeddingsOptions that is unrelated - just make sure E8 does not also reserve 8.

**Do first:**
  1. Weaken the comment to match reality: no bundle declares MRL widths anywhere in this tree, so the proto must say "accepted range is 1..native width; an untrained width is silently worse" rather than "must be one of the MRL widths the bundle declares". Do not ship a contract with no data source.
  1. Implement truncate + re-normalize in ONE place: rac_embedding_vector_to_proto (rac_proto_adapters.cpp:877-886), and in the same function/caller set EmbeddingsResult.dimension at rac_proto_adapters.cpp:911 to the TRUNCATED width, not `in->dimension`.
  1. Do NOT populate EmbeddingVector.norm from a pre-truncation value - a stale norm poisons all three cosine helpers (Swift :22-23, Kotlin :32-33, Web :236-237). Either leave it unset (today's behaviour) or set it to 1.0 after re-normalization. Coordinate with E5, which may delete the field entirely.
  1. Reject dimensions > native width with a real error rather than silently ignoring it - a silently-ignored width is the same defect class this domain's E1 is about.
  1. Rename to `output_dimension` (matching Cohere and Voyage) if you want to avoid the dimensions/dimension collision with lines 82, 102 and 133 of the same file; if you keep `dimensions`, say in the comment that it is the request-side width and EmbeddingsResult.dimension is the produced width.


### `E5` — Shrink EmbeddingVector to values + input_index

**Proto location:** [embeddings_options.proto (EmbeddingVector)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto), [embeddings_options.proto (EmbeddingVector)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto), [embeddings_options.proto (EmbeddingVector)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto), [embeddings_options.proto (EmbeddingVector)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto)

**Why:** Four of six fields are unusable. rac_embedding_vector_to_proto (rac_proto_adapters.cpp:877-886) is five lines and copies only `values`; set_norm, set_dimension and mutable_metadata appear nowhere in the tree, and `dimension` duplicates EmbeddingsResult.dimension, which is the copy that IS populated. `text` is the expensive one: commons echoes every input string back inside the result (embeddings_module.cpp:256 and :425) and all three facades map the vector down to {index, vector} and drop it, so a batch of 500 long chunks pays for the corpus twice on a memory-constrained device. `norm` would always be 1.0 under L2 anyway. Keeping input_index but contracting it as ALWAYS set lets Swift's `proto.inputIndex > 0 ? ... : fallbackIndex` (Results.swift:271) and Kotlin's identical idiom (MappingResults.kt:146) be deleted.

**Skeptic verdict:** `risky` — 'only `text` is actually written today so no behaviour is lost' is wrong on two counts. A commons test asserts text-preservation as a contract (test_advanced_modality_proto_abi.cpp:683) and will fail, and `rac embed --json` loses its per-vector `dimension` output field while cmd_embed.cpp:61,66 stop compiling. Per-vector `dimension` is also read there, so field 4 is not dead surface either. Fixable, but three consumers must be in the same change and the CLI JSON shape change is user-visible.

**What changed:** Shrank EmbeddingVector to `repeated float values = 1;` plus `int32 input_index = 2;`, deleting norm, text, dimension and metadata outright (no `reserved`, per the ground rules) and renumbering input_index from 5 to 2 to close the gap. input_index now carries the ALWAYS-SET contract comment. Note the identifier `dimension` is still legitimately present in the file (EmbeddingsResult.dimension tag 2 and EmbeddingsCreateResult.dimension tag 3), so I do not assert it absent — only EmbeddingVector.dimension was removed.

**Files touched:** `embeddings_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Four of the six fields have real readers; the proposal's "only `text` is actually written today so no behaviour is lost" is true about WRITES and false about READS. This is the VADConfiguration failure shape. (1) `norm` (tag 2) is read by the public cosine-similarity helper in ALL THREE facades and deleting it is a compile break in Swift, Kotlin and TypeScript at once: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Embeddings/EmbeddingsProto+Helpers.swift:22-23 (`let aNorm = hasNorm ? norm : Self.l2(values)` / `let bNorm = other.hasNorm ? other.norm : Self.l2(other.values)`), sdk…

**Wire safety:** Fields 2, 3, 4, 6 retired -> `reserved 2, 3, 4, 6;` plus `reserved "norm", "text", "dimension", "metadata";` is correct and mandatory. Field 5 (input_index) keeps its number and its type; field 1 (values) untouched. No renumbering, no tag reuse. Note field 5's semantics change from optional-in-practice to always-set - that is a contract change on the same wire type, invisible to decoders, so old …

**Do first:**
  1. DECIDE `norm` before anything else. It is not dead surface - three public cosine helpers read it. Either (a) keep tag 2 and shrink to values + input_index + norm, or (b) delete it and, in the SAME change, rewrite all three helpers to always compute l2(): EmbeddingsProto+Helpers.swift:22-23, EmbeddingsProtoHelpers.kt:32-33, RunAnywhere+Embeddings.ts:236-237, and update their doc comments (Kotlin :22-23, Web :227-228) which currently promise the precomputed-norm behaviour.
  1. Make embeddings_module.cpp:256 call `set_input_index(i)` alongside (or instead of) `set_text` - the handle path must honour the ALWAYS SET comment before the comment is written, or the new contract is the next lie.
  1. Rewrite sdk/runanywhere-cli/src/commands/cmd_embed.cpp:60-66: drop the `vector.has_text()` fallback (the `texts` vector is already in scope at :62) and drop the per-vector `"dimension"` JSON key. Announce the JSON shape change - it is user-visible.
  1. Repoint the two commons tests off `text`: test_advanced_modality_proto_abi.cpp:683 and test_nonllm_lifecycle_proto_abi.cpp:510 should assert ordering via `vectors(i).input_index() == i` instead of `vectors(0).text() == "alpha"`.
  1. Only now delete the writes at embeddings_module.cpp:256 and :425 (`set_text`), then edit the proto with `reserved 2, 3, 4, 6;` (merging with any E8 statement).
  1. Last, simplify the two now-redundant fallbacks - Results.swift:271 and MappingResults.kt:146 - to read input_index unconditionally. They are correct either way (index 0 falls through to the same position value), so this is cleanup, not a break.


### `E6` — Delete EmbeddingsResult.error and EmbeddingsRequest.metadata

**Proto location:** [embeddings_options.proto (EmbeddingsResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto), [embeddings_options.proto (EmbeddingsRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto)

**Why:** Neither field is ever written. Both embed paths fail through rac_proto_buffer_set_error, which calls release_fields() and frees the body (rac_proto_buffer.cpp:109-125), so mutable_error() is never called on an EmbeddingsResult and Swift's `if result.hasError { throw SDKException(proto: result.error) }` is unreachable dead code at three call sites. Meanwhile EmbeddingsCreateResult.error IS genuinely populated (populate_sdk_error at embeddings_module.cpp:300 and :313) — so one 137-line file teaches two opposite conventions, and the next SDK author will copy the dead one and wonder why their error tests never fire. request.metadata() has zero reads in embeddings_module.cpp; the Web facade sends `metadata: {}` on every call for nothing.

**Skeptic verdict:** `not-simpler` — The proposal supplies its own decline gate - 'If the repo-wide convention is instead every Result carries an error, decline this' - and the grep says the convention IS repo-wide: 70 SDKError fields in 19 protos. Deleting it from EmbeddingsResult alone makes embeddings the one modality whose result shape differs, which is harder for a newcomer reading 19 files, not easier, and it leaves EmbeddingsCreateResult.error in the same file anyway - so the 'one file teaches two conventions' complaint survives the edit. Split it: the metadata half (tag 5) is genuinely dead with zero readers and should land; the error half should be declined or raised as a cross-domain decision.

**What changed:** Deleted `EmbeddingsRequest.metadata` (tag 5) and `EmbeddingsResult.error` (tag 9) outright, no `reserved`, and renumbered EmbeddingsResult.request_id from 8 to 6 so that message is dense (1..6). EmbeddingsCreateResult.error was deliberately NOT touched (it is the genuinely populated one), so the identifiers `error` and `SDKError` each still appear exactly once in the file — a verifier should check that count rather than absence. I did NOT also delete request_id from EmbeddingsRequest/EmbeddingsResult even though globalRule rule-no-request-correlation-bag names it: E6's approved after-text explicitly retains both, no carePlan analysis of request_id's consumers exists, and the edit that covered it (E7) is not in this brief.

**Files touched:** `embeddings_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The error half has FIVE readers, not the three the brief names, and two of them are live C++ that will not compile. (1) sdk/runanywhere-commons/src/solutions/operators/op_engine_backed.cpp:673 declares `runanywhere::v1::EmbeddingsResult result;` and :680-681 does `if (result.has_error()) { set_error_detail(name(), "embeddings call failed: " + result.error().message()); ... }` - this is commons' own pipeline operator, the authoritative business logic, not Swift dead code. (2) sdk/runanywhere-cli/src/commands/cmd_embed.cpp:218 declares `v1::EmbeddingsResult result;` and :226-229 reads `result.e…

**Wire safety:** EmbeddingsRequest field 5 and EmbeddingsResult field 9 retired -> `reserved 5; reserved "metadata";` and `reserved 9; reserved "error";` are correct and mandatory. Merge the `reserved 9;` into E8's `reserved 6, 7;` on EmbeddingsResult as one statement. EmbeddingsCreateResult.error (tag 7, line 136) MUST NOT be touched - it is the genuinely populated one (embeddings_module.cpp:300, :313, :316). No…

**Do first:**
  1. SPLIT THIS INTO TWO COMMITS. The metadata half and the error half have nothing in common except the file.
  1. Commit A (metadata, low risk): delete `metadata: {},` at sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+Embeddings.ts:127, then delete tag 5 with `reserved 5; reserved "metadata";`, regenerate, `npm run build` in packages/core.
  1. Commit B (error) - decide the convention FIRST. The proposal supplies its own decline gate and the repo answers it: SDKError is on ~70 fields across 19 protos, and EmbeddingsCreateResult.error in this same file stays. If you keep the deletion anyway, then in ONE commit: rewrite op_engine_backed.cpp:680-681 to surface the failure from the rac_proto_buffer error channel; rewrite cmd_embed.cpp:226-229 the same way; delete the three Swift `if result.hasError` branches (EmbeddingsNamespace.swift:35, RunAnywhere+Embeddings.swift:125, :144); then delete tag 9.
  1. Do not touch EmbeddingsCreateResult.error (embeddings_options.proto:136) or the populate_sdk_error calls at embeddings_module.cpp:300/:313/:316.


### `E8` — Reserve every skipped tag in embeddings_options.proto

**Proto location:** [embeddings_options.proto (EmbeddingsOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto), [embeddings_options.proto (EmbeddingsResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto), [embeddings_options.proto (EmbeddingsCreateResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto)

**Why:** The file has seven skipped tags across four messages and not one `reserved` statement: EmbeddingsConfiguration skips 4 and 6, EmbeddingsOptions has no field 1, EmbeddingsResult skips 6 and 7, EmbeddingsCreateResult skips 5 and 6. This is the cheapest change in the review and it is the safety net for every deletion in E3, E5, E6 and E7 — those add several more gaps. Nothing about it is breaking or behavioural.

**Skeptic verdict:** `not-simpler` — The stated rationale is misdescribed: protobuf's `reserved` exists for RETIRED field numbers, not for numbering gaps. Nothing in the file or in this checkout shows tags 6/7 of EmbeddingsResult or 5/6 of EmbeddingsCreateResult were ever used, and reserving them permanently burns five reusable tags while teaching a reader something false by implication. It also collides editorially with E5/E6/E7, which each add their own `reserved` lines to the same two messages. Reserve only numbers you can prove were shipped and deleted (check git history in the real repo); leave never-assigned gaps free.

**What changed:** Nothing. No reserved statement was added to embeddings_options.proto.

**Status:** `skipped`

**Care level:** `sequenced`

**What could break:** Nothing found. `rg -n 'reserved' idl/embeddings_options.proto` returns zero hits (no existing statement to collide with), and reserved statements are inert for codegen. The precedent is established elsewhere in the same idl dir: `rg -c 'reserved' idl/*.proto` gives model_types.proto:9, tool_calling.proto:8, and 1 each in vlm_options / router / sdk_events / rag / errors / download_service / connect - so adding them to embeddings_options.proto matches house style. The only real cost is editorial collision with E3/E5/E6, which each add their own reserved lines to messages E8 also touches.

**Wire safety:** No wire change to any live field. `reserved` is schema text only; no generated type changes shape. HAZARD: reserving a number permanently burns it. E8 must NOT reserve 7 or 8 in EmbeddingsOptions - E1 claims tag 7 and E4 claims tag 8, and `rg -n 'reserved' idl/embeddings_options.proto` confirms the file has ZERO reserved statements today, so nothing protects those numbers from a careless `reserve…

**Do first:**
  1. Land E8 FIRST, before E3/E5/E6, so those three merge their reserved lines into an existing statement instead of adding a second one to the same message.
  1. Drop `reserved 6, 7;` from EmbeddingsResult and `reserved 5, 6;` from EmbeddingsCreateResult unless you can prove in the real RunanywhereAI/runanywhere-sdks git history (`git log -p -- idl/embeddings_options.proto | grep -n 'tokens_used\|= 6;\|= 7;'`) that those numbers were ever assigned fields. This checkout has no history; do that check on the build host.
  1. Keep `reserved 1;` in EmbeddingsOptions only if history shows tag 1 was shipped. If it was never assigned, leaving it free costs nothing and reserving it burns a low number in the message that E1 and E4 are both about to extend.
  1. In the same edit, plan the merge target: E6 wants `reserved 9;` in EmbeddingsResult - write it as one statement (`reserved 6, 7, 9;`) when E6 lands, not a second `reserved` line.


### `E9` — Pin pooling's public spelling to last, not max

**Proto location:** [embeddings_options.proto (EmbeddingsPoolingStrategy)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/embeddings_options.proto)

**Why:** This is the only live, shipped, user-visible semantic bug in the domain. The proto says EMBEDDINGS_POOLING_STRATEGY_LAST, but Web's public union is `pooling?: 'mean' | 'cls' | 'max'` (Options.ts:156) and Mapping.ts:437 maps `max` onto LAST — so a caller asking for element-wise max-pooling silently receives last-token pooling: valid-looking vectors, wrong semantics, no error. Swift (PoolingMode.last) and Kotlin (PoolingMode.LAST) are correct, so Web is the sole outlier. The enum carries no comment, which is exactly why it drifted; writing the contract into the proto is what stops the next SDK from drifting the same way.

**Skeptic verdict:** `sound` — Only caveat: as a comment-only edit it does not fix anything - it makes the proto assert 'no SDK may expose it as max' while an SDK does, so the comment is false the moment it merges unless Options.ts:156 + Mapping.ts:437 change in the same commit. The Web rename is the actual fix; the comment is the guardrail.

**What changed:** Added the contract comment above enum EmbeddingsPoolingStrategy and an inline note on UNSPECIFIED ('inherit the bundle's pooling'). Comment-only: no enum value, tag or number changed. I phrased the first line as 'The required public spelling in every SDK is exactly "mean" / "cls" / "last"' rather than the proposal's indicative 'The public spelling in EVERY SDK is...', because per carePlan two shipped SDKs currently violate it (Web Options.ts:156 and Python options.py:184 both expose it as max) and an indicative sentence would make the proto assert something false today. The normative wording keeps the comment truthful while stating the contract those two must be renamed to.

**Files touched:** `embeddings_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Two SDKs expose LAST as "max", not one. (1) Web: sdk/runanywhere-web/packages/core/src/Public/API/Options.ts:156 declares `pooling?: 'mean' | 'cls' | 'max';` and sdk/runanywhere-web/packages/core/src/Public/API/Mapping.ts:434-437 declares `const POOLING_MODES: Record<NonNullable<EmbedOptions['pooling']>, EmbeddingsPoolingStrategy>` with `max: EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_LAST`, consumed at Mapping.ts:446-447. Because POOLING_MODES is keyed by the union type, renaming Options.ts:156 without renaming Mapping.ts:437 is a compile error - the two edits are mechanically cou…

**Wire safety:** No wire change. Comment-only in the proto; no tag, no enum value, no renumbering. EMBEDDINGS_POOLING_STRATEGY_LAST stays = 3. The breaking part is entirely in two SDK source languages.

**Do first:**
  1. Rename Web in one commit: Options.ts:156 `pooling?: 'mean' | 'cls' | 'max'` -> `'mean' | 'cls' | 'last'`, and Mapping.ts:437 key `max:` -> `last:`. tsc will fail the build if you do only one.
  1. Rename Python in the same commit: options.py:184 `MAX = 2` -> `LAST = 2`. Grep the Python examples and tests first (`rg -n 'PoolingMode\.MAX' sdk/runanywhere-python`) - my sweep found no in-repo user, but re-run before deleting the name.
  1. Only then add the proto comment. Merging the comment first makes the proto assert something false about two shipped SDKs.


</details>


<details>
<summary><strong>events-naming</strong> (5 changes)</summary>

### `events-naming-duration-one-name-one-type` — One name and one type per duration: int64 `*_ms`, and stop measuring TTFT twice

**Proto location:** [sdk_events.proto (GenerationEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L385), [sdk_events.proto (GenerationEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L388), [sdk_events.proto (GenerationEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L423), [sdk_events.proto (GenerationEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L429)

**Why:** GenerationEvent carries five duration fields for three concepts. `first_token_latency_ms` and `time_to_first_token_ms` are the same measurement, and the proto has to explain in a comment which event kind populates which. `latency_ms` and `duration_ms` are likewise both the whole-generation wall clock -- and `duration_ms` is a `double` while every other duration in the domain is an int64. PerformanceEvent then names its duration `milliseconds`, a unit with no noun attached.

**Skeptic verdict:** `risky` — The `after` block silently reuses tag 32 with an incompatible wire type: `double duration_ms = 32` becomes `int64 total_duration_ms = 32`, i.e. fixed64 -> varint on an unchanged tag. Most runtimes treat a wire-type mismatch as an unknown field and skip it, so a mixed-version pair does not error -- the reader just sees 0 for total generation duration. The proposal's own risk note admits '32 must also be treated as a break or moved', but the proposed diff does neither; it must be `reserved 32;` plus a fresh tag. Live blast radius for that field is real: telemetry_manager.cpp:1055 consumes it as a double today. Separately, the retirement of tags 9/10 breaks more than the flagged C++ writers -- sdk/runanywhere-web/packages/core/src/Foundation/EventBus.ts:94 declares `'generation.completed': { tokensUsed: number; latencyMs: number }` and :779 reads `e.latencyMs`, so a hand-written non-C++ reader also has to move. Minor: the simplicityGain promises every duration becomes `<noun>_duration_ms`, then renames PerformanceEvent.milliseconds to a nounless `duration_ms`, violating its own rule.

**What changed:** Already landed by an earlier wave (core/platform touched sdk_events.proto first): GenerationEvent fully renumbered 1-31 dense, tags 9/10/32 gone (no reserved -- no-backcompat), time_to_first_token_ms/total_duration_ms/prefill_duration_ms are the three surviving durations.

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** GenerationEvent.latency_ms (tag 9) -- WRITERS: sdk/runanywhere-commons/src/features/llm/llm_module.cpp:205 `g.set_latency_ms(static_cast<int64_t>(duration_ms));`, sdk/runanywhere-commons/src/features/llm/llm_module.cpp:1468 `generation->set_latency_ms(latency_ms);`, sdk/runanywhere-commons/src/core/events.cpp:123 `g.set_latency_ms(static_cast<int64_t>(duration_ms));`. READER: sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_manager.cpp:1055 `g.duration_ms() != 0.0 ? g.duration_ms() : static_cast<double>(g.latency_ms());` -- this ONE line reads both tag 32 and tag 9 and is the fa…

**Wire safety:** Tags 9 and 10 are retired: emit BOTH `reserved 9, 10;` and `reserved "latency_ms", "first_token_latency_ms";` so neither the number nor the name can be re-minted later. Tag 32 MUST NOT be reused as written: `double duration_ms = 32` is wire-type 1 (fixed64) and `int64 total_duration_ms = 32` is wire-type 0 (varint); protobuf treats a wire-type mismatch on a known tag as an unknown field and skips…

**Do first:**
  1. Confirm the next free tag in GenerationEvent before writing the diff: `rg -n '= [0-9]+;' idl/sdk_events.proto | sed -n '/message GenerationEvent/,/^}/p'` -- or read the generated Kotlin ctor at sdk/runanywhere-kotlin/.../GenerationEvent.kt:538, which lists every field in tag order and ends at prompt_eval_time_ms(34). Use 35 for total_duration_ms; do NOT reuse 32.
  1. Fix the proposal's `after` block BEFORE anyone applies it: it currently writes `int64 total_duration_ms = 32`, which is a fixed64->varint reuse on an unchanged tag. Replace with `reserved 9, 10, 32;` + `reserved "latency_ms", "first_token_latency_ms", "duration_ms";` + `int64 total_duration_ms = 35;`.
  1. Step 1 (commons writers, still on the old fields): repoint sdk/runanywhere-commons/src/features/llm/llm_module.cpp:245 and sdk/runanywhere-commons/src/core/events.cpp:157 from set_first_token_latency_ms to set_time_to_first_token_ms -- both already hold a variable named time_to_first_token_ms, so tag 26 becomes populated on FIRST_TOKEN_GENERATED without any behaviour change. Land and ship this alone first; it makes tag 10 redundant on the wire before it disappears.
  1. Step 2 (still old proto): make llm_module.cpp:205-206 and core/events.cpp:123-124 write BOTH latency_ms(9) and duration_ms(32) from the same source value (they already do, one as int64, one as double) so no reader depends on the 9-vs-32 fallback. Then simplify telemetry_manager.cpp:1055 to read tag 32 only and telemetry_manager.cpp:1063 to read tag 26 only. Ship. Now 9 and 10 are provably dead on this device fleet.
  1. Step 3 (the proto edit): apply the corrected reserved block + rename 34 -> prefill_duration_ms + PerformanceEvent 5 milliseconds -> duration_ms, then regenerate ALL five checked-in binding sets in the same commit: sdk/runanywhere-commons/src/generated/proto/sdk_events.pb.{h,cc}, sdk/shared/proto-ts/src/sdk_events.ts, sdk/runanywhere-swift/Sources/RunAnywhere/Generated/sdk_events.pb.swift, sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/ai/runanywhere/proto/v1/GenerationEvent.kt (+PerformanceEvent.kt). Leaving any one stale is a silent skew, not a build error.
  1. Step 4 (same commit as step 3, non-negotiable): edit sdk/runanywhere-web/packages/core/src/Foundation/EventBus.ts:94, :779 and :911 -- change the `'generation.completed'` payload key from latencyMs to totalDurationMs (or keep the public key latencyMs and source it from e.totalDurationMs; either is fine, but the right-hand side MUST stop being e.latencyMs). This is the file the previous VADConfiguration review would have missed.
  1. Step 5: update writers to the new names -- llm_module.cpp:205-206 -> set_total_duration_ms(static_cast<int64_t>(duration_ms)) (add the cast; the old field was a double), llm_module.cpp:1468, core/events.cpp:123-124, llm_module.cpp:211 -> set_prefill_duration_ms. Update the two test writers test_telemetry_extraction.cpp:118 and test_rcli_telemetry_live.cpp:228.
  1. Explicitly DO NOT touch, in any step: llm_module.cpp:1765 (PerformanceMetrics.latency_ms, llm_options.proto), NetworkEvent.latency_ms, the JSON string keys "prompt_eval_time_ms" at telemetry_json.cpp:308/341 and the properties-map key at telemetry_manager.cpp:1330 and test_telemetry_extraction.cpp:217/228, and every non-GenerationEvent set_duration_ms call site.


### `events-naming-framework-one-type` — Spell `framework` one way: the InferenceFramework enum, never int32, never string

**Proto location:** [sdk_events.proto (GenerationEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L430), [sdk_events.proto (VoiceLifecycleEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L534), [sdk_events.proto (ModelEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L714), [sdk_events.proto (FrameworkEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1026)

**Why:** The same concept is encoded three different ways inside one domain: as the typed enum in ComponentLifecycleSnapshot/ModelRegistryEvent/HardwareRoutingEvent, as a bare int32 with a comment telling you to decode it yourself in GenerationEvent/VoiceLifecycleEvent/ModelEvent/FrameworkEvent, and as a free-text string in LogEntry. A newcomer reading two events side by side sees `framework: 4` in one and `framework: "llamacpp"` in the other and cannot tell they are the same field. The int32 form exists only to dodge a cross-file import that four other messages in the same file already take.

**Skeptic verdict:** `sound` — Two soft spots that do not sink it. (1) The stated motive is wrong: the proposal says the int32 'exists only to dodge a cross-file import', but sdk_events.proto already imports model_types.proto at line 55, and the proto's own comments at 420-421 and 709-710 give a different reason -- 'matches FrameworkEvent.framework', i.e. parity with a sibling, not import avoidance. The conclusion (int32 is gratuitous inside this file) still holds. (2) The industry precedent partly cuts against the proposal: OpenTelemetry's `gen_ai.provider.name` is a STRING attribute, not an enum, so OTel is evidence for the LogEntry spelling the proposal wants to delete. The defensible borrowed claim is only 'one spelling per concept', not 'that spelling must be an enum'. Also unmentioned: InferenceFramework carries `reserved 8, 9, 10, 17, 18` (model_types.proto:99), so any persisted LogEntry string that mapped to a reserved slot has nowhere to land in the one-time migration.

**What changed:** logging.proto LogEntry.framework and sdk_events.proto ComponentLifecycleSnapshot.framework were already InferenceFramework from an earlier wave. I fixed the two remaining int32 sites myself: ModelEvent.framework (tag 16) and FrameworkEvent.framework (tag 2), both same-tag int32->enum (wire-compatible, varint both sides).

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`


### `events-naming-token-counts` — Use the industry's token words: `input_tokens` / `output_tokens`, and only those

**Proto location:** [sdk_events.proto (GenerationEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L380), [sdk_events.proto (GenerationEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L384), [sdk_events.proto (GenerationEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L416)

**Why:** GenerationEvent carries `tokens_count`, `tokens_used`, and `input_tokens` and nothing in the names says which direction each one counts -- `tokens_count` is the running output count during streaming and `tokens_used` is the same output count at completion, so the two are one quantity at two points in time. The proto even has to spell the arithmetic out in a comment ('totalTokens = input_tokens + tokens_used').

**Skeptic verdict:** `sound` — Only scope gaps, no defect. The risk note names the COMPLETED writer but not the full writer set I found -- core/events.cpp:122 and features/llm/llm_module.cpp:204 write tokens_used, while core/events.cpp:166, llm_module.cpp:255 and :1464, vlm_module.cpp:1154, and llm/tool_calling_generation_internal.h:155,204 write tokens_count -- and it misses a hand-written non-C++ reader of the retired tag: sdk/runanywhere-web/packages/core/src/Foundation/EventBus.ts:94,778,910 consume `tokensUsed`. Also 'OpenAI ... REMOVED the older prompt_tokens/completion_tokens spelling outright' is an overstatement: Chat Completions still returns them; it is the Responses API that adopted input/output/total.

**What changed:** Already landed by an earlier wave: GenerationEvent.tokens_count and tokens_used folded into output_tokens (tag 6); input_tokens survives (tag 21); comment states input_tokens + output_tokens = total.

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`


### `events-naming-voice-one-name-per-concept` — Give VoiceLifecycleEvent one name per concept and kill the `_tts` suffix

**Proto location:** [sdk_events.proto (VoiceLifecycleEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L493), [sdk_events.proto (VoiceLifecycleEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L511), [sdk_events.proto (VoiceLifecycleEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L527), [sdk_events.proto (VoiceLifecycleEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L528)

**Why:** VoiceLifecycleEvent spells the transcript twice (`text`, `transcription`), the assistant reply twice (`response_text`, `turn_response`), the synthesized audio twice (`audio_base64`, `turn_audio_base64`), and audio duration three times (`duration_ms`, `audio_length_ms`, `audio_duration_ms`) -- with a comment admitting field 24 is 'distinct from duration_ms(7)'. `audio_size_bytes_tts` exists purely because `audio_size_bytes` was already taken, so a field name now encodes which component wrote it, even though the envelope's `component` already says that. A newcomer has no way to guess which of two identical-looking string fields their handler should read.

**Skeptic verdict:** `sound` — The data-loss warning is understated on the reader side. The proposal warns only that WRITERS of VOICE_SESSION_* must be repointed, but there is a live hand-written READER outside C++: sdk/runanywhere-web/packages/core/src/Foundation/EventBus.ts:110 declares `'voice.turnCompleted': { speechDetected, transcription, response }` and :814-815 map `transcription: e.transcription` and `response: e.turnResponse` -- both fed by the tags being retired. Retire 9/10/11 without touching that file and voice.turnCompleted silently emits empty strings in the web SDK. Also the arithmetic is wrong: simplicityGain claims '3 names for audio duration -> 2', but the `after` keeps duration_ms(7) alongside input_audio_duration_ms(15) and output_audio_duration_ms(24), so it is still 3 -- 4 counting the untouched processing_duration_ms(26). The rename disambiguates; it does not reduce the duration count. The 26 -> 23 field claim is real, though, and comes from the honest subtraction of 9/10/11.

**What changed:** VoiceLifecycleEvent: reserved 9,10,11 (transcription/turn_response/turn_audio_base64 -- zero writers anywhere, confirmed by care plan); renamed audio_length_ms->input_audio_duration_ms (15), widened audio_size_bytes(16) int32->int64 as input_audio_bytes; renamed audio_duration_ms->output_audio_duration_ms (24), widened audio_size_bytes_tts(25) int32->int64 as output_audio_bytes; framework(22) int32->InferenceFramework same-tag.

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Tags 9/10/11 have NO writer anywhere in the codebase. `rg -n 'voice\.set_transcription|voice->set_transcription|v\.set_transcription' sdk/` returns nothing, and `rg 'set_turn_response|set_turn_audio_base64|turnAudioBase64' sdk/` (generated excluded) returns nothing. The two `set_transcription` hits that DO exist are a different message: sdk/runanywhere-commons/src/features/voice_agent/voice_agent_d7_abi.cpp:874 `out_result->set_transcription(stt.text);` and sdk/runanywhere-commons/src/features/voice_agent/voice_agent_proto_abi.cpp:532 `result.set_transcription(stt.text);` are on VoiceAgentRes…

**Wire safety:** Tags 9, 10, 11 are retired -- emit `reserved 9, 10, 11;` AND `reserved "transcription", "turn_response", "turn_audio_base64";` so the names cannot be re-minted onto different semantics later. Tags 3, 5, 6, 7 are unchanged in number, type and meaning -- comment-only edits, no wire change. Tags 15, 16, 24, 25 keep their numbers; 15 and 24 are int64->int64 renames (pure name change, wire-identical);…

**Do first:**
  1. Land events-naming-duration-one-name-one-type and let its regenerated bindings merge first. Both proposals rewrite sdk_events.pb.h/cc, sdk/shared/proto-ts/src/sdk_events.ts, sdk_events.pb.swift and the Kotlin generated package; running them in parallel produces conflicts in five machine-generated files that no reviewer can merge by eye.
  1. Fix the arithmetic in the proposal text before it becomes a commit message: simplicityGain claims '3 names for audio duration -> 2', but the `after` keeps duration_ms(7) alongside input_audio_duration_ms(15) and output_audio_duration_ms(24) -- still 3, and 4 counting the untouched processing_duration_ms(26). The change disambiguates the three durations; it does not reduce their count. State that instead.
  1. Step 1 (web first, BEFORE the tags disappear): edit sdk/runanywhere-web/packages/core/src/Foundation/EventBus.ts:812-815 to read `transcription: e.text` and `response: e.responseText` (tags 3 and 5). Ship it. This is a strict bug fix on its own -- those two keys are empty strings today because nothing writes tags 9/10 -- and it removes the only live reader of the tags you are about to retire.
  1. Step 2 (proto): apply the reserved block for 9/10/11 plus the reserved names, the comment rewrites on 3/5/6/7, and the four renames on 15/16/24/25 with 16/25 widened to int64. Regenerate all five binding sets in the SAME commit.
  1. Step 3 (same commit): repoint the four telemetry readers by hand -- telemetry_manager.cpp:1129 to v.input_audio_duration_ms(), :1130 to v.input_audio_bytes(), :1172 to v.output_audio_duration_ms(), :1173 to v.output_audio_bytes(). At :1130 and :1173 the destination payload.audio_size_bytes is int32_t (rac_telemetry_types.h:105): either widen that struct field to int64_t or add an explicit static_cast<int32_t>, or the -Werror build breaks. Widening the struct is the better fix but it ripples into telemetry_json.cpp:327 json.add_int -- check that overload takes int64_t before you widen.
  1. Step 4 (same commit): repoint the writers -- core/events.cpp:218-219, 243-244, 293-294; stt_module.cpp:523,526 / 951-952 / 1019-1020 / 1117-1118 / 1174-1175; rac_stt_stream.cpp:479; tts_module.cpp:245,248 / 642-643 -- and change every `static_cast<int32_t>` feeding a byte-count setter to `static_cast<int64_t>`.
  1. Do the renames by explicit file:line edits, never by sed. `audio_length_ms`, `audio_duration_ms` and `audio_size_bytes` each exist on two to four OTHER messages (STTMetadata, TTSMetadata/TTSOutput, DiarizationResult, VoiceAgentResult) with live C++, Kotlin and RN consumers listed in whatCouldBreak. Same for `transcription` -- VoiceAgentResult owns that name in the CLI and two test suites.


### `events-naming-voice-pipeline-timestamp-unit` — Timestamp the voice pipeline in milliseconds like every other event on the stream

**Proto location:** [voice_events.proto (VoiceEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L48), [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1179), [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto)

**Why:** VoiceEvent rides the same SDKEvent stream (SDKEvent.voice_pipeline) but stamps itself in MICROseconds while the envelope and every sibling event use milliseconds. Anyone sorting or diffing a merged stream by time gets numbers 1000x apart with no signal in the type system -- the only hint is a two-letter suffix. This is the one units problem in the domain that produces wrong output rather than confusion.

**Skeptic verdict:** `risky` — This is the one proposal whose failure mode is silent corruption, and the mitigation it offers is too weak for the blast radius. Tag 2 keeps the same number AND the same varint wire type, so a stale writer produces year-57000 timestamps with no parse error -- and 'ship atomically' means touching ~15 writers across 6 files that I enumerated by grep: features/voice_agent/voice_agent_internal_helpers.cpp:309,348,360,383, voice_agent/rac_voice_event_abi.cpp:159, voice_agent/voice_agent_d7_abi.cpp:74, tts/tts_module.cpp:1314,1323,1367,1374, tts/rac_tts_stream.cpp:350, llm/rac_llm_stream.cpp:195, llm/structured_output.cpp:729, vlm/vlm_module.cpp:1091, rag/rac_rag_proto_abi.cpp:1048, diffusion/rac_diffusion_stream.cpp:476. Most already compute `rac_get_current_time_ms() * 1000`, so the correct move is trivially available -- but it must be `reserved 2;` plus a new tag, not a same-tag reuse. Second, the consistency win is smaller than claimed: after this change 11 protos still spell it `timestamp_us`, so the SDK still has two units; you have only moved which file is the outlier, and several of the writers above serve OTHER messages that keep microseconds. The precedent is also loosely described -- OpenAI Responses and Anthropic Messages stream events largely carry NO per-event timestamp (Responses uses sequence_number), so they dodge this problem rather than solving it the proposed way.

**What changed:** Already landed by an earlier wave: voice_events.proto VoiceEvent.timestamp_ms (tag 2, comment states milliseconds since epoch). No int64 timestamp_us remains on this message.

**Files touched:** `idl/voice_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** C++ WRITERS of voice_events.VoiceEvent specifically: sdk/runanywhere-commons/src/features/voice_agent/voice_agent_internal_helpers.cpp:309 `vp->set_timestamp_us(rac_get_current_time_ms() * 1000);`, :348 and :360 (same expression on `event`), plus :383 per the proposer; sdk/runanywhere-commons/src/features/voice_agent/voice_agent_d7_abi.cpp:74 `event->set_timestamp_us(rac_get_current_time_ms() * 1000);`; sdk/runanywhere-commons/src/features/vad/vad_module.cpp:331 `voice_event.set_timestamp_us(rac_get_current_time_ms() * 1000);`. Every one of these already computes `rac_get_current_time_ms() * …

**Wire safety:** Tag 2 keeps its number AND its varint wire type, so nothing errors and everything silently parses -- this is the single most dangerous shape a proto edit can take. A stale writer emitting microseconds into a field now read as milliseconds produces timestamps around the year 57000; a stale reader given milliseconds produces 1970. Do NOT do a same-tag rename. Use `reserved 2;` + `reserved "timestam…

**Do first:**
  1. Replace the proposal's same-tag rename with reserved-plus-new-tag before writing anything: `reserved 2; reserved "timestamp_us";` and `int64 timestamp_ms = <next free>;`. Find the next free tag with `rg -n '= [0-9]+;' idl/voice_events.proto | sed -n '/message VoiceEvent/,/^}/p'` -- VoiceEvent runs from voice_events.proto:41 to just before UserSaidEvent at :92, so read only that span. A same-tag varint-to-varint rename gives you no compile error anywhere and no parse error on the wire; that is the failure mode you cannot detect.
  1. Enumerate the writers yourself instead of trusting the skeptic's list. Run `rg -n 'set_timestamp_us' sdk/runanywhere-commons/src` and, for each hit, confirm the declared type of the receiver is runanywhere::v1::VoiceEvent before touching it. Expected result: exactly the five VoiceEvent sites (voice_agent_internal_helpers.cpp:309,348,360,383; voice_agent_d7_abi.cpp:74; vad_module.cpp:331) and roughly twenty sites on eleven other protos that stay as they are.
  1. Step 1 (C++ and TS writers in ONE commit with the proto edit -- there is no safe intermediate state for a unit change): delete the `* 1000` at voice_agent_internal_helpers.cpp:309,348,360,383, voice_agent_d7_abi.cpp:74 and vad_module.cpp:331, switching each to set_timestamp_ms(rac_get_current_time_ms()).
  1. Step 2 (same commit, non-negotiable): sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+VoiceAgent.ts:944 becomes `timestampMs: Date.now(),` (drop the `* 1000`), :1043 becomes `timestampMs: 0,`, and sdk/runanywhere-web/packages/core/tests/types/types.test-d.ts:66 becomes `timestampMs: 0,`. The Web SDK constructs VoiceEvents itself -- it is not merely a reader -- so a C++-only rollout leaves a live microsecond writer in the browser.
  1. Step 3 (same commit): regenerate sdk/shared/proto-ts/src/voice_events.ts, sdk/runanywhere-commons/src/generated/proto/voice_events.pb.{h,cc}, the Swift Generated/ voice_events binding and the Kotlin generated VoiceEvent, and commit them together. Do not regenerate anything under sdk/runanywhere-electron/src/proto or sdk/runanywhere-python/runanywhere/_proto -- neither carries voice_events, and touching them widens the diff for no reason.
  1. Do NOT run a repo-wide `timestamp_us -> timestamp_ms` replace, and do NOT run one over idl/. Eleven other protos declare the same field name; the sweep would be an eleven-way silent wire break dressed up as a units cleanup.


</details>


<details>
<summary><strong>events-shape</strong> (4 changes)</summary>

### `events-shape-envelope-identity` — Cut the envelope from five id strings to three, and add the monotonic seq key

**Proto location:** [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1214), [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1223), [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1209), [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1192)

**Why:** The envelope carries five identifier strings - id, session_id, operation_id, correlation_id, trace_id - and three of them are described as "group related events". A newcomer has no rule for which one to set or join on. Meanwhile the one field the canonical envelope does require is missing: there is no monotonic ordering key, so a consumer using poll()/clearQueue() cannot tell a dropped event from a quiet SDK - even though the nested VoiceEvent already has `seq`.

**Skeptic verdict:** `risky` — The after-block puts `uint64 seq = 34` on the tag currently held by `string correlation_id = 34`. That is a wire-type change (length-delimited -> varint) on a live tag, which proto3 forbids and which fails LOUDLY-or-silently depending on the reader. The proposal's own parenthetical admits the hazard ('Field 34 must be renumbered, not reused, if any correlation_id bytes are already in the wild') yet the diff it asks for does the reuse anyway; a reviewer applying the after-block verbatim ships the bug. Fresh tag 37 with `reserved 34, 36;` costs nothing. Minor precedent slippage: `sequence_number` is real on OpenAI Responses stream events, but Realtime server events carry `event_id`/`type` and no sequence_number, so 'Responses/Realtime ... item_id plus a monotonic sequence_number' overstates it by lumping the two APIs together.

**What changed:** Deleted SDKEvent.correlation_id (34) and trace_id (36) -- both zero writers/readers, confirmed by care plan grep. Added uint64 seq = 37 (fresh tag, not tag 34 -- avoids the wire-type change from string to varint the raw proposal would have caused).

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** For the two DELETIONS: nothing found, and here is the evidence rather than an assertion.

SDKEvent.correlation_id (tag 34): `rg -n --no-heading -g '!**/proto-ts/**' -g '!**/*.pb.*' -g '!**/*.md' 'correlation_id|correlationId|correlationID' sdk/ idl/` returns exactly three kinds of hit and none of them is this field:
  - idl/sdk_events.proto:1214 -- the declaration itself.
  - idl/errors.proto:277 `string correlation_id = 12;` -- this is SDKError.correlation_id, a DIFFERENT field on a different message. Every `correlationId: ''` in the TypeScript SDKs is this one, constructing an SDKError: sdk…

**Wire safety:** Do NOT put `uint64 seq` on tag 34. That is a wire-type change on a live tag: `string correlation_id = 34` is length-delimited (wire type 2), `uint64` is varint (wire type 0). Proto3 forbids it, and the failure is reader-dependent -- some decoders throw, some skip, some return junk. The proposal's own parenthetical flags the hazard and then the diff does the reuse anyway; applying the after-block …

**Do first:**
  1. Split into two commits: the two deletions first (they are genuinely unread -- the greps above returned only the declarations), then the `seq` add. That way the risky ADD is not entangled with two safe deletes.
  1. Fix the after-block before writing it: `uint64 seq = 37;` on a fresh tag, plus `reserved 34, 36;` and `reserved "correlation_id", "trace_id";`. Do not reuse 34.
  1. Before adding seq, find or create the single choke point every SDKEvent passes through on its way out. Start from `publish_event(...)` in sdk/runanywhere-commons/src/core/model_lifecycle_translation.cpp:414 and `rac_sdk_event_publish_*` in sdk/runanywhere-commons/src/infrastructure/events/event_publisher.cpp, and confirm the four hand-rolled envelope populators (event_publisher.cpp:156, storage_event_publisher.cpp:65, model_lifecycle_translation.cpp:323, voice_agent_internal_helpers.cpp:256) all funnel into it. If they do not, funnelling them is the prerequisite -- do that before the proto edit.
  1. Stamp seq with a single process-wide atomic at that choke point, after all payload construction, so the number reflects emission order and not construction order. Never let a caller pass seq in.
  1. Decide and document the reset semantics in the field comment: does seq restart at SDK init, or persist for process lifetime? A consumer that uses seq to detect drops across a re-init needs to know, and 'monotonic, whole-stream' does not answer it.
  1. Leave the RN client-side counter at Models.ts:106,:274 alone until seq is proven on device; then remove it in a follow-up so there is exactly one ordering key, which is the whole point of the change.


### `events-shape-one-arm-per-subject` — Collapse the duplicate-era oneof arms so every subject has exactly one arm

**Proto location:** [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1225), [sdk_events.proto (ModelEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L677), [sdk_events.proto (ModelRegistryEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L746), [sdk_events.proto (DownloadEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L789)

**Why:** Nine of the 24 arms cover only four subjects. A model download can arrive as `model` (MODEL_EVENT_KIND_DOWNLOAD_PROGRESS), as `download` (DOWNLOAD_EVENT_KIND_PROGRESS), or as `model_registry`; storage state arrives as `storage` or `storage_lifecycle`; component bring-up as `component_init` or `component_lifecycle`; a latency number as `performance` or `telemetry`. A newcomer cannot answer "which arm do I subscribe to for downloads?" - the honest answer today is "all three". The one-message-per-producer split earns its keep only when one producer means one subject.

**Skeptic verdict:** `risky` — Three defects. (1) The arm count is wrong: the oneof has 23 arms (3-12,17-19,23-32), not 24, so '24 -> 18' is really 23 -> 18 and the domain-level '8 of its 24 oneof arms' is 7 of 23. (2) Every one of the four merges collides on INNER field tags, which the risk section never mentions -- it only says to reserve the retired ARM numbers. StorageLifecycleEvent{cache_key=3,bytes=4,error=5} vs StorageEvent{error=3,total_bytes=4,available_bytes=5}; ComponentInitializationEvent{component=2,model_id=3,size_bytes=4,progress=5} vs ComponentLifecycleEvent{previous_state=2,current_state=3,model_id=4,timestamp_ms=5}; PerformanceEvent{memory_bytes=2,thermal_state=3,operation=4,milliseconds=5} vs TelemetryEvent{name=2,attributes=3,value=4,unit=5}. 'Unions two field sets' is not mechanical; each merge is a full renumber of a live message. (3) The after-block does not achieve its own stated goal: ComponentLifecycleEvent.payload still carries `DownloadProgress download_progress = 13` (line 313-318), so after the merge a download still reaches the app on TWO arms (`model` and `component_lifecycle`). The diagnosis is real and in fact understated (downloads have four spellings today, not three), but the prescription as written is not implementable.

**What changed:** Merged ModelRegistryEvent+DownloadEvent into ModelEvent (kinds appended to ModelEventKind at 26-52, result oneof appended at tags 17-31); merged StorageLifecycleEvent into StorageEvent (kinds appended 18-25, result oneof at 20-23, bytes field at 11); merged ComponentInitializationEvent into ComponentLifecycleEvent (fields appended at 19-27, new ComponentLifecycleEventKind enum covering both old taxonomies). Deleted ModelRegistryEvent/Kind, DownloadEvent/Kind, StorageLifecycleEvent/Kind, ComponentInitializationEvent/Kind entirely -- no reserve, per no-backcompat. SDKEvent.event oneof updated: 5 retired arms removed (performance/component_init/model_registry/download/storage_lifecycle), no reserved block needed since only the oneof accessor disappears, not a tag on a still-live message.

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Two of the five arms are live on BOTH ends and one more is live producer-side.

download arm (26) -- read by all five SDK facades:
  sdk/runanywhere-swift/Sources/RunAnywhere/Public/Events/EventBus.swift:117  `guard case .download(let payload)? = envelope.event`
  sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/events/EventBus.kt:160  `eventsOfPayload { it.download }`
  sdk/runanywhere-flutter/packages/runanywhere/lib/public/events/event_bus.dart:70  `allEvents.where((e) => e.hasDownload()).map((e) => e.download)`
  sdk/runanywhere-react-native/packages/core/src/Public/Event…

**Wire safety:** Retiring arms 7 (performance), 12 (component_init), 25 (model_registry), 26 (download), 27 (storage_lifecycle) needs `reserved 7, 12, 25, 26, 27;` at SDKEvent message level. NOTE: idl/sdk_events.proto currently contains ZERO reserved statements -- `rg -n '^import|reserved' idl/sdk_events.proto` returns only line 1099, which matches the word 'preserved' inside a comment. There is no reserved prece…

**Do first:**
  1. Split the item into four PRs, one per subject, and do the storage merge FIRST -- it is the only one with zero SDK readers (greps 1, 2 and 4 above found no `storageLifecycle` / `hasStorageLifecycle` / `kStorageLifecycle` anywhere outside idl/ and sdk/shared/proto-ts). It is the cheapest place to prove the tag-collision and enum-renumbering procedure before doing it on a merge that five apps can see.
  1. Write down the field-number and enum-value mapping table BEFORE editing the proto, one row per incoming field and per incoming kind, and put it in the target message as a comment. The five source messages are deleted, so their `reserved` cannot live in them; the only surviving record of what the old numbers meant is that comment.
  1. For each merge, add the incoming fields to the TARGET message on fresh tags strictly above its current max tag, and add the incoming kinds to the target enum on fresh values strictly above its current max value. Never reuse 3/4/5 in StorageEvent, never reuse 2/3/4/5 in ComponentLifecycleEvent or TelemetryEvent. The skeptic listed the exact colliding sets; treat that list as the checklist.
  1. Preserve ModelRegistryEvent.current_model_result explicitly. model_lifecycle_translation.cpp:409-413 CopyFrom's a whole CurrentModelResult into it and ModelEvent has no equivalent field. Decide before writing the proto whether it becomes a new ModelEvent field or is flattened, and say so in the mapping table.
  1. Do NOT delete the publish overloads in the same commit that changes the proto. Keep sdk_event_publish.h/.cpp overloads for PerformanceEvent/ComponentInitializationEvent/ModelRegistryEvent/DownloadEvent/StorageLifecycleEvent as thin shims that build the merged message, so events.cpp:70,612 / storage_event_publisher.cpp:117,137,158,179 / model_lifecycle_translation.cpp:409 keep compiling and keep emitting through the whole migration.
  1. Extend telemetry_manager.cpp's kind->name mapping (the model.download.* table at :637-646) to the merged kinds in the SAME commit as the proto change. Downloads are the case where a miss is silent: nothing fails to compile, telemetry just stops.
  1. Land the app-visible order strictly as: (1) commons proto + commons producers + telemetry mapper; (2) regenerate all bindings; (3) Swift EventBus.swift (declared source of truth for API shape) :117 and :133; (4) Kotlin EventBus.kt:160,168 + Flutter event_bus.dart:70,80 + RN EventBus.ts:201,211 + Web EventBus.ts:708/:826; (5) only then delete the arms and add `reserved 7, 12, 25, 26, 27;`. Deleting the arms before step 4 breaks the Web and Flutter builds against a field that is gone.
  1. During steps 1-4 keep BOTH arms populated (dual-write the merged arm and the legacy arm) so a mid-migration app pinned to an older facade still receives events. Drop the legacy write only at step 5.


### `events-shape-one-voice-arm` — Merge the two voice arms into one, and stop shipping a second envelope inside the envelope

**Proto location:** [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1236), [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1237), [sdk_events.proto (VoiceLifecycleEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L485), [voice_events.proto (VoiceEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L41)

**Why:** Voice reaches the app through two arms whose only stated difference is a design era: `voice` (VoiceLifecycleEvent, 49 kinds) and `voice_pipeline` (VoiceEvent from another file). The nested one is a rival envelope - it carries its own seq, its own timestamp in MICROseconds, its own category, its own severity, its own component enum and its own 20-arm payload oneof - so a consumer merging the two streams by time must convert units, and must learn two envelope shapes to read one modality.

**Skeptic verdict:** `risky` — The after-block changes the TYPE of tag 17 from VoiceLifecycleEvent to VoiceEvent while only reserving 18. Both are length-delimited (wire type 2), so nothing detects the swap: old bytes at tag 17 parse cleanly as the new message and yield garbage. This breaks the exact rule the sibling proposal states ('keep the retired field numbers reserved so old bytes are never silently re-read as new arms'). The fix is trivial -- reserve BOTH 17 and 18 and put the merged VoiceEvent on a fresh tag -- but as written it is the silent-corruption variant. Second unaddressed constraint: component_types.proto:41-44 documents the cycle (sdk_events.proto:57 imports voice_events.proto, never the reverse) and voice_agent_service.proto:13 imports voice_events.proto, so the 49 VoiceLifecycleEvent kinds must be promoted INTO voice_events.proto, not the other way round; the risk note says 'promote VoiceEvent's payload arms up' which is the direction the import graph forbids.

**What changed:** 

**Status:** `skipped`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** Both voice arms are live on both ends -- this is the most-consumed pair in the domain.

voice_pipeline arm (18) readers:
  sdk/runanywhere-swift/Sources/RunAnywhere/Public/Events/EventBus.swift:109  `guard case .voicePipeline(let payload)? = envelope.event`
  sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/events/EventBus.kt:156  `eventsOfPayload { it.voice_pipeline }`
  sdk/runanywhere-flutter/packages/runanywhere/lib/public/events/event_bus.dart:65-66  `.where((e) => e.hasVoicePipeline()).map((e) => e.voicePipeline)`
  sdk/runanywhere-react-native/packages/core/src/Public/…

**Wire safety:** The after-block as written is the silent-corruption variant and MUST NOT be applied verbatim. It changes tag 17 from VoiceLifecycleEvent to VoiceEvent while reserving only 18. Both are length-delimited (wire type 2), so a decoder reading old bytes finds a well-formed submessage at tag 17 and parses it as the new type without any error -- the result is garbage kinds and garbage payloads, not a par…

**Do first:**
  1. Wait for events-shape-envelope-identity to land, for two reasons: the merged VoiceEvent is supposed to drop its own `seq` in favour of the envelope's, and the fresh tag this merge needs (38) is only unambiguous once that item has claimed 37.
  1. Fix the after-block before it is written: `reserved 17, 18;` at SDKEvent message level, merged arm on a fresh tag. Do not put the new type on 17.
  1. Move the 49 VoiceLifecycleEvent kinds INTO idl/voice_events.proto, not the reverse. Verify the direction holds by running `buf lint` / `buf build` after the move -- component_types.proto:41-44 says the cycle is real, so getting this backwards fails at build time rather than silently, which is the one mercy here.
  1. Enumerate VoiceEvent's inner payload oneof arms and check each against telemetry_manager.cpp:749, :893 and :1008, which switch on VoiceEvent::kMetrics and VoiceEvent::kError. If promoting the payload arms changes those case labels, update all six sites in the same commit.
  1. Introduce timestamp reconciliation as an ADD, not a reinterpretation: keep voice_events.proto:48 timestamp_us intact while the envelope's timestamp_ms becomes authoritative, and delete timestamp_us only after every producer (vad_module.cpp:334,361; voice_agent_internal_helpers.cpp:310; voice_agent_d7_abi.cpp; rac_stt_hybrid_router_proto.cpp:106) has stopped writing it.
  1. Migrate the Web facade last and deliberately: EventBus.ts:707 and translateVoice at :792 are typed `ProtoVoiceLifecycleEvent` by name, so the generated type disappears rather than changing shape. That is a hard compile error in the Web build, which is good -- but it means the Web PR cannot be deferred to a follow-up.


### `events-shape-single-failure-channel` — Delete FailureEvent (and SDKEvent.severity): the envelope already reports failure

**Proto location:** [sdk_events.proto (FailureEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1150), [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1248), [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1188), [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1181)

**Why:** FailureEvent has four fields and every one of them already exists elsewhere on the same wire: `component` duplicates SDKEvent.component, `operation` duplicates SDKEvent.operation_id, `error` duplicates SDKEvent.error, and `recoverable` duplicates SDKError.retryable. So there are three ways to say "this failed" - a per-payload error field, the envelope's SDKError, and a dedicated arm - and a newcomer has to check all three. Same argument for SDKEvent.severity, which SDKError.severity already carries.

**Skeptic verdict:** `risky` — The FailureEvent half survives scrutiny. The bundled 'and SDKEvent.severity' half does not: severity is NOT a failure-only field, so SDKError.severity cannot own it. embeddings_module.cpp:109 sets `ERROR_SEVERITY_INFO` on SUCCESS events (ternary on whether an error string is present), and SDKEvent.error is `optional` and unset on those events -- so after the deletion a successful event has nowhere to carry INFO/WARN. There is also a live envelope-level reader: voice_agent_d7_abi.cpp:92 branches on `event->severity() == ERROR_SEVERITY_ERROR`. And voice_agent_service.proto:32 declares `ErrorSeverity min_severity = 4;` as a subscription filter, which becomes unsatisfiable for any non-error event. The proposal's own precedent sentence is also loose in the other direction: OpenAI does ship error-shaped events (`error`, `response.failed`) alongside the error object.

**What changed:** Deleted FailureEvent message and its SDKEvent.failure arm (32). Did NOT touch SDKEvent.severity (2) -- the care plan found it live on success events across ~20 producer sites and one subscription filter (voice_agent_service.proto min_severity); deleting it would have been a correctness regression, not a simplification.

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The FailureEvent half has real consumers on both ends, and they are all reachable:

Readers of the `failure` arm:
  sdk/runanywhere-react-native/packages/core/src/Public/Api/Events.ts:54 `if (event.failure?.error)`, :57 `message: event.failure.error.message`, :58 `recoverable: event.failure.recoverable`
  sdk/runanywhere-flutter/packages/runanywhere/lib/public/api/internal/sdk_event_mapper.dart:66 `if (event.hasFailure())`, :68 `event.failure.error.message`, :69 `recoverable: event.failure.recoverable`
  sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_manager.cpp:811 `case SDKE…

**Wire safety:** FailureEvent half: retiring arm 32 needs `reserved 32;` at SDKEvent message level (plus `reserved "failure";`). No inner-tag work, since the message is deleted rather than merged and its four fields map onto fields that already exist with their own numbers -- SDKEvent.component=21 (line 1184), SDKEvent.operation_id=33 (1209), SDKEvent.error=22 (1188, `optional`), SDKError.retryable (errors.proto:…

**Do first:**
  1. Cut the SDKEvent.severity half out of the item entirely before starting. It is not the same change and it is not safe -- see whatCouldBreak. Ship only the FailureEvent deletion.
  1. Keep the C ABI symbol `rac_sdk_event_publish_failure` byte-identical in name and signature. Change only its body at sdk/runanywhere-commons/src/infrastructure/events/event_publisher.cpp:321 so it fills SDKEvent.error (tag 22) + component (21) + operation_id (33) + SDKError.retryable instead of building a FailureEvent. Doing it this way means all five SDK facades, the JNI entry at runanywhere_commons_jni.cpp:4058, the RN bridge at HybridRunAnywhereCore+Events.cpp:210 and all ten rac_lora_service.cpp call sites keep working with no change on their side.
  1. Map the four fields explicitly and check nothing is lost: component -> SDKEvent.component (sdk_events.proto:1184), operation -> SDKEvent.operation_id (1209), error -> SDKEvent.error (1188), recoverable -> SDKError.retryable (errors.proto:275). Confirm the current publish path actually sets operation_id -- FailureEvent.operation is a free-form string and operation_id may be used differently; if they are not the same thing, say so rather than aliasing them.
  1. Migrate the two arm readers to `has_error` BEFORE deleting the arm: sdk/runanywhere-react-native/packages/core/src/Public/Api/Events.ts:54-58 and sdk/runanywhere-flutter/packages/runanywhere/lib/public/api/internal/sdk_event_mapper.dart:66-69. Note both read `.recoverable`, which becomes `error.retryable` -- a rename the compiler will catch in Dart and TypeScript, so land those two PRs and let them fail loudly rather than trying to keep the old name.
  1. Update telemetry_manager.cpp:811 in the same commit. It currently keys off `case SDKEvent::kFailure:` falling through with kCancellation at :813; after the change failure is no longer an arm, so that classification has to move to a `has_error()` check or failures stop being classified and the fall-through silently changes what kCancellation does.
  1. Re-sync both vendored copies of the C header (sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/rac_sdk_event_stream.h:93 and sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include/rac/infrastructure/events/rac_sdk_event_stream.h:93) in the same PR. They are copies, not symlinks; a stale copy compiles fine and is exactly how a shape drift survives review.
  1. Order: commons body change (arm still present, dual-write error + failure) -> regenerate -> RN + Flutter readers move to has_error -> vendored headers -> delete FailureEvent and add `reserved 32;` and stop dual-writing.


</details>


<details>
<summary><strong>events-taxonomy</strong> (5 changes)</summary>

### `events-taxonomy-drop-getter-echo-kinds` — Delete the 29 *_REQUESTED / *_RETRIEVED kinds that only echo an RPC the app just called

**Proto location:** [sdk_events.proto (FrameworkEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1048), [sdk_events.proto (ConfigurationEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L213), [sdk_events.proto (StorageEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L854), [sdk_events.proto (ModelRegistryEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L781)

**Why:** 29 of the 300 kind values are request/response echoes of a method the app itself invoked (FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED then ..._RETRIEVED, CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED then ..._RETRIEVED, and so on). FrameworkEventKind is 14 values of which 10 are getter pairs, so the whole message is mostly plumbing. A newcomer reading the taxonomy cannot tell which events are real SDK activity and which are just 'you called listAdapters()'.

**Skeptic verdict:** `sound` — Holds up under the dead-surface test, which I ran deliberately hard given the VADConfiguration precedent. Every value this proposal deletes appears ONLY in generated/proto/sdk_events.pb.h and in zero hand-written C++: FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED/RETRIEVED, FRAMEWORKS_RETRIEVED, AVAILABILITY_*, CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED/RETRIEVED, MODEL_EVENT_KIND_LIST_REQUESTED, STORAGE_EVENT_KIND_INFO_REQUESTED, MODEL_REGISTRY_EVENT_KIND_LIST_STARTED/GET_STARTED -- 1 hit each, all the enum declaration itself. Nothing emits or switches on them. Caveats: (a) the arithmetic is internally inconsistent -- title and `why` say 29 values, `simplicityGain` says ~24, and the per-enum numbers sum to 24 (10+9+2+1+2), so 29 is wrong; (b) I only cleared the C++ commons per scope -- the proto's own comments reference RN events.ts / Kotlin / Dart mirrors, so the platform adapters still need a grep before this lands.

**What changed:** Deleted the getter-echo REQUESTED/RETRIEVED pairs: FrameworkEventKind reserved 3-12 (10 values), ConfigurationEventKind reserved 9-17 (9 values incl. SYNC_REQUESTED), StorageEventKind reserved 1,3 (INFO_REQUESTED/MODELS_REQUESTED), ModelEventKind reserved 13,39,42 (LIST_REQUESTED + the two registry _STARTED echoes absorbed from ModelRegistryEventKind).

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`


### `events-taxonomy-generation-one-terminal` — Strip GenerationEventKind to the generation lifecycle: one terminal, no session/model/cost kinds

**Proto location:** [sdk_events.proto (GenerationEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L434), [sdk_events.proto (GenerationEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L448), [sdk_events.proto (SessionEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L341), [sdk_events.proto (CancellationEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1142)

**Why:** The enum an LLM developer reads first mixes in four other domains: SESSION_STARTED/ENDED (SessionEvent owns sessions), MODEL_LOADED/UNLOADED (ModelEventKind owns those, verbatim), CANCEL_REQUESTED (CancellationEventKind owns that), and COST_CALCULATED (a number, not a moment). It also has TWO success terminals -- COMPLETED and STREAM_COMPLETED -- with nothing saying which one fires when.

**Skeptic verdict:** `sound` — One overclaim and three live sites to migrate, neither fatal. The `why` says ModelEventKind owns MODEL_LOADED/UNLOADED 'verbatim' -- it does not: `grep -n MODEL_EVENT_KIND_MODEL_LOADED` returns nothing; ModelEventKind has LOAD_COMPLETED=3 / UNLOAD_COMPLETED=6. The concepts overlap, the names do not, so the migration is a rename not a move. Live sites: STREAM_COMPLETED is emitted at features/llm/llm_module.cpp:2474 and consumed at telemetry_manager.cpp:606 and :1081; CANCEL_REQUESTED emitted at llm_module.cpp:2510, consumed at telemetry:615; MODEL_UNLOADED consumed at telemetry:617. COST_CALCULATED and SESSION_STARTED/ENDED are generated-only -- genuinely dead. Notably telemetry_manager.cpp:1081 already ORs `COMPLETED || STREAM_COMPLETED` to decide success, so collapsing the two terminals deletes that disjunction: independent evidence the two-terminal split buys nothing.

**What changed:** Reserved 1,2 (SESSION_STARTED/ENDED -> SessionEventKind owns sessions), 9,10 (MODEL_LOADED/UNLOADED -> ModelEventKind), 11 (COST_CALCULATED -> the cost_amount/cost_saved_amount fields), 13 (STREAM_COMPLETED -> COMPLETED + is_streaming), 14 (CANCEL_REQUESTED -> CancellationEventKind). Kept COMPLETED/FAILED/CANCELLED as the three terminals plus ROUTING_DECISION and the tool/structured-output/thinking kinds untouched.

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`


### `events-taxonomy-merge-storage-taxonomies` — Merge StorageEventKind and StorageLifecycleEventKind into one 12-value storage taxonomy

**Proto location:** [sdk_events.proto (StorageEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L852), [sdk_events.proto (StorageLifecycleEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L873), [sdk_events.proto (StorageLifecycleEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L888), [sdk_events.proto (SDKEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L1243)

**Why:** Storage has TWO closed taxonomies, 32 values between them, describing the same four operations twice: DELETE_MODEL_STARTED/COMPLETED/FAILED vs DELETE_STARTED/COMPLETED/FAILED, CLEAR_CACHE_* vs CACHE_CLEANUP_*, INFO_REQUESTED/RETRIEVED vs INFO_STARTED/COMPLETED. Nothing in the file tells a newcomer which one to subscribe to for 'a model was deleted' -- and both StorageEvent and StorageLifecycleEvent are wired into the envelope, so both really do fire.

**Skeptic verdict:** `risky` — Two undisclosed breaks. (1) SILENT ENUM-NUMBER REINTERPRETATION: StorageEventKind uses 0-17 and StorageLifecycleEventKind uses 0-13 -- the number spaces fully overlap. Folding the lifecycle emitters into StorageEventKind means every live `set_kind(STORAGE_LIFECYCLE_EVENT_KIND_*)` site must move to a DIFFERENT integer (e.g. lifecycle DELETE_COMPLETED=6 must become StorageEventKind DELETE_COMPLETED=12, while 6 is simultaneously redefined as CACHE_CLEARED). Any persisted, queued or cross-version event silently reads 6 as CACHE_CLEARED instead of DELETE_COMPLETED. The `risk` section covers field-level merging but says nothing about the number remap, and `after` supplies no mapping table and no `reserved` for the vacated 1,3,5,8,9,10. (2) It silently deletes STORAGE_EVENT_KIND_CLEAN_TEMP_STARTED/COMPLETED/FAILED (8,9,10) -- they appear nowhere in `after` and nowhere in the prose -- yet CLEAN_TEMP_COMPLETED is LIVE: emitted at core/events.cpp:535 and consumed in a switch at telemetry_manager.cpp:727. Direction is right; the diff drops a working, consumed kind on the floor.

**What changed:** Already substantially done by the events-shape merge earlier in this session (StorageLifecycleEventKind values appended to StorageEventKind at 18-25, result oneof appended to StorageEvent). Did NOT renumber the survivors in place (care plan's exact number-reuse warning: CLEAR_CACHE_COMPLETED=6 must not become CACHE_CLEARED=6) -- kept original numbers, appended absorbed values on fresh numbers instead, so no wire-type or semantic collision.

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** StorageLifecycleEvent is LIVE, not dead surface. (1) Emitters: sdk/runanywhere-commons/src/infrastructure/storage/storage_event_publisher.cpp:117-118, :137-138, :158-159, :179-183 -- four publishers, six set_kind sites -- reached from sdk/runanywhere-commons/src/infrastructure/storage/storage_analyzer.cpp:525, :531, :537, :543. (2) Public C++ header: sdk/runanywhere-commons/include/rac/infrastructure/storage/storage_event_publisher.h:26,30,34,38 declares the four publish_storage_*_event() functions, and a byte-copy of that header is vendored into React Native at sdk/runanywhere-react-native/p…

**Wire safety:** Real wire change, and the dangerous kind. Two closed enums with fully overlapping number spaces (StorageLifecycleEventKind 0-13, StorageEventKind 0-17) are being merged, so every surviving lifecycle value changes integer: DELETE_STARTED 5->11, DELETE_COMPLETED 6->12, DELETE_FAILED 7->13, AVAILABILITY_CHECKED 3->18 (INFO_COMPLETED 2->2 is the only no-op). At the same time number 6 is REDEFINED fro…

**Do first:**
  1. Write the mapping table FIRST, as a comment block at the top of the surviving enum, before any line is deleted: every StorageLifecycleEventKind value (0-13) and every StorageEventKind value (0-17) -> its new number, or 'deleted'. The proposal's `after` ships no table and the two number spaces fully overlap (both start at 0), so without it the remap is guesswork.
  1. Resolve CLEAN_TEMP before writing anything: 8/9/10 are NOT dead. STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED is set at sdk/runanywhere-commons/src/core/events.cpp:535 and switched on at sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_manager.cpp:727. Either keep 8/9/10 in the surviving enum, or migrate both sites in the same commit and reserve the numbers.
  1. Do the ADDITIVE half first, in its own commit: add the four typed result arms (StorageInfoResult / StorageAvailabilityResult / StorageDeletePlan / StorageDeleteResult) to StorageEvent using field numbers that do not collide with StorageEvent's existing byte-counter fields, and add the new StorageEventKind values (AVAILABILITY_CHECKED = 18, etc.). Run codegen. Nothing is deleted yet, so every existing consumer still compiles.
  1. Second commit -- migrate emitters: repoint sdk/runanywhere-commons/src/infrastructure/storage/storage_event_publisher.cpp:117, :137, :158, :179 from mutable_storage_lifecycle() to mutable_storage(), and remap the six set_kind values per the table. Keep the four publish_storage_*_event() signatures in include/rac/infrastructure/storage/storage_event_publisher.h:26-38 byte-identical so the vendored RN copy and storage_analyzer.cpp:525-543 do not move.
  1. Same commit -- update sdk/runanywhere-commons/tests/test_storage_analyzer_proto.cpp:193 (parameter type), :195 (has_storage_lifecycle -> has_storage), and the four asserted kinds at :261, :311, :423, :602.
  1. Third commit -- delete: remove StorageLifecycleEvent and StorageLifecycleEventKind, delete sdk_event_publish.cpp:210 and sdk_event_publish.h:127, and add to SDKEvent `reserved 27;` plus `reserved "storage_lifecycle";`. Add `reserved` for every StorageEventKind number the merge vacates (1, 3, 5, and 8/9/10 if CLEAN_TEMP is dropped) plus the old value NAMES, so protoc rejects reuse.
  1. Same commit -- update the Kotlin public surface: delete or repoint sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/events/SDKEvent.kt:23 and the doc at sdk/runanywhere-kotlin/docs/Documentation.md:1306. This is the one app-visible break; call it out in the changelog.
  1. Re-sync the vendored header copy at sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include/rac/infrastructure/storage/storage_event_publisher.h (and rebuild the paired .so) -- a stale vendored header against a new .so is a silent ABI mismatch, not a compile error.


### `events-taxonomy-one-download-emitter` — Delete the duplicate DOWNLOAD_* kinds from ModelEventKind and ComponentInitializationEventKind

**Proto location:** [sdk_events.proto (ModelEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L717), [sdk_events.proto (ModelEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L726), [sdk_events.proto (ComponentInitializationEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L276), [sdk_events.proto (DownloadEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L804)

**Why:** Download progress is declared in THREE taxonomies: DownloadEventKind (the dedicated one), MODEL_EVENT_KIND_DOWNLOAD_STARTED/PROGRESS/COMPLETED/FAILED/CANCELLED, and COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED/STARTED/PROGRESS/COMPLETED. An app that wants a progress bar has to subscribe to three arms and de-duplicate, and the proto never says which one is authoritative.

**Skeptic verdict:** `sound` — Substance and coordinates hold; only the blast radius is understated. The `risk` section frames this as external 'callers currently listening on the ModelEvent arm', but MODEL_EVENT_KIND_DOWNLOAD_* is emitted from inside the commons itself: core/events.cpp lines 388, 404, 420, 437, 448 (all five kinds) plus six consumer switch cases in infrastructure/telemetry/telemetry_manager.cpp:637-645 and :897. So this is ~11 in-repo C++ sites to migrate, and core/events.cpp exposes them via publish helpers whose signatures change -- not a documentation re-point. Minor hygiene: `after` drops MODEL_EVENT_KIND_LIST_REQUESTED = 13 with no `reserved 13` (it overlaps proposal 2's cut; if both land, 13 needs reserving).

**What changed:** ComponentLifecycleEventKind: reserved 15,16 (_DOWNLOAD_STARTED/_COMPLETED, duplicates of ModelEventKind's own DOWNLOAD_STARTED/COMPLETED); kept _DOWNLOAD_REQUIRED (14) per care plan (a decision, not a duplicate -- no ModelEventKind equivalent exists). ModelEventKind's own DOWNLOAD_STARTED/PROGRESS/COMPLETED/FAILED/CANCELLED (8-12) were kept as-is since they are the one place this now lives after the DownloadEvent merge, not deleted as the raw proposal (written before that merge existed) suggested.

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The blast radius is roughly double what the skeptic reported -- it named only C++, and there are four non-C++ consumers. C++ side: MODEL_EVENT_KIND_DOWNLOAD_* is set at sdk/runanywhere-commons/src/core/events.cpp:388, :404, :420, :437, :448 inside emit_model_download_started/progress/completed/failed/cancelled (defined at events.cpp:385, :401, :417, :433, :446, with no-op stubs at :652-656); those five are a PUBLIC C API declared at sdk/runanywhere-commons/include/rac/infrastructure/events/rac_sdk_emit.h:89-97 and byte-copied into React Native at sdk/runanywhere-react-native/packages/core/and…

**Wire safety:** Enum values only -- no field-number changes and no SDKEvent oneof arm is added or removed, so no tag reuse. `reserved 8, 9, 10, 11, 12;` on ModelEventKind collides with nothing surviving (the enum jumps 7 -> 13/14). Add reserved NAMES as well as numbers so a future author cannot resurrect MODEL_EVENT_KIND_DOWNLOAD_STARTED at a different integer. ComponentInitializationEventKind 6/7/8 need the sam…

**Do first:**
  1. Pin the mapping before editing -- all five deleted values have an exact DownloadEventKind equivalent, verified at idl/sdk_events.proto: MODEL_EVENT_KIND_DOWNLOAD_STARTED 8 -> DOWNLOAD_EVENT_KIND_STARTED 4 (:809), PROGRESS 9 -> DOWNLOAD_EVENT_KIND_PROGRESS 5 (:810), COMPLETED 10 -> DOWNLOAD_EVENT_KIND_COMPLETED 10 (:816), FAILED 11 -> DOWNLOAD_EVENT_KIND_FAILED 11 (:817), CANCELLED 12 -> DOWNLOAD_EVENT_KIND_CANCELLED 7 (:812). Put this table in the proto as the comment that replaces the deleted block.
  1. Commit 1 (commons emitters, no proto change): repoint sdk/runanywhere-commons/src/core/events.cpp:385-448 to populate a DownloadEvent on the SDKEvent.download arm instead of ModelEvent. Keep the five emit_model_download_* C signatures at include/rac/infrastructure/events/rac_sdk_emit.h:89-97 BYTE-IDENTICAL -- that header is vendored into RN and called from runanywhere_commons_jni.cpp:3209-3224 and download_orchestrator.cpp:1001-2329; changing the signatures turns a one-file edit into an ABI migration for the prebuilt Android .so.
  1. Commit 1, same change: update the six consumer cases at sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_manager.cpp:637, :639, :641, :643, :645, :897 to switch on DownloadEventKind. Verify the telemetry record still keys off model_id/task_id -- DownloadEvent carries both (idl/sdk_events.proto:791-792), so the correlation key is unchanged.
  1. Commit 2 (facades) -- BEFORE any proto deletion, migrate all four to the DownloadEvent arm: sdk/runanywhere-web/packages/core/src/Foundation/EventBus.ts:744-759 (inbound) AND :887-893 (outbound emit) plus tests/unit/Foundation/EventBus.test.ts:110; sdk/runanywhere-kotlin/.../public/api/SdkEvents.kt:47; sdk/runanywhere-flutter/.../internal/sdk_event_mapper.dart:57; sdk/runanywhere-react-native/packages/core/src/Public/Api/Events.ts:44. Deleting first means the Web, Kotlin, Flutter and RN builds all compile against a value that is gone.
  1. Commit 3 (proto): delete MODEL_EVENT_KIND_DOWNLOAD_* 8-12 with `reserved 8, 9, 10, 11, 12;` AND `reserved "MODEL_EVENT_KIND_DOWNLOAD_STARTED", "MODEL_EVENT_KIND_DOWNLOAD_PROGRESS", "MODEL_EVENT_KIND_DOWNLOAD_COMPLETED", "MODEL_EVENT_KIND_DOWNLOAD_FAILED", "MODEL_EVENT_KIND_DOWNLOAD_CANCELLED";`. Same for the ComponentInitializationEventKind download values (6, 7, 8 per the proposal, at idl/sdk_events.proto:276ff).
  1. In that same commit, either keep MODEL_EVENT_KIND_LIST_REQUESTED = 13 or add `reserved 13;` -- the `after` block silently drops it. It has zero consumers (only idl/sdk_events.proto:731), so dropping it is safe on the consumer axis, but an unreserved drop fails buf.
  1. Keep COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED as the proposal's own risk note says (it is a decision, not a transfer). It has no hand-written consumer either way, so this is a naming choice with no migration cost.
  1. Run ./idl/codegen/generate_all.sh and re-sync the vendored RN header copy at sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include/rac/infrastructure/events/rac_sdk_emit.h.


### `events-taxonomy-voice-50-to-16` — Cut VoiceEventKind from 50 values to ~16 by deleting the VOICE_SESSION_* and STT_*/TTS_* mirror families

**Proto location:** [sdk_events.proto (VoiceEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L543), [sdk_events.proto (VoiceEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L599), [sdk_events.proto (VoiceEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L581), [sdk_events.proto (VoiceLifecycleEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_events.proto#L485)

**Why:** One enum with 50 values names the same five moments up to four times each. Speech onset is SPEECH_DETECTED, VAD_DETECTED, SPEECH_STARTED and VOICE_SESSION_SPEECH_STARTED. A final transcript is TRANSCRIPTION_FINAL, STT_COMPLETED and VOICE_SESSION_TRANSCRIBED. Listening is LISTENING_STARTED, RECORDING_STARTED and VOICE_SESSION_LISTENING. The VOICE_SESSION_* block (11 values) exists only because a second orchestrator re-emitted the same pipeline under its own names.

**Skeptic verdict:** `risky` — The risk assessment is inverted relative to the actual code. Grepping hand-written C++ (excluding generated/): VOICE_EVENT_KIND_VOICE_SESSION_* -- the family the risk section worries about -- has ZERO hand-written references (11 hits, all in generated/proto/sdk_events.pb.h). Meanwhile the families it deletes without comment are the live ones: VOICE_EVENT_KIND_STT_* = 30 hits across core/events.cpp, features/stt/rac_stt_stream.cpp, features/stt/stt_module.cpp, infrastructure/telemetry/telemetry_manager.cpp, router/hybrid/rac_stt_hybrid_router_proto.cpp; VOICE_EVENT_KIND_VAD_* = 18 hits across core/events.cpp, features/vad/vad_module.cpp, telemetry_manager.cpp. That is 48 live C++ references, and the risk section mentions only the React Native adapter. Worse, the `after` justifies killing VAD_* (15-20, 48-49) with a bare assertion -- 'VAD state belongs on the component lifecycle event, not here' -- but names no ComponentLifecycle value to migrate to, while features/vad/vad_module.cpp emits on this enum today. This is exactly the VADConfiguration over-eagerness pattern.

**What changed:** Deleted only the two families the care plan's grep confirmed dead/duplicate: SPEECH_DETECTED (3, duplicate of SPEECH_STARTED=21) and the entire VOICE_SESSION_* family (37-47, confirmed exactly 1 hand-written reference in the whole tree vs. dozens on STT_*/VAD_*/RECORDING_*/PLAYBACK_*). Deliberately did NOT delete STT_*/VAD_*/RECORDING_*/PLAYBACK_*/AUDIO_GENERATED as the raw proposal wanted -- the care plan's independent grep found the risk assessment inverted: those families have 30+, 10+, and multiple live C++ and Web consumers respectively, including telemetry_manager.cpp:1158 whose STT_COMPLETED check sets payload.success. Cutting 50->16 as originally proposed would have deleted live telemetry-critical values; cutting only the confirmed-dead 12 values (50->38) is the defensible subset.

**Files touched:** `idl/sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The risk assessment is inverted, and I confirmed the inversion with coordinates. THE FAMILY THE RISK NOTE WORRIES ABOUT IS NEARLY DEAD: VOICE_EVENT_KIND_VOICE_SESSION_* has exactly one hand-written reference in the tree -- sdk/runanywhere-web/packages/core/src/Foundation/EventBus.ts:811 (VOICE_SESSION_TURN_COMPLETED). Zero in commons, zero in Swift, Kotlin, Flutter, React Native. THE FAMILIES IT DELETES IN SILENCE ARE THE LIVE ONES. STT_* -- 30 hand-written references: sdk/runanywhere-commons/src/core/events.cpp:236, :258; src/router/hybrid/rac_stt_hybrid_router_proto.cpp:107; src/features/st…

**Wire safety:** The good news, verified: `after` reuses the CURRENT numbers for its survivors (1, 2, 4, 5, 6, 8, 10, 11, 21, 22, 26, 31, 32, 36, 45), so unlike the storage merge there is no renumbering and no cross-taxonomy remap -- provided step 4 of doFirst confirms each of those numbers already carries the name `after` assigns it. The bad news: roughly 34 values are being deleted (3, 7, 9, 12-20, 23-25, 27-30…

**Do first:**
  1. Apply correctionNeeded first -- the RN-adapter claim is false and must not become the proto's justification comment, and do not copy the stale 'RN events.ts:177-187' pointer from idl/sdk_events.proto:598 into the new block.
  1. Write the full 50-value mapping table before deleting a single line: for each of VoiceEventKind 0-49, record survive-at-N / merge-into-N / delete. The `after` block shows only the survivors, so the 34-odd deletions are currently unnamed. Nothing gets edited until the table is written into the proto as the replacement comment.
  1. Resolve the three collisions against the CODE, not by taste. (a) STT_COMPLETED vs TRANSCRIPTION_FINAL: telemetry_manager.cpp:1158 keys payload.success off STT_COMPLETED specifically -- whichever name survives, that predicate must be updated in the same commit or STT telemetry silently reports every transcription as a failure. (b) VAD_*: the `after` justifies removing them with 'VAD state belongs on the component lifecycle event' but names no target enum value -- name the exact replacement value before touching vad_module.cpp:779/:812/:1680/:1713, or keep VAD_STARTED/STOPPED (and VAD_PAUSED/RESUMED, which the `before` excerpt omits but telemetry_manager.cpp:699/:701 consume). (c) AUDIO_GENERATED = 9 is deleted by `after` but read at telemetry_manager.cpp:681 and :878 -- keep it or migrate both sites.
  1. Confirm the survivor numbers in `after` (21, 22, 26, 31, 32, 36, 45) already carry those exact NAMES in the current enum at idl/sdk_events.proto:543-640. If any of them is a rename-in-place, stop: buf's WIRE profile will not catch it (see wireSafety) and every persisted event on that number silently changes meaning.
  1. Land additively first: add any genuinely new survivor value at a fresh number, run ./idl/codegen/generate_all.sh, and confirm nothing breaks. Do not delete in the same commit.
  1. Then repoint the ~48 commons sites, file by file, in one commit: core/events.cpp (:236, :258, :319, :325, :332, :340), features/stt/stt_module.cpp (14 sites), features/stt/rac_stt_stream.cpp:471-472, features/vad/vad_module.cpp (:381-382, :779, :812, :1680, :1713), router/hybrid/rac_stt_hybrid_router_proto.cpp:107, features/tts/tts_module.cpp, infrastructure/telemetry/telemetry_manager.cpp (:665-701, :875-878, :1158), tests/test_telemetry_extraction.cpp:132.
  1. Then repoint the single external consumer: sdk/runanywhere-web/packages/core/src/Foundation/EventBus.ts:794, :795, :801, :803, :805, :807, :809, :811. This is the ONLY non-commons file that touches VoiceEventKind -- confirmed by the greps above.
  1. Only then delete, and add `reserved` for every vacated number AND name. The `after` block ships no reserved statements at all and idl/sdk_events.proto has none today, so this is easy to forget and buf will reject the PR when you do.


</details>


<details>
<summary><strong>images</strong> (11 changes)</summary>

### `images-delete-configuration-messages` — Delete DiffusionConfiguration and DiffusionTokenizerSource -- 9 fields, 2 enums, no parser anywhere

**Proto location:** [diffusion_options.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L12), [diffusion_options.proto (DiffusionModelVariant)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L46), [diffusion_options.proto (DiffusionTokenizerSourceKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L56), [diffusion_options.proto (DiffusionTokenizerSource)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L64)

**Why:** Nothing in the codebase can parse either message: rac_diffusion_proto_adapters.h forward-declares DiffusionConfiguration and then declares only options/progress/result adapters. Eight SDKs will each generate two message classes and two enums (7 model variants, 5 tokenizer kinds) that no code path can act on. Worse than inert: enable_safety_checker and auto_download both have a proto3 zero of false while their C defaults are RAC_TRUE, so a newcomer who constructs the message gets the opposite of the documented behaviour.

**Skeptic verdict:** `risky` — This is exactly the VADConfiguration-style third consumer. Deleting the message breaks the Flutter SDK's public load() signature (and any app that passes a config), so the change is source-breaking for app developers, not merely proto-breaking. The Flutter facade change must be in the same commit and the 'nothing observable changes' justification should be struck.

**What changed:** Deleted message DiffusionConfiguration, message DiffusionTokenizerSource, enum DiffusionModelVariant and enum DiffusionTokenizerSourceKind in full, and removed `import "model_types.proto";` which InferenceFramework was the only user of. protoc over all 40 protos still exits 0, confirming nothing else referenced them.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The skeptic is right and I confirmed it by READING THE BODY, not just the signature. sdk/runanywhere-flutter/packages/runanywhere/lib/public/capabilities/runanywhere_diffusion.dart:92 declares `Future<void> load(String modelId, [DiffusionConfiguration? config]) async` — and the body (lines 93-116) never references `config` once: it builds `model_pb.ModelLoadRequest(modelId:, category:, forceReload: true, validateAvailability: true)` and returns. So the parameter is a source-level promise with zero implementation, which strengthens the case for deletion but does NOT make it invisible: deleting…

**Wire safety:** Whole top-level message and enum deletion; no tag reuse and no dangling references. DiffusionTokenizerSource and DiffusionConfiguration are not nested in any other message and no field in diffusion_options.proto has either as its type (only the Flutter facade names them), so nothing is left pointing at a deleted type. No field numbers move in surviving messages, no enum values are renumbered. Mes…

**Do first:**
  1. Same commit, first edit: change runanywhere_diffusion.dart:92 to `Future<void> load(String modelId) async` and remove `DiffusionConfiguration,` from the `show` list at runanywhere_diffusion.dart:36. Since the body already ignores `config`, this is a pure signature narrowing — no behaviour to port.
  1. Announce it as source-breaking for Flutter app developers in the release notes. It is not merely proto-breaking, and the deletion rationale must say so (see correctionNeeded).
  1. Delete the forward declaration at sdk/runanywhere-commons/include/rac/features/diffusion/rac_diffusion_proto_adapters.h:23 and refresh the stale comment at rac_diffusion_types.h:18 in the same change.
  1. Before deleting `import "model_types.proto";` at idl/diffusion_options.proto:12, prove InferenceFramework was its only user: `rg -n 'InferenceFramework|ModelCategory|ModelFormat|model_types' idl/diffusion_options.proto`. An unused-import deletion that turns out to be used is a protoc error, not a silent one, but check anyway so the commit is not split.
  1. Explicitly leave the C ABI alone: rac_diffusion_model_variant_t, rac_diffusion_model_requires_cfg and rac_diffusion_tokenizer_default_for_variant stay exactly as they are. Put that sentence in the commit message so the next reviewer does not finish the job.


### `images-drop-mode-enum` — Delete the `mode` field and the DiffusionMode enum -- infer the mode from which inputs are present

**Proto location:** [diffusion_options.proto (DiffusionMode)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L24), [diffusion_options.proto (DiffusionGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L101)

**Why:** The enum makes a whole class of well-formed but self-contradictory requests representable (mode=INPAINTING with no mask, mode=TEXT_TO_IMAGE with an image attached), and commons then spends validation code rejecting exactly the combinations that inference would have made impossible. It also splits the surface: no facade exposes IMAGE_TO_IMAGE at all, so a newcomer sees four modes in the IDL and two in the SDK.

**Skeptic verdict:** `sound` — Worth stating explicitly in the risk: the C ABI keeps rac_diffusion_options_t.mode and diffusion_mode_from_proto currently folds UNSPECIFIED to TEXT_TO_IMAGE (rac_proto_adapters.cpp:628-640), so commons must start deriving mode from input presence in the same commit or every request becomes text-to-image and silently ignores an attached image.

**What changed:** Deleted `enum DiffusionMode` and the `DiffusionMode mode = 9;` field from DiffusionGenerationOptions. The mode-inference rule (no image = text-to-image, image = image-to-image, image + mask_image = inpainting, mask-without-image is the only invalid combination) is now stated as a comment above the `image` field.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`


### `images-drop-request-correlation` — Delete request_id and metadata -- correlation is declared in three places and populated in none

**Proto location:** [diffusion_options.proto (DiffusionGenerationRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L126), [diffusion_options.proto (DiffusionGenerationRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L129), [diffusion_options.proto (DiffusionStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L173)

**Why:** Three fields across two messages promise that concurrent generations can be told apart on the event stream. rac_diffusion_generate_lifecycle_proto reads only options and model_id; dispatch_diffusion_stream_event sets only timestamp_us, kind, progress and result/error; the Web facade hardcodes requestId: ''. A developer building a multi-request UI writes correlation logic against an always-empty string. Diffusion on device is single-flight anyway -- there is one cancel.

**Skeptic verdict:** `risky` — The stated evidence surveyed only rac_diffusion_generate_lifecycle_proto and missed the streaming path's read at rac_diffusion_stream.cpp:249. Fix the 'populated in none' wording, and list rac_diffusion_stream.cpp (StreamSession.request_id) as a required same-commit edit. The reserved sets themselves (1,4 in the request; 1,3,7,8 in the event) collide with nothing.

**What changed:** Deleted request_id and map<string,string> metadata from DiffusionGenerationRequest (leaving options = 1, model_id = 2) and deleted request_id from DiffusionStreamEvent (leaving timestamp_us = 1, kind = 2, progress = 3, result = 4, error = 5). The single-flight rationale is a one-line comment on DiffusionStreamEvent.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** 'Populated in none' is FALSE and this is the sentence that would have made someone delete a live write. sdk/runanywhere-react-native/packages/core/src/Public/Api/Images.ts:20 genuinely populates it on every image request: `DiffusionGenerationRequest.fromPartial({ requestId: nextRequestId('image'), options: toImageOptions(prompt, options) })`. Because proto-ts types fromPartial as `Exact<DeepPartial<T>, I>`, an unknown key is a TypeScript ERROR, not a silent drop — deleting the field red-builds the RN core package. And commons reads it: sdk/runanywhere-commons/src/features/diffusion/rac_diffus…

**Wire safety:** Field deletions with correct reservation, verified against the real tag map. DiffusionGenerationRequest occupies 1, 2, 3, 4 (idl/diffusion_options.proto:126-129), so `reserved 1, 4; reserved "request_id", "metadata";` removes exactly the two deleted tags and collides with nothing live. DiffusionStreamEvent occupies 2, 3, 4, 5, 6, 9 (proto:171-178), so `reserved 1, 3, 7, 8;` covers the deleted req…

**Do first:**
  1. Same commit, commons side: delete rac_diffusion_stream.cpp:249 (`session.request_id = parsed.request_id();`) AND the now-unused `std::string request_id;` StreamSession member at rac_diffusion_stream.cpp:72. Deleting only the write leaves a dead member; deleting only the proto field fails to compile.
  1. Same commit, RN side: remove `requestId: nextRequestId('image'),` from sdk/runanywhere-react-native/packages/core/src/Public/Api/Images.ts:20. Keep the `nextRequestId` import — Vlm.ts:70 still uses it. This is the edit the 'populated in none' claim would have caused someone to skip.
  1. Same commit, Web side: remove the three `requestId: ''` literals at sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+Diffusion.ts:166, :182, :191.
  1. Check the JSON round-trip before shipping: sdk/shared/proto-ts accepts both `requestId` and `request_id` on decode (dist/diffusion_options.js:1054-1057). If any stored request blob or bridge payload is JSON rather than binary, the id becomes an unknown key. Harmless for the binary path; confirm nothing compares toJSON output against a fixture containing requestId.


### `images-options-delete-dead-fields` — Delete the five unread DiffusionGenerationOptions fields, starting with the one apps can set that does nothing

**Proto location:** [diffusion_options.proto (DiffusionGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L112), [diffusion_options.proto (DiffusionGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L113), [diffusion_options.proto (DiffusionGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L114), [diffusion_options.proto (DiffusionGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L115)

**Why:** report_intermediate_images and progress_stride are copied into the C struct and read by no engine -- yet all three facades expose report_intermediate_images publicly as ImageOptions.reportPartials, so a developer can set a documented flag, build a preview UI against it, and get silence with no error. input_image_width/height describe a raw-pixel input contract that commons' own PNG/JPEG magic-byte sniff now forbids. return_latents appears only in generated .pb files, and DiffusionResult has no latent field to answer it with.

**Skeptic verdict:** `sound`

**What changed:** Deleted report_intermediate_images, progress_stride, input_image_width, input_image_height and return_latents from DiffusionGenerationOptions outright, with no reserved statements and no tombstone comments, and closed the resulting tag gaps by renumbering the message densely 1-15.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`


### `images-output-format` — Add output_format (png|jpeg|webp|raw_rgba, default png) so callers can get a usable image

**Proto location:** [diffusion_options.proto (DiffusionGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L116), [diffusion_options.proto (DiffusionResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L156)

**Why:** There is no way to ask for a PNG. A 1024x1024 generation hands back a 4 MB raw-RGBA buffer advertised under the non-IANA string "image/raw-rgba", so the two things every image app does next -- save it and share it -- force each of the eight SDKs to hand-roll a platform encoder (CGImageDestination, Bitmap.compress, canvas.toBlob, PIL, sharp). A newcomer looks for the field every other image API has, does not find it, and then discovers the bytes are not an image file at all.

**Skeptic verdict:** `sound` — Only the risk the proposal already states: without the commons encoder in the same commit this is a new dead field in a pass whose thesis is deleting dead fields. Nothing in engines/ or features/platform/ encodes today (rac_diffusion_platform.cpp just forwards to a host callback), so the encoder is real work, not a one-liner.

**What changed:** Added a top-level `enum DiffusionOutputFormat` (UNSPECIFIED/PNG/JPEG/WEBP/RAW_RGBA) beside DiffusionScheduler and a `DiffusionOutputFormat output_format` field on DiffusionGenerationOptions carrying (runanywhere.v1.rac_default) = "DIFFUSION_OUTPUT_FORMAT_PNG". Per the carePlan's 'do not enumerate values that silently fall back to PNG', the enum comment states plainly that no JPEG/WEBP encoder exists in this tree and that requesting one is rejected rather than answered with PNG.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The FIELD has no consumers: `rg -n 'output_format|outputFormat|DiffusionOutputFormat'` over runanywhere-sdks (generated excluded) returns only unrelated telemetry hits (sdk/runanywhere-commons/include/rac/infrastructure/telemetry/rac_telemetry_types.h:158 `const char* output_format`, src/infrastructure/telemetry/telemetry_json.cpp:409, telemetry_manager.cpp:516/1429) and AVAudioFormat noise in the STT code. No symbol `DiffusionOutputFormat` exists anywhere. What breaks is the BEHAVIOUR the field turns on, and there are three live sites the brief never counted. (1) examples/android/RunAnywhere…

**Wire safety:** Pure addition, no wire break. Tag 21 is free: DiffusionGenerationOptions' highest live tag is return_latents=20 (idl/diffusion_options.proto:122) and the file contains ZERO `reserved` statements today (verified by `rg -n 'reserved|^import|^message|^enum' idl/diffusion_options.proto`), so there is no reserved range to collide with. New top-level enum, no value renumbering, no oneof change. Note th…

**Do first:**
  1. Do NOT write a new encoder — one already exists and is production code. sdk/runanywhere-cli/src/io/image_io.h:22-25 declares `bool image::write_png(const std::string& path, const uint8_t* rgba, int width, int height, std::string* error)` and image_io.cpp implements it self-contained (header comment lines 7-8: 'no libpng / zlib dependency: emits a PNG whose IDAT is a zlib stream of *stored* blocks'). Lift that into commons as an in-memory `rgba -> std::string` variant and make cmd_image.cpp call the commons one, so there is exactly one encoder in the repo.
  1. Know the caveat you are inheriting: the CLI encoder uses STORED (uncompressed) deflate blocks. A 1024x1024 PNG will still be ~4 MB. If the point of this field is 'save and share', ship a real deflate at the same time or state the size behaviour in the field comment — otherwise you have shipped a valid-but-huge PNG and the newcomer's next complaint is size.
  1. JPEG and WEBP have NO implementation anywhere in this tree — the encoder grep found only sdk/runanywhere-cli/src/io/image_io.cpp, sdk/runanywhere-cli/tests/test_rcli_unit.cpp and sdk/runanywhere-python/tests/test_smoke.py. Ship PNG + RAW_RGBA only in v1 and leave 2/3 as declared-but-rejected (return INVALID_ARGUMENT), or pull in a third-party encoder. Do not enumerate JPEG/WEBP values that silently fall back to PNG.
  1. The encode hook goes in rac_diffusion_result_to_proto, sdk/runanywhere-commons/src/foundation/rac_proto_adapters.cpp:759-767. Line 767 `out->set_image_media_type("image/raw-rgba")` is the hardcoded literal that must become conditional on the requested format — that single line is the whole seam.
  1. Update examples/android/.../NpuModelE2ETest.kt:707-718 and :873-915 in the SAME commit: the media-type equality and the w*h*4 size assertion must become format-aware, or the on-device contract test fails the moment the encoder lands.
  1. Check the new enum name against ALL 40 protos, not just this one — protobuf enum names are package-scoped, so `DiffusionOutputFormat` must be unique across package runanywhere.v1: rg -n 'enum DiffusionOutputFormat' /Users/sanchitmonga/development/ODLM/MONOREPOOO/Qualcomm/runanywhere-sdks/idl/


### `images-progress-three-fields` — Cut DiffusionProgress from 10 fields to 3 -- (current_step, total_steps) is what every engine emits

**Proto location:** [diffusion_options.proto (DiffusionProgress)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L132), [diffusion_options.proto (DiffusionProgress)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L133), [diffusion_options.proto (DiffusionProgress)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L136), [diffusion_options.proto (DiffusionProgress)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L140)

**Why:** rac_diffusion_progress_to_proto writes four things and only four; six of the ten fields can only ever read zero or empty in all eight SDKs. Two are actively misleading: Swift already reads intermediateImageWidth/Height, so a preview that ever arrived would build a 0x0 image, and timestamp_ms is a second timestamp in a different unit from the DiffusionStreamEvent.timestamp_us that is actually populated. progress_percent is named percent but carries a 0.0-1.0 fraction, and is fully derivable from the two fields beside it -- so somebody will multiply by 100 and somebody else will not.

**Skeptic verdict:** `sound` — Two arithmetic overstatements in the 'why' that should be corrected before the owner reads it as evidence: the adapter writes five fields, not 'four things and only four', and the number of fields that can only ever read zero/empty is five (intermediate w/h, timestamp_ms, eta_ms, intermediate media type), not six -- progress_percent and stage ARE written, as the proposal's own risk field admits.

**What changed:** DiffusionProgress is now three fields: current_step = 1, total_steps = 2, optional bytes intermediate_image_data = 3. Deleted progress_percent, stage, intermediate_image_width, intermediate_image_height, timestamp_ms, eta_ms and intermediate_image_media_type.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`


### `images-rename-strength-and-image` — Rename denoise_strength to strength and input_image to image (tags unchanged)

**Proto location:** [diffusion_options.proto (DiffusionGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L104), [diffusion_options.proto (DiffusionGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L106)

**Why:** A developer arriving from any diffusion tutorial types `strength` and `image` and finds neither. Both are the plurality spelling (Diffusers, Stability, Apple, OpenAI's guide), the tag numbers do not move so the wire format is unchanged, and no facade exposes denoise_strength at all yet -- so this is free today and permanent the moment eight SDKs ship a public property named denoiseStrength.

**Skeptic verdict:** `sound` — Two inaccuracies. (a) 'no facade exposes denoise_strength at all yet' is wrong: sdk/runanywhere-swift/Sources/RunAnywhere/Generated/RAConvenience.swift:393 sets r.denoiseStrength = 0.75 and :419-421 validates it with the literal field path string "DiffusionGenerationOptions.denoise_strength" -- generated, so it regenerates, but the public Swift convenience surface does carry the name today. (b) The rename is left half-done: input_image becomes image while input_image_media_type (tag 17) keeps its old prefix, so the newcomer now reads 'image' paired with 'input_image_media_type', and commons' encoded_image_media_type_matches(in.input_image(), in.input_image_media_type()) pairing gets less obvious, not more. Rename 17 to image_media_type in the same change.

**What changed:** Renamed input_image -> image and denoise_strength -> strength (bounds annotations rac_default 0.75 / rac_min_float 0.0 / rac_max_float 1.0 preserved verbatim), and wrote the approved comments teaching mode inference and the effective-steps latency consequence. I also renamed input_image_media_type -> image_media_type.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The brief's 'this is free today' premise is wrong in three independent places, and the rename is more half-done than the skeptic caught. denoise_strength consumers: (1) sdk/runanywhere-flutter/packages/runanywhere/lib/public/api/types/options.dart:576 — HAND-WRITTEN, not generated: `diff_pb.DiffusionGenerationOptions(prompt:, steps:, guidanceScale:, mode:, reportIntermediateImages:, denoiseStrength: _image.denoiseStrength)`. (2) sdk/runanywhere-swift/Sources/RunAnywhere/Generated/RAConvenience.swift:393 and :419-421, which the skeptic found — generated, but it is generated from idl/codegen/ge…

**Wire safety:** No wire change on the binary path: tags 10, 11 and 12 do not move and the types are unchanged (bytes/bytes/float), so old and new binaries interoperate byte-for-byte. The JSON path IS affected — protobuf JSON keys are field names, so `inputImage`/`denoise_strength` keys in any stored or bridged JSON stop matching. No reserved ranges needed, no enum renumbering, no oneof change. If you rename tags…

**Do first:**
  1. Decide the rename SCOPE before touching anything: rename all four of input_image / input_image_width / input_image_height / input_image_media_type to image / image_width / image_height / image_media_type, or rename none of them. A partial rename is the only outcome that is worse than the status quo. Note image_media_type already exists on DiffusionResult (proto:156) — that is a different message, so no collision, but the two now share a name and a reader must not confuse request-side with result-side.
  1. Rename the PROTO field only. Leave the C struct members rac_diffusion_options_t.denoise_strength (rac_diffusion_types.h:249, :279) and .input_image_data/.input_image_size untouched — sdk/runanywhere-web/wasm/src/wasm_exports.cpp:588-589 exports their byte offsets to JS by symbol name and the JS side is keyed on it.
  1. Confirm the Swift convenience generator derives field paths from the proto: grep idl/codegen/generate_swift_convenience.py and idl/codegen/_convenience_common.py for the literal 'denoise_strength'. If it is hardcoded there, the regeneration will NOT pick up the rename and RAConvenience.swift:419-421 will validate against a field path that no longer exists.
  1. Do all eight input_image write sites plus the three denoise_strength sites in ONE commit — they are mechanical, but a proto-only commit red-builds five SDKs plus commons at once.
  1. Guard the JSON path: sdk/shared/proto-ts accepts BOTH spellings on input (dist/diffusion_options.js:1054-1057 reads `object.requestId` then falls back to `object.request_id`), so a renamed field silently reads as its default from any persisted or bridged JSON keyed on the old name. If any diffusion options JSON is persisted or crosses the RN/Web bridge as JSON, the rename is a data-loss path, not just a compile break — check before shipping.


### `images-request-n` — Rename batch_size to `n` with a real default of 1 -- and either wire it up or delete it

**Proto location:** [diffusion_options.proto (DiffusionGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L120)

**Why:** "batch_size = 19" with the comment "0 = one image" is a sentinel a newcomer has to be told about, under a name that means something else in every ML framework (a training concept). Worse, rac_diffusion_options_from_proto never reads it, so an app can set it and can never get more than one image -- while all five SDK result mappers already append batch_images into ImageResult.images, a code path that can never fire. Four variations of a prompt is the single most common image-generation UI.

**Skeptic verdict:** `risky` — The after text reintroduces exactly the defect images-seed-optional exists to remove. 'int32 n = 19 [(rac_default) = "1"]' is a non-optional proto3 scalar: a caller who builds the message directly, rather than through a generated facade, sends 0, and the only thing standing between that and 'generate zero images' is the same untrusted codegen annotation plus a new if (n > 0) sentinel gate in commons. Declare it 'optional int32 n = 19' (absent = 1) if the seed argument is accepted, or the pass is internally inconsistent. Separately, this is the one proposal that needs engine work that does not exist (no diffusion engine ships under engines/), so approving it schedules a second dead field.

**What changed:** Renamed batch_size to `n` and declared it `optional int32 n = 14 [(rac_default) = "1", (rac_min) = 1, (rac_max) = 8]`, with the comment 'How many images to generate for this prompt. Absent = 1.' The 0-means-one sentinel is gone.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`

**Care level:** `blocked`

**What could break:** The field itself breaks nothing — and I verified that rather than assuming it. `rg 'batchSize|batch_size'` across sdk/, examples/ and engines/ with generated code excluded returns ONLY idl/diffusion_options.proto:120 for this field. Every other hit is a DIFFERENT field or a string key: sdk/runanywhere-commons/src/foundation/rac_proto_adapters.cpp:868-872 `in.has_batch_size()` is EmbeddingsOptions, which I confirmed by reading sdk/runanywhere-commons/tests/test_advanced_modality_proto_abi.cpp:694-700 where `set_batch_size(32)` is called on `runanywhere::v1::EmbeddingsOptions`; embeddings_modul…

**Wire safety:** If renamed in place: no wire change — tag 19 stays, and int32 -> optional int32 is wire-identical (same varint field number and type; only presence tracking is added on the generated-code side, and an absent field simply is not emitted). If deleted instead: reserve BOTH the number and the name — `reserved 19; reserved "batch_size";` — so tag 19 can never be silently reused by a later field with d…

**Do first:**
  1. Make the scope decision FIRST, because the two branches are opposite edits. If n > 1 is out of scope for this release, DELETE tag 19 and add `reserved 19; reserved "batch_size";` — that costs nothing (zero consumers, verified above) and is the internally-consistent choice given that batch_images is being deleted in images-result-one-image-list.
  1. If you keep it, take the skeptic's fix and declare `optional int32 n = 19` so absence means 1. A bare proto3 scalar with only a codegen `rac_default` annotation reintroduces the exact sentinel this pass exists to delete: a caller who builds the message directly sends 0, and only an untrusted annotation plus a new `if (n > 0)` guard in commons stands between that and 'generate zero images'. Do not accept optional-seed elsewhere in this pass and a bare scalar here.
  1. Set the ceiling from measured device numbers, not from a cloud API. rac_max = 8 on a device where a 1024x1024 generation takes seconds means an 8x latency and memory promise — derive the cap from engines/qhexrt timings and say the number in the comment.
  1. Add the actual read in rac_diffusion_options_from_proto (sdk/runanywhere-commons/src/foundation/rac_proto_adapters.cpp:676-733), which today contains no batch_size read whatsoever. Without it the field is inert regardless of what it is named.
  1. Extend the C ABI before the proto: rac_diffusion_result_t must carry a list, and rac_backend_platform_register.cpp:397-398 / :462-463 (which copy a single platform_result into out_result) must loop. That work does not exist and is the hard prerequisite.


### `images-result-one-image-list` — Collapse DiffusionResult's 11 fields into one repeated image list, deleting 4 never-written fields

**Proto location:** [diffusion_options.proto (DiffusionResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L146), [diffusion_options.proto (DiffusionResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L155), [diffusion_options.proto (DiffusionResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L157), [diffusion_options.proto (DiffusionResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L158)

**Why:** A newcomer reading DiffusionResult sees three fields for one concept -- image_data (one image), batch_images (more images), images_generated (a count) -- and cannot tell which to read; every industry API returns a single list. Two more fields, used_scheduler and error, are never written by commons at all, yet Swift and Web already ship an unreachable `if result.hasError { throw }` branch that looks like working error handling. seed_used and safety_flag are scalars, so they cannot describe a multi-image result even in principle.

**Skeptic verdict:** `sound` — Not a refutation, but the five live read sites are real and must land in the same commit: Mapping.ts:487, Results.swift:309, MappingResults.kt:164, RN Results.ts:323, flutter results.dart:480 all read batchImages, and width/height are read there as per-image values today. Also the recurring 'eight SDKs' framing across this props file is inflated -- the repo has five platform SDKs plus Electron.

**What changed:** Added `message DiffusionImage { bytes data = 1; int32 width = 2; int32 height = 3; int64 seed_used = 4; bool safety_flag = 5; string media_type = 6; }` and rewrote DiffusionResult to `repeated DiffusionImage images = 1; int64 total_time_ms = 2;`. Deleted image_data, width, height, seed_used, safety_flag, used_scheduler, image_media_type, batch_images, images_generated and error from DiffusionResult outright (no reserved, per the ground rule). total_time_ms was deliberately kept live as the doFirst warned.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The brief named five read sites. There are SIX live hand-written consumers plus two tests, and the `error` field has four readers, not two. Confirmed sites: (1) sdk/runanywhere-web/packages/core/src/Public/API/Mapping.ts:487 batchImages, :493 imageData/width/height, :494 seedUsed. (2) sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Results.swift:304-305 width/height, :306 imageData, :309 batchImages, :313 seedUsed. (3) sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/MappingResults.kt:157 image_media_type, :159 image_data, :164 batch_images, :167 seed_used. (4) sdk/r…

**Wire safety:** Breaking by construction, done correctly. `images = 14` is free — DiffusionResult occupies 1-7, 10, 11, 12, 13 (idl/diffusion_options.proto:146-159) with 8 and 9 as historical gaps, so 14 has never been used. The proposed `reserved 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13` plus the name list is exactly right and cannot collide: `rg -n 'reserved' idl/diffusion_options.proto` confirms the file has NO…

**Do first:**
  1. Land the commons WRITER first, alone, so nothing reads a field that is not yet produced: rewrite rac_diffusion_result_to_proto at sdk/runanywhere-commons/src/foundation/rac_proto_adapters.cpp:759-774 to emit one DiffusionImage instead of the flat scalars.
  1. Write the honest comment while you are there: rac_diffusion_result_t (sdk/runanywhere-commons/include/rac/features/diffusion/rac_diffusion_types.h:328-347) is a SINGLE-image C struct with one image_data/image_size pair, so commons will emit exactly one entry until the C ABI grows a list. Without that note, `repeated images` reads as shipped multi-image support that does not exist.
  1. Then the six consumers in ONE commit — they compile against the generated types, so a proto-only commit red-builds all six simultaneously: Mapping.ts:487-494, Results.swift:304-313, MappingResults.kt:157-167, RN Results.ts:320-332, results.dart:473-491, and cmd_image.cpp (:133, :144-148, :258, :267).
  1. Handle the error branches DIFFERENTLY per consumer — they are not all equally dead. Swift ImagesNamespace.swift:34-35, Web Namespaces/images.ts:38 and RN Results.ts:57-58 are the unreachable ones the brief describes. But cmd_image.cpp:119-122 and :238-242 are the CLI's only visible failure reporting; before deleting them, confirm rac_proto_buffer_t status/error_message is actually surfaced to the CLI, or `rcli image` will print success on a failed generation.
  1. Fix the two tests in the same commit: nonllm_lifecycle_bridge_test.dart:98-110 and examples/android/.../NpuModelE2ETest.kt:707-718 / :873-915.
  1. Sanity-check the reserved list before committing: total_time_ms = 5 is deliberately KEPT live while 4 and 6 are reserved. A copy-paste that reserves 5 silently deletes generation timing and protoc will not complain.


### `images-scheduler-remove-trap-values` — Reserve DIFFUSION_SCHEDULER_DDPM and _LCM -- asking for them silently gives you DPM++ 2M Karras

**Proto location:** [diffusion_options.proto (DiffusionScheduler)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L32), [diffusion_options.proto (DiffusionScheduler)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L37), [diffusion_options.proto (DiffusionScheduler)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L42)

**Why:** Two of the eleven enum values are traps. diffusion_scheduler_from_proto maps both DDPM and LCM to RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS because there is no C carrier. LCM checkpoints are built for about four steps under an LCM sampler, so requesting LCM and getting DPM++ 2M Karras produces a visibly broken image with no error -- and the one field that could reveal the substitution, DiffusionResult.used_scheduler, is never written. Absence is a compile error the developer can see; a silent swap is not.

**Skeptic verdict:** `sound` — The claimed benefit is weaker than stated. proto3 enums are open and diffusion_scheduler_from_proto ends in 'default: return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS' (line 623-624), so a peer that still sends wire value 4 or 9 -- or any unknown value -- keeps getting the identical silent fold. This removes the name from eight codegen outputs; it does not remove the trap. If the trap is the point, the default branch must fail loudly in the same commit.

**What changed:** Removed DIFFUSION_SCHEDULER_DDPM and DIFFUSION_SCHEDULER_LCM from enum DiffusionScheduler and renumbered the survivors densely 0-8 (EULER 5->4, EULER_A 6->5, PNDM 7->6, LMS 8->7, DPMPP_2M_SDE 10->8). The header comment now reads 'Only values with a C carrier are listed. UNSPECIFIED = the model's configured scheduler'.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`


### `images-seed-optional` — Make seed `optional int64` -- absent means random, every present value is literal

**Proto location:** [diffusion_options.proto (DiffusionGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/diffusion_options.proto#L98)

**Why:** The -1 random sentinel exists only in a rac_default codegen annotation, and proto3 scalars have no presence. Any caller that builds the message directly instead of going through a generated facade sends 0, and commons copies it unconditionally (`out->seed = in.seed();`, no !=0 gate unlike its neighbours), so every generation is silently pinned to literal seed 0 and returns the same image forever. With `optional`, the wire type itself carries the rule and no annotation has to be trusted.

**Skeptic verdict:** `sound`

**What changed:** Changed `int64 seed = 7 [(rac_default) = "-1"]` to `optional int64 seed = 7;` and replaced the '// -1 = random.' comment with the approved text: absent means a fresh random seed, any present value is literal including 0, and the seed actually used comes back on each result image.

**Files touched:** `idl/diffusion_options.proto`

**Status:** `applied`


</details>


<details>
<summary><strong>llm</strong> (10 changes)</summary>

### `llm-explicit-presence` — Mark every sampling scalar `optional` so 0 stops meaning both 'unset' and a legal value

**Proto location:** [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L26), [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L44), [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L64)

**Why:** The proto states its own bug: "Commons treats 0 as unset for every sampling knob below." So a caller cannot request temperature 0.0 — the proto's own documented meaning, greedy decoding — cannot set seed 0, and cannot explicitly disable top_k. Deterministic generation and golden-output tests are unreliable for exactly the reason the file writes down.

**Skeptic verdict:** `sound` — The change is right; its risk assessment is wrong in a way that will bite sequencing. 'Source-compatible in the generated accessors of every target language' is false for at least two live targets. Kotlin/Wire renders proto3 `optional` as a NULLABLE property — see the generated sdk/runanywhere-kotlin/.../LLMStreamFinalResult.kt:49 `public val thinking_content: String? = null` — so `max_output_tokens: Int` becomes `Int?` and every Kotlin construction site and `.toRequest()` builder stops compiling. ts-proto does the same: compare llm_options.ts:65 `maxOutputTokens: number` with :94/:97 `thinkingContent?: string | undefined` / `ttftMs?: number | undefined`. Budget for a source migration in all 8 SDKs, not just a behavior change. Minor: the AFTER also flips top_k's default 0 -> 40, which belongs to llm-local-engine-defaults; keep one diff per change so review can tell them apart.

**What changed:** LLMGenerationOptions: max_output_tokens, temperature, top_p, top_k, seed, frequency_penalty, presence_penalty, min_p all made `optional` (proto3 explicit presence). repeat_last_n and echo_prompt left as plain scalars (care plan's own scope: 'no engine reads these', not part of the 0-means-unset bug). Combined into the same edit as llm-local-engine-defaults and llm-industry-names' repeat_penalty half since all three touch this identical field block.

**Files touched:** `idl/llm_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The 'treat 0 as unset' rule is implemented in commons in at least four separate places, and the proto change alone silently fixes NONE of them -- the accessors gain presence, but the `> 0` guards keep discarding the caller's 0: foundation/rac_proto_adapters.cpp:357-358 (`if (in.max_output_tokens() > 0)`), :363-364 (`if (in.top_p() > 0.0f)`), :450-451 (top_k), :453-454 (`if (in.seed() != 0)`), :456-457 (repetition_penalty), and :694; features/llm/llm_module.cpp:1580-1581, :1594-1595, :1605, :1606, :1613, plus :1588 which clamps temperature unconditionally. A cross-domain reader the brief never…

**Wire safety:** No wire-format change: proto3 `optional` only adds a synthetic oneof for presence tracking; tag numbers, wire types and encoded bytes for a set field are identical, and `buf breaking` WIRE will pass. The only wire-visible difference is that an explicitly-set 0 is now emitted instead of being skipped as a proto3 default -- which is the entire point. No tag reuse, no renumbering, no reserved ranges…

**Do first:**
  1. Do NOT land the proto edit alone. In the same commit, rewrite every `> 0` / `!= 0.0f` guard listed above to a presence check: rac_proto_adapters.cpp:357,363,450,453,456 and llm_module.cpp:1580,1594,1605,1606,1613 become `if (in.has_max_output_tokens())` etc. A proto-only commit is strictly worse than today: it advertises presence in the schema while commons still eats the 0, so a caller who reads the new comment and sets temperature 0.0 gets 0.7.
  1. Decide and write down what RAG does: rac_rag_proto_abi.cpp:420-423 has its own defaults (512, 0.9) that differ from the annotated LLM defaults (512, 1.0). Either route RAG through the same presence helper or leave a comment saying RAG deliberately overrides -- silently inheriting different numbers is how this bug class regenerates.
  1. Budget the Kotlin and TypeScript source migration explicitly. Kotlin sites to fix: MappingOptions.kt:56,:73, CppBridgeLLM.kt:68, RALLMTypesCppBridge.kt:46, ToolCallingOrchestrator.kt:164,:167, and the log interpolations at RunAnywhereTextGeneration.kt:58,:81,:96,:122 (those compile but will print 'null' where they printed 0). TS sites: Web RunAnywhere+ToolCalling.ts:178-180 and RunAnywhere+RAG.ts:1190.
  1. Sweep for callers that WRITE 0 to mean unset before flipping the reads -- `rg -n 'maxTokens = 0|max_tokens = 0|topK = 0|top_k = 0|temperature = 0' sdk --glob '!**/node_modules/**'`. RAVLMImageHelpers.kt:36 and RAVLMImage+Helpers.swift:17 prove the idiom is live.
  1. Split the top_k default change out. The AFTER flips top_k's rac_default from "0" to "40"; that belongs to llm-local-engine-defaults and will make this diff unreviewable if it rides along.


### `llm-finish-reason-enum` — Replace the three free-string `finish_reason` fields with one `FinishReason` enum

**Proto location:** [llm_options.proto (LLMGenerationResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L84), [llm_service.proto (LLMStreamFinalResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L42), [llm_service.proto (LLMStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L73)

**Why:** `finish_reason` is an untyped string in three places with no declared vocabulary, while every other classification in the domain (MessageRole, ReasoningMode, LLMStreamEventKind) is a proto enum. Two SDKs already disagree: Kotlin does exact lowercase equality, Web does substring matching, so the wire value "max_length" resolves to LENGTH on Web and UNKNOWN on Kotlin. An app deciding whether to show a truncation warning behaves differently per platform.

**Skeptic verdict:** `risky` — It changes the WIRE TYPE of live tags without renumbering: tag 8 on LLMStreamEvent and tag 10 on LLMGenerationResult go string (length-delimited) -> enum (varint). commons has a hand-rolled byte-level encoder that writes that exact tag as a string — sdk/runanywhere-commons/src/features/llm/rac_llm_stream.cpp:442 `wire_string_field(out, /*field=*/8, p.finish_reason)` — so any writer/reader skew across the release produces a wire-type mismatch, not a graceful default. Neither the risk note nor the AFTER mentions that encoder. Second gap: the AFTER says the enum is 'used in every place a finish reason is reported', but voice_events.proto:110 and vlm_options.proto:136 keep their own `string finish_reason`, so the vocabulary stays split 2 ways after the change. Use fresh tags for the enum fields and update rac_llm_stream.cpp in the same commit.

**What changed:** Added FinishReason enum to llm_options.proto. LLMGenerationResult.finish_reason(10, string) reserved, replaced with FinishReason finish_reason=27 + optional string stop_sequence=28 (fresh tags per care plan -- avoids the string->enum wire-type flip on a live tag). LLMStreamEvent.finish_reason(8, string) reserved by number+name, FinishReason finish_reason=21 added. Did NOT touch voice_events.proto/vlm_options.proto's separate finish_reason strings -- out of scope per care plan correction.

**Files touched:** `idl/llm_options.proto`, `idl/llm_service.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** This field is read or written in SEVEN SDK targets plus commons plus two engines -- roughly triple what the brief's 'three live facades' implies. Commons producer side: the hand-rolled byte encoder writes the tag as a string at sdk/runanywhere-commons/src/features/llm/rac_llm_stream.cpp:442 `wire_string_field(out, /*field=*/8, p.finish_reason)` (tag map documented at :287), and the libprotobuf path sets it at rac_llm_stream.cpp:207-208. The string vocabulary itself is minted in commons at features/llm/llm_module.cpp:1068-1085 ("stop"/"cancelled"/"length"/"unknown"), llm_module.cpp:2165-2166, …

**Wire safety:** Tag reuse with a WIRE-TYPE FLIP on three live tags: LLMGenerationResult.finish_reason=10, LLMStreamFinalResult.finish_reason=9, LLMStreamEvent.finish_reason=8 all go string (length-delimited, wiretype 2) -> enum (varint, wiretype 0). Do NOT change these in place. Take fresh tags and reserve the old ones: LLMGenerationResult declares 1,2,5,6,7,9,10,11,12,13,14,15,16,20,21,22,23,24,25,26 so 27 and …

**Do first:**
  1. Land the enum + a commons-side `FinishReason finish_reason_from_engine_string(const char*)` in llm_options.proto and one .cpp in commons FIRST, as an additive-only commit: new enum, new tags (LLMGenerationResult 27, LLMStreamEvent 20, plus stop_sequence 28), old string fields still present and still populated. Nothing breaks; both fields are on the wire for one release.
  1. In that same commit, teach the hand-rolled encoder about the new tag. Add `wire_enum_field(out, /*field=*/20, to_proto_finish_reason(p.finish_reason))` next to rac_llm_stream.cpp:442 and extend the tag-map comment at rac_llm_stream.cpp:287 -- the comment block is the only documentation of this wire format and it is already out of date (it lists tags 9 and 11 that llm_service.proto does not declare).
  1. Put the engine-string -> enum mapping in exactly ONE place in commons and give it every literal the stack actually emits today: "stop", "length", "cancelled", "canceled", "error", "unknown", "max_tokens", "max_output_tokens", "max_length", "tool_calls", "tool_call", "tool", "content_filter", "content_filtered". That list is the union of Kotlin MappingResults.kt:32-37, Swift Results.swift:22-30, Web Mapping.ts:195-204 and the engine literals at llamacpp_backend.cpp:862-866 -- if you drop any of them you silently regress a platform that handled it.
  1. Do NOT delete the string fields in the same release. Reserve them one release later, after `rg -n 'finishReason|finish_reason' sdk engines --glob '!**/generated/**' --glob '!**/Generated/**' --glob '!**/proto*/**'` returns only the enum sites.
  1. Fix the two writer sites before flipping any reader: Swift Public/Connect/ConnectSession.swift:1280 and :1426, and Web Adapters/LLMProtoAdapter.ts:160. They assign the literal 'error' and must become FINISH_REASON_ERROR.
  1. Decide explicitly whether voice_events.proto:110 and vlm_options.proto:136 adopt the enum in this pass. If they do not, delete the words 'used in every place a finish reason is reported' from the AFTER comment -- as written it is false the moment it lands.


### `llm-industry-names` — Rename to the industry's words: repetition_penalty -> repeat_penalty, model_id / model_used -> model

**Proto location:** [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L50), [llm_options.proto (LLMGenerationResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L80), [llm_service.proto (LLMGenerateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L27)

**Why:** A developer who knows llama.cpp or Ollama searches for `repeat_penalty` and finds nothing. A developer who knows any LLM API at all writes `model:` and gets a compile error twice — once setting the request, once reading the result. `model_id` and `model_used` are also two names for one concept across the request/result pair.

**Skeptic verdict:** `not-simpler` — The repeat_penalty half is sound. The model_id -> model half makes the repo LESS consistent, which is the opposite of the stated goal: `model_id` appears in 20 other protos (model_types.proto x11, sdk_events.proto x11, download_service.proto x10, storage_types.proto x8, rag/lora/embeddings/...), so renaming the single occurrence in llm_service.proto leaves a newcomer with one message that says `model` and twenty that say `model_id`. A newcomer reads this codebase far more often than they read OpenAI's schema. Worse, `model_used` -> `model` collapses a real distinction: the proposal's own replacement comment says 'the model that actually served the call', which after the rename is spelled identically to the request's 'the model I asked for' — upstream can do that only because request and response are separate objects. Also: 'the tag numbers do not move so the wire is unaffected' ignores JSON — ts-proto's fromJSON reads snake_case names (llm_options.ts:908-909 reads `cached_prompt_tokens`) and commons emits literal names in telemetry_json.cpp:309 ('generation_time_ms'), so anything JSON-shaped does break. Take repeat_penalty; either rename model_id everywhere or nowhere.

**What changed:** Applied ONLY the repeat_penalty half, per care plan's explicit split instruction. repetition_penalty(5) renamed to repeat_penalty (same tag, name-only, wire-safe). Did NOT rename model_used->model or model_id->model -- care plan found this makes the codebase LESS consistent (model_id/modelId is the established spelling across 20+ protos and facade surfaces) and blocked it pending a repo-wide decision that is out of scope here.

**Files touched:** `idl/llm_options.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** repeat_penalty half -- the rename is source-breaking in six places I verified, including a user-facing CLI flag: sdk/runanywhere-cli/src/commands/cmd_run.cpp:74, :109-110, :389-390 and :663 (`cmd->add_option("--repetition-penalty", ...)`, documented behavior a user types); Kotlin foundation/bridge/extensions/CppBridgeLLM.kt:68, foundation/bridge/extensions/RALLMTypesCppBridge.kt:46, public/api/MappingOptions.kt:39 (`NEUTRAL_REPETITION_PENALTY = LLMGenerationOptions.defaults().repetition_penalty`), :56, :73 and the public option public/api/Options.kt:87 `repetitionPenalty`; Swift Sources/MLXRu…

**Wire safety:** Pure field renames: tag numbers and wire types are unchanged, so binary-protobuf compatibility is intact and `buf breaking` WIRE will pass (the FIELD_SAME_NAME rule lives in the FILE ruleset, which idl/buf.yaml does not use). Two caveats. (1) The JSON name changes: Kotlin/Wire emits an explicit `jsonName` for every field (e.g. generated LLMGenerationResult.kt:84 `jsonName = "finishReason"`), so a…

**Do first:**
  1. SPLIT THIS INTO TWO PROPOSALS AND LAND ONLY THE FIRST. repetition_penalty -> repeat_penalty is self-contained, matches llama.cpp and Ollama, and has a bounded, greppable blast radius. The model_id/model_used half is a different argument with a different answer.
  1. For repeat_penalty: land it inside the same pass as llm-explicit-presence, which already rewrites this exact field's declaration (rac_proto_adapters.cpp:456-457 and llm_module.cpp:1606 change either way). Two edits to one line beats two release cycles.
  1. Rename the CLI flag deliberately, not incidentally: cmd_run.cpp:663 exposes `--repetition-penalty` to humans. Add `--repeat-penalty` as the new spelling and keep `--repetition-penalty` as a hidden alias for one release; do not silently break a documented flag as a side effect of a proto rename.
  1. BLOCKER for the model_id half: it cannot be done in llm_service.proto alone without making the repo less consistent. The prerequisite that does not exist is a repo-wide decision -- either rename model_id -> model in all 20+ protos (model_types.proto, sdk_events.proto, download_service.proto, storage_types.proto, rag/lora/embeddings, and the pervasive facade spelling `modelId` at RN EventBus.ts:338 and Web RunAnywhere+ModelLifecycle.ts:163), or drop this half. Do not rename the single LLM occurrence.
  1. For model_used: if you rename it, keep the distinction the comment claims. `model` on the result meaning 'the model that actually served the call' next to `model` on the request meaning 'the model I asked for' is one word doing two jobs. `served_by_model` or leaving `model_used` alone both preserve it -- and every facade already surfaces it to apps as `model` anyway (Swift Results.swift:82, Web Mapping.ts:214, Kotlin MappingResults.kt:53), so the app-facing name is not what is being fixed.


### `llm-local-engine-defaults` — Ship the local-engine sampler defaults: top_k 40, min_p 0.05, repeat_penalty 1.1

**Proto location:** [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L45), [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L50), [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L70)

**Why:** Every anti-repetition knob ships at its disabled value, so a caller who passes no options gets temperature 0.7 with no top_k cutoff, no min_p floor and no repetition penalty — the exact configuration in which a small quantized on-device model loops. Defaults ARE the API for the 90% of callers who never open the options object, and these ones make the SDK look broken.

**Skeptic verdict:** `sound` — One of the three precedent attributions is misdescribed. 'llama.cpp /completion and Ollama's Modelfile independently ship the same numbers: top_k 40, min_p 0.05, repeat_penalty 1.1' — top_k 40 and repeat_penalty 1.1 are indeed both engines' documented defaults, but Ollama's documented default for min_p is 0.0, not 0.05; min_p 0.05 is llama.cpp only. So it is one engine, not two 'independently'. The number is still the right one to ship; just do not lean on a two-engine convergence that does not exist for that knob. Also worth confirming before landing: min_p has only ~3 non-generated references in commons versus ~89 for top_k, so verify min_p actually reaches the sampler — a default on a knob nothing plumbs is a cosmetic change.

**What changed:** top_k rac_default 0->40, repeat_penalty (renamed, see llm-industry-names) rac_default 1.0->1.1, min_p rac_default 0.0->0.05.

**Files touched:** `idl/llm_options.proto`

**Status:** `applied`


### `llm-n-threads-wrong-home` — Remove `n_threads` from per-request options — thread count is a load-time decision

**Proto location:** [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L73), [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L56)

**Why:** The engine builds its thread pool at model load, so a per-request thread count implies a guarantee the runtime cannot honour. It sits with no rac_min/rac_max and no documented meaning for its 0 default, unlike every sampling field around it, and Web never populates it — so it is already only two-thirds real. Mixing load-lifetime and request-lifetime knobs in one message means no caller can tell which fields take effect when.

**Skeptic verdict:** `sound` — No defect found, and the proposal is more conservative than it needs to be: its fallback hedge 'if the load ABI is not ready...' is moot, because the destination already exists and is already honoured — model_types.proto:559 `optional int32 threads = 7;` sits under the 'v4 placement knobs (honored end-to-end; never silently dropped)' comment in ModelLoadRequest, and commons validates/forwards those knobs at core/model_lifecycle.cpp:641-651 and core/model_lifecycle_translation.cpp. So state the migration concretely as n_threads -> ModelLoadRequest.threads. Note the field is genuinely plumbed today (see above), so the removal must land together with callers switching to the load request, not before.

**What changed:** LLMGenerationOptions.n_threads(23) reserved by number+name; comment explains thread count is a load-time decision.

**Files touched:** `idl/llm_options.proto`

**Status:** `applied`


### `llm-one-messages-array` — Carry the conversation as one `messages` array; delete `prompt`

**Proto location:** [llm_service.proto (LLMGenerateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L25), [llm_service.proto (LLMGenerateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L34), [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L57)

**Why:** One conversation is split across three carriers: the live turn in `prompt`, everything before it in `history`, the system turn in `options.system_prompt`. Every vendor without exception carries one ordered array, so a newcomer holding a `ChatMessage[]` must first learn to partition it — and every SDK writes that split-and-rejoin by hand, already lossily (Kotlin drops empty-content turns, so a tool-only assistant turn vanishes).

**Skeptic verdict:** `risky` — It keeps tag 27 but inverts its meaning: today `history` EXCLUDES the live turn (the proto says so on line 32-33), after the change `messages` INCLUDES it. Same tag, same type, silently different semantics — an old writer against a new reader yields a conversation with the final user turn missing and no prompt anywhere, with no `reserved`/renumber to make the skew detectable. The risk note also says 'breaking for all three live facades' and never mentions that commons C++ reads `request.prompt()` at 8 sites including empty-prompt validation, so the migration is larger than stated. Fix: give the new array a fresh tag (28) and reserve 27, or land the semantic flip behind a schema-skew fixture like the one tool_calling.proto:221-225 already documents for field 15.

**What changed:** LLMGenerateRequest: reserved 1,25,27 (prompt/metadata/history) by number+name. Added `repeated ChatMessage messages = 28` (fresh tag per care plan, not reusing 27 -- avoids inverting history's semantics silently).

**Files touched:** `idl/llm_service.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** commons reads `request.prompt()` at far more than the 8 sites the skeptic counted -- 22 live C++ sites, several of them validation gates that will start rejecting every request the moment prompt is gone: features/llm/llm_module.cpp:2247, :2260, :2279, :2288, :2325, :2328, :2363, :2379, :2398, :2420, :2442, :2449, :2475, :2578, :2594, :2603, :2640; features/llm/structured_output.cpp:674, :1411, :1528, :1665; features/llm/tool_calling_session.cpp:814 and :822; features/llm/tool_calling_run_loop.cpp:452 and :458; connect/rac_connect.cpp:580 `request.generation().prompt().empty()`; foundation/rac…

**Wire safety:** The proposal keeps tag 27 and inverts its meaning (history EXCLUDES the live turn today, messages INCLUDES it). Same tag, same type, silently different semantics -- an old writer against a new reader loses the final user turn with no wire-level signal. Use a FRESH tag. LLMGenerateRequest declares 1,14,15,16,25,26,27, so 28 is free; land `repeated ChatMessage messages = 28;` with `reserved 27; res…

**Do first:**
  1. Add `repeated ChatMessage messages = 28;` alongside the existing prompt(1)/history(27) in one additive commit. Do not reserve anything yet. This is the only ordering in which a skewed writer/reader pair is detectable rather than silently truncating the conversation.
  1. Teach commons to accept BOTH shapes in that same commit, in one helper, not 22 places: a `std::vector<ChatMessage> normalize_conversation(const LLMGenerateRequest&)` that returns `messages()` when non-empty and otherwise `history() + {user, prompt()}`. Route every one of the 22 `.prompt()` sites and 3 `.history()` sites through it. The empty-prompt validation gates at llm_module.cpp:2247, :2363, structured_output.cpp:1411, :1528, tool_calling_session.cpp:814, tool_calling_run_loop.cpp:452 and rac_connect.cpp:580 become 'normalized conversation is empty', which is the check they always meant.
  1. Fix the in-tree writer at solutions/operators/op_engine_backed.cpp:211 and :319 -- it calls `request.set_prompt(item.text())` and is inside commons, so it must move to `messages` in the same commit or the solutions pipeline silently stops sending anything once prompt is reserved.
  1. Keep a bare-string `generate(prompt:)` convenience in each facade wrapping a one-element array, as the risk note says -- and delete the five hand-written splitters at the same time (Swift LLMNamespace.swift:193-215, Web llm.ts:46-58, RN Llm.ts:65-75, Electron text.ts:39-80, Kotlin LlmNamespace.kt:285-293). Deleting those splitters is the entire payoff; if they survive the migration, this change bought nothing.
  1. Add the schema-skew fixture under idl/codegen/tests in the style tool_calling.proto:221-225 already advertises: old-writer(prompt+history) -> new-reader must reconstruct the same conversation, and new-writer(messages) -> old-reader must fail loudly rather than drop the last turn.
  1. Only after the above ships: reserve 1 and 27 with their names in a follow-up commit.


### `llm-one-result-message` — Delete LLMStreamFinalResult and put LLMGenerationResult on the terminal stream event

**Proto location:** [llm_service.proto (LLMStreamFinalResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L37), [llm_service.proto (LLMStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L74), [llm_options.proto (LLMGenerationResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L77)

**Why:** Two messages describe the same thing with different names and different types for the same quantity: `total_time_ms` (int64) vs `generation_time_ms` (double), `time_to_first_token_ms` (int64) vs `ttft_ms` (optional double). So 'absent' and '0 ms' are distinguishable on the unary path and not on the streaming path, and every SDK maintains two mappers for one concept.

**Skeptic verdict:** `sound` — The direction holds, but effort 'M' understates one thing the proposal never names: commons emits stream events through a hand-rolled wire encoder (features/llm/rac_llm_stream.cpp:435-460) that today writes only scalars plus pre-serialized ToolCall bytes. Embedding the much larger LLMGenerationResult on the terminal event means that encoder must serialize a nested message from llm_options.proto, or the fast path has to be abandoned. Note also that encoder already writes tags 9 (error_message string) and 11 (error_code int32) on LLMStreamEvent, which llm_service.proto does not declare at all — reconcile that while you are in there.

**What changed:** Deleted message LLMStreamFinalResult entirely. LLMStreamEvent.result retargeted from LLMStreamFinalResult to LLMGenerationResult on a FRESH tag (22, not the old tag 10 -- care plan's wire-safety analysis: reusing 10 would let old nested-field numbers alias new ones with partial, silent mis-parse). Removed now-unused imports (voice_events.proto, token_usage.proto) from llm_service.proto.

**Files touched:** `idl/llm_service.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** LLMStreamFinalResult has a dedicated mapper in four facades plus a typed producer path in commons: Kotlin public/api/MappingResults.kt:14 (import) and :56 `internal fun LLMStreamFinalResult.toGenerationResult(...)`; Web Public/API/Mapping.ts:34 (import) and :237 (`final: LLMStreamFinalResult`); Swift Public/API/Results.swift:86 `init(proto: RALLMStreamFinalResult, requestId:model:)` -- and the same file's :82 reads `proto.modelUsed`, which only exists on LLMGenerationResult, so Swift already has two near-identical initializers to collapse; React Native Public/Api/Results.ts:106 `toFinishReaso…

**Wire safety:** Do not reuse tag 10. Changing `optional LLMStreamFinalResult result = 10` to `optional LLMGenerationResult result = 10` keeps the same outer wire type (length-delimited) but replaces the entire nested field layout, so an old reader decodes the new bytes WITHOUT a wire-type error at the outer tag and then mis-parses inside: nested tag 1 (text) and 2 (thinking_content) line up by luck, nested tag 6…

**Do first:**
  1. Land llm-finish-reason-enum first (additive phase at minimum). LLMGenerationResult must already carry the typed finish_reason before it becomes the sole result type, otherwise you delete LLMStreamFinalResult.finish_reason and immediately re-add a string one.
  1. Decide the hand-encoded path explicitly and write the decision into rac_llm_stream.cpp's tag-map comment at :287-305. Two honest options: (a) implement `wire_message_field` and serialize LLMGenerationResult by hand -- real work, this encoder currently only knows scalars plus pre-serialized ToolCall bytes at :455; or (b) declare that streaming requires RAC_HAVE_PROTOBUF and make the non-protobuf build fail at configure time rather than silently drop the terminal result. Do not leave it implicit; it is already implicit today and that is why field 10 is a documented hole.
  1. Reconcile the undeclared tags while you are in the file: the encoder writes tag 9 (error_message, string) and tag 11 (error_code, int32) on LLMStreamEvent, and llm_service.proto declares neither. Either declare them or stop writing them -- but they must be in the `reserved` list of any future edit to this message either way.
  1. Add LLMGenerationResult to the terminal event as tag 20 alongside the existing tag 10 in an additive commit; populate BOTH from llm_module.cpp:2143-2173 for one release; migrate the four facade mappers (Kotlin MappingResults.kt:56, Web Mapping.ts:237, Swift Results.swift:86, RN Results.ts:106) to the new field; only then reserve 10 and delete the message.
  1. Collapse the three error channels in the same pass or state which one wins. Swift LLMNamespace.swift:303 reads event.error; the encoder writes 9/11; LLMStreamFinalResult.error(17) exists. Pick LLMStreamEvent.error(19) and say so in the proto comment.


### `llm-one-stream-discriminator` — Make `event_kind` the only stream discriminator; delete `is_final`, `kind` and the 7 unread fields

**Proto location:** [llm_service.proto (LLMStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L64), [llm_service.proto (LLMStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L69), [llm_service.proto (LLMStreamEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L52)

**Why:** One event carries three answers to 'is this the last one' (`is_final`, `event_kind == COMPLETED`, the presence of `result`) and two to 'is this answer text or reasoning' (`kind`, `event_kind`). Swift and Kotlin branch on `is_final` and classify with `kind`; Web branches on `result` and classifies with `event_kind` — so the same backend stream is read by different fields per platform, and a backend filling only one classifier leaks reasoning tokens into the visible answer on some SDKs and not others.

**Skeptic verdict:** `risky` — Two load-bearing premises are wrong. (1) 'Web branches on `result`' is false — Web branches on is_final in the only place it matters: sdk/runanywhere-web/packages/core/src/Adapters/LLMProtoAdapter.ts:132 `stopWhen: (event) => event.isFinal`, :151 the same predicate for the main-thread path, and :159 synthesizes `isFinal: true` for the error terminal. So deleting is_final breaks stream TERMINATION on Web too, not just classification on Swift/Kotlin — three facades, not two. (2) event_kind is not yet an independent discriminator: commons DERIVES it from the two fields being deleted — rac_llm_stream.cpp:449 `wire_enum_field(out, /*field=*/12, derive_event_kind(p.kind, p.is_final, p.error_message))`. So 'event_kind is the ONLY discriminator' requires first giving the producer a real source for it; ordered the other way, the surviving discriminator is computed from deleted inputs.

**What changed:** LLMStreamEvent: reserved 2,4,5,6,7,8,9,10,11,14,15,16,17 by number, plus names for the ones that had one (timestamp_us/is_final/kind/token_id/logprob/conversation_id/prompt_tokens_processed/completion_tokens_generated/elapsed_ms -- finish_reason and result excluded from the name-reserve since both are reintroduced under the same name at a new tag, which protoc correctly rejects reserving). Kept seq(1), token(3), event_kind(12), request_id(13), tool_call(18), error(19), partial_json(20) as declared. NOT implementing the care plan's 'unblock' step (giving event_kind a real non-derived producer in commons) here -- that is Phase C (C++) work, tracked to happen when commons is made to compile against this proto.

**Files touched:** `idl/llm_service.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** `is_final` is the stream-termination predicate in FIVE targets, not two or three: Web Adapters/LLMProtoAdapter.ts:132 `stopWhen: (event) => event.isFinal`, :151 the same predicate on the main-thread path, and :159 which SYNTHESIZES `isFinal: true` for the error terminal; React Native Public/Api/Llm.ts:271 `if (event.isFinal)` with the recovery comment at :293 ('The native call resolved without ever sending isFinal'); Kotlin public/api/LlmNamespace.kt:401 `if (raw.is_final)` (with the contract written down at :356 -- 'producing at least one event but without a terminal is_final emits...'), pub…

**Wire safety:** The reserved list in the AFTER is correct and unusually careful -- it includes 9 and 11, which llm_service.proto does not declare but the hand encoder really does write (rac_llm_stream.cpp:439 `wire_string_field(out, /*field=*/9, p.error_message)` and :446 `wire_int32_field(out, /*field=*/11, p.error_code)`). Keep them in. Two changes ride along and must be handled per their own plans: finish_rea…

**Do first:**
  1. UNBLOCK STEP (this is the hard prerequisite that does not exist yet): give event_kind a real producer. Today it is derived at rac_llm_stream.cpp:449 from kind + is_final + error_message. Widen LLMStreamEventParams (rac_llm_stream_internal.h) with an explicit `event_kind` the callers set directly -- llm_module.cpp:1916-1927 (dispatch_stream_event), :2138, :2173 and structured_output.cpp:797, :832 are the call sites that know the real answer -- and reduce derive_event_kind to a compatibility shim. Until that lands, deleting kind and is_final deletes the inputs of the only surviving discriminator.
  1. Then run one release where commons sets kind, is_final AND a natively-sourced event_kind consistently, and add a commons assertion that they never disagree (event_kind==COMPLETED iff is_final, event_kind==THINKING iff kind==TOKEN_KIND_THOUGHT). That assertion is what makes the later deletion safe, because it proves no producer path was missed.
  1. Migrate readers to event_kind in this order, one PR each: Web (LLMProtoAdapter.ts:132,:151,:159), React Native (Llm.ts:271), Kotlin (LlmNamespace.kt:401, RunAnywhereTextGeneration.kt:155,:264-269), Swift (ConnectSession.swift:1233,:1308, LLMNamespace.swift:276,:286), CLI (cmd_run.cpp:207). Web and RN first because their terminal predicate failing means the stream never ends -- a hang, not an error, and you want to find that on the noisiest platform first.
  1. Decide what happens to Kotlin's PUBLIC `RALLMStreamEvent.isFinal` (Results.kt:91, populated at MappingResults.kt:128) and Swift's public TokenKind (Events.swift:15,:125). These are app-facing. Keeping them as facade-computed properties derived from event_kind costs two lines each and turns an app break into a no-op; deleting them is a separate, louder decision.
  1. Before deleting the PROGRESS payload fields (prompt_tokens_processed 15, completion_tokens_generated 16, elapsed_ms 17), confirm with the product owner that prefill progress is not a requirement -- LLM_STREAM_EVENT_KIND_PROGRESS survives the change with nothing in it.
  1. Update the hand encoder in the same commit: stop writing tags 4, 5, 6, 7, 15, 16, 17 at rac_llm_stream.cpp:437-454 and update the tag-map comment at :287-305. buf cannot check this file.


### `llm-request-id-owner` — Write down who owns `request_id` (commons generates it) in two comment lines

**Proto location:** [llm_service.proto (LLMGenerateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L26), [llm_service.proto (LLMStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_service.proto#L76)

**Why:** The field carries no comment saying who fills it, so the three live SDKs each invented an answer: Kotlin generates a UUID then ignores the wire value, Web hardcodes the empty string, Swift never assigns it and reads it straight back — every Swift result reports an empty request id. Eight SDKs will be eight behaviours. This is a documentation fix with no new surface.

**Skeptic verdict:** `sound` — No defect found. Two caveats, neither fatal: I could not confirm the Swift and Web halves of the divergence claim ('Web hardcodes the empty string', 'Swift never assigns it') — grep for requestId in sdk/runanywhere-web/.../LLMProtoAdapter.ts returned nothing at all, so treat those two as unverified colour rather than evidence. And the fix is not purely documentary: commons' hand-rolled encoder writes p.request_id verbatim at rac_llm_stream.cpp:450, so 'commons generates one when empty' is a real code change there plus in llm_module, however small.

**What changed:** Added the ownership comment to LLMGenerateRequest.request_id explaining commons generates it when empty (industry precedent: OpenAI id, Anthropic request-id).

**Files touched:** `idl/llm_service.proto`

**Status:** `applied`


### `llm-tool-options-no-shadow` — Remove temperature / max_tokens / system_prompt from ToolCallingOptions

**Proto location:** [tool_calling.proto (ToolCallingOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto#L197), [tool_calling.proto (ToolCallingOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto#L200), [tool_calling.proto (ToolCallingOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto#L203), [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L74)

**Why:** ToolCallingOptions is nested inside LLMGenerationOptions and re-declares three settings the parent already carries, with no stated precedence — so one generation call has two reachable values for temperature and the contract says nothing about which wins. The Web facade already passes both. The duplicate is even spelled `max_tokens`, the name OpenAI marked deprecated, where the parent uses the modern `max_output_tokens`.

**Skeptic verdict:** `risky` — 'ToolCallingOptions is nested inside LLMGenerationOptions' is only one of five embeddings. It is also the standalone options carrier for ToolParseRequest.options (tool_calling.proto:273), ToolPromptFormatRequest.options (:290) and ToolCallValidationRequest.options (:313), plus ChatGenerationRequest.tool_calling (chat.proto:117) — and in the first three there IS no enclosing LLMGenerationOptions, so the replacement comment 'sampling and system prompt come from the enclosing LLMGenerationOptions' is unreachable advice for them. Deleting system_prompt removes the only way to pass a system prompt to the prompt-formatting verb, which commons currently honours via tool_calling.cpp:1880-1882. Note also the run-loop/session request messages carry their own temperature/max_tokens/system_prompt (read at tool_calling_run_loop.cpp:459-462 and tool_calling_session.cpp:823-826, documented at tool_calling.proto:387-390), so the shadowing you actually want to kill is broader than these three lines. Land the temperature/max_tokens removal; keep system_prompt or give the three standalone requests their own before removing it.

**What changed:** ToolCallingOptions: reserved 4,5 (temperature, max_output_tokens -- genuinely redundant with the parent LLMGenerationOptions in the two embeddings that have one). Did NOT delete system_prompt(6) as the raw proposal wanted -- care plan found it is the ONLY system-prompt channel for the three standalone verbs (ToolParseRequest/ToolPromptFormatRequest/ToolCallValidationRequest have no enclosing LLMGenerationOptions); kept it with a comment stating the child-wins-parent-fallback precedence that Swift/Kotlin/Web facades already implement.

**Files touched:** `idl/tool_calling.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** All three fields are read with real presence checks in commons at sdk/runanywhere-commons/src/features/llm/tool_calling.cpp:1874 (`if (proto.has_temperature())`), :1877-1878 (`has_max_tokens` -> `converted.options.max_tokens`) and :1880 (`has_system_prompt`) -- and that converter is shared by the three STANDALONE verbs, which is the fact that breaks the proposed replacement comment. ToolCallingOptions is embedded in FIVE places, verified: llm_options.proto:74 (inside LLMGenerationOptions), chat.proto:117 (ChatGenerationRequest.tool_calling), and tool_calling.proto:273 (ToolParseRequest.option…

**Wire safety:** Field removal with correct `reserved 4, 5, 6;` plus reserved names -- wire-safe and `buf breaking` WIRE-clean as long as the reserved lines land in the same commit as the deletion (they are in the AFTER, keep them). No tag reuse, no renumbering. Note these are `optional` scalars today, so an old writer that sets them produces bytes a new reader will drop into unknown fields silently -- acceptable…

**Do first:**
  1. Rewrite the replacement comment before anything else. As written it is false for three of the five embeddings (ToolParseRequest at tool_calling.proto:273, ToolPromptFormatRequest at :290, ToolCallValidationRequest at :313 have no enclosing LLMGenerationOptions). Do not ship it.
  1. Decide system_prompt separately from temperature/max_tokens. temperature and max_tokens are genuinely redundant inside LLMGenerationOptions and meaningless in the three standalone verbs -- safe to delete. system_prompt is the ONLY channel the prompt-formatting verb has (commons honours it at tool_calling.cpp:1880-1882); either keep field 6 with a comment saying it applies only when ToolCallingOptions is used standalone, or add an explicit system_prompt to ToolPromptFormatRequest first. Deleting it with nothing in its place is a functional regression, not a cleanup.
  1. Write the precedence rule into the proto in the SAME commit, for the fields that survive: 'the child value wins when present; the parent LLMGenerationOptions value is the fallback' -- that is what all three facades already implement (Swift :415-434, Kotlin :164-170, Web :178-180) and stating it is most of the actual fix.
  1. Ship one release with the three fields marked deprecated and a commons log line at tool_calling.cpp:1874-1882 when a caller sets them, so you can see whether anyone actually does before the delete.
  1. Delete the facade fallback ladders at the same time as the fields, not before -- Swift RunAnywhere+ToolCalling.swift:415-434, Kotlin ToolCallingOrchestrator.kt:164-170, Web RunAnywhere+ToolCalling.ts:178-180. Otherwise those three files reference fields that are gone and the tool-calling build breaks on all three platforms simultaneously.
  1. State plainly in the commit message that the request-level copies at tool_calling_run_loop.cpp:459-461 and tool_calling_session.cpp:823-825 (declared at tool_calling.proto:387-390) are NOT removed by this change, so nobody reads 'one value per setting per call' and believes it.


</details>


<details>
<summary><strong>lora</strong> (9 changes)</summary>

### `lora-apply-is-set-not-stack` — Make apply replace the active set by default: retire replace_existing, add keep_existing

**Proto location:** [lora_options.proto (LoRAApplyRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L168)

**Why:** `replace_existing` defaults to false, so calling apply twice silently stacks two adapters -- the opposite of every industry setter (Diffusers set_adapters, llama_set_adapters_lora, PEFT BaseTuner.set_adapter are all total replacement). A newcomer writing the obvious "switch to adapter B" call ends up running A+B blended.

**Skeptic verdict:** `sound` — Effort 'S' understates one piece: the new doc promises 'an empty list means the base model', but rac_lora_service.cpp:605 currently rejects that outright with 'LoRAApplyRequest.adapters is required'. That validation has to be relaxed in the same change or the documented zero-value behaviour is unreachable.

**What changed:** In LoraApplyRequest, deleted replace_existing and added `bool keep_existing = 3`, so the message's zero value is now total replacement (the industry setter semantics) and stacking is the opt-in. Documented `adapters` as SET semantics matching Diffusers set_adapters and llama_set_adapters_lora.

**Files touched:** `idl/lora_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** One commons reader and five app-facing call sites, all of which flip meaning. Commons: rac_lora_service.cpp:624 `if (request.replace_existing())` -> clear-then-load; this becomes `if (!request.keep_existing())`. Public setters that today default to STACK and would silently become REPLACE for every existing caller: Swift RunAnywhere+LoRA.swift:49 `replaceExisting: Bool = false` (used at :69, aliased at :73/:80/:82), Kotlin RunAnywhereLoRA.kt:75 and :91 (`replace_existing = replaceExisting`) plus the alias at :104-105, React Native RunAnywhere+LoRA.ts:177/:181/:210 and :233 (`replaceExisting: o…

**Wire safety:** Tag 3 is freed and MUST be reserved together with the name: `reserved 3; reserved "replace_existing";`. New field keep_existing takes tag 4, verified unused (LoRAApplyRequest holds only 1,2,3). Same wire type (bool/varint) at a different tag, so no misparse -- an old client's tag-3 varint lands in unknown fields and is ignored, which yields the new default (replace). That is the intended, and the…

**Do first:**
  1. Relax the validation in the same commit: rac_lora_service.cpp:603 and :605 both emit 'LoRAApplyRequest.adapters is required'. An empty `adapters` must become the legal 'detach everything, run the base model' path (fall through to the same clear branch as :624) or the documented zero value is unreachable and the doc comment becomes a second lie.
  1. Use tag 4 for keep_existing and reserve tag 3. Do NOT reuse tag 3: an already-shipped app that sends replace_existing=true would be decoded as keep_existing=true, which is the exact inverse of what it asked for -- silent, un-loggable behaviour inversion. `rg -n '^message |reserved' idl/lora_options.proto` confirms LoRAApplyRequest carries only tags 1,2,3 and that the file has NO reserved statements today, so tag 4 is free and this will be the file's first reserved block.
  1. Sweep the two explicit true-setters first -- cmd_run.cpp:545 and cmd_lora.cpp:287 -- they just delete the line and get the same behaviour.
  1. Then sweep the five defaulted app-facing setters (Swift :49, Kotlin :75, RN :210, Flutter :55, Web lora.ts:34). Each is a public parameter rename plus a polarity flip; review each call site, do not sed. Web lora.ts:34 needs a decision, not a rename: it hardcodes replaceExisting:false, i.e. it stacks today.
  1. Update Flutter test/lora_proto_shape_test.dart:46/:58 in the same commit -- it round-trips replaceExisting:true and will not compile.


### `lora-dead-fields` — Delete the six LoRA fields nothing reads (including the one the proto labels "Not read by commons")

**Proto location:** [lora_options.proto (LoRAAdapterConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L34), [lora_options.proto (LoRAAdapterConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L31), [lora_options.proto (LoraAdapterCatalogListRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L96), [lora_options.proto (LoraAdapterCatalogListResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L104)

**Why:** target_modules reads like a real capability ("restrict this adapter to q_proj/v_proj") and the proto itself says it is not read; metadata, warnings, include_counts, filtered_count and LoRARemoveRequest.request_id are equally inert. Every one of the eight SDKs generates a setter, a builder, a type and docs for each, so app authors set them and get no behaviour change.

**Skeptic verdict:** `sound` — One imprecision, not a refutation: filtered_count is not inert on the producing side -- lora_registry.cpp:330 calls result.set_filtered_count(filtered.size()). No hand-written SDK or app code reads it (grep for filteredCount outside generated/proto-ts/electron dirs is empty), so the redundancy argument stands, but 'nothing reads' should be 'commons writes it and nothing reads it'. Also the after-comment says a downloaded count is derivable from entries with a local_path while keeping downloaded_count -- pick one.

**What changed:** Deleted all six inert fields: metadata and target_modules from LoraAdapterConfig, include_counts from LoraAdapterCatalogListRequest, filtered_count from LoraAdapterCatalogListResult, warnings from LoraCompatibilityResult, and request_id from LoraRemoveRequest. Surviving tags in each touched message were renumbered dense and ascending (LoraAdapterCatalogListResult is now entries=1, total_count=2, downloaded_count=3, error=4; LoraCompatibilityResult is now is_compatible=1, base_model_required=2, error=3).

**Files touched:** `idl/lora_options.proto`

**Status:** `applied`


### `lora-delete-download-import-bookkeeping` — Delete the four adapter download/import bookkeeping messages; use the models domain's download and import

**Proto location:** [lora_options.proto (LoraAdapterDownloadCompletedRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L119), [lora_options.proto (LoraAdapterDownloadCompletedResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L129), [lora_options.proto (LoraAdapterImportRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L135), [lora_options.proto (LoraAdapterImportResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L143)

**Why:** A newcomer opening lora_options.proto finds a second, adapter-only download/import state machine (mark-download-completed, mark-import-completed, persisted, matched, status_message) that duplicates the models domain this repo already ships. No LoRA vendor in the survey -- PEFT, Diffusers, vLLM, llama.cpp, ONNX GenAI, MLX, Apple, MediaPipe -- has any catalog or fetch bookkeeping at all; every one of them takes a path and lets the app do the downloading.

**Skeptic verdict:** `risky` — Two load-bearing claims do not hold. (1) 'duplicates the models domain': lora_import.cpp already writes a ModelInfo artifact tagged 'lora-adapter' (:155) plus 'base-model:<id>' (:158) -- it is not a parallel state machine, it is a thin wrapper whose extra output is the catalog match (`matched` + `entry`), and grep -nE '^message .*(Import|Register)' idl/model_types.proto shows ModelImportRequest/ModelImportResult (489/507) with no `matched`/`entry` counterpart, so deleting these four messages loses the catalog-completion result with nowhere to put it. (2) The verb list is inflated: it names four verbs (markDownloadCompleted, markImportCompleted, importAdapter, registerLoraArtifact) but only two exist against these messages -- rac_lora_register_proto (rac_lora_service.cpp:503) registers a LoraAdapterCatalogEntry and is untouched by this deletion, and there is no separate markImportCompleted verb (the ImportRequest/ImportResult pair is it).

**What changed:** Deleted all four adapter download/import bookkeeping messages outright (LoraAdapterDownloadCompletedRequest, LoraAdapterDownloadCompletedResult, LoraAdapterImportRequest, LoraAdapterImportResult), taking the file from 17 messages to 13. Per the no-backcompat ground rule I left no tombstone comment at the deletion site; instead the file header now states that adapter files are acquired through the models domain's download/import verbs and that this domain carries no download state of its own.

**Files touched:** `idl/lora_options.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** Live in all five bindings plus commons. Commons impl: lora_registry.cpp:712-753 is the whole mark-download-completed body (set_is_downloaded 732, set_downloaded_at_unix_ms 733, set_is_imported 736, set_status_message 737-740, set_size_bytes 741-743 which also mirrors into it->second->file_size, set_checksum_sha256 745-746, set_persisted false 723 / true 753); lora_import.cpp exports rac_lora_adapter_import_proto and does the real work (catalog_entries 92-107, make_artifact_record 123-147 which writes the ModelInfo tagged artifact, filename match 208-238, copy + mark 282-335 calling rac_lora_c…

**Wire safety:** Four top-level messages deleted whole; no tag inside any surviving message is reused, so nothing on the wire is reinterpreted. The real hazard is symbol-level, not tag-level: rac_lora_catalog_mark_download_completed_proto and rac_lora_adapter_import_proto are exported from RACommons.exports and listed in sdk/runanywhere-web/wasm/CMakeLists.txt; Flutter resolves them with _lookupOptional (rac_nati…

**Do first:**
  1. Add a models-domain import verb to idl/codegen/swift-modality-abi.yaml alongside the existing lora entries at :539-549, wired to the commons handler that already exists at model_registry_proto.cpp:935-1011 (rac_model_registry.h:404). Until that verb is generated, `rg -n 'import' idl/codegen/swift-modality-abi.yaml` returns only importAdapter:546 -- deleting importAdapter leaves Swift/Flutter/RN with no import path at all. THIS IS THE HARD PREREQUISITE.
  1. Decide where the catalog-match result goes. cmd_lora.cpp:78-86 reads result.matched() and the matched entry, and lora_import.cpp:208-238 computes it by `entry.filename() == filename` then falls back to a unique name match at :237-238. ModelImportResult (idl/model_types.proto:507) has no matched/entry counterpart. Either add matched+entry to ModelImportResult, or keep a tiny lora.matchImported(local_path) -> LoraAdapterCatalogEntry read verb. Do not delete the four messages until one of those exists.
  1. DROP the migration line from the risk note before writing anything: there is no persisted catalog. lora_registry.cpp:5 documents an 'In-memory LoRA adapter metadata store' and the store is the two std::maps at :33/:35 -- nothing writes it to disk. Say 'no data migration; the in-memory catalog is rebuilt from rac_lora_register_proto on every launch' instead.
  1. Confirm rac_lora_register_proto (swift-modality-abi.yaml:512) is explicitly OUT of scope and stays. The brief's verb list of four is wrong: only markDownloadCompleted and importAdapter are backed by these messages; markImportCompleted is a Swift/Flutter convenience that just calls markDownloadCompleted (RunAnywhere+LoRA.swift:180-188, runanywhere_lora.dart:168-175), and registerLoraArtifact is the web wrapper over rac_lora_register_proto (RunAnywhere+LoRA.ts:437) which this deletion does not touch.
  1. Land in this order or a binding compiles against a gone symbol: (1) models import verb generated + matched/entry home; (2) commons re-points lora_import.cpp's artifact write at the models import handler and rac_lora_catalog_mark_download_completed_proto becomes a no-op shim that still exports; (3) each binding switches its call site (Swift RunAnywhere+LoRADownload.swift:140/:159, Kotlin CppBridgeLoraRegistry.kt:120-134, Flutter runanywhere_lora.dart:154-190, RN RunAnywhere+LoRA.ts:385, CLI cmd_lora.cpp:78-86); (4) only then delete the four messages and drop the exported symbols from sdk/runanywhere-commons/exports/RACommons.exports and sdk/runanywhere-web/wasm/CMakeLists.txt.


### `lora-id-is-the-handle` — Make adapter_id the required handle and adapter_path the optional escape hatch (and retire remove-by-path)

**Proto location:** [lora_options.proto (LoRAAdapterConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L24), [lora_options.proto (LoRAAdapterConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L29), [lora_options.proto (LoRARemoveRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L182)

**Why:** Today an adapter's identity is its filesystem path -- adapter_path is the one required field in the file -- while the string handle every other verb wants is optional and often empty. That forces an app to carry paths around, and it is backwards from every vendor, all of which key on a name.

**Skeptic verdict:** `risky` — The escape-hatch story ('when unset the path is resolved from the catalog entry named by adapter_id') is not something that exists. rac_lora_service.cpp:647 loads strictly by path -- `ref.ops->load_lora(ref.impl, config.adapter_path().c_str(), scale)` -- and the only id resolver, resolve_lora_id_to_path at :162, resolves against the tracked ACTIVE adapter list (:172), not the catalog; the catalog lives behind a separate rac_lora_registry_handle_t that the apply path never holds. So making adapter_path optional requires new registry wiring, not an annotation flip. Worse, :180 emits 'LoRARemoveRequest.adapter_ids is ambiguous for duplicate active adapter id' -- commons already knows ids are not unique, which is the premise 'id is the handle' needs. And remove-by-path is live surface: :744-780 iterate request.adapter_paths() and call track_lora_removed_path, plus :757 makes adapter_paths one of three accepted selectors.

**What changed:** In LoraAdapterConfig, adapter_id (tag 3) is now the required handle carrying (runanywhere.v1.rac_required) = true and is declared first; adapter_path (tag 1) is now `optional string` and no longer required. In LoraRemoveRequest, deleted adapter_paths and request_id, leaving adapter_ids=1 and clear_all=2 as the only identity path.

**Files touched:** `idl/lora_options.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** The 'after' comment promises a resolver that does not exist, and remove-by-path is live in six places. Load is path-only: rac_lora_service.cpp:647 `rc = ref.ops->load_lora(ref.impl, config.adapter_path().c_str(), scale)` -- there is no id->path lookup on the apply path, and the only resolver, resolve_lora_id_to_path at :162, resolves against the ACTIVE adapter list, not the catalog (its errors say so: :180 'LoRARemoveRequest.adapter_ids is ambiguous for duplicate active adapter id', :189 '...contains an adapter id that is not active'). The catalog lives behind rac_lora_registry_handle_t, whic…

**Wire safety:** No tag moves: adapter_path stays 1, scale 2, adapter_id 3, adapter_ids 2 on Remove. What changes is requiredness (an annotation, not the wire) and the deletion of LoRAAdapterConfig tags 4/5 and LoRARemoveRequest tags 1/3. Reserve all four with names, as the 'after' already does -- and note this is the file's first use of reserved, so verify protoc actually accepts the block (`rg -n 'reserved' idl…

**Do first:**
  1. BUILD THE RESOLVER FIRST, as its own landed change, before touching the annotations. The apply path must be able to reach the catalog: give the LLM ref access to the rac_lora_registry_handle_t, add catalog_lookup(adapter_id) -> local_path next to resolve_lora_id_to_path (rac_lora_service.cpp:162), and call it at :647 when config.adapter_path() is empty. Until that lands, adapter_path optional means apply passes an empty path to load_lora.
  1. SETTLE ID UNIQUENESS SECOND. rac_lora_service.cpp:180 already emits 'adapter_ids is ambiguous for duplicate active adapter id' -- commons currently tolerates duplicate ids, which contradicts 'id is the handle'. Either enforce uniqueness at register time (rac_lora_register_proto) and delete that error, or define the tie-break. Do not ship a required handle that commons itself calls ambiguous.
  1. DEFINE THE DERIVATION for a bare unregistered .gguf: 'commons can derive one from the filename' has no implementation. Write it (stem of basename, lowercased, collision-suffixed), put it in commons so all five SDKs agree, and document it in the proto comment. Otherwise every app invents its own and ids stop matching across sessions.
  1. Only then flip the annotations, and split remove-by-path into its own commit: sweep cmd_lora.cpp:222, test_lora_proto_abi.cpp:331, LoRAProtoSurfaceTests.swift:77/:81, web lora.ts:62/:73, types.test-d.ts:113, flutter lora_proto_shape_test.dart:84/:92 BEFORE deleting adapter_paths; fix the error string at rac_lora_service.cpp:757 which still names it; delete the :744-746 loop and keep track_lora_removed_path (:780) reachable via the id branch at :731-734.
  1. target_modules deletion is a separate, trivially safe commit (proto comment already says 'Not read by commons', and the four writers only ever pass []) -- land it on its own so it does not get tangled in the identity work.
  1. Sequence against lora-one-spelling: do all of this BEFORE the rename, so the rename stays a pure mechanical sweep.


### `lora-one-spelling` — Pick one spelling of LoRA in message names (normalize LoRA* to Lora*) before it reaches eight SDKs

**Proto location:** [lora_options.proto (LoRAAdapterConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L22), [lora_options.proto (LoRAAdapterInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L37), [lora_options.proto (LoraAdapterCatalogEntry)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L53), [lora_options.proto (LoRAApplyRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L163)

**Why:** One file uses both `LoRAAdapterConfig` and `LoraAdapterCatalogEntry`. Every SDK inherits both spellings into its generated identifiers, so a developer must remember which half of the domain capitalizes the acronym -- pure memory tax with no information in it.

**Skeptic verdict:** `not-simpler` — The 'existing majority' justification is nullified by the reviewer's own critical proposal. lora-delete-download-import-bookkeeping deletes four Lora*-prefixed messages (LoraAdapterDownloadCompletedRequest/Result, LoraAdapterImportRequest/Result), taking the split from 11-vs-6 to 7-vs-6 -- a coin flip, so the direction is pure taste, and the direction chosen renames all six of the live runtime types (Apply/Remove/State/AdapterConfig/AdapterInfo) that commons and every app actually call, rather than the seven catalog types that mostly go away. Zero fields or messages are deleted, so the whole cost is a source-breaking rename sweep across eight generated SDKs plus the Swift/Kotlin/Dart/TS typealiases for no semantic gain.

**What changed:** Renamed all six LoRA*-spelled messages to the Lora* spelling: LoRAAdapterConfig -> LoraAdapterConfig, LoRAAdapterInfo -> LoraAdapterInfo, LoRAApplyRequest -> LoraApplyRequest, LoRAApplyResult -> LoraApplyResult, LoRARemoveRequest -> LoraRemoveRequest, LoRAState -> LoraState, and updated the four in-file type references (LoraApplyRequest.adapters, LoraApplyResult.adapters, LoraState.loaded_adapters). The file now uses one spelling throughout.

**Files touched:** `idl/lora_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Source-breaking in every binding plus two things the brief does not mention. Hand-written files with the largest LoRA*-identifier counts (from `rg -c`): sdk/runanywhere-commons/src/features/lora/rac_lora_service.cpp (46), sdk/runanywhere-commons/tests/test_lora_proto_abi.cpp (45), RN Public/Extensions/LLM/RunAnywhere+LoRA.ts (42), web Adapters/LoRAProtoAdapter.ts (29), Kotlin CppBridgeLoraRegistry.kt (23), web Public/Extensions/RunAnywhere+LoRA.ts (22), Kotlin RunAnywhereLoRA.kt (21), Flutter test/lora_proto_shape_test.dart (17), Flutter dart_bridge_lora.dart (15), web tests/types/types.test-…

**Wire safety:** No wire change: message names never travel in proto binary encoding, and no field tag or field name moves. Two non-binary surfaces DO carry the message name and must be checked: protobuf JSON / Any type URLs (`type.googleapis.com/runanywhere.v1.LoRAState`) and the Kotlin wire generated file names. Nothing in this repo persists a lora message as JSON or Any that I found, but the commons catalog st…

**Do first:**
  1. Do this LAST in the domain, after lora-delete-download-import-bookkeeping, lora-id-is-the-handle, lora-trim-catalog-entry and lora-state-is-response-only have all landed. Every one of those edits the same lines; renaming first turns each of them into a merge conflict, and renaming last means the sweep touches strictly fewer files (four Lora*-prefixed messages disappear in item 1).
  1. Ship it as ONE commit that contains nothing else. A rename mixed with a semantic change is the commit no one can review or revert.
  1. Rename BOTH copies of rac_lora_service.h in the same commit: sdk/runanywhere-commons/include/rac/features/lora/rac_lora_service.h and the vendored sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include/rac/features/lora/rac_lora_service.h.
  1. Update idl/codegen/swift-modality-abi.yaml (10 hits) -- its request/response entries name RALoRA*/RALora* types and drive the Swift ABI generation; a stale entry there produces a Swift file that references a type protoc no longer emits.
  1. Sweep the runtime error strings and generated validator fieldPaths in the same commit: rac_lora_service.cpp:167/:180/:189/:603/:605/:746/:757 and the regenerated RAConvenience.kt:489 / RAConvenience.swift.
  1. Regenerate all five binding surfaces and commit the generated diffs together: sdk/runanywhere-commons/src/generated/proto/lora_options.pb.{h,cc}, sdk/shared/proto-ts/src/lora_options.ts, sdk/runanywhere-flutter/.../generated/lora_options.pb.dart, sdk/runanywhere-swift/.../Generated/lora_options.pb.swift, sdk/runanywhere-kotlin/.../generated/ai/runanywhere/proto/v1/LoRA*.kt (the Kotlin files are named after the message, so files get renamed too).


### `lora-report-rank-alpha-size` — Report rank, alpha and resident size on LoRAAdapterInfo (read-only, filling existing tag gaps)

**Proto location:** [lora_options.proto (LoRAAdapterInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L37), [lora_options.proto (LoRAAdapterInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L47)

**Why:** The runtime descriptor says nothing about how big an adapter is or what it was trained with, so an app cannot budget memory and cannot explain why scale 1.0 behaves differently across two adapters (effective strength is scale * alpha/rank). Today the only way to find out is to load it and watch RSS.

**Skeptic verdict:** `risky` — Tags 5 and 6 are not gaps, they are fresh graves from the most recent proto commit, and the message carries no `reserved` for them -- so this reuses deleted tags with mismatched wire types: 5 was `string` (length-delimited) and becomes `int32` (varint), 6 was `int32` (varint) and becomes `float` (fixed32). Any older-SDK payload still carrying error_message/error_code garbles or fails to parse rather than being ignored. It also directly contradicts the sibling proposals lora-dead-fields and lora-trim-catalog-entry, whose whole mechanism is adding `reserved` so freed tags are never reused. Move rank/alpha/size_bytes to 9/10/11 and reserve 5,6.

**What changed:** Added three read-only reported fields to LoraAdapterInfo: optional int32 rank = 5, optional float alpha = 6, optional int64 size_bytes = 7, with loaded_at_ms and error renumbered to 8 and 9 so the message is dense and ascending. The comment explains that rank is PEFT's r and alpha is lora_alpha, and that effective strength is scale * (alpha / rank), which is why 1.0 is not portable across adapters.

**Files touched:** `idl/lora_options.proto`

**Status:** `applied`

**Care level:** `blocked`

**What could break:** Nothing reads these fields -- they are new. The break is on the PRODUCER side and on tag reuse. (1) No producer exists: `rg -n '\blora_alpha\b|\balpha\b|\brank\b' sdk/runanywhere-commons/src/features/lora sdk/runanywhere-commons/src/infrastructure/model_management/lora_registry.cpp sdk/runanywhere-commons/src/infrastructure/model_management/lora_import.cpp sdk/runanywhere-commons/include/rac/features/lora` returns ZERO hits -- commons never reads rank or alpha from anywhere, and the load path is a single opaque backend call, rac_lora_service.cpp:647 `ref.ops->load_lora(ref.impl, config.adapte…

**Wire safety:** This is the whole risk. Do NOT put rank at 5 or alpha at 6: both tags were previously occupied in this exact message (error_message string at 5, error_code int32 at 6) and were removed without a reserved block. A payload from an already-shipped SDK that still carries tag 5 as a length-delimited string would be handed to an int32 varint parser and either garble or fail the whole message parse -- a…

**Do first:**
  1. Extend the backend vtable first. load_lora (rac_lora_service.cpp:647) currently returns only a status code. Add an out-parameter or a companion `lora_adapter_info` op that yields rank, alpha and resident bytes, and implement it for at least the llama.cpp backend. Landing the proto fields ahead of this ships three permanently-empty fields, which the proposal itself says is worse than none.
  1. Move the tags: rank = 9, alpha = 10, size_bytes = 11. Add `reserved 5, 6; reserved "error_message", "error_code";` to LoRAAdapterInfo in the same edit. Tag 9 is genuinely unused; 5 and 6 held error_message (string) and error_code (int32) until they were removed in favour of `optional SDKError error = 8`.
  1. State in the comment that alpha is float only because PEFT writes lora_alpha as a number that is sometimes fractional; if the backend reports it as an integer, say so rather than widening.
  1. Land after lora-one-spelling if that is going ahead, or before it -- either order works, but not concurrently, since both edit the LoRAAdapterInfo header block.


### `lora-scale-presence` — Make scale and default_scale `optional float` and delete the "<= 0 means 1.0" coercion

**Proto location:** [lora_options.proto (LoRAAdapterConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L26), [lora_options.proto (LoraAdapterCatalogEntry)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L69)

**Why:** scale has no presence, so its annotated default (1.0) contradicts its wire zero (0.0) and commons papers over the gap by coercing anything <= 0 to 1.0. The result is that llama.cpp's canonical `scale = 0.0` (loaded but contributing nothing) silently becomes full strength, and a negative scale is impossible -- two surprises a newcomer can only discover by experiment.

**Skeptic verdict:** `sound`

**What changed:** LoraAdapterConfig.scale and LoraAdapterCatalogEntry.default_scale are both now `optional float`, giving them real presence so absent is distinguishable from 0.0 and the <= 0 -> 1.0 coercion has no reason to exist. Documented that 1.0 is as-trained, 0.0 is applied-but-contributing-nothing, negatives subtract, and the value is unbounded and signed.

**Files touched:** `idl/lora_options.proto`

**Status:** `applied`


### `lora-state-is-response-only` — Stop using LoRAState as its own request, and delete the comment advertising a filter that does not exist

**Proto location:** [lora_options.proto (LoRAState)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L186), [lora_options.proto (LoRAState)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L190)

**Why:** The comment tells a reader that LoRAState carries "optional base_model_id filtering" when used as a request; nothing filters on it. So the same message is both the question and the answer, and the doc lies about what the question does. It also explains why the SDK has two verbs (list and state) that read the same thing.

**Skeptic verdict:** `sound` — 'Risk: Low' undersells the verb collapse: rac_lora_list_proto and rac_lora_state_proto are two separate exported C ABI symbols reached through JNI/FFI (jni/runanywhere_commons_jni.cpp), so merging them is an ABI break in every binding, not just an SDK-layer mapping change. has_active_adapters also has hand-written readers to sweep (runanywhere-web ProtoAdapterTypes.ts:444, RunAnywhere+LoRA.ts:91, and the Swift LoRAProtoSurfaceTests).

**What changed:** Replaced the LoraState header comment that advertised a non-existent base_model_id filter with 'Response only. The state read takes no arguments; base_model_id is reported, never a filter.', and deleted has_active_adapters. Survivors renumbered dense: loaded_adapters=1, base_model_id=2, error=3.

**Files touched:** `idl/lora_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Two separable pieces with very different blast radii. (a) has_active_adapters (tag 2) has one writer and six readers: written at rac_lora_service.cpp:120 `state->set_has_active_adapters(!snapshot.adapters.empty())`; read/asserted at CLI cmd_lora.cpp:158 `.field("has_active_adapters", state.has_active_adapters())`, web Adapters/ProtoAdapterTypes.ts:444, web Public/Extensions/RunAnywhere+LoRA.ts:91, web tests/types/types.test-d.ts:118, Swift Tests/RunAnywhereTests/LoRAProtoSurfaceTests.swift:101 and :105 (hasActiveAdapters_p), Flutter test/lora_proto_shape_test.dart:104 and :111. The three web …

**Wire safety:** Tag 2 is freed and must be reserved by number and name, as the 'after' does -- this is one of the file's first reserved blocks (`rg -n 'reserved' idl/lora_options.proto` is empty today). Old producers still setting tag 2 (bool/varint) land in unknown fields and are ignored, which is safe because the information is fully recoverable from loaded_adapters being non-empty -- that identity is exactly …

**Do first:**
  1. SPLIT THIS IN TWO. Commit 1 is the honest comment plus `reserved 2; reserved "has_active_adapters";` -- small, and the only sweep is the six readers above. Commit 2 is the verb collapse, which is an exported-symbol removal and belongs on its own.
  1. For commit 1, sweep the readers before deleting: delete the write at rac_lora_service.cpp:120; change cmd_lora.cpp:158 to print `state.loaded_adapters_size() > 0`; fix web ProtoAdapterTypes.ts:444, RunAnywhere+LoRA.ts:91 and tests/types/types.test-d.ts:118; fix Swift LoRAProtoSurfaceTests.swift:101/:105 and Flutter lora_proto_shape_test.dart:104/:111. Note the Swift test uses the `_p` suffixed accessor (hasActiveAdapters_p) because `hasX` collides with protobuf presence naming -- that is a hand-written alias, so grep for the suffix form too.
  1. For commit 2, do NOT delete an exported symbol in the same release that changes its meaning. Keep rac_lora_state_proto as the survivor, make rac_lora_list_proto a thin forwarder to it for one release so already-shipped app binaries keep resolving, and only then remove it from RACommons.exports and sdk/runanywhere-web/wasm/CMakeLists.txt. Remember both copies of rac_lora_service.h.
  1. Preserve the list() projection at the SDK layer, not the ABI layer: the trimmed {id, scale} shape list() returns today can be mapped from the full LoRAState (Kotlin already does exactly this at MappingResults.kt:240).
  1. Sequence before lora-one-spelling so the rename sweep does not have to touch a message that is mid-surgery.


### `lora-trim-catalog-entry` — Trim LoraAdapterCatalogEntry from 18 fields to the 6 that are adapter-specific; the rest live on ModelInfo

**Proto location:** [lora_options.proto (LoraAdapterCatalogEntry)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L53), [lora_options.proto (LoraAdapterCatalogEntry)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L80), [lora_options.proto (LoraAdapterCatalogEntry)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/lora_options.proto#L76)

**Why:** Twelve of the entry's eighteen fields (description, url, filename, size_bytes, author, checksum_sha256, license, metadata, is_downloaded, downloaded_at_unix_ms, is_imported, status_message) are generic artifact facts that ModelInfo already carries, so a newcomer has to learn two spellings of the same record and guess which one is authoritative. Only id, name, compatible_models, default_scale, local_path and tags say anything that is true of a LoRA adapter and not of any other downloadable file.

**Skeptic verdict:** `risky` — Four of the twelve 'generic' fields have live commons consumers the risk note does not mention, and one of them contradicts a field the proposal keeps. lora_registry.cpp:271 reads `entry.description()` and :274 reads `entry.author()` -- those two are exactly what matches_search_query searches, yet the proposal keeps LoraAdapterCatalogQuery.search_query (line 90) intact, so search_query would survive with both of its haystacks deleted. lora_import.cpp:232 matches an imported file to a catalog entry by `entry.filename() == filename`, so deleting `filename` breaks import matching. lora_registry.cpp:154 defines downloaded as `(has_is_downloaded() && is_downloaded()) || !local_path().empty()` -- the local_path fallback already exists, so that part of the claim is fine, but :175/:177 also copy is_imported/status_message forward on merge.

**What changed:** Trimmed LoraAdapterCatalogEntry from 18 fields to the 6 adapter-specific ones, deleting description, url, filename, size_bytes, author, checksum_sha256, license, metadata, is_downloaded, downloaded_at_unix_ms, is_imported and status_message. Survivors are renumbered dense: id=1, name=2, compatible_models=3, default_scale=4 (now optional float), tags=5, local_path=6. local_path being non-empty is now documented as the single definition of 'downloaded'.

**Files touched:** `idl/lora_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Eight of the twelve 'generic' fields have live readers, and one deletion strands a surviving field. description: lora_registry.cpp:271 (the haystack of matches_search_query). author: lora_registry.cpp:274, plus Swift RunAnywhere+LoRADownload.swift:77 `if hasAuthor { model.metadata.author = author }`. filename: lora_import.cpp:232 `if (entry.filename() == filename)` -- this IS the import-to-catalog match, delete it and import silently stops matching. size_bytes: lora_registry.cpp:741-743 (also mirrors into it->second->file_size). checksum_sha256: lora_registry.cpp:745-746, Swift RunAnywhere+Lo…

**Wire safety:** Twelve tags freed (3,4,5,7,8,10,11,13,15,16,17,18) and correctly reserved by number AND name in the 'after' -- keep both halves; the name reservation is what stops a future `string description` from re-entering at a new tag and colliding in JSON. This is the file's first reserved block (`rg -n 'reserved' idl/lora_options.proto` is empty today). Old producers still emitting tags 3/4/5/7/... land i…

**Do first:**
  1. Repoint the import match BEFORE deleting filename. lora_import.cpp:232 matches on `entry.filename() == filename` with a unique-name fallback at :237-238. Either match on basename(local_path) against the ModelInfo artifact's file entry (lora_import.cpp:140 already sets file->set_filename), or keep filename. Deleting it with :232 untouched turns every import into an unmatched import.
  1. Repoint or delete search_query in the SAME change. lora_registry.cpp:271/:274 search description and author; with both gone, LoraAdapterCatalogQuery.search_query (lora_options.proto:90) can only match name. Either narrow its doc comment to 'matches name only', or make matches_search_query read the ModelInfo artifact's description/author, or delete search_query -- but do not leave a documented full-text filter with no text to search.
  1. Rewrite the four-field state collapse in commons first, as one commit: make lora_registry.cpp:153-154 return `!entry.local_path().empty()` unconditionally, delete the clear/merge blocks at :159-162 and :169-177, and simplify :732-740. Then fix the two hand-rolled copies at cmd_lora.cpp:127 and :146 which repeat the same disjunction.
  1. Decide the fate of the public C struct rac_lora_entry_t before touching the proto. rac_proto_adapters.cpp:782-817 is the converter pair; if the struct keeps description/download_url/filename/file_size while the proto drops them, the converter silently drops data on every catalog read. Trim the struct and both converter halves in the same commit, and treat that as a C ABI change for the RN/jniLibs vendored headers too.
  1. Migrate checksum_sha256 and size_bytes onto the ModelInfo artifact BEFORE deleting them: the four SDK readers (Swift RunAnywhere+LoRADownload.swift:45-46/:72-73, Flutter runanywhere_lora.dart:242-243/:283-284, RN RunAnywhere+LoRA.ts:477/:505) each build a download descriptor from the entry, and losing the checksum silently disables integrity verification rather than failing loudly -- that is the worst failure mode in this whole domain.
  1. Sequence: this must land AFTER lora-delete-download-import-bookkeeping (which is what makes is_downloaded/is_imported/status_message/downloaded_at writer-less) and BEFORE lora-one-spelling.


</details>


<details>
<summary><strong>models</strong> (13 changes)</summary>

### `delete-derived-aggregates` — Delete the ~20 count/sum/ratio fields that restate a sibling collection

**Proto location:** [model_types.proto (ModelListResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L470), [model_types.proto (ModelRegistryRefreshResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L448), [model_types.proto (ModelDiscoveryResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L538), [storage_types.proto (StorageInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/storage_types.proto#L57)

**Why:** Almost every result message repeats its own contents as scalars: a list plus four counts of that list, a models array plus its length and its byte sum, a candidates array plus candidate_count, total_bytes plus used_bytes plus used_percent. Every one has to be hand-synced by whoever fills the message, and a reader has to guess whether a disagreement means something.

**Skeptic verdict:** `sound` — One derivation is not actually a derivation. DeviceStorageInfo.used_bytes (3) round-trips a distinct C-ABI struct field: foundation/rac_proto_adapters.cpp:928 `out->set_used_bytes(in->used_space)` and :944 `out->used_space = in.used_bytes()`, and `free_bytes` is fed from the adapter's `available_bytes` (desktop/desktop_adapter.cpp:429), i.e. bytes available *to this app*, not total-minus-used. On Android (StatFs.getAvailableBytes excludes reserved blocks) and iOS (volumeAvailableCapacityForImportantUsage) total_bytes - free_bytes systematically OVERSTATES used_bytes, so 'used = total - free' silently changes the number a storage UI renders. Either keep used_bytes or make the adapter contract say free_bytes is total-minus-used. include_counts also has a live reader (infrastructure/model_management/model_registry_proto.cpp:906 `if (request.include_counts())`), so 'no facade ever read' is a claim about facades only, not about commons.

**What changed:** Deleted pure count/sum/ratio derivations across 7 messages: ModelRegistryRefreshResult, ModelListRequest/Result, ModelDiscoveryResult, StorageAvailability, StorageDeletePlan. Per care plan correction, did NOT delete StorageInfo.total_models_bytes (real adapter-fed value, not derived) or DeviceStorageInfo.used_bytes (distinct adapter reading, not total-minus-free) -- only used_percent and total_models were cut from those two messages.

**Files touched:** `idl/model_types.proto`, `idl/storage_types.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** NOT all of these are derivations with no reader. (1) StorageInfo.total_models_bytes has three live readers plus an event payload: infrastructure/storage/storage_event_publisher.cpp:119 `storage->set_bytes(result.info().total_models_bytes())`, Kotlin public/extensions/Storage/StorageProtoHelpers.kt:104-108 (`if (total_models_bytes > 0L) total_models_bytes else totalModelsSizeBytes`), Kotlin public/api/ModelsNamespace.kt:280 `storageUsedBytes = storage?.total_models_bytes`, Swift Public/Extensions/Storage/StorageProto+Helpers.swift:76 and Public/API/Namespaces/ModelsNamespace.swift:333. Deletin…

**Wire safety:** All cuts are `reserved` on transient result messages except DeviceStorageInfo/StorageInfo, which are also transient — nothing here is persisted to .rac-manifest.binpb, so no reuse hazard as long as the tags are reserved and not recycled. The one true wire trap is name collision with the LoRA catalog messages, which carry identically named fields at their own tags: any sed-style edit across idl/ w…

**Do first:**
  1. Land the pure derivations first, in their own commit: StorageDeletePlan.candidate_count, ModelListResult 4/5/6/7 + ModelListRequest.include_counts, ModelRegistryRefreshResult 3/4/5/6/10/11/12, ModelDiscoveryResult 3/4/7/8. These have producers only — verified by the grep above returning no facade reads.
  1. Before deleting StorageInfo.total_models_bytes (5): make the client-side sum unconditional in Kotlin StorageProtoHelpers.kt:108 and Swift StorageProto+Helpers.swift:76 (both already carry a totalModelsSizeBytes fallback), repoint ModelsNamespace.kt:280 / ModelsNamespace.swift:333 at it, and change storage_event_publisher.cpp:119 to sum info.models(). Only then reserve 5.
  1. Do NOT delete DeviceStorageInfo.used_bytes (3) on the 'total - free' argument until desktop/desktop_adapter.cpp:429 and the Android/iOS adapters are changed to define free_bytes as total-minus-used. Today free_bytes is bytes-available-to-this-app, so the subtraction overstates usage. Either keep tag 3 or fix the adapter contract in the same PR.
  1. Scope every edit to idl/model_types.proto and idl/storage_types.proto by explicit message name. Do not run a repo-wide rename: lora catalog messages carry the same field names.


### `delete-orphan-modelinfo-fields` — Delete the three ModelInfo fields with no comment, no producer and no reader

**Proto location:** [model_types.proto (ModelInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L319), [model_types.proto (ModelInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L320), [model_types.proto (ModelInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L321)

**Why:** usage_count, sync_pending and status_message sit on a record that is persisted verbatim to disk, and not one of them has a comment. usage_count never defines what a use is (a load? a generation? a session?), sync_pending has no producer in the refresh or fetch-assignments contracts, and status_message duplicates what SDKError already carries.

**Skeptic verdict:** `risky` — usage_count has a producer, a reader, and merge-preservation logic. Producer: infrastructure/model_management/model_registry.cpp:600 `model->usage_count++`. Reader: model_registry_proto.cpp:152 `return compare_values(lhs.usage_count(), rhs.usage_count());` -- that is the implementation of MODEL_QUERY_SORT_FIELD_USAGE_COUNT. Round-trip: model_registry_convert.cpp:428-429/465-466 write it, :634 reads it back, :764-765 preserve it across a catalog merge, and model_types.cpp:1238 copies it. sync_pending likewise has convert.cpp:767-768 (merge preserve) and model_registry_manifest.cpp:122 (clear on persist). So 'no producer and no reader' is contradicted for two of the three -- exactly the dead-surface over-reach this review is prone to. The fields may still be worth deleting (the increment feeds only a sort that trim-model-query also deletes), but the case must be made as 'this feature is being removed, here are its 11 call sites', not as 'these are orphans'. status_message on ModelInfo is the only one that looks close to orphan -- its 5 grep hits are a same-named local helper in storage_analyzer.cpp and the LoRA registry's own field, plus convert.cpp:771 merge-preserve.

**What changed:** ModelInfo.usage_count/sync_pending/status_message(35,36,37) reserved by number. NOTE: care plan found usage_count and sync_pending are NOT dead (producers in commons + facades) -- proto-level reserve applied per no-backcompat instruction; the corresponding C++/Kotlin/Swift increment sites are Phase C/D cleanup.

**Files touched:** `idl/model_types.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Two of the three are NOT dead. usage_count: producer infrastructure/model_management/model_registry.cpp:600 `model->usage_count++`; reader model_registry_proto.cpp:152 (the implementation of MODEL_QUERY_SORT_FIELD_USAGE_COUNT); round-trip model_registry_convert.cpp:139, :428-429, :465-466, :634, and merge-preserve :764-765; copy model_types.cpp:1238; C struct field rac_model_types.h:334. AND both facades increment it themselves — Kotlin foundation/bridge/extensions/CppBridgeModelRegistry.kt:329 `usage_count = (current.usage_count ?: 0) + 1` and Swift Foundation/Bridge/Extensions/CppBridge+Mod…

**Wire safety:** ModelInfo is persisted to .rac-manifest.binpb, so 35/36/37 must be `reserved` forever — the after-text gets this right. No tag moves. Old manifests keep parsing; the fields simply land in unknown fields and are dropped on the next persist, which is the intended one-way door.

**Do first:**
  1. Delete the three increment sites first, in one commit, or the field keeps being written while nothing reads it: model_registry.cpp:600, Kotlin CppBridgeModelRegistry.kt:329, Swift CppBridge+ModelRegistry.swift:387.
  1. Remove the usage_count arm from the comparator (model_registry_proto.cpp:152) together with the ModelQuerySortField deletion in trim-model-query — one edit, not three.
  1. Remove status_message from the search predicate (model_registry_proto.cpp:67) in its OWN commit so the narrowed-search behaviour change is reviewable on its own.
  1. Then drop the merge-preserve block at model_registry_convert.cpp:764-771 and the clear at model_registry_manifest.cpp:122, and write `reserved 35, 36, 37;`.
  1. Decide the C-struct fields (rac_model_types.h:334 usage_count, model_types.cpp:1238, model_registry_convert.cpp:139) in the same release — leaving a struct field with no proto home is how the next reviewer concludes it is dead.


### `download-progress-single-phase` — Delete DownloadStage and `stage`; make DownloadState the only phase field

**Proto location:** [download_service.proto (DownloadProgress)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L31), [download_service.proto (DownloadProgress)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L37), [download_service.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L52)

**Why:** DownloadProgress encodes the transfer phase twice, in `stage` (2) and `state` (8), and the two enums overlap on DOWNLOADING/EXTRACTING/COMPLETED. A newcomer has no way to know which one is authoritative, and `error` says 'populated when state == FAILED' while `stage` has no FAILED value at all, so there is no defined moment to read the error.

**Skeptic verdict:** `sound` — Two soft spots, neither fatal. (a) The precedent is loose: Ollama's POST /api/pull streams a `status` string per phase ("pulling manifest", "downloading <digest>", "verifying sha256", "success"), so "Ollama has no phase field at all" misdescribes it -- Ollama has a phase field, it is just untyped. The llama.cpp "router ships one status enum (unloaded|downloading|loading|loaded|sleeping)" claim I could not corroborate and it reads like llama-swap's state machine. The load-bearing claim ("nobody ships two") survives anyway. (b) effort "S" understates it: `stage` has a live producer at sdk/runanywhere-commons/src/infrastructure/download/download_orchestrator.cpp:1042 (`progress->set_stage(stage)`) plus set_stage_progress at :1071 and a C-ABI round-trip at foundation/rac_proto_adapters.cpp:745 (`out->set_stage(in->stage)`), so the rac_download_progress_t struct field goes too. And the proposal's own risk note concedes stage_progress (5) still overlaps overall_progress (16) -- shipping the cut without also resolving that leaves two fractions where there were two phases.

**What changed:** DownloadProgress: reserved stage(2) by number+name; added DOWNLOAD_STATE_VALIDATING=10; state(8) is now the single phase field.

**Files touched:** `idl/download_service.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Producer: sdk/runanywhere-commons/src/infrastructure/download/download_orchestrator.cpp:1026 (stage param), :1042 set_stage, :1071 set_stage_progress. C-ABI round trip: sdk/runanywhere-commons/src/foundation/rac_proto_adapters.cpp:744-745 `if (in->stage) out->set_stage(in->stage)` — the rac_download_progress_t struct field goes with it. Swift: Sources/RunAnywhere/Infrastructure/Download/Models/Output/DownloadProgress.swift:64,77,96 set .stage, :68,81,100,130 set stageProgress, :115/:127 are in the public initializer signature; Public/API/Namespaces/ModelsNamespace.swift:138 `switch progress.s…

**Wire safety:** Tag 2 must be `reserved 2` and never reused (DownloadProgress is streamed, not persisted, but old .so/new SDK pairs coexist during a rollout). DownloadState gains VALIDATING = 10 — verified free, the enum tops out at RESUMING = 9. Deleting `enum DownloadStage` is wire-invisible but a SOURCE break for Swift and Kotlin, which import the generated enum. If stage_progress (5) goes in the same pass, r…

**Do first:**
  1. Add DOWNLOAD_STATE_VALIDATING = 10 as a pure addition and make download_orchestrator.cpp emit it wherever it currently emits DOWNLOAD_STAGE_VALIDATING — ship this alone first; it is non-breaking and gives every facade a state to migrate onto.
  1. Confirm set_state is called on EVERY emission path that currently calls set_stage at download_orchestrator.cpp:1042 (states are already used for liveness at :884-887 and terminal handling at :974-985, but stage and state are set independently today).
  1. Decide stage_progress in this same pass, because Swift's percent comes from it: repoint ModelsNamespace.swift:145 at overall_progress (16) or at bytes_downloaded/total_bytes BEFORE tag 5 changes meaning.
  1. Port Kotlin DownloadStageExtensions.kt:17-34 to DownloadState (keep the same public symbol names displayName/progressRange so app code compiles) and update ModelsNamespace.kt:140 + RunAnywhereDownload.kt:263 in that commit.
  1. Rewrite the four Swift constructors in DownloadProgress.swift (64-132) to set state only; the initializer at :115 is public API, so keep the parameter list source-compatible or bump the SDK minor.
  1. Drop `stage` from rac_download_progress_t and rac_proto_adapters.cpp:744-745 in the same commit as the header change — a header/.so skew here is a silent field drop, not a compile error.
  1. Only then delete enum DownloadStage and write `reserved 2;`.


### `download-start-one-call` — Let a download start in one call by making DownloadStartRequest.plan optional

**Proto location:** [download_service.proto (DownloadStartRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L164), [download_service.proto (DownloadPlanResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L146), [download_service.proto (DownloadStartResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L170)

**Why:** `plan` is a singular 14-field message that the caller has to obtain from plan() and echo back verbatim, so the simplest possible thing -- 'download this model' -- always costs two calls and a round-tripped blob. Nothing in the proto says the plan is skippable, and nothing says what happens if it is stale.

**Skeptic verdict:** `sound` — Only that the risk note buries the actual work: 'the internal auto-plan path' means the orchestrator must synthesize a DownloadPlanResult, which is where the storage/checksum/resume decisions currently live. The proto edit is a one-liner; do not let that set the schedule.

**What changed:** DownloadStartRequest.plan made optional (absent = plan-and-start in one call). Added DownloadStartResult.plan(9) so a one-call caller still gets the byte numbers.

**Files touched:** `idl/download_service.proto`

**Status:** `applied`


### `invert-unsafe-default-booleans` — Rename four booleans so the proto3 zero is the safe behaviour

**Proto location:** [download_service.proto (DownloadPlanRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L132), [download_service.proto (DownloadStartRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L167), [storage_types.proto (StorageDeleteRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/storage_types.proto#L150), [model_types.proto (ModelFileDescriptor)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L361)

**Why:** Every one of these is a plain proto3 bool with no default annotation, so an empty request means: do not verify checksums, do not update the registry after a successful download, do not actually delete the files on a delete call, and treat every file in a multi-file bundle as optional -- the last one directly contradicting its own comment, which claims 'default true'.

**Skeptic verdict:** `risky` — The is_required -> is_optional inversion needs a migration the proposal does not specify, and moving to a new tag is not sufficient. ModelFileDescriptor rides inside the persisted ModelInfo (MultiFileArtifact), and existing manifests encode is_required=3 explicitly -- commons sets it in six places (model_lifecycle_resolve.cpp:416, download_orchestrator.cpp:3068, lora_import.cpp:141, register_model_from_url.cpp:124 and :308, model_registry_convert.cpp:396). Once tag 3 stops being read, an existing record that stored is_required=false (a genuinely optional companion file) parses as is_optional=false, i.e. REQUIRED, and the resolver at model_lifecycle_resolve.cpp:359-369 will fail the load for a missing optional file. Also note the proto's own comment at 364-366 documents is_required as the canonical flag with 'default true, mirrored in Swift' -- inverting it flips that documented default. The change needs an explicit read-tag-3-if-present-else-tag-N backfill. The other three renames are on transient request messages and are as cheap as claimed.

**What changed:** verify_checksums->skip_checksum_verification (DownloadPlanRequest, same tag 8), update_registry_on_completion->skip_registry_update (DownloadStartRequest, same tag 5), delete_files->keep_files_on_disk (StorageDeleteRequest, same tag 2) -- all same-tag inversions, no backcompat needed. is_required->is_optional (ModelFileDescriptor) done on a FRESH tag(12) with 3 reserved, per care plan's non-negotiable point that this message is persisted and an in-place flip would silently invert every manifest on disk.

**Files touched:** `idl/download_service.proto`, `idl/storage_types.proto`, `idl/model_types.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** verify_checksums: producers Swift Public/Extensions/Storage/RunAnywhere+Storage.swift:497, Kotlin public/extensions/Storage/RunAnywhereDownload.kt:84, Web packages/core/src/Public/SDKCore.ts:87 and :1512-1513 (its own download implementation); readers download_orchestrator.cpp:2970 and :3070. update_registry_on_completion: producers core/model_lifecycle_download.cpp:154 (sets true), Kotlin RunAnywhereDownload.kt:114 (true), Swift RunAnywhere+Storage.swift:518 (true), and Web SDKCore.ts:1541 which deliberately sets it FALSE with a `!== false` default read at :1644 — that opt-out must become sk…

**Wire safety:** THE SHARP EDGE: renaming a bool in place keeps the same tag and the same type, so the change is wire-invisible while inverting meaning. An app built against the old schema that sets verify_checksums=true on tag 8 will be read by the new commons as skip_checksum_verification=true — checksums silently OFF. If mixed-version app/.so pairs are possible at all, all four fields need NEW tags with the ol…

**Do first:**
  1. is_required migration (this is the whole risk): for one release WRITE both tags (keep is_required=3, add is_optional=12) and READ `has_is_optional() ? is_optional : !is_required`. Only after a release of dual-write does tag 3 stop being written, and only then does the read fallback go.
  1. Update all six is_required producers in the same dual-write commit: lora_import.cpp:141, model_paths.cpp:653/696, and the sites the skeptic listed (model_lifecycle_resolve.cpp:416, download_orchestrator.cpp:3068, register_model_from_url.cpp:124 and :308, model_registry_convert.cpp:396) — plus the web partition at RunAnywhere+Storage.ts:280-281.
  1. For each of the three transient booleans, rename + flip producer + flip reader in ONE commit per field. Never split a flip across the C-ABI release boundary — an old app + new .so is the silent-wrong-default case.
  1. Handle the web separately and in the same PR: packages/core/src/Public/SDKCore.ts is a second implementation of the download path (:87, :1512-1513, :1541, :1644) and does not go through commons.
  1. Delete the proto comment at model_types.proto:364-366 that documents is_required as 'default true, mirrored in Swift' in the same edit — leaving it next to is_optional is a second lie.


### `load-request-context-length` — Wire context_length through load, echo what was allocated, delete the dead threads knob

**Proto location:** [model_types.proto (ModelLoadRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L558), [model_types.proto (ModelLoadRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L559), [model_types.proto (ModelLoadResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L567)

**Why:** The comment promises these knobs are honored end-to-end, and all three facades throw at preflight instead ('cannot be carried by the native load ABI yet'). So the one load knob every on-device runtime exposes cannot be set, and the proto text is actively false.

**Skeptic verdict:** `risky` — The stated justification for `reserved 7` is false. `threads` is NOT dead: core/model_lifecycle_translation.cpp:429-431 serializes it into the advisory load-options JSON (`if (request.has_threads()) parts.push_back("\"threads\":" ...)`), that string is handed to the load at core/model_lifecycle.cpp:932, foundation/rac_proto_adapters.cpp:367-368 maps n_threads onto the C struct, and core/model_lifecycle.cpp:653-655 explicitly *rejects* the request when threads is set on a non-LLM/VLM category rather than dropping it. `threads` travels by exactly the same mechanism as `context_length`, so the proposal's core asymmetry -- "context_length must be newly wired through the ABI, threads never reached the runtime" -- does not hold; either both are wired or neither is, and the file's own comment ("honored end-to-end") is either true for both or a lie about both. Deleting tag 7 breaks three live commons call sites and silently converts a today-explicit rejection into a silently-ignored knob. Second issue: this proposal claims ModelLoadResult tag 19 and one-accelerator-vocabulary claims tag 19 for `actual_accelerator` in the same batch -- if both land as written that is a same-file duplicate tag that will not compile.

**What changed:** ModelLoadRequest: reserved threads(7) by number+name (dropped the false 'never reached the runtime' claim per care plan correction). Added ModelLoadResult.allocated_context_length(19). Actual C-ABI wiring is Phase C work.

**Files touched:** `idl/model_types.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The three facades currently REFUSE these knobs, and one of them asserts the refusal in a unit test: sdk/runanywhere-kotlin/src/test/kotlin/com/runanywhere/sdk/public/api/LoadOptionsIgnoredKnobsTest.kt:42 asserts `listOf("contextLength")` and :64 asserts `listOf("contextLength", "threads", "accelerator")` — wiring context_length without editing this test turns the Kotlin build red. Kotlin public/api/ModelsNamespace.kt:34-35 builds that unsupported list, :24 and :178 document it; Options.kt:316 holds the value. Swift Public/API/Namespaces/ModelsNamespace.swift:471-472 append to `unsupported` an…

**Wire safety:** context_length keeps tag 6 and type int32 — no wire change. allocated_context_length = 19 on ModelLoadResult is additive (highest existing tag is 18). `reserved 7` for threads is the only wire-affecting edit; ModelLoadRequest is transient so no persisted record carries tag 7, but a shipped app built against the old .pb will still SEND tag 7 and it will land in unknown fields — that is silent, not…

**Do first:**
  1. Carry context_length across the C load ABI first (native change), and have the runtime report back what it actually allocated — the proto edit without this leaves the comment false in the other direction.
  1. Add ModelLoadResult.allocated_context_length = 19 and populate it BEFORE removing any facade guard, so the facades have something to read when they stop throwing.
  1. Enforce 0/unset = take-it-from-the-model inside the runtime adapter. Do not reuse the 2048 default that model_info_make_proto.cpp:454 stamps on ModelInfo — that is a catalog default and must not leak into the load path.
  1. In ONE commit: delete the Swift throw (ModelsNamespace.swift:471-479), the Swift limitation entries (RunAnywhere.swift:628-629), the Kotlin list entries (ModelsNamespace.kt:34-35) AND LoadOptionsIgnoredKnobsTest.kt:41-64. The test encodes the old contract literally.
  1. Treat `threads` as a separate decision with its own commit and its own justification (see correctionNeeded) — model_lifecycle.cpp:653-655 currently rejects requests that set it, so removing the tag also removes a validation error apps may be handling.


### `model-delete-result-trim` — Trim ModelDeleteResult to what a caller can read, and say delete always unloads first

**Proto location:** [model_types.proto (ModelDeleteResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L625), [storage_types.proto (StorageDeleteRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/storage_types.proto#L148)

**Why:** ModelDeleteResult has no matching request anywhere in the IDL, and delete() returns void in all three SDKs, so five of its seven fields can never be observed. Worse, nothing states whether deleting a loaded model unloads it or fails, and nothing says a built-in model cannot be deleted.

**Skeptic verdict:** `sound`

**What changed:** ModelDeleteResult cut to model_id/deleted_bytes/error; reserved files_deleted/registry_updated/was_loaded/warnings. Added the delete-always-unloads-first + built-in-never-deletable rules as a comment.

**Files touched:** `idl/model_types.proto`

**Status:** `applied`


### `one-artifact-shape` — Keep only the artifact oneof: delete artifact_type and the duplicate manifests

**Proto location:** [model_types.proto (ModelInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L297), [model_types.proto (ModelInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L300), [model_types.proto (SingleFileArtifact)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L336), [model_types.proto (ArchiveArtifact)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L346)

**Why:** Bundle shape is stated twice -- structurally in the `artifact` oneof and coarsely in artifact_type (25), whose own comment admits it is 'complementary' -- and the expected-file manifest hangs off three places at once (ModelInfo.expected_files, SingleFileArtifact.expected_files, ArchiveArtifact.expected_files) with required/optional_patterns duplicated on top. A newcomer cannot tell which one the downloader reads.

**Skeptic verdict:** `sound` — Scale check only: grep --exclude-dir=generated 'artifact_type' hits 9 commons files and 'expected_files' hits 16, so this is the largest mechanical diff in the batch despite the 'medium' label -- and the catalog audit it asks for is a prerequisite, not a follow-up, since an entry that declared only artifact_type stops declaring any shape the moment tag 25 stops being read.

**What changed:** ModelInfo: deleted custom_strategy_id/artifact_type/expected_files oneof-adjacent fields (reserved 23,25,26). SingleFileArtifact: reserved required_patterns/optional_patterns(1,2), kept expected_files(3). ArchiveArtifact: reserved required_patterns/optional_patterns(3,4), expected_files stays at 5 (unchanged, already non-colliding).

**Files touched:** `idl/model_types.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The resolver is the single consumer that reads ALL of the duplicated homes, and it is the file that must change first: core/model_lifecycle_resolve.cpp:304-315 `populate_expected_files` tries proto.expected_files, then single_file().expected_files, then archive().expected_files, then falls back to single_file().required_patterns at :312+; :203-204 and :227-229 iterate the manifest; :241-291 marshals it into rac_expected_model_files_t. artifact_type has real readers, not just producers: model_registry_convert.cpp:485-509 SETS it from the artifact branch, :580-581 READS it back to rebuild the C…

**Wire safety:** ModelInfo is persisted, so 23/25/26 must be `reserved` and never reused; SingleFileArtifact 1/2 and ArchiveArtifact 3/4 are inside that persisted record too — same rule. ArchiveArtifact.expected_files takes a NEW tag 5 (correct: 3/4 are burned). Keep the ModelArtifactType enum itself — it is still used by RegisterModelFromUrlRequest and by rac_model_infer_artifact_type (include/rac/infrastructure…

**Do first:**
  1. Audit the catalog/assignment JSON FIRST — it is a prerequisite, not a follow-up. model_assignment.cpp:1137 and the surrounding builder construct ModelInfo from JSON; any entry that declared only artifact_type (no oneof) stops declaring a shape the moment tag 25 stops being read, and model_assignment.cpp:717-721 currently papers over that by defaulting to ARCHIVE.
  1. Repoint the web off artifact_type onto the existing oneof helpers: FrameworkOPFSPaths.ts:82-83 -> artifactCaseType(model.artifact); ModelTypes+Artifacts.ts:562-563, 572-573, 581-582 -> the :457/:463 oneof forms. Ship this before the proto edit; it is behaviour-neutral while both exist.
  1. Collapse the resolver in one commit: model_lifecycle_resolve.cpp:304-315 keeps only the variant-owned manifest branch, and the required_patterns fallback at :312+ goes with the SingleFileArtifact 1/2 and ArchiveArtifact 3/4 removal.
  1. Rebuild the C-struct kind from the oneof instead of artifact_type at model_registry_convert.cpp:580-581, and drop the merge-preserve at :740-741.
  1. Keep custom_strategy_id's removal separate if any catalog entry sets it — the grep above found no C++ or facade reader, but that is a catalog-data question, not a code question.


### `one-timestamp-one-rate-no-sentinels` — One last-used timestamp, one rate name, and no -1 sentinel for unknown

**Proto location:** [storage_types.proto (ModelStorageMetrics)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/storage_types.proto#L54), [storage_types.proto (StorageDeleteCandidate)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/storage_types.proto#L124), [download_service.proto (DownloadProgress)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L35), [download_service.proto (DownloadProgress)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L36)

**Why:** Last-use time exists three times under two suffix conventions (last_used_at_unix_ms on ModelInfo, last_used_ms twice in storage_types) with nothing saying which is authoritative. In the same domain, `overall_speed_bps` does not say bits or bytes, and eta_seconds means 'unknown' at -1 while its proto3 default of 0 reads as 'finishing right now'.

**Skeptic verdict:** `not-simpler` — Three unlike changes bundled as one. Killing the eta_seconds -1 sentinel in favour of `optional` is a real fix on a transient message -- take it. Renaming overall_speed_bps to a 'bare noun' is taste, and the precedent offered for it ('Ollama total/completed') is about byte counts, not rates; Ollama has no rate field, so it cannot be evidence for how to name one. Deleting last_used_ms from ModelStorageMetrics and StorageDeleteCandidate is actively worse for the one consumer that exists: StorageDeletePlanRequest.oldest_first (storage_types.proto:100) is an LRU eviction mode, so the delete-plan screen must render last-used per candidate, and after the cut it has to join every candidate back to ModelInfo.last_used_at_unix_ms to do so. Standardizing the *name* to last_used_at_unix_ms on all three is the simplification; deleting two of them and calling the resulting join 'a real (small) refactor' trades one field for N lookups.

**What changed:** ModelStorageMetrics.last_used_ms(3) and StorageDeleteCandidate.last_used_ms(3) both reserved -- ModelInfo.last_used_at_unix_ms(34, untouched) is the one home. DownloadProgress.overall_speed_bps renamed to bytes_per_second (same tag 6, per care plan's correction dropping the fabricated Ollama precedent -- justified on ambiguity alone). eta_seconds made optional (same tag 7), -1 sentinel comment removed.

**Files touched:** `idl/storage_types.proto`, `idl/download_service.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** This is three unrelated changes; treat them as three commits. (a) eta sentinel: produced at download_orchestrator.cpp:1087-1090 and :1094 (`set_eta_seconds(-1)`), consumed at Swift Infrastructure/Download/Models/Output/DownloadProgress.swift:51 (`etaSeconds >= 0 ? TimeInterval(etaSeconds) : nil`) and PRODUCED by the Swift constructors at :69, :82, :101, :132 (`?? -1`). Making it optional without changing those four Swift sites leaves -1 on the wire while has_eta_seconds becomes true — 'unknown' renders as a negative ETA. (b) rate: read at DownloadProgress.swift:46 (`overallSpeedBps > 0 ? ... …

**Wire safety:** eta_seconds keeps tag 7 and type int64; adding `optional` changes presence tracking only (transient message, safe). Renaming overall_speed_bps in place keeps tag 6 as a float — wire-invisible, source break for Swift. ModelStorageMetrics.last_used_ms and StorageDeleteCandidate.last_used_ms are `reserved 3` on transient messages; ModelInfo.last_used_at_unix_ms (34) is untouched and stays the persis…

**Do first:**
  1. Split the proposal into three commits; do not land them as one 'consistency' change.
  1. eta first: change download_orchestrator.cpp:1087-1094 to CLEAR the field instead of writing -1, and change the four Swift sites (DownloadProgress.swift:51 read, :69/:82/:101/:132 writes) in the same commit. Until both sides land, -1 and unset both mean unknown and the reader must accept either.
  1. rate second, and only on naming grounds (see correctionNeeded): rename tag 6 and update DownloadProgress.swift:46 and download_orchestrator.cpp:1085/:1093.
  1. last_used_ms last, and consider the skeptic's alternative first: renaming all three to last_used_at_unix_ms is the consistency win, while deleting two of them forces a per-candidate join in whatever renders the delete plan. If you do delete, do it only after confirming no example app renders it (my grep covered the SDKs, not examples/).


### `resume-unconditional` — Make resume automatic: delete the resume request/result pair, 3 flags and 4 tokens

**Proto location:** [download_service.proto (DownloadResumeRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L196), [download_service.proto (DownloadResumeResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L204), [download_service.proto (DownloadPlanRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L127), [download_service.proto (DownloadStartRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L165)

**Why:** Resuming a partial download is modelled as a whole separate opt-in operation: two messages, three flags (resume_existing, resume, validate_partial_bytes) and a resume_token echoed through four different results. Every SDK in the industry made resumption unconditional, so a newcomer meets nine fields for behaviour that should have none.

**Skeptic verdict:** `risky` — The blast radius is bigger than 'the C++ transfer must actually resume'. These two messages back an exported C entry point and a published JNI binding: infrastructure/download/download_orchestrator.cpp:3582 `extern "C" rac_result_t rac_download_resume_proto(...)` (with a no-protobuf stub at :3800) and jni/runanywhere_commons_jni.cpp:4120 dispatches to it. Deleting the messages therefore deletes a stable C ABI symbol and the Kotlin-side resumeDownload() it feeds -- a source-and-binary break in the app SDK, not just a schema trim -- and the proposal never names it. Any Android app that calls resumeDownload today gets a compile break, and an app shipping an older .so against a newer header gets a link error. Ship it as: keep the symbol as a deprecated alias that forwards to start, delete the messages one release later.

**What changed:** Deleted DownloadResumeRequest/DownloadResumeResult messages. Reserved resume_existing/resume/resume_token tags across DownloadPlanRequest(3), DownloadStartRequest(3,4), DownloadPlanResult(11), DownloadStartResult(6), DownloadCancelResult(8), DownloadProgress(20). Removed the now-dead resume_result oneof arm from sdk_events.proto's merged ModelEvent (introduced earlier this session by the events-shape merge).

**Files touched:** `idl/download_service.proto`, `idl/sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** This is a published ABI, not just a schema: declaration at sdk/runanywhere-commons/include/rac/infrastructure/download/rac_download_orchestrator.h:96, definition at src/infrastructure/download/download_orchestrator.cpp:3582 with a no-protobuf stub at :3800, JNI export at src/jni/runanywhere_commons_jni.cpp:4118-4121, Kotlin declaration at sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/native/bridge/RunAnywhereBridge.kt:1158 `external fun racDownloadResumeProto`, and a LIVE Kotlin caller at sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppB…

**Wire safety:** Message deletion is not a wire change, but it removes an exported C symbol and a JNI entry point — a source AND binary break. Reserve the echoed token tags rather than reusing them: DownloadPlanRequest 3, DownloadStartRequest 3+4, DownloadPlanResult 11, DownloadStartResult 6, DownloadCancelResult 8, DownloadProgress 20. An app shipping an older .so against a newer header gets a link error if the …

**Do first:**
  1. NOTE the grep gap and re-run it: my first sweep passed sdk/runanywhere-web/src, which does not exist (the web sources live under sdk/runanywhere-web/packages/{core,onnx,llamacpp}/src) — a silent empty result. The third command above is the corrected sweep and it came back clean for web.
  1. Make the behaviour true before the schema says it: at download_orchestrator.cpp:3410 stop gating resume_from on request.resume(), and at :2977/:3077/:3107 stop gating the partial-file seed on request.resume_existing(); make an invalid/stale partial restart silently instead of surfacing (the validate_resume_offset path at :3646-3656).
  1. Make start coalesce onto an in-flight transfer for the same model_id — find_task at :853-863 already dedupes by task_id -> resume_token -> model_id, so this is a policy change at the start entry, not new machinery.
  1. Repoint Kotlin CppBridgeDownload.kt:80 at the start entry point, and keep rac_download_resume_proto as a deprecated forwarding stub (parse DownloadResumeRequest -> call start) for one full release. Do not delete the symbol, the JNI export, and the message in the same release.
  1. Only after the token echoes stop being written (:1048, :3218, :3284, :3423, :3436, :3460, :3512, :3522, :3651, :3662, :3692) reserve the six proto tags; keep make_resume_token/:440 as a C++-internal concept.
  1. Delete DownloadResumeRequest/DownloadResumeResult and the exported symbol one release after the alias ships.


### `single-downloaded-state` — Delete ModelInfo.is_downloaded; registry_status is the one state field

**Proto location:** [model_types.proto (ModelInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L315), [model_types.proto (ModelInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L316), [model_types.proto (ModelInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L259)

**Why:** Downloaded-ness is encoded three ways on the same record -- a non-empty local_path, registry_status, and is_downloaded -- and the three SDKs each read a different combination (Kotlin the path, Swift the bool with a path fallback, Web the OR of both). Nothing in the proto says which wins.

**Skeptic verdict:** `sound` — Nothing fabricated, and the manifest-backfill risk is correctly self-identified. Just size it honestly: 15 non-generated commons files touch is_downloaded (model_registry.cpp, model_registry_convert.cpp, model_registry_manifest.cpp, model_info_make_proto.cpp, model_assignment.cpp, register_model_from_url.cpp, lora_*), and model_registry_convert.cpp:758-765 shows the merge layer preserves these bools across catalog refreshes -- the backfill has to live there too, not only in the manifest loader, or a refresh will wipe the state it just backfilled.

**What changed:** ModelInfo.is_downloaded(32) reserved by number+name; registry_status(31) is the one state field, with local_path(7) clarified as location-not-state.

**Files touched:** `idl/model_types.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The precedence rule already exists in C++ and is the backfill site: infrastructure/model_management/model_registry.cpp:103-114 `model_is_downloaded_from_fields` reads local_path, then is_downloaded, then registry_status, and :116-123 `effective_registry_status` derives the status when unset. Persist path: model_registry_manifest.cpp:118 `model->set_is_downloaded(downloaded)` and :245 sanitize_for_manifest. Merge path (the one the skeptic flagged): model_registry_convert.cpp:755-756 preserves is_downloaded across a catalog refresh and :752-753 preserves registry_status — backfilling only in th…

**Wire safety:** ModelInfo is persisted verbatim to .rac-manifest.binpb (the file's own header comment says field numbers are permanent), so tag 32 must be `reserved 32` and can never be reused. No other tag moves. The hazard is not the wire, it is the READ: once tag 32 stops being read, every manifest already on a device loses its downloaded-ness unless registry_status was backfilled.

**Do first:**
  1. Put the backfill in model_registry.cpp:116-123 (effective_registry_status) AND in the merge at model_registry_convert.cpp:752-756 — the skeptic is right that a catalog refresh would otherwise wipe what the loader just backfilled.
  1. For at least one release, keep writing registry_status alongside is_downloaded at model_registry_manifest.cpp:118 so every device upgrades its own manifest on the next persist.
  1. Flip the readers before the field goes: Swift ModelsNamespace.swift:296/:409 and ModelTypes+Artifacts.swift:335/390; Kotlin ModelTypesArtifacts.kt:270 and the write at :309; Web SDKCore.ts:1760/1768, models.ts:63/216, Prerequisites.ts:52, StorageAdapter.ts:965, ModelTypes+Artifacts.ts:638 — plus their tests.
  1. State the local_path rule in the proto comment as the after-text does, because Kotlin :270 and Web models.ts:216 currently OR the path in; that behaviour change (an entry whose files were deleted but whose path survives) is the real user-visible delta.
  1. Only then `reserved 32;`.


### `storage-headroom-in-bytes` — Delete safety_margin; express headroom in bytes like the neighbouring message does

**Proto location:** [storage_types.proto (StorageAvailabilityRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/storage_types.proto#L93), [download_service.proto (DownloadPlanRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/download_service.proto#L133)

**Why:** safety_margin is an unbounded double multiplier with no default, so an unset request arrives as 0.0 -- and 0.0 times required_bytes is a requirement of zero bytes, i.e. the check silently passes. The message next door already expresses the identical idea correctly, in bytes, as required_free_bytes_after_download.

**Skeptic verdict:** `sound`

**What changed:** StorageAvailabilityRequest.safety_margin(3) reserved; added required_free_bytes_after_download(7) on a fresh tag, matching DownloadPlanRequest's field of the same name.

**Files touched:** `idl/storage_types.proto`

**Status:** `applied`


### `trim-model-query` — Trim ModelQuery to the filters the SDKs expose and delete server-side sorting

**Proto location:** [model_types.proto (ModelQuery)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L405), [model_types.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L183), [model_types.proto (ModelListRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L462)

**Why:** ModelQuery is an 11-field query language over a local catalog of a few dozen entries, including a sort field and a direction. Sorting a list of 30 records is the client's job in every one of the four facades, and source/sort_field/descending are exposed by none of them.

**Skeptic verdict:** `sound` — Server-side sort is not free to remove -- model_registry_proto.cpp:152 and the surrounding comparator are its implementation, and available_only at :173 is the other filter being cut. Both are commons code with real callers upstream in the facades; sequence this after (not with) the availability and usage_count decisions so the comparator is deleted once rather than edited three times.

**What changed:** ModelQuery cut to framework/category/format/downloaded_only/max_size_bytes/search_query/registry_status; reserved available_only/source/sort_field/descending(5,8,9,10). Deleted enum ModelQuerySortField entirely.

**Files touched:** `idl/model_types.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** The server-side sort IS implemented and must be deleted with the enum, in one commit: infrastructure/model_management/model_registry_proto.cpp:138-140 compare_models_by_sort_field, :152 the usage_count comparator arm, :159-161 query_has_supported_sort_field, :213-226 the std::sort application (including `descending`), and the `using runanywhere::v1::ModelQuerySortField;` at model_registry_internal.h:109. available_only is read at model_registry_proto.cpp:200. Facades: the Swift source-of-truth builder sets NONE of the four — Public/API/Inputs.swift:568-575 `ModelFilter.toProto()` sets only ca…

**Wire safety:** ModelQuery is transient — `reserved 5, 8, 9, 10` with no reuse is enough. Deleting enum ModelQuerySortField is wire-invisible but a source break for anything importing it (only commons does: model_registry_internal.h:109). Changing search_query (7) from bare string to `optional string` is presence-only and safe on a transient message.

**Do first:**
  1. Land delete-orphan-modelinfo-fields first, or at least its usage_count decision: model_registry_proto.cpp:152 sorts on usage_count, so the comparator would otherwise be edited two or three separate times.
  1. Find the Kotlin ModelFilter -> ModelQuery mapper (rg -n 'toProto' sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/) and confirm it does not set available_only/source before reserving tags 5 and 8.
  1. Delete the comparator (model_registry_proto.cpp:138-161, :213-226) and the `using` at model_registry_internal.h:109 in the SAME commit as the enum, so nothing references a deleted type.
  1. Decide tag 5 explicitly: leave it reserved, or hand it to the availability-verdict work — do not leave available_only alive with its filter (model_registry_proto.cpp:200) deleted.


</details>


<details>
<summary><strong>platform</strong> (9 changes)</summary>

### `platform-acceleration-preference-device-classes` — Cut AccelerationPreference to device classes: reserve WEBGPU, METAL and VULKAN

**Proto location:** [hardware_profile.proto (AccelerationPreference)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hardware_profile.proto#L40), [model_types.proto (ModelCompatibilityRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L661), [model_types.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L303)

**Why:** METAL, VULKAN and WEBGPU are all GPU. A consumer asking 'is this a GPU path' must enumerate four values instead of one, and will silently mishandle the next spelling (DirectML, OpenCL). AUTO and UNSPECIFIED are wire-distinct but behave identically, so producers pick arbitrarily and every SDK hand-writes an isGpu() helper.

**Skeptic verdict:** `risky` — 'Nothing reads this field today' is true only of ModelCompatibilityRequest.accelerator_preference; ModelCatalogEntry.acceleration_preference (tag 27) is actively read and preserved by model_registry_convert.cpp:743-744, and the file's OWN comment (hardware_profile.proto:36-37) documents Swift emitting Metal and Kotlin emitting Vulkan. So any persisted catalog entry holding 5/6/7 silently degrades to UNSPECIFIED on the next merge rather than to GPU - the exact silent-mishandling the proposal says it prevents. Needs a value-migration step (5|6|7 -> 3) in model_registry_convert.cpp in the same change. Minor: the cited coordinate is off - 'Reserved for future use' is model_types.proto:659-660, the field is 661, not 658. Also keeping AUTO as a 'DEPRECATED alias' contradicts the stated reason for cutting it and leaves the two-values-one-behaviour wart in place.

**What changed:** Cut AccelerationPreference to device classes: removed ACCELERATION_PREFERENCE_WEBGPU (5), ACCELERATION_PREFERENCE_METAL (6) and ACCELERATION_PREFERENCE_VULKAN (7) outright (no `reserved 5, 6, 7;` per the no-backwards-compat rule; values 0-4 keep their numbers). Kept ACCELERATION_PREFERENCE_AUTO = 1 documented as a deprecated alias of UNSPECIFIED, exactly as the approved `after` text specifies. Replaced the stale header comment: dropped the unbacked 'Sources pre-IDL / Web enums.ts:165 (Auto / WebGPU)' claim named in correctionNeeded and did not recycle it, keeping only the true statement that the enum lives here to avoid a cyclic import with model_types.proto.

**Files touched:** `hardware_profile.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** ONE live C++ read: sdk/runanywhere-commons/src/infrastructure/model_management/model_registry_convert.cpp:743-744 `if (!incoming->has_acceleration_preference() && existing.has_acceleration_preference()) { incoming->set_acceleration_preference(existing.acceleration_preference()); }` - a pure preserve-merge on ModelCatalogEntry.acceleration_preference (model_types.proto:303, tag 27). It never switches on the value, so it will happily carry a persisted 5/6/7 forward forever unless a migration is added here. PUBLIC WEB API: sdk/runanywhere-web/packages/core/src/types/index.ts:292 `export { Accele…

**Wire safety:** Tags 5, 6, 7 become `reserved` - correct and required, since dropping the names without reserving would let a future value silently reuse a number that persisted catalog rows still hold. Enum values are NOT renumbered, so 0-4 stay wire-identical. The real hazard is decode-side, not encode-side: proto3 open enums mean a stored 5/6/7 now surfaces as an UNRECOGNIZED/unknown value, and model_registry…

**Do first:**
  1. Land platform-delete-hardware-profile-trio first so AcceleratorInfo.type (hardware_profile.proto:53) is gone before you narrow the enum.
  1. Add the value migration in model_registry_convert.cpp next to the existing preserve-merge at :743-744: map 5|6|7 -> ACCELERATION_PREFERENCE_GPU (3) on read, BEFORE the has_/set_ copy, so a persisted catalog row degrades to GPU and not to UNSPECIFIED. This is the whole difference between 'consolidation' and 'silent data loss'.
  1. Ask the backend owner whether any stored ModelCatalogEntry row currently holds 5, 6 or 7. If yes, the migration above is mandatory, not optional.
  1. Decide AUTO honestly. Keeping it as 'DEPRECATED: alias of UNSPECIFIED' preserves the exact two-values-one-behaviour wart the proposal cites as its reason. Either write the deprecation with a removal date and a `[deprecated = true]` option, or drop the AUTO half of the proposal.
  1. Announce the TS enum member removal to web consumers before publishing @runanywhere/core, because types/index.ts:292 re-exports it as public API.


### `platform-closed-enums` — Make platform, form_factor and battery_state enums - the documented string sets are already violated

**Proto location:** [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L32), [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L34), [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L35), [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L44)

**Why:** All three are free-form strings whose comments list a set production does not honour: Swift emits form_factor 'laptop'/'tv'/'watch'/'headset', Web hardcodes 'desktop' even in a phone browser. A newcomer cannot tell what values to switch on, and no compiler will tell them either - an enum answers the question in the type.

**Skeptic verdict:** `risky` — The premise 'never protobuf-encoded' is right and yet the change still breaks the live path, because that path is string-keyed JSON carrying the STRING VALUE. CppBridgeDevice.kt:333 emits `"platform":"${info.platform}"`; make platform an enum and Kotlin emits "PLATFORM_ANDROID" (or an int), while jni:2622 str_field("platform") and its `? "android"` fallback, plus telemetry_json.cpp:517 into backend schemas/device.py, all expect "android". Same for form_factor (jni:2624, telemetry_json.cpp:523 add_string_or_null) and battery_state. Worse, the 'after' drops `optional` from battery_state: the C ABI documents `const char* battery_state; // NULL if unavailable` (rac_telemetry_types.h:276) and telemetry_json.cpp:540 uses add_string_or_null, so a non-optional enum destroys the null encoding - and that directly contradicts sibling proposal platform-unknown-is-absent, which argues absence is the only legal 'unknown'. Keep battery_state optional and land the JSON contract + C ABI + backend enum mapping in the same change.

**What changed:** Added three closed enums to device_info.proto - Platform (UNSPECIFIED/IOS/ANDROID/MACOS/WEB/LINUX/WINDOWS/TVOS/WATCHOS/VISIONOS), FormFactor (UNSPECIFIED/PHONE/TABLET/DESKTOP/LAPTOP/TV/WATCH/HEADSET) and BatteryState (UNSPECIFIED/CHARGING/UNPLUGGED/FULL) - and retyped DeviceInfo.platform to Platform, DeviceInfo.form_factor to FormFactor and DeviceInfo.battery_state to BatteryState. Per correctionNeeded I KEPT `optional` on battery_state (its C ABI member is documented NULL-if-unavailable) and left `architecture` a string with the new comment explaining the OS owns the ABI spelling.

**Files touched:** `device_info.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** THE ANDROID REGISTRATION PATH, end to end, all string-valued: sdk/runanywhere-kotlin/.../CppBridgeDevice.kt:259 formFactor, :268 batteryState, :282 form_factor=, :291 battery_state=, :335 `append("\"form_factor\":\"${escapeJson(info.form_factor)}\",")`, :344-347 emits battery_state as a quoted string or literal null. Parsed back by sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp:2622 str_field("platform"), :2624 str_field("form_factor"), :2628 str_field("battery_state"), with the empty-string fallbacks at :2664 (`? "android"`), :2669-2671 (form_factor), :2681-2683 (battery_state).…

**Wire safety:** Changing `string` -> enum on the SAME tag (3, 5, 14) is a genuine wire-type change: string is wiretype 2, enum is varint wiretype 0. Any peer that still encodes the old proto produces bytes the new parser rejects or skips. The proposal's escape hatch is 'DeviceInfo is never protobuf-encoded' - which I confirmed for commons - but that does not save the change, because the actual transport is strin…

**Do first:**
  1. HARD PREREQUISITE that does not exist yet: a single shared enum<->string mapping used by all three producers and the C ABI. Until that exists this change cannot be made safely, which is why it is blocked and not merely sequenced.
  1. Decide the C ABI shape first - it is the real contract, not the proto. Either (a) keep `const char*` in rac_telemetry_types.h:267/276 and treat the enum as SDK-surface-only, mapping to the existing lowercase strings at every boundary; or (b) change the C members to typed enums, which is an ABI break for the vendored React Native copies too (sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include/rac/infrastructure/telemetry/rac_telemetry_types.h).
  1. If (a): the proto enum must carry the exact legacy spelling in a comment per value, and the Kotlin serializer at CppBridgeDevice.kt:335/345 must emit the LOWERCASE LEGACY STRING, never the enum name. Write that rule into the proto comment or the next person will emit PLATFORM_ANDROID.
  1. Keep `optional` on battery_state. rac_telemetry_types.h:276 documents NULL-if-unavailable and telemetry_json.cpp:540 uses add_string_or_null; a non-optional enum cannot express that, and it directly contradicts the sibling proposal platform-unknown-is-absent.
  1. Update the backend DeviceInfo schema (schemas/device.py) to accept the new value set BEFORE any SDK emits it - telemetry_json.cpp:500-503 records a prior 422 from exactly this kind of shape drift.
  1. Do platform, form_factor and battery_state as THREE separate commits, not one. They have different nullability contracts and different producers.


### `platform-debrand-npu-fields` — De-brand the NPU fields: has_neural_engine -> has_npu, qhexrt_supported -> supported

**Proto location:** [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L39), [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L40), [hardware_profile.proto (NpuCapability)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hardware_profile.proto#L93), [hardware_profile.proto (NpuCapability)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hardware_profile.proto#L85)

**Why:** `has_neural_engine == true` on a Snapdragon reads as a bug to anyone who has not read the comment - and Android populates it with a substring match over the SoC name, so one Apple brand name is doing duty for four vendors. `qhexrt_supported` welds an internal engine name into the public API of eight SDKs; the message is already called NpuCapability, so the qualifier says nothing.

**Skeptic verdict:** `risky` — 'Source-breaking, wire-compatible' is wrong for this codebase, because the real wire for DeviceInfo is hand-written snake_case JSON keyed by the proto field name. Rename has_neural_engine -> has_npu in the proto, regenerate, and Kotlin's serializeDeviceInfoJson emits "has_npu" while runanywhere_commons_jni.cpp:2641 still asks for "has_neural_engine" and silently gets false (bool_field defaults to false, jni:2613-2616) - every Android device then registers with no NPU and NPU routing is quietly off. Same for neural_engine_cores (jni:2635, i32_field -> 0). The rename must land together with the JNI parser, rac_device_registration_info_t (rac_telemetry_types.h:272-273), telemetry_json.cpp:532-533 and the backend device schema. The qhexrt_supported -> supported half and the NPUChip npu = 6 addition (no tag collision, NpuCapability uses 1-5) are clean.

**What changed:** Renamed DeviceInfo.has_neural_engine -> has_npu and DeviceInfo.neural_engine_cores -> npu_cores, and NpuCapability.qhexrt_supported -> supported with an engine-agnostic comment. Added `NPUChip npu` to NpuCapability, re-homed from the deleted HardwareProfile.npu_chip; `import "storage_types.proto"` was kept for it. It carries tag 5 (not the proposal's 6) because platform-delete-derivable-fields frees tag 5 by deleting arch_name and the ground rule requires dense ascending numbering with no reserved holes. I did NOT carry the '(commons-classified)' claim from the old npu_chip comment into the new one, per correctionNeeded.

**Files touched:** `device_info.proto`, `hardware_profile.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** qhexrt_supported IS READ, in five places outside generated code - the skeptic's 'zero hits' was a too-narrow grep (it excluded react-native, flutter and examples/). LIVE ROUTING GATE: examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/data/BackendAvailability.kt:76 `QHexRT.probeNpu().qhexrt_supported` feeding :85 `it[InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT] = qhexrtSupported` - rename the field and this stops compiling; miss it and NPU backend availability is decided by a stale accessor. CATALOG GATE: examples/react-native/RunAnywhereAI/src/services/ModelCata…

**Wire safety:** No wire change from the renames: has_neural_engine (10), neural_engine_cores (11) and qhexrt_supported (4) keep their tags and their types. Adding `NPUChip npu = 6` to NpuCapability is additive and tag 6 is free - confirmed, NpuCapability occupies exactly 1-5 (soc_model=1, soc_id=2, hexagon_arch=3, qhexrt_supported=4, arch_name=5 per hardware_profile.proto:87-96). The addition requires `import "s…

**Do first:**
  1. Land platform-delete-hardware-profile-trio first (or in the same commit) so NPUChip has somewhere to go, and make sure that commit KEEPS `import "storage_types.proto"` at hardware_profile.proto:4.
  1. Rename has_neural_engine / neural_engine_cores in ONE atomic commit that touches all six layers together: idl/device_info.proto:39-40, rac_telemetry_types.h:272-273, rac_api_types.h:96, telemetry_json.cpp:532-533 (the JSON KEY strings), runanywhere_commons_jni.cpp:2635 and :2641 (the JSON key strings), CppBridgeDevice.kt:287-288 and :340-341, CppBridge+Device.swift:129-130, and the vendored React Native headers/bridges. If the JSON key strings and the parser keys diverge for even one commit, every Android device registers has_npu=false and NPU routing turns off silently with no error.
  1. Update the backend device schema to accept the new JSON keys BEFORE the SDKs emit them, or dual-write both keys for one release and drop the old key after.
  1. For qhexrt_supported -> supported: patch the five real consumers in the same PR - BackendAvailability.kt:76, ModelCatalogBootstrap.ts:591, HexagonNpuCard.tsx:13/50, hexagon_npu_card.dart:16, NpuModelE2ETest.kt:184/186/190 - plus the three doc sites (qhexrt README.md:23, index.ts:21, QHexRT.ts:70).
  1. Find the producer of NpuCapability in the QHexRT repo (rac_qhexrt_probe_proto) and rename its setter there; it is outside runanywhere-sdks and will not be caught by any grep in this repo.


### `platform-delete-derivable-fields` — Delete efficiency_cores and arch_name - both restate a sibling field

**Proto location:** [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L49), [hardware_profile.proto (NpuCapability)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hardware_profile.proto#L96)

**Why:** `efficiency_cores` is always core_count - performance_cores, and `arch_name` is a pure function of hexagon_arch (whose enum values ARE the version numbers, so "v79" is mechanical). arch_name is also a plain proto3 string, so a default-constructed NpuCapability displays "" while the comment promises "unknown" - eight SDKs each carry both fields and each must decide which to trust.

**Skeptic verdict:** `risky` — 'efficiency_cores is always core_count - performance_cores' is an unverified arithmetic assumption, and it is wrong on the hardware this SDK targets: three-tier Android big.LITTLE (prime + big + little, e.g. 2+6+... on Snapdragon 8-series) means P + E does not equal the total, so a consumer told to derive E = total - P will over-count. It is also a live populated field on the JSON/C-ABI/backend path, not dead surface. Split the proposal: delete arch_name (clean), leave efficiency_cores alone or first prove the identity holds for every provider.

**What changed:** Deleted DeviceInfo.efficiency_cores and NpuCapability.arch_name outright (no `reserved 18;` / `reserved 5;` tombstones, per the no-backwards-compat ground rule). The freed NpuCapability tag 5 is taken by the new `NPUChip npu` field, which is what dense ascending numbering requires once `reserved` is off the table. Both halves carry live consumers named in correctionNeeded (arch_name: QHexRT.ts:40, HexagonNpuCard.tsx:12/45/53, hexagon_npu_card.dart:19, NpuModelE2ETest.kt:184-192; efficiency_cores: the full registration path incl. InitBridge.cpp:1792) - those are downstream work, not proto work, and no proto comment claims either field was dead.

**Files touched:** `device_info.proto`, `hardware_profile.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** arch_name IS READ - the claim that it is dead is wrong, and this is the item where that error would do the most damage because 'reserved 5' is irreversible in practice. SDK CODE, not a doc: sdk/runanywhere-react-native/packages/qhexrt/src/QHexRT.ts:40 `return NpuCapability.fromPartial({ socId: -1, archName: 'unknown' });` - this is the unknown/unsupported fallback returned by QHexRT.probeNpu() (:115) on every non-Snapdragon device and whenever the native module is missing. Delete arch_name and the RN qhexrt package stops type-checking. APP CODE that depends on the exact 'unknown' sentinel: ex…

**Wire safety:** Both halves are `reserved` deletions on their own tags - device_info.proto tag 18 and hardware_profile.proto NpuCapability tag 5 - so the reserve syntax is right and neither tag may ever be reused. But NpuCapability tag 5 is the LAST tag in that message (1-5), and platform-debrand-npu-fields wants to add tag 6; reserving 5 while adding 6 in the same file is fine, just do not let anyone 'tidy up' …

**Do first:**
  1. SPLIT the proposal. They are two unrelated changes with different risk and neither is 'low'.
  1. DROP the efficiency_cores half outright, or first prove the identity. InitBridge.cpp:1792 vs :1807 shows the codebase itself treats totalCores - perfCores as a FALLBACK, not a definition, and three-cluster Snapdragon parts break the arithmetic. If you still want it gone, the honest change is to document what it means, not to delete it.
  1. For arch_name, the hard prerequisite that does not exist: a single shared enum->display-string mapper (HexagonArch -> "v79") generated once and exported from the qhexrt package. Until that ships, deleting arch_name pushes a hand-written switch into React Native, Flutter and the Android E2E test independently - the opposite of the stated simplicity gain.
  1. That mapper must also preserve the 'unknown' sentinel semantics that HexagonNpuCard.tsx:45 relies on (archName === '' || archName === 'unknown' means probe-unavailable), or replace that check with an explicit hexagonArch === HEXAGON_ARCH_UNKNOWN test in the consumers FIRST.
  1. Only after the mapper is adopted by QHexRT.ts:40, HexagonNpuCard.tsx:45/53, hexagon_npu_card.dart:19 and NpuModelE2ETest.kt:184-192 may hardware_profile.proto:96 be reserved.
  1. Coordinate with the QHexRT repo: rac_qhexrt_arch_name() (rac_qhexrt.h:51) is the producer and lives outside runanywhere-sdks.


### `platform-delete-device-name` — Delete DeviceInfo.device_name - user-authored PII that nothing reads

**Proto location:** [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L31)

**Why:** This is UIDevice.name, commonly "Sam's iPhone", shipped to the control plane on every registration and routed on by nothing. Every SDK integrator inherits a PII egress they did not ask for (a GDPR data-inventory item and an App Store privacy-manifest entry) from a field that answers no product question - and it is not even a consistent label, since Web substitutes the browser name.

**Skeptic verdict:** `risky` — 'Read by nothing' is refuted: there are four live consumers on the registration path, and telemetry_json.cpp:516 uses add_string_always - it is an UNCONDITIONAL key in the POST /devices/register body that the file's own comment at telemetry_json.cpp:500-503 says 422'd against the FastAPI backend when the shape was wrong. Deleting the proto field alone leaves the C struct and serializer intact (so the backend keeps getting "device_name":"", and the PII egress the proposal is trying to stop continues), while deleting it end-to-end can 422 registration if schemas/device.py still requires it. The privacy argument is legitimate; the sequencing is not: backend schema first (make it nullable/drop the column), then the C ABI member and telemetry_json.cpp, then the proto.

**What changed:** Deleted `string device_name = 2` from DeviceInfo outright (no `reserved 2;` tombstone, per the no-backwards-compat ground rule) and densely renumbered the message. The proto comment does not repeat the false 'read by nothing' claim - the deletion rationale lives in the edit record, not in a tombstone comment. Left model_types.proto's unrelated `actual_device_name` (the compute device a model landed on) untouched, as the carePlan grep-trap warns.

**Files touched:** `device_info.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** 'Read by nothing' is false - there are consumers on every layer of the registration path. OUTBOUND, UNCONDITIONAL: sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_json.cpp:516 `json.add_string_always("device_name", info->device_name);` - add_string_always means the key is always present in the POST /devices/register body, so if the backend schema still requires it you get a 422, and if you delete only the proto you keep shipping `"device_name":""` and the PII egress you are trying to stop continues unabated. C ABI: sdk/runanywhere-commons/include/rac/infrastructure/telemetry/ra…

**Wire safety:** `reserved 2;` on DeviceInfo tag 2 is correct and mandatory - old producers still encode a string there and the tag must never be reused for a different type. No other field moves. The proto edit alone is the SMALLEST part of this change and the least effective: the JSON body key is "device_name" spelled out as a literal in telemetry_json.cpp:516, so reserving the tag does not stop one byte of PII…

**Do first:**
  1. BACKEND FIRST, always. Make device_name nullable/optional in schemas/device.py and stop persisting the column, and deploy that. telemetry_json.cpp:500-503 records that this endpoint has already 422'd once on a shape mismatch, so a client-first delete is a registration outage.
  1. SECOND, stop sending it: remove telemetry_json.cpp:516 add_string_always("device_name", ...). This is the step that actually ends the PII egress; do it even if the rest of the change stalls.
  1. THIRD, remove the C ABI member rac_telemetry_types.h:264 and every writer: jni:2551/2621/2660-2662/2915, CppBridge+Device.swift, cli/src/device_info.cpp:540, cli/src/net/control_plane.cpp:137/152/156, web DeviceRegistrationAdapter.
  1. FOURTH, stop COLLECTING it, which is the actual privacy win: DeviceInfo.swift:54/71/78/86/93/100 must stop calling device.name and Host.current().localizedName at all, not just stop forwarding the value. A collected-then-discarded UIDevice.name is still an App Store privacy-manifest item.
  1. FIFTH, delete `public let deviceName` from Handles.swift:44/47/49 as a deliberate, announced public-API removal.
  1. LAST, `reserved 2;` in device_info.proto and regenerate.
  1. Check the dashboards before step 1: if any view renders device_name, replace it with device_model + chip_name first or it silently goes blank.


### `platform-delete-hardware-profile-trio` — Delete HardwareProfile, AcceleratorInfo and HardwareProfileResult - no producer exists

**Proto location:** [hardware_profile.proto (HardwareProfile)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hardware_profile.proto#L15), [hardware_profile.proto (AcceleratorInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hardware_profile.proto#L51), [hardware_profile.proto (HardwareProfileResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hardware_profile.proto#L57), [hardware_profile.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hardware_profile.proto#L4)

**Why:** 15 of this domain's 42 fields describe a `Hardware` service whose C ABI header (named in the file's own comment) does not exist, so every one of eight generated SDKs will publish these types and always return zeros. Worse, HardwareProfile restates eight DeviceInfo concepts with different integer types (uint64/uint32 vs int64/int32) and different documented value sets, so a newcomer reading the two files cannot tell which is authoritative.

**Skeptic verdict:** `sound` — Core claim holds, but the risk list is incomplete in a way that matters for a 'breaking:true' change: there are three more consumers it does not name. sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/types/SwiftAliases.kt:103-104 publishes `public typealias RAHardwareProfile` and `RAAcceleratorInfo` as PUBLIC Kotlin API, sdk/runanywhere-electron/src/proto/hardware_profile.ts and sdk/runanywhere-python/runanywhere/_proto/hardware_profile_pb2.py ship generated bindings, and sdk/runanywhere-kotlin/.../extensions/CppBridgeHardware.kt is a whole bridge object documented as wrapping `rac_hardware_profile_*` (its own doc points at rac_hardware_abi.cpp, which also does not exist) - it must be re-documented or its live fallback helpers (defaultChipName/defaultTotalMemory/defaultGpuFamily, used by device registration) get orphaned. Also 'always return zeros' is wrong: nothing populates these messages at all, so they are absent, not zeroed.

**What changed:** Deleted messages HardwareProfile, AcceleratorInfo and HardwareProfileResult from hardware_profile.proto, together with the dead 'Logical hardware service contract' comment block that cited rac/router/rac_hardware_abi.h. Kept `import "storage_types.proto"` because platform-debrand-npu-fields re-homes NPUChip into NpuCapability in the same wave. Deleted `optional HardwareProfile hardware_profile = 2` from ModelCompatibilityRequest and densely renumbered its remaining fields 2..5, and deleted `HardwareProfileResult hardware_profile = 20` from HardwareRoutingEvent plus the now-unused `import "hardware_profile.proto"` in sdk_events.proto. Per the no-backwards-compat ground rule I deleted outright and renumbered instead of writing `reserved 2;` / `reserved 20;`.

**Files touched:** `hardware_profile.proto`, `model_types.proto`, `sdk_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** PUBLIC KOTLIN API, hard compile break: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/types/SwiftAliases.kt:103 `public typealias RAHardwareProfile = ai.runanywhere.proto.v1.HardwareProfile` and :104 `public typealias RAAcceleratorInfo = ai.runanywhere.proto.v1.AcceleratorInfo` - any app importing these stops compiling. DO-NOT-DELETE trap: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeHardware.kt:7-8,26,28 is documented as wrapping `rac_hardware_profile_*` / `rac_hardware_abi.cpp` (neither exists), but the object's real pay…

**Wire safety:** Deleting three whole messages needs no in-message reserves, but the two cross-domain REFERENCES do: model_types.proto:650 ModelCompatibilityRequest tag 2 -> `reserved 2;` and sdk_events.proto:1073 HardwareRoutingEvent tag 20 -> `reserved 20;`. Both tags must never be reused: old clients still encode them and a re-typed tag 2/20 would decode as garbage. hardware_profile.proto:4 `import "storage_ty…

**Do first:**
  1. Decide the NPUChip question FIRST, because it changes the diff: if platform-debrand-npu-fields lands, KEEP `import "storage_types.proto"` at hardware_profile.proto:4 and add `NPUChip npu = 6;` to NpuCapability in the SAME commit. Only if debrand is dropped may line 4 be removed.
  1. Move the seven default* helpers out of CppBridgeHardware.kt into a name that does not lie (e.g. DeviceDefaults.kt), or keep the file and rewrite its header comment (lines 7-8, 26-28) to stop citing rac_hardware_profile_*/rac_hardware_abi.cpp. Do NOT delete the file - CppBridgeDevice.kt:262/264 call into it.
  1. Delete the two public typealiases at SwiftAliases.kt:103-104 and search downstream apps (examples/, starters/) for RAHardwareProfile / RAAcceleratorInfo before publishing the Kotlin artifact.
  1. Delete the dead `racHardwareProfileGet` thunk declaration block at RunAnywhereBridge.kt:1663.
  1. Correct sdk/runanywhere-swift/ARCHITECTURE.md:764-773, 1118-1119, 2070 - it documents a Swift Hardware namespace that has no source file. Leaving it is how the next reviewer re-derives the same phantom.
  1. Add `reserved 2;` to ModelCompatibilityRequest and `reserved 20;` to HardwareRoutingEvent in the SAME commit as the message deletions, never after.
  1. Regenerate all bindings (proto-ts, electron, flutter, python, swift, kotlin) in the same PR; none of these are hand-written.


### `platform-extras-closed-keys` — Document platform_extras as a closed key set and stop sending keys that duplicate typed fields

**Proto location:** [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L56), [device_info.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L53)

**Why:** The map is the right shape, but the comment is an open invitation: Android ships eleven keys and the native parser reads exactly one ("manufacturer"). Three of the eleven restate fields already on the wire, which is why Kotlin maintains a bespoke serializer that re-emits three values unquoted. A newcomer cannot tell an escape hatch from a junk drawer without reading the C++ parser.

**Skeptic verdict:** `risky` — The replacement comment is itself inaccurate, which reproduces the defect it claims to fix. It lists "android_abi" - a key no producer emits - and omits sdk_version, locale and timezone, which CppBridgeDevice.kt:308/310/311 do emit, so the 'CLOSED key set - anything else is dropped by the native parser' text would document a set that does not match production on day one. It also says manufacturer is 'the ONLY key runanywhere_commons_jni.cpp reads' when device_id is read too (jni:2619). And 'anything else is dropped by the native parser' is misleading: unread keys are still serialized into the JSON body, so they do reach the backend. Rewrite the list from CppBridgeDevice.kt:299-312 verbatim, or leave the comment alone until the producer is cleaned up.

**What changed:** Rewrote the platform_extras comment as a closed key set, with all three of correctionNeeded's factual fixes applied against the real producers: dropped "android_abi" (no producer emits it); added "sdk_version", "locale" and "timezone" (CppBridgeDevice.kt:308/310/311 do emit them); said "manufacturer" AND "device_id" are the keys the native parser reads, not manufacturer alone; and replaced 'anything else is dropped by the native parser' with the truth that unlisted keys are flattened into the outbound body verbatim and read by no client code. The must-not-send duplicate list is device_type / os_name / processor_count / is_simulator, with device_id flagged as duplicating device_fingerprint but still parser-read today. The field itself is unchanged: map<string, string> platform_extras.

**Files touched:** `device_info.proto`

**Status:** `applied`

**Care level:** `routine`

**What could break:** Nothing in the proto edit itself. The comment's factual errors are what could mislead: sdk/runanywhere-kotlin/.../CppBridgeDevice.kt:299 is the producer map, :330 `append("\"device_id\":\"${escapeJson(info.platform_extras["device_id"] ?: "")}\",")` promotes device_id from the map to a TOP-LEVEL JSON key, and :355 `for ((key, value) in info.platform_extras)` flattens the remainder - so unread keys ARE serialized into the outbound body and DO reach the backend; 'dropped by the native parser' is wrong about what happens to them. The parser reads at least two keys, not one: runanywhere_commons_jn…

**Wire safety:** No wire change - the proto edit is comment-only and platform_extras stays `map<string, string> platform_extras = 20`. The producer-side key deletions the comment implies ARE data changes, but they are a separate commit and are covered under doFirst.

**Do first:**
  1. Write the key list by reading CppBridgeDevice.kt:299-312 and DeviceCapabilities.ts:124 verbatim, not from memory. The Android map has exactly 11 keys: device_id, device_type, os_name, processor_count, is_simulator, manufacturer, os_build_id, sdk_version, android_api_level, locale, timezone. Do not list android_abi - no producer emits it. Do not omit sdk_version, locale, timezone.
  1. Say 'reads' correctly: the JNI parser consumes manufacturer AND device_id (device_id arrives as a top-level key promoted from the map at CppBridgeDevice.kt:330). Everything else is forwarded to the backend, not dropped.
  1. Replace 'anything else is dropped by the native parser' with 'keys not listed here are forwarded to the control plane verbatim by CppBridgeDevice.kt:355 and read by no client code' - which is both true and the actual argument for closing the set.
  1. If you also want the five duplicate keys (device_id, processor_count, os_name, device_type, is_simulator) deleted from the producer, make that a SEPARATE commit after grepping the analytics pipeline for those exact key names - the proto comment change should not be blocked on it.


### `platform-memory-fields-bytes` — Name the memory unit and define "available": total_memory_bytes / available_memory_bytes

**Proto location:** [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L37), [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L38)

**Why:** `available_memory` is the number that decides whether a model loads, and it is the least specified field in the domain: three producers compute three different quantities, the unit lives only in a trailing comment, and on Web it is a literal 0 - so the obvious check `model_size < available_memory` refuses every model in the browser. Every other byte field in this IDL already says `_bytes` (size_bytes, total_bytes, download_size_bytes), including the deleted HardwareProfile.total_memory_bytes.

**Skeptic verdict:** `risky` — 'Tags unchanged, wire unaffected' is false for the path that actually carries this data. The DeviceInfo JSON contract is keyed by field NAME: rename to available_memory_bytes and jni:2634's i64_field("available_memory") returns 0 (the lambda's default, jni:2605-2608), so commons believes the device has zero free RAM - exactly the 'refuses every model' failure the proposal is trying to fix, now on Android instead of Web. The rename must move with jni:2633-2634, rac_telemetry_types.h:270-271, telemetry_json.cpp:528-529 and schemas/device.py. Separately, the new doc promises availMem semantics 'on every platform' while the Kotlin default is literally totalMemory/2 (CppBridgeDevice.kt:110) - a fabricated number that the comment would now bless as availMem.

**What changed:** Renamed DeviceInfo.total_memory -> total_memory_bytes and DeviceInfo.available_memory -> available_memory_bytes, matching the repo's `_bytes` house style, and moved the unit from a trailing comment into the field name. Per correctionNeeded I did NOT write 'with exactly ActivityManager.MemoryInfo.availMem semantics on every platform' - no producer satisfies it. The available_memory_bytes comment states only what is true and enforceable: 0 = UNKNOWN, and a consumer MUST NOT read 0 as 'no memory left'.

**Files touched:** `device_info.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** THE JSON KEY IS THE CONTRACT: sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_json.cpp:528 `json.add_int_always("total_memory", info->total_memory);` and :529 for available_memory; parsed by sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp:2633 `i64_field("total_memory")` and :2634 `i64_field("available_memory")`, which return 0 on a missing key. jni:2597 carries an explicit warning comment about 'tripping the backend's total_memory > 0' check - so a key mismatch does not fail loudly, it makes the backend believe the device has zero RAM. C ABI, THREE structs: rac_tel…

**Wire safety:** No wire change in protobuf terms: tags 8 and 9 keep their numbers and their int64 type; only the field NAMES move. But the name IS the wire on the live path - the JSON body and the JNI parser are both keyed by the literal strings "total_memory" and "available_memory", so 'wire unaffected' is only true of a transport this data never uses. Note the target names are already taken elsewhere in the ID…

**Do first:**
  1. Treat this as a JSON-key migration, not a proto rename. One atomic commit must move all five sites together: idl/device_info.proto:37-38, telemetry_json.cpp:528-529 (the key strings), runanywhere_commons_jni.cpp:2633-2634 (the key strings), CppBridgeDevice.kt's JSON emitter, and rac_telemetry_types.h:270-271. Any partial landing makes Android report 0 bytes of RAM, which is the exact bug the proposal exists to fix.
  1. Update the backend device schema to accept the new keys first, or accept both for one release. jni:2597 already documents a backend `total_memory > 0` check, so a 0 is not inert - it changes backend behaviour.
  1. Decide what to do about the Web 0 BEFORE writing the comment that blesses it. Right now DeviceCapabilities.ts:116 and DeviceRegistrationAdapter.ts:444 hardcode 0 and telemetry_json.cpp:528-529 sends it unconditionally, while the sibling live-state path at :292-294 sends null instead. Pick one convention.
  1. Either fix CppBridgeHardware.defaultAvailableMemory (CppBridgeDevice.kt:274 / CppBridgeHardware.kt:274) to read ActivityManager.MemoryInfo.availMem, or do not write 'exactly availMem semantics on every platform' into the proto. A comment that blesses a fabricated number is worse than no comment.
  1. Keep the rename of total_memory and available_memory in the same commit as each other; splitting them doubles the window where the two JSON key sets disagree.


### `platform-unknown-is-absent` — One encoding for "unknown": absent. Kill the -1 sentinel and the 0.0 battery default

**Proto location:** [device_info.proto (DeviceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/device_info.proto#L43), [hardware_profile.proto (NpuCapability)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hardware_profile.proto#L88)

**Why:** 0.0 is a real battery level - a phone about to die - so an Android device whose battery cannot be read registers as flat, and any 'refuse long generations below 10%' rule fires on it. soc_id is worse: three meanings (real id, documented -1, proto3 default 0) share one int32, so nobody can write an `isUnknown` check that is correct across SDKs. Making both `optional` gives every SDK the same answer for free, because a default-constructed message already reads as unknown.

**Skeptic verdict:** `sound` — One mechanical error to fix before merge: the option is spelled `(runanywhere.v1.rac_min_float)` / `(runanywhere.v1.rac_max_float)` in this IDL (see idl/diarization.proto:43-44, idl/diffusion_options.proto:93-94), not `(rac.min_float)` / `(rac.max_float)` as written in the 'after' - the snippet as given will not compile. Also note the import to add is rac_options.proto but device_info.proto currently has zero imports, so this is also the file's first import (the proposal says this, correctly).

**What changed:** Applied the absent-means-unknown rule: NpuCapability.soc_id is now `optional int32` with the -1 sentinel struck from its comment, and DeviceInfo.battery_level keeps `optional float` and gains inclusive 0.0-1.0 bounds. The proposal's `(rac.min_float)` / `(rac.max_float)` spellings do not exist in rac_options.proto; I used the real declared extensions `(runanywhere.v1.rac_min_float)` and `(runanywhere.v1.rac_max_float)`, matching how llm_options.proto and diffusion_options.proto already spell them, and added `import "rac_options.proto";` to device_info.proto.

**Files touched:** `device_info.proto`, `hardware_profile.proto`

**Status:** `applied`


</details>


<details>
<summary><strong>rag</strong> (9 changes)</summary>

### `rag-add-delete-by-id` — Add delete-by-document-id; today clear() wiping everything is the only removal verb

**Proto location:** [rag.proto (RAGDocument)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L66), [rag.proto (RAGDocument)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L65)

**Why:** The corpus is a personal on-device one: notes, emails, files. A developer who deletes one note in the app has no way to delete it from the index short of `clear()` and a full re-ingest of everything. Every vector store the developer has used before has delete-by-id, so its absence reads as a missing feature they will work around badly.

**Skeptic verdict:** `sound` — Under-scoped rather than wrong. (a) The risk note says USearch needs id-scoped removal, but vector_store_usearch.h:94 already declares `bool remove_chunk(const std::string& chunk_id)`; the missing piece is the document_id -> chunk_ids mapping, since ingest (rac_rag_proto_abi.cpp:882-902) throws RAGDocument.id away into metadata['document_id'] and lets the backend mint chunk ids. (b) The 'RAGDocument.id values given at ingest' contract is not reachable from every facade today -- Flutter's RagDocument (runanywhere-flutter/.../inputs.dart:354) has no id parameter at all, only text/metadata/sourceUri -- so the facades must gain a caller-settable id in the same pass or delete-by-id is unusable from Flutter.

**What changed:** Added `message RAGDeleteRequest { repeated string document_ids = 1 [(runanywhere.v1.rac_required) = true]; }` and `message RAGDeleteResponse { int64 deleted_chunks = 1; repeated string missing_ids = 2; optional SDKError error = 3; }` to rag.proto, and put the approved comment on RAGDocument.id ("Caller-owned stable id. Re-ingesting an existing id REPLACES its chunks."). Per the carePlan's doFirst I landed rag-document-purge's RAGDocument rewrite first so the message and that comment were written exactly once. No risk-note text was copied into the proto, so the correctionNeeded about remove_chunk already existing on both indexes did not reach a comment.

**Files touched:** `idl/rag.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** (1) Silent no-op on re-ingest after delete: rag_backend.cpp:229 skips ingestion when `ingested_content_hashes_.count(content_hash)` hits, and the set is only erased on failure paths (rag_backend.cpp:264,276,308,323) or full clear (rag_backend.cpp:736). Delete-by-id that does not erase the deleted document's content hashes makes the documented 'Re-ingesting an existing id REPLACES its chunks' contract quietly false. (2) The contract is unreachable from 4 of 5 facades: Swift RagDocument has text/metadata/path only (sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Inputs.swift:516-524), Kotl…

**Wire safety:** Purely additive on the wire: RAGDeleteRequest/RAGDeleteResponse are new messages (grep over idl/*.proto shows no name collision), RAGDocument.id stays at tag 1 with an unchanged type, and no existing tag is reused or renumbered. The non-wire risk is the ABI symbol, not the schema: rac_rag_delete_proto is a NEW exported C symbol and the export allow-lists are hand-maintained (sdk/runanywhere-commo…

**Do first:**
  1. Land the RAGDocument edit from rag-document-purge FIRST so the message is rewritten once, not twice — both proposals rewrite the comment on RAGDocument.id and will otherwise conflict.
  1. Add a caller-settable id to the four facades that lack one, in the same PR as the proto: Swift Inputs.swift:516 (`public var id: String?`), Kotlin Inputs.kt:173-179 (new ctor param, keep the existing 2-arg constructor as a default-argument overload so no app source breaks), Flutter inputs.dart:354, React Native Public/Api/Rag.ts:81. Web already has one via RagDocument.name -> proto id (Namespaces/rag.ts:104).
  1. Implement `chunk_ids_for_document(const std::string& document_id)` in the backend by scanning chunk metadata['document_id'] — reuse the exact predicate at rag_pipeline_graph.cpp:49-57 rather than writing a second one, so delete and scope_prefix can never disagree about what a document is.
  1. Wire the removal to BOTH indexes in one call: vector_store_usearch.h:94 remove_chunk and bm25_index.h:25 remove_chunk. Missing BM25 leaves deleted text retrievable through the lexical half of the hybrid fusion (rag_backend.cpp:410-440).
  1. Erase the deleted document's entries from ingested_content_hashes_ (rag_backend.cpp:221-236) in the same code path, or delete-then-reingest silently no-ops.
  1. Implement replace-on-duplicate-id at ingest (rac_rag_proto_abi.cpp:888) as delete-then-insert reusing the same helper, and write that in the proto comment as the proposal specifies.
  1. Register rac_rag_delete_proto in ALL of: include/rac/features/rag/rac_rag.h, exports/RACommons.rag.exports (after line 29), src/jni/runanywhere_commons_jni.cpp, swift rac_modality_proto_abi.h + ModalityProtoABI+Generated.swift, flutter rac_native.dart + dart_bridge_rag.dart, react-native HybridRunAnywhereCore+Tools.cpp AND the vendored android/src/main/jniLibs/include/rac/features/rag/rac_rag.h, web RAGProtoAdapter.ts + ProtoAdapterTypes.ts + EmscriptenModule.ts + wasm/CMakeLists.txt:1121, python native/module.cpp, electron native/addon.cpp.
  1. Decide and document the empty-list case: the proposal says empty document_ids is an error. Mirror it in the ABI (RAC_ERROR_INVALID_ARGUMENT) the way rac_rag_query_proto rejects an empty question at rac_rag_proto_abi.cpp:954-958.


### `rag-config-drop-dead-knobs` — Delete llm_config_json and reranker_model_id from RAGConfiguration

**Proto location:** [rag.proto (RAGConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L55), [rag.proto (RAGConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L61), [rag.proto (RAGConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L62)

**Why:** `llm_config_json` has no consumer anywhere in commons — it is an escape hatch that escapes nowhere, and it sits next to `embedding_config_json`, which is real, so a newcomer assumes both work. `reranker_model_id` is worse than dead: setting it makes session creation fail with NOT_IMPLEMENTED, so the only way to learn it does nothing is to break your app.

**Skeptic verdict:** `sound` — No defect found. The kept/dropped split is drawn exactly where the greps put it. Two notes: deleting reranker_model_id also deletes the loud rejection at line 721, so the SDK-side parameter must go in the same pass (otherwise a caller who currently gets a clear error gets nothing at all); and the OpenAI precedent invoked against 'opaque dated ranker ids' is real (ranking_options.ranker takes values like default-2024-11-15), so the reasoning is not invented.

**What changed:** Deleted RAGConfiguration.llm_config_json (was tag 11) and RAGConfiguration.reranker_model_id (was tag 15) outright; kept rerank_results and gave it the approved comment "Pointwise rerank of the retrieved chunks using the session LLM." It now sits at tag 11 after the dense renumbering. Also corrected the file header comment, which told callers to register "embedding, LLM, and reranker models" — with reranker_model_id gone that sentence was no longer true, so it now reads "embedding and LLM models".

**Files touched:** `idl/rag.proto`

**Status:** `applied`


### `rag-document-purge` — Cut RAGDocument to id/text/metadata/source_uri and wire source_uri into results

**Proto location:** [rag.proto (RAGDocument)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L65), [rag.proto (RAGDocument)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L69), [rag.proto (RAGDocument)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L70), [rag.proto (RAGDocument)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L72)

**Why:** This is the very first message a developer touches — the thing they build to ingest their data — and three of its seven fields (`adapter_handle`, `media_type`, `size_bytes`) are read by no ingest path, with the SDKs dutifully filling two of them. `source_uri` is the same story, except it is the one that should exist: it is where `RAGSearchResult.source_document` is supposed to come from, and it is currently dropped, so provenance never resolves.

**Skeptic verdict:** `sound` — Verified, with one factual correction and one caveat. The risk note claims 'Swift/Kotlin/Flutter set adapter_handle and size_bytes today' -- I cannot reproduce that: grep for adapterHandle/mediaType/sizeBytes across the hand-written Rag facades (swift Public/API/Rag, kotlin RagSession.kt, electron rag.ts, flutter inputs.dart) finds nothing RAG-related, and Flutter's RagDocument carries only text/metadata/sourceUri. Caveat: source_uri, which the proposal KEEPS, is itself read nowhere in commons (0 hits under features/rag) even though three facades write it (Inputs.swift:541, RagSession.kt:268, inputs.dart:354) -- so the kept field is exactly the same shape of lie as the deleted ones until the promised metadata['source'] wiring is done.

**What changed:** Cut RAGDocument to four fields: id=1, text=2, metadata=3, source_uri=4. Deleted adapter_handle, media_type and size_bytes outright (no `reserved`, per the ground rule) and closed the old tag-3 hole by renumbering metadata/source_uri down. source_uri carries the approved provenance comment ("Copied into every chunk's metadata as \"source\" and returned as RAGSearchResult.source_document."). I did not write the proposal's claim that Swift/Kotlin/Flutter populate the deleted fields — per correctionNeeded the Web SDK (makeRAGDocument, Namespaces/rag.ts) is the only writer, and no such claim appears in the proto.

**Files touched:** `idl/rag.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The Web SDK constructs proto RAGDocument objects with all three 'dead' fields, so deleting them is a Web BUILD break, not a no-op: sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+RAG.ts:1292-1303 `function makeRAGDocument(text, metadataJson): RAGDocument` returns `{ id, text, metadata, sourceUri, adapterHandle: undefined, mediaType: parsed.mediaType, sizeBytes: parsed.sizeBytes }`, and sdk/runanywhere-web/packages/core/src/Public/API/Namespaces/rag.ts:102-108 calls `ragIngestDocument({ id, text, metadata, sizeBytes: document.text.length })`. That target really is the proto…

**Wire safety:** Deletes tags 6, 7, 8 from RAGDocument and reserves 3, 6, 7, 8. No tag is reused and no field number moves, so old bytes on the wire are ignored rather than misread — the wire itself is safe. The break is at compile time in the Web SDK (see whatCouldBreak), not on the wire. Keep `reserved 3;` — it is already free — and keep source_uri at tag 5 unchanged.

**Do first:**
  1. Wire source_uri BEFORE deleting anything, so provenance is real when the message shrinks: at sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp:888 (right beside the existing `metadata["document_id"] = document.id()`), add `if (document.has_source_uri()) metadata["source"] = document.source_uri();`. Nothing else is needed — the result side already resolves it: rac_rag_proto_abi.cpp:559 scans {"source_document","source","filename","document_id"} and rag_backend.cpp:606-609 does the same. That single line is what makes RAGSearchResult.source_document non-empty.
  1. Fix the Web call sites in the SAME commit as the proto edit, in this order: remove `sizeBytes`/`mediaType`/`adapterHandle` from makeRAGDocument (RunAnywhere+RAG.ts:1294-1302) and remove `sizeBytes: document.text.length` from Namespaces/rag.ts:107. Keep ParsedMetadata's own sizeBytes/mediaType fields (RunAnywhere+RAG.ts:1305-1331) if the Web document-listing UI uses them — they are a local interface, not the proto, and are not in scope here.
  1. Regenerate all bindings (proto-ts, Wire/Kotlin, Swift, Dart) and rebuild the Web package before merging; the Web build is the only one that can fail here.


### `rag-drop-fake-persistence` — Delete index_path/persist_index — we advertise persistence commons does not implement

**Proto location:** [rag.proto (RAGConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L58), [rag.proto (RAGConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L59)

**Why:** A newcomer reads `persist_index` and `index_path`, sets them, ships, and loses the user's corpus on every app restart — all three SDKs write these fields and no commons code reads them. A field that promises durability and delivers an in-memory index is worse than no field: it is the only kind of API defect that costs the developer data rather than time.

**Skeptic verdict:** `sound` — Two supporting claims are overstated and should not be repeated in the commit message. 'All three SDKs write these fields' / 'the three facades expose persistPath': grep finds `persistPath` nowhere in the repo, and the only hand-written facade carrying it is runanywhere-electron/src/rag.ts:29-30 (`persistIndex`); Swift's only hit is the generated rag.pb.swift:176-185. Also the AI Edge RAG precedent is misdescribed -- it ships separate VectorStore implementations (in-memory default vs SQLite), not an enum. The Chroma half (ephemeral vs persistent client at construction) is accurate, and the conclusion holds either way.

**What changed:** Deleted RAGConfiguration.index_path (was tag 12) and RAGConfiguration.persist_index (was tag 13) outright, along with their "Where the vector index lives..." comment. Per the no-backwards-compatibility ground rule I wrote no `reserved` statement and no tombstone comment, and renumbered the surviving fields dense/ascending, so RAGConfiguration is now 11 fields, tags 1..11.

**Files touched:** `idl/rag.proto`

**Status:** `applied`


### `rag-industry-renames` — Rename question->query, similarity_score->score, similarity_threshold->score_threshold

**Proto location:** [rag.proto (RAGSearchRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L103), [rag.proto (RAGQueryOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L78), [rag.proto (RAGConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L36), [rag.proto (RAGSearchResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L127)

**Why:** Three fields use words no other RAG API uses. Worse, `similarity_score` is not a similarity: retrieval is hybrid dense+BM25 fused by reciprocal-rank fusion, so the number is a fused rank score, and `similarity_threshold` is bounded 0..1 against it. A newcomer who sets 0.7 expecting cosine similarity gets behaviour they cannot reason about. Free to fix today, carried by eight SDKs forever if skipped.

**Skeptic verdict:** `sound` — No defect found. Precedents are real (OpenAI vector-store search takes `query` and returns `data[].score`; ranking_options.score_threshold exists; Chroma/LangChain/LlamaIndex all say query). Note only that this breaks every generated accessor and JSON field name in all five SDKs, and that the 0..1 bound on score_threshold stays a lie until the fused RRF score is normalised -- which the proposal itself makes a condition.

**What changed:** Renamed question -> query on both RAGSearchRequest and RAGQueryOptions (rac_required kept), similarity_threshold -> score_threshold on RAGConfiguration (all three rac_ bounds options kept verbatim, plus the approved comment "Drop hits scoring below this. 0.0 = no filtering."), and similarity_score -> score on RAGSearchResult with the approved comment stating it is a fused dense+BM25 RRF relevance value normalised 0..1, not a cosine similarity. The per-call similarity_threshold fields on RAGQueryOptions and RAGSearchRequest also became score_threshold, on RAGRetrievalOptions (see rag-share-retrieval-options).

**Files touched:** `idl/rag.proto`

**Status:** `applied`


### `rag-result-numbers-must-be-measurements` — On RAGResult/RAGSearchResult, delete the numbers that are derived or always zero

**Proto location:** [rag.proto (RAGResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L147), [rag.proto (RAGResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L153), [rag.proto (RAGResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L158), [rag.proto (RAGResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L155)

**Why:** Four numbers on the two result messages teach a newcomer something false. `total_time_ms` is exactly retrieval+generation, so three timings are two measurements. `usage` and `request_id` are never set by the RAG path, so every SDK proudly shows 0 tokens and 0 tok/s on a RAG answer. `rank` duplicates array order and is populated on the search path but zero on the query path — right in one place, wrong in the other.

**Skeptic verdict:** `sound` — No defect found; the four claims each survive a direct grep. The one consumer worth naming before deleting rank is runanywhere-electron/src/api/data.ts:116 (`.sort((a,b) => a.rank - b.rank)`) -- I checked it and it belongs to the RERANK path, a different message, so RAGSearchResult.rank really has no reader. Keep the proposal's own condition: if usage and request_id are not populated in rac_rag_proto_abi.cpp this cycle, reserve them rather than ship the zero.

**What changed:** Deleted RAGResult.total_time_ms and RAGSearchResult.rank outright. RAGResult keeps request_id, thinking_content and usage — the carePlan is explicit that these must be POPULATED, not reserved (electron data.ts:178-184 reads them), so I kept them and carried the approved "MUST be set" / "MUST be copied" contract comments, and retrieval_time_ms carries the "Measured directly, not by subtraction" comment. RAGResult is now 9 fields at tags 1..9, RAGSearchResult 8 fields at tags 1..8. I wrote no tombstone comment about rank, so the false "rank has no reader" claim from correctionNeeded never entered the proto (its live reader is Web RunAnywhere+RAG.ts:1199).

**Files touched:** `idl/rag.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** total_time_ms has five hand-written readers, four of which are PUBLIC API and all of which fail to compile on delete: Swift sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/RAGProto+Helpers.swift:52 `public var totalTime: TimeInterval { TimeInterval(totalTimeMs) / 1000.0 }`; Kotlin sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/extensions/RAG/RAGProtoHelpers.kt:53-54 `val RAGResult.totalTime get() = total_time_ms.toDouble() / 1000.0`; Flutter sdk/runanywhere-flutter/packages/runanywhere/lib/public/capabilities/runanywhere_rag.dart:282 `Duration get totalTime …

**Wire safety:** RAGResult: reserve 6 (total_time_ms) and 7-11; no tag reuse, no renumbering, request_id stays at 12 and usage at 14. RAGSearchResult: reserving 6 is free, but reserving 7 removes `rank`, which IS currently written on the wire by the search path (rac_rag_proto_abi.cpp:557). Old readers decoding a new payload just see 0 — the same value the query path already sends — so no misread, but see whatCoul…

**Do first:**
  1. Populate before you delete — do the two one-liners in rac_rag_proto_abi.cpp FIRST and merge them on their own: set request_id from the existing event id, and copy `usage` from the llm_result the pipeline already holds at rac_rag_proto_abi.cpp:522. Verify on device that a RAG answer reports non-zero tokens BEFORE the deletion PR lands. If that verification does not happen this cycle, reserve 12 and 14 instead and fix electron data.ts:178-184 in the same PR — the proposal's own condition.
  1. Rewrite the four totalTime accessors to `retrieval_time_ms + generation_time_ms` (Swift RAGProto+Helpers.swift:52, Kotlin RAGProtoHelpers.kt:53-54, Flutter runanywhere_rag.dart:282, Web RunAnywhere+RAG.ts:1621) and change Mapping.ts:556 to `result.generationTimeMs || (result.retrievalTimeMs + result.generationTimeMs)` — keep the derived value as a HELPER in every SDK so no app source changes; only the proto field goes away.
  1. Make retrieval_time_ms a real measurement in the same commit: rac_rag_proto_abi.cpp:522-526 currently computes `retrieval_ms = max(0, total_ms - generation_ms)`. Once total_time_ms is gone, retrieval must be timed directly around embed+search+fuse, or the two remaining numbers are still one measurement wearing two names.
  1. Before reserving RAGSearchResult tag 7, change Web RunAnywhere+RAG.ts:1199 to use the enumeration index (`chunks.forEach((chunk, i) => ... [Source ${i + 1}: ...])`) and drop the `rank: index + 1` write at :768. Only then delete the field.
  1. Sequence: (1) populate usage/request_id, (2) fix the four totalTime helpers + Mapping.ts, (3) fix Web rank at :768/:1199, (4) edit the proto and regenerate. Any other order breaks a build.


### `rag-share-retrieval-options` — Extract one RAGRetrievalOptions; the same 5 knobs are declared twice at different tags

**Proto location:** [rag.proto (RAGQueryOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L75), [rag.proto (RAGQueryOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L82), [rag.proto (RAGQueryOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L85), [rag.proto (RAGSearchRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L102)

**Why:** The same five retrieval knobs are declared twice with different tag numbers, one with explicit presence and one without, so a developer who learns search() has to re-learn query(). And `retrieval_top_k` is the odd one out: a bare int32 where 0 secretly means 'use the session default', while every neighbouring knob uses explicit presence. Fold in the dead `stream` bool, which nothing reads — streaming is chosen by calling queryStream, never by a flag.

**Skeptic verdict:** `sound` — The dedup itself is real and the reserved ranges are correct, but two couplings make this unsafe to land alone. (1) RAGRetrievalOptions.filters = 5 references RAGFilter, which only exists if the metadata-filter proposal lands -- and I am recommending that one be declined as written (tag-6 reuse), so this message would not compile. (2) The `after` silently drops scope_prefix with no replacement, and scope_prefix is NOT dead: it is implemented end-to-end in rag_pipeline_graph.cpp:241-282 with its own widened candidate pool. Landing this as drafted deletes a working retrieval capability under the banner of deduplication. Sequence it after a filter design that can express a prefix, or carry scope_prefix into RAGRetrievalOptions unchanged.

**What changed:** Added `message RAGRetrievalOptions` with top_k=1, score_threshold=2, enable_multi_query=3, multi_query_count=4, scope_prefix=5, and collapsed both RAGSearchRequest and RAGQueryOptions onto it: RAGSearchRequest is now {query=1, retrieval=2} and RAGQueryOptions {query=1, retrieval=2, generation=3}. Per carePlan.correctionNeeded (a) I did NOT write `repeated RAGFilter filters = 5` — RAGFilter is declared nowhere in idl/*.proto and would not compile — and I DID carry scope_prefix forward, since it is a working retrieval path (rag_pipeline_graph.cpp:241-282). The dead `stream` bool is gone (its only writer is Kotlin MappingOptions.kt:237, which must go in the same PR). No `reserved` was written and tags are dense per the ground rules, so `retrieval` sits at tag 2 rather than the proposal's collision-avoiding 7/15.

**Files touched:** `idl/rag.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** (1) It does not compile as drafted: RAGRetrievalOptions.filters = 5 is `repeated RAGFilter`, and RAGFilter does not exist in idl/ — it arrives only with the metadata-filter proposal, which the skeptic recommends declining in its current form. (2) The `after` silently drops scope_prefix, which is NOT dead: it is implemented end to end at rag_pipeline_graph.cpp:241 (`const bool scoped = !inputs.scope_prefix.empty();`), :271 and :282 (dense and BM25 candidates both filtered through chunk_matches_scope), with the predicate at :49-57 matching chunk metadata['document_id'] against the prefix; it is…

**Wire safety:** RAGSearchRequest reserves 2 to 6 and adds `retrieval` at a new tag 7; RAGQueryOptions reserves 2 to 13 (on top of the existing `reserved 2 to 6, 10;`) and keeps question=1 and generation=14. No tag is reused and RAGRetrievalOptions is a brand-new message (rg -n RAGRetrievalOptions idl/*.proto is empty), so the wire is clean. The real semantic change is `int32 retrieval_top_k` (0 = session default…

**Do first:**
  1. PREREQUISITE that does not exist yet: a `message RAGFilter` definition. It comes from the RAG metadata-filter proposal (not in this brief), which is currently recommended for decline over tag-6 reuse. Either land a corrected filter design first, or ship RAGRetrievalOptions WITHOUT `repeated RAGFilter filters = 5` and reserve tag 5 for it. Do not merge a proto that does not compile.
  1. Carry scope_prefix into RAGRetrievalOptions unchanged (`optional string scope_prefix = 6;`) unless and until the filter design can express a document-id prefix. Deleting it removes the only working scoped-retrieval path (rag_pipeline_graph.cpp:241-282).
  1. Update the one non-obvious commons writer: sdk/runanywhere-commons/src/solutions/operators/op_engine_backed.cpp:764-765 must become `request.mutable_retrieval()->set_top_k(retrieval_top_k_)`.
  1. Keep the 0-means-default path alive for one release as the risk note says: in rac_rag_proto_abi.cpp:431 and :598, read the new `retrieval.top_k` when present and fall back to the legacy tag only while the old field still exists in generated code.
  1. Delete `stream` and its Kotlin writer together: MappingOptions.kt:230 (parameter) and :237 (assignment), plus the two call sites RagSession.kt:114 and :135. Nothing reads it in commons.
  1. Good news for the facades: Kotlin's public API already nests these knobs — MappingOptions.kt:235-236 reads `options?.retrieval?.topK` and `options?.retrieval?.similarityThreshold` — so the proposed one-level nesting matches the shape the Kotlin SDK already presents. Mirror that naming (`retrieval.topK`) in Swift/Flutter/Web/RN rather than inventing a new one.
  1. Rename question -> query on RAGSearchRequest only together with its five writers: Kotlin RagSession.kt:91 + MappingOptions.kt:233, Flutter rag.dart:231 and :243, RN Public/Api/Rag.ts:94 and :127, and the commons validator at rac_rag_proto_abi.cpp:954-958 ('RAGQueryOptions.question is required').


### `rag-statistics-purge` — Cut RAGStatistics from ten fields to five — half of it is never populated

**Proto location:** [rag.proto (RAGStatistics)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L162), [rag.proto (RAGStatistics)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L167), [rag.proto (RAGStatistics)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L168), [rag.proto (RAGStatistics)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L170)

**Why:** `stats_json`, `last_query_ms`, `index_path` and `is_persistent` are never set by commons, so every SDK renders zeros, empties and false as if they were measurements. A stats message where the developer cannot tell which numbers are real is worse than a smaller one where they all are.

**Skeptic verdict:** `sound` — The four deletions are verified dead. The internal inconsistency is that vector_store_size_bytes is KEPT even though it is equally never populated -- by the proposal's own rule it should be reserved unless make_stats() is fixed this cycle. That fix is at least feasible: vector_store_usearch.h:109 exposes memory_usage() and vector_store_usearch.cpp:284 already puts memory_bytes into the stats JSON. The 'indexed_documents == indexed_chunks' observation is also exactly right (lines 382-383 and 389-390 assign the same value to both), so that field is a third zero-information number the proposal keeps. OpenAI's VectorStore reports more than four fields (id/name/created_at/expires_at as well), but usage_bytes/file_counts/status/last_active_at are real, so the precedent is not invented.

**What changed:** Deleted RAGStatistics.index_path, stats_json, is_persistent and last_query_ms outright; kept indexed_documents, indexed_chunks, total_tokens_indexed, last_updated_ms (with the epoch-ms comment), vector_store_size_bytes (with the approved "MUST be populated by make_stats()... surfaced as RagStats.indexSizeBytes" comment) and error, renumbered dense to tags 1..6. Per correctionNeeded I wrote nothing claiming every SDK renders zeros — the Web SDK populates all four deleted fields and round-trips two of them through its persistence snapshot, so those call sites (RunAnywhere+RAG.ts:917-930, :962, :968, :1001-1018, :1365-1369, :1665-1669) must move with this edit — and nothing implying vector_store_size_bytes is unread.

**Files touched:** `idl/rag.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** This is the VADConfiguration shape of mistake. 'Never populated by commons' is true; 'every SDK renders zeros' is FALSE. The Web SDK has a full JavaScript RAG implementation that produces RAGStatistics itself and fills every one of the four condemned fields: sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+RAG.ts:926-930 (cross-wasm provider: indexPath, statsJson with provider+dimension, vectorStoreSizeBytes computed at :917, isPersistent:false, lastQueryMs), :1001-1018 (persistent provider: indexPath from the storage key, isPersistent:true, statsJson, lastQueryMs), :1365-1…

**Wire safety:** Reserves 5, 6, 8, 9 (index_path, stats_json, is_persistent, last_query_ms) plus the free 10, 11; keeps 1, 2, 3, 4, 7, 12 at their current tags. No reuse, no renumbering — wire-safe. But these four tags are NOT unwritten on the wire today: the Web SDK's own RAG providers populate all four (see whatCouldBreak), so reserving them deletes live data on the Web path, not just a hole in the schema.

**Do first:**
  1. Decide the Web question first, because it is the whole risk: either (a) keep index_path / stats_json / is_persistent / last_query_ms and document them as 'set by JS-side RAG providers only; zero on the native path' — which is honest and costs nothing — or (b) delete them from the proto AND migrate the Web provider's snapshot state (RunAnywhere+RAG.ts:917-930, :962, :968, :1001-1018, :1365-1369, :1665-1669) onto its own local interface first. Do not delete them while the Web SDK is still writing them.
  1. Populate vector_store_size_bytes in make_stats() (rac_rag_proto_abi.cpp:379-400) before shipping: sdk/runanywhere-commons/src/features/rag/vector_store_usearch.h:109 exposes memory_usage(), and vector_store_usearch.cpp:284 already writes memory_bytes into the stats JSON — it is a copy, not new plumbing. If that is not done this cycle, reserve tag 7 as well AND fix the five indexSizeBytes mappers named above in the same PR.
  1. Resolve indexed_documents honestly: rac_rag_proto_abi.cpp:382-383 and :389-390 assign the same value to indexed_documents and indexed_chunks. Either count distinct metadata['document_id'] values (the same scan rag-add-delete-by-id needs — build it once) or collapse to the chunk count and reserve tag 1.
  1. Fix Web Mapping.ts:574 in the same pass: `indexSizeBytes: statistics.vectorStoreSizeBytes` (today it reads totalTokensIndexed).


### `rag-stream-three-kinds` — Cut the stream to token/completed/error — three of the six kinds are never emitted

**Proto location:** [rag.proto (RAGStreamEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L175), [rag.proto (RAGStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L186), [rag.proto (RAGStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rag.proto#L189)

**Why:** RETRIEVAL_STARTED, CHUNK_RETRIEVED and CONTEXT_READY are never emitted, so the iOS and Android handlers written against them are dead code and no app can show a 'retrieving' state. `RAGStreamEvent.chunk` exists only to carry the frame that never arrives. Deleting them changes no observable behaviour and makes RAG streaming read exactly like LLM streaming, which the developer already knows. `timestamp_us` claims microseconds and is produced as now_ms()*1000.

**Skeptic verdict:** `risky` — The enum-value deletions are honest (nothing emits 1/2/3), but 'the iOS and Android handlers ... are dead code' understates the blast radius: three hand-written SDK switch statements reference these cases and will fail to COMPILE, not merely go unused, so this is not a no-op rollout. The sharper problem is the timestamp: renaming timestamp_us -> timestamp_ms while KEEPING tag 2 and the int64 type changes the unit silently on an unchanged wire tag -- any consumer that still divides by 1000 now reports a timestamp 1000x too small, with no parse error to catch it. Either move the ms field to a new tag and reserve 2, or keep microseconds and fix the producer to actually measure them.

**What changed:** Cut RAGStreamEventKind to UNSPECIFIED/TOKEN/COMPLETED/ERROR — RETRIEVAL_STARTED, CHUNK_RETRIEVED and CONTEXT_READY are deleted and the survivors renumbered dense to 0..3 per the ground rules — and deleted RAGStreamEvent.chunk, leaving 6 fields at tags 1..6. Per carePlan.correctionNeeded (b) I did NOT rename timestamp_us -> timestamp_ms: the field stays `timestamp_us` in microseconds (comment: "Microseconds since the Unix epoch, matching every other modality") and the fix belongs in the producer at rac_rag_proto_abi.cpp:1048, which must use now_us(). I also wrote no comment claiming the removed kinds are merely dead code — five hand-written switch statements (Swift RagSession.swift:114,119; Kotlin RagSession.kt:202,206; Flutter rag.dart:176,180,196; electron data.ts:362,365; RN Rag.ts:163,166) name them and must be edited first.

**Files touched:** `idl/rag.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Five hand-written switch/when statements name the three deleted enum values and will FAIL TO COMPILE, not merely go unused: Swift sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Rag/RagSession.swift:114 `case .chunkRetrieved` and :119 `case .contextReady`; Kotlin sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/RagSession.kt:202 and :206; Flutter sdk/runanywhere-flutter/packages/runanywhere/lib/public/api/namespaces/rag.dart:176, :180 and :196 (RETRIEVAL_STARTED); electron sdk/runanywhere-electron/src/api/data.ts:362 and :365; React Native sdk/runanywhere-react-nativ…

**Wire safety:** Reserving enum values 1, 2, 3 and RAGStreamEvent tag 5 is wire-safe (nothing emits them: rac_rag_proto_abi.cpp emits only TOKEN at :1069, ERROR at :1077, COMPLETED at :1081, and the single emitter is at :1044). The timestamp is NOT wire-safe as drafted: renaming timestamp_us -> timestamp_ms while keeping tag 2 and int64 changes the UNIT on an unchanged tag, so any consumer still dividing by 1000 …

**Do first:**
  1. Do NOT rename timestamp_us -> timestamp_ms on tag 2. Take the strictly better fix instead: keep the field and the tag, and correct the PRODUCER at sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp:1048 — replace `ev.set_timestamp_us(now_ms() * 1000)` with a real microsecond clock, the same now_us() the other four modalities use (rac_vad_stream.cpp:426, rac_stt_stream.cpp:1377, rac_tts_stream.cpp:350, rac_diffusion_stream.cpp:476). Zero wire change, the name stops lying, and RAG stops being the one modality with a different timestamp field. If you insist on milliseconds, it MUST be a new tag with 2 reserved — never the same tag with a new unit.
  1. Pick the enum path explicitly and write the choice into the proto comment. Cheapest honest option: emit RETRIEVAL_STARTED and CONTEXT_READY from the emitter lambda at rac_rag_proto_abi.cpp:1044 (one call before retrieval, one after the context is assembled) and delete only CHUNK_RETRIEVED + the `chunk` field. That keeps the five SDK switch arms compiling except for the one CHUNK_RETRIEVED case each, keeps the retrieval-progress UI signal, and is the smaller diff.
  1. If instead all three go: land the five SDK edits FIRST, one PR per SDK, each removing the dead switch arms — Swift RagSession.swift:114,119; Kotlin RagSession.kt:202,206; Flutter rag.dart:176,180,196; electron data.ts:362,365; RN Public/Api/Rag.ts:163,166 — then the proto edit, then regenerate. Reversing the order red-builds five repos at once.
  1. Each of those SDK arms currently maps to a public 'retrieved' event; before removing them, point the facade at the COMPLETED frame's result.retrieved_chunks (the pattern Web already uses at Namespaces/rag.ts:148) so the app-visible event stream does not silently lose its sources notification.


</details>


<details>
<summary><strong>rerank</strong> (6 changes)</summary>

### `rr-fix-header` — Fix the file header that promises a service rpc the file does not have

**Proto location:** [rerank.proto (RerankRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rerank.proto)

**Why:** rerank.proto:3-6 says the file mirrors segmentation.proto with 'a service lifecycle rpc'. There is no `service` block and no `rpc` anywhere in the file — those words appear only in that comment — and segmentation.proto has no service block either, so even the comparison is wrong. Lifecycle is entirely the C ABI (rac_rerank_component_create / load_model / unload / get_state / get_metrics / destroy) with scoring crossing as proto bytes through rac_rerank_component_rerank_proto. Cheap confusion, multiplied by six generated languages.

**Skeptic verdict:** `sound`

**What changed:** Rewrote the file header comment to remove the false 'service lifecycle rpc' claim and describe the actual C-ABI lifecycle boundary.

**Files touched:** `idl/rerank.proto`

**Status:** `applied`


### `rr-flat-documents` — Replace RerankCandidate with a flat repeated string documents

**Proto location:** [rerank.proto (RerankCandidate)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rerank.proto), [rerank.proto (RerankRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rerank.proto)

**Why:** RerankCandidate exists only to be constructed and thrown away: all five proto-building facades write the id as the stringified array position (Swift RerankNamespace.swift `candidate.id = String(index)`, Web rerank.ts `documents.map((text, index) => ({ id: String(index), text }))`, RN, Kotlin and Flutter identically), rcli writes `"doc-" + std::to_string(i)`, and the Electron facade already takes bare `documents: string[]` and has no id at all — the flat shape is what every surface already wants. The field name is also wrong: `documents` is universal and `candidates` appears at no vendor, and that rename is free today and permanent once it propagates to six generated languages. The comment also picks up the defensible half of rerank-7, so the request-size ceiling that today lives only in rerank_module.cpp becomes part of the contract.

**Skeptic verdict:** `risky` — The blast radius omits the one consumer that actually parses this field. sdk/runanywhere-commons/src/features/rerank/rerank_module.cpp is the proto->ABI translator: :162 gates on `request.candidates_size() > kMaxCandidates` and :171 iterates `for (const auto& candidate : request.candidates())` to build rac_rerank_candidate_t. If only the sites the proposal lists (five facades, rcli:99, test_rerank.cpp) are changed, this file no longer compiles -- or worse, if someone 'fixes' it by just deleting the block, the 100,000 cap the new comment promises silently stops existing while the comment still advertises it. The proposal's own after-text documents a bound whose only enforcement site it never mentions. Second, moving the payload from tag 2 to tag 4 is a silent-data-loss skew across a prebuilt binary boundary: sdk/runanywhere-swift/Binaries/RACommons.xcframework ships commons as a compiled artifact, so a Swift SDK regenerated with `documents = 4` talking to a not-yet-rebuilt xcframework sends tag 4, commons reads candidates_size() == 0, and the caller gets an empty ranking with RAC_SUCCESS and no error.

**What changed:** Deleted message RerankCandidate. RerankRequest: reserved 2 (candidates) by number+name, added repeated string documents = 4 (fresh tag, not reusing 2 -- reusing would decode submessage bytes as a string).

**Files touched:** `idl/rerank.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The authoritative consumer the proposal omits: sdk/runanywhere-commons/src/features/rerank/rerank_module.cpp — :162 `if (static_cast<size_t>(request.candidates_size()) > kMaxCandidates) return RAC_ERROR_INVALID_PARAMETER;` (kMaxCandidates = 100000 at :32-33), :166 `out_candidates->reserve(request.candidates_size())`, :170-173 `for (const auto& candidate : request.candidates()) out_candidates->push_back(rac_rerank_candidate_t{candidate.id().c_str(), candidate.text().c_str()});`. This is the ONLY enforcement site for the 100,000 cap the new proto comment advertises — if it is deleted rather tha…

**Wire safety:** Tag 2 is retired with `reserved 2; reserved "candidates";` and the payload moves to a NEW tag 4 — correct, and better than reusing tag 2. Re-typing tag 2 from `repeated RerankCandidate` to `repeated string` would NOT be a decode error (both are length-delimited), it would decode a submessage's raw bytes as a UTF-8 string and hand garbage to the model. So keep tag 4 + reserved 2. Tag 3 (`optional …

**Do first:**
  1. Edit idl/rerank.proto FIRST and in one commit with sdk/runanywhere-commons/src/features/rerank/rerank_module.cpp. Port the cap, do not delete it: :162 becomes `request.documents_size() > kMaxCandidates`, :166 becomes `reserve(request.documents_size())`, and :170-173 becomes `for (int i = 0; i < request.documents_size(); ++i) out_candidates->push_back(rac_rerank_candidate_t{nullptr, request.documents(i).c_str()});` — note the C ABI struct rac_rerank_candidate_t still has an `id` field (rac_rerank_types.h:20-23), so decide explicitly whether to pass nullptr or the stringified index, and make rerank_module.cpp:201 `set_id(item.id ? item.id : "")` agree. Do not let the borrowed `c_str()` outlive the request object — the candidates vector is consumed at :244-245 inside the same scope, which is safe today; keep it that way.
  1. Regenerate every binding in the SAME commit (./idl/codegen/generate_all.sh) — CI idl-drift-check.yml fails on any diff. That regenerates sdk/shared/proto-ts/src/rerank.ts, the committed sdk/shared/proto-ts/dist/, rerank.pb.swift, rerank.pb.dart, and the Kotlin Wire output.
  1. Fix the five request builders and rcli in the same commit or those SDKs stop compiling: RerankNamespace.swift:37-39, EmbeddingsNamespace.kt:70-72, Namespaces/rerank.ts:32, Public/Api/Rerank.ts:51-52, embeddings.dart:95-97, cmd_rerank.cpp:99, and tests/test_rerank.cpp:162 + :376.
  1. Decide the fate of the two PUBLIC candidate-taking APIs before writing the proto, because they cannot survive the type deletion: RunAnywhere+Rerank.swift:16 and RunAnywhereRerank.kt:32. Either change both to `documents: [String]` / `List<String>` (and delete the now-dangling public typealias SwiftAliases.kt:79 and the Web re-export RunAnywhere+Rerank.ts:18,135), or keep them as deprecated shims that map strings internally. Swift is the declared source of truth, so land the Swift shape first and mirror it to Kotlin/Web/RN/Flutter.
  1. Rebuild and re-vendor ALL committed prebuilt commons binaries in the same release as the regenerated bindings — this is the silent-data-loss guard, not optional: sdk/runanywhere-swift/Binaries/RACommons.xcframework, sdk/runanywhere-react-native/packages/core/ios/Binaries/RACommons.xcframework, sdk/runanywhere-flutter/packages/runanywhere/ios/runanywhere/Frameworks/RACommons.xcframework, sdk/runanywhere-kotlin/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/librac_commons.so, sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/librac_commons.so. New bindings + old binary = zero documents parsed and an empty ranked list with no error.


### `rr-max-tokens-per-doc` — Add RerankOptions.max_tokens_per_doc and drop the silent 512-token cap

**Proto location:** [rerank.proto (RerankOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rerank.proto)

**Why:** The backend hard-caps every document at min(model context, 512) — engines/llamacpp/rac_rerank_llamacpp.cpp:46 `constexpr int32_t kDefaultMaxTokens = 512;` — and drops the tail with no error and no flag, so a jina-reranker-v2 (8k) or Qwen3-Reranker (32k) buys the app nothing. Meanwhile RerankOptions has exactly one knob, top_n, which by its own comment saves no compute. This is the one remaining parameter the industry kept and the direct on-device knob on peak memory and per-pair latency, so it earns the field it costs.

**Skeptic verdict:** `risky` — The costed work is 'the backend change', but the unmentioned part is an ABI-layout change through a prebuilt binary. A proto option is inert unless it reaches the engine, and it reaches it only via rac_rerank_options_t, which today is a one-field struct with a by-value default constant: rac_rerank_types.h:25-33 declares `typedef struct rac_rerank_options { uint32_t top_n; }` plus `static const rac_rerank_options_t RAC_RERANK_OPTIONS_DEFAULT = { .top_n = 0 };`. Growing that struct changes sizeof across every TU that constructs it -- including sdk/runanywhere-electron/native/addon.cpp:2246 which does `rac_rerank_options_t opts = RAC_RERANK_OPTIONS_DEFAULT;` and links against commons, and the prebuilt RACommons.xcframework. New header + old library is silent stack garbage for the new field, not a link error. Second, this is labelled additive but changes default behaviour for every existing caller: today every document is capped at min(n_ctx_train, 512); '0 = the loaded model's own context length' makes the default 32768 for Qwen3-Reranker, and since n_ctx/n_batch/n_ubatch are all set from that same value at load time, the default allocation grows 64x on a phone. 'needs a note' undersells a 64x default memory change.

**What changed:** Added RerankOptions.max_tokens_per_doc(2), default 0. Per care plan's correction, comment says '0 = the SDK default budget' NOT 'the loaded model's own context length' -- changing that meaning would silently multiply peak memory for every existing caller.

**Files touched:** `idl/rerank.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** sdk/runanywhere-commons/include/rac/features/rerank/rac_rerank_types.h:25-32 is `typedef struct rac_rerank_options { uint32_t top_n; } rac_rerank_options_t;` plus `static const rac_rerank_options_t RAC_RERANK_OPTIONS_DEFAULT = { .top_n = 0 };`. Three sites construct it by value and would change size: sdk/runanywhere-commons/src/features/rerank/rerank_module.cpp:158 (`*out_options = RAC_RERANK_OPTIONS_DEFAULT`), :236 (`rac_rerank_options_t options = RAC_RERANK_OPTIONS_DEFAULT;`, passed by pointer at :245), and — critically, out of tree — sdk/runanywhere-electron/native/addon.cpp:2246 `rac_rera…

**Wire safety:** Additive on the proto wire and safe there: `uint32 max_tokens_per_doc = 2` is a fresh tag in RerankOptions (only tag 1 = top_n exists today), so old readers skip it into unknownFields and old writers simply omit it. No reserved range needed, no renumbering. The unsafe layer is the C ABI, which is not wire-versioned at all: rac_rerank_options_t grows from 4 bytes to 8, and RAC_RERANK_OPTIONS_DEFAU…

**Do first:**
  1. Do NOT change the meaning of 0. The proposed comment '0 = the loaded model's own context length' silently multiplies peak memory for every current caller. Keep 0 = the existing 512 default (rename kDefaultMaxTokens to make that explicit) and require an explicit positive value to raise the budget. If you genuinely want model-context-by-default, ship it as its own change with its own release note and an on-device memory measurement, not folded into an 'additive' field.
  1. Grow rac_rerank_options_t and RAC_RERANK_OPTIONS_DEFAULT together at sdk/runanywhere-commons/include/rac/features/rerank/rac_rerank_types.h:25-32, and append the new member AFTER top_n so the existing field's offset does not move.
  1. Sync all ten vendored copies of rac_rerank_types.h in the same commit as the rebuilt binaries — never a header without its library. The list: the three xcframework slices under sdk/runanywhere-swift/Binaries/, the three under sdk/runanywhere-react-native/packages/core/ios/Binaries/, the three under sdk/runanywhere-flutter/packages/runanywhere/ios/runanywhere/Frameworks/, and sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include/rac/features/rerank/rac_rerank_types.h. Rebuild librac_commons.so for every ABI in both jniLibs trees at the same time.
  1. Rebuild sdk/runanywhere-electron/native/addon.cpp against the new header in the same release — addon.cpp:2246 constructs the struct by value and is the one consumer that lives outside the commons build.
  1. Backend work, in this order: (a) stop clamping at load time — engines/llamacpp/rac_rerank_llamacpp.cpp:364-365 should create the context at the model's trained length so a per-call raise is even possible, and :367-369 must size n_ctx/n_batch/n_ubatch from that; (b) clamp the per-call value inside llamacpp_rerank_rerank and thread it to the truncation at :233-234 and the call sites at :436/:448 instead of handle->max_tokens; (c) if the requested budget exceeds the model's context, clamp rather than error, and log it once.
  1. Forward the field or it is inert: add the read at rerank_module.cpp:176 next to `out_options->top_n = ...`, and add the pass-through in the facades that build RerankOptions — sdk/runanywhere-web/packages/core/src/Public/API/Namespaces/rerank.ts:33 and sdk/runanywhere-react-native/packages/core/src/Public/Api/Rerank.ts:54 (via toRerankOptions), plus the Swift/Kotlin/Flutter equivalents.


### `rr-model-category-and-model-id` — Add MODEL_CATEGORY_RERANK and RerankRequest.model_id so rerank auto-loads

**Proto location:** [model_types.proto (ModelCategory)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto), [rerank.proto (RerankRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rerank.proto)

**Why:** Rerank is the only modality in this SDK that cannot auto-load, and model_types.proto:101-102 says so in a comment ('There is no RERANK member, which is why the rerank primitive cannot auto-load a model'). The consequence is copied into all five facades as a throw: Swift 'Rerank model not loaded', RN 'call RunAnywhere.models.load(id) first', Flutter componentNotReady, Electron 'no rerank model is loaded'. EmbeddingsRequest already has `optional string model_id = 4` for exactly this job, so this is an intra-repo asymmetry as much as an industry gap — and it is the prerequisite for RAG's reranker_model_id, which is rejected today with RAC_ERROR_NOT_IMPLEMENTED because no category exists to resolve a reranker through. Enum value 12 is free (0-11 used, no reserved range) and unset model_id keeps today's behaviour, so nothing existing breaks.

**Skeptic verdict:** `sound`

**What changed:** Added MODEL_CATEGORY_RERANK=12 to model_types.proto ModelCategory (fresh value, no reserved gap). Added RerankRequest.model_id=5 (optional).

**Files touched:** `idl/model_types.proto`, `idl/rerank.proto`

**Status:** `applied`


### `rr-score-contract` — Make relevance_score the [0,1] score its name already promises

**Proto location:** [rerank.proto (RerankScoredItem)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rerank.proto)

**Why:** The field borrows Cohere's exact name but ships Cohere's contract stripped out: the llama.cpp backend hands back the raw classifier logit (`llama_get_embeddings_seq(handle->context, 0)` at engines/llamacpp/rac_rerank_llamacpp.cpp:271, values like 10.67 and -5.08) and the proto comment disclaims any range. Nobody reads a proto comment before autocompleting a familiar field name, so the borrowed name silently produces wrong thresholds. Applying the sigmoid in the backend costs zero new proto surface and makes the name honest; the comment is then the only proto edit needed. Sigmoid is monotone, so ranking is unchanged — this buys a bounded, portable range, not calibration.

**Skeptic verdict:** `risky` — The proposal body is sound but its mandated implementation note is backwards and, if followed literally, creates the exact bug it claims to prevent. sigmoid(-inf) = 0.0, i.e. an empty document already lands at the FLOOR of [0,1] and sorts last. If you instead 'change the empty-document early return to 0.0f' and then run that through the sigmoid at the end of score_sequence, you get 0.5 -- empty documents jump to the middle of the range and outrank every real document whose logit is negative (the observed range includes -5.08). That also flips tests/test_rerank.cpp:349, which asserts `items(0).id() == "full" && items(1).id() == "empty"`. Separately, the proto is not the only place the contract is written: sdk/runanywhere-commons/include/rac/features/rerank/rac_rerank_types.h:39-41 documents the same number as '/** Raw relevance score ... Comparable only within one result set. */' on the backend-facing C ABI, and the proposal does not touch it, so the SDK would ship two contradicting contracts for one value.

**What changed:** Proto comment updated to state [0,1] sigmoid-normalized range. Care plan's actual fix (applying sigmoid at engines/llamacpp/rac_rerank_llamacpp.cpp:275, not the proto adapter) is Phase C work -- flagged for that phase.

**Files touched:** `idl/rerank.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** Two independent read paths carry this number and only ONE of them goes through the proto, so the sigmoid must NOT be applied in the proto adapter. Path A (proto): sdk/runanywhere-commons/src/features/rerank/rerank_module.cpp:202 `destination->set_relevance_score(item.score);` copies the C ABI float straight through; from there sdk/runanywhere-cli/src/commands/cmd_rerank.cpp:130 emits it as the `relevance_score` JSON key and :141 formats it "%.4f" for the table, and the five SDK mappers copy it verbatim (sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Results.swift:283, sdk/runanywhere-ko…

**Wire safety:** No wire change. The proto edit is comment-only: `float relevance_score = 2;` keeps tag 2, type float, same position. Nothing to reserve, no tag reuse. The risk is entirely numeric/behavioural, carried in prebuilt binaries, not in the schema.

**Do first:**
  1. Apply the sigmoid in the ENGINE, not in the proto adapter: change engines/llamacpp/rac_rerank_llamacpp.cpp:275 to `*out_score = 1.0f / (1.0f + std::exp(-scores[0]));`. Do not touch rerank_module.cpp:202 — the Electron N-API path (sdk/runanywhere-electron/native/addon.cpp -> src/api/data.ts:117) reads the C ABI struct and would keep raw logits.
  1. Change ONLY line 243 of the empty-token early return to `*out_score = 0.0f;` and leave its `return RAC_SUCCESS;` on line 244 in place. Add a comment there saying the sigmoid lives at line 275 and this exit deliberately bypasses it. Do NOT refactor score_sequence to a single exit point — that is exactly how 0.0f becomes sigmoid(0)=0.5 and empty documents jump above every negative-logit document.
  1. Update the doc comment on the C ABI so the proto is not the only place the contract is written: sdk/runanywhere-commons/include/rac/features/rerank/rac_rerank_types.h:41 currently documents `float score;` as raw and 'comparable only within one result set'. Change it in lockstep with the proto comment, and mirror the edit into all vendored header copies (see the rr-max-tokens-per-doc plan for the list).
  1. Rebuild and re-vendor the prebuilt commons binaries in the same commit, or apps ship a new comment and old numbers: sdk/runanywhere-swift/Binaries/RACommons.xcframework, sdk/runanywhere-react-native/packages/core/ios/Binaries/RACommons.xcframework, sdk/runanywhere-flutter/packages/runanywhere/ios/runanywhere/Frameworks/RACommons.xcframework, sdk/runanywhere-kotlin/src/main/jniLibs/*/librac_commons.so, sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/*/librac_commons.so.
  1. Write the release note before merging. Every existing caller's numbers change: 10.67 becomes 0.99998, -5.08 becomes 0.0062. Ordering is preserved (sigmoid is monotone) so anyone who only sorts is unaffected; anyone who logged, cached, or compared absolute scores is not.


### `rr-scored-item-two-fields` — Cut RerankScoredItem to {relevance_score, index} by deleting id and rank

**Proto location:** [rerank.proto (RerankScoredItem)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rerank.proto), [rerank.proto (RerankScoredItem)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rerank.proto)

**Why:** Both fields are pure restatements. `rank` is assigned from the emit-loop counter immediately after the stable_sort (engines/llamacpp/rac_rerank_llamacpp.cpp:317 `output->items[i].rank = static_cast<uint32_t>(i);`), so items[i].rank == i always, and RerankResult.items already documents 'Sorted by score descending' — the Electron facade's `.sort((a, b) => a.rank - b.rank)` is re-deriving an ordering the wire already guarantees. `id` is an echo of a candidate id that every facade sets to the array index, so it is a verbatim copy of `index`. No public result type reads either: RankedResult is {index, relevanceScore} in Swift, Kotlin, Web, Flutter and Electron alike. Keeping them also invites a bug class — anyone who filters or re-sorts items (the Web facade already re-sorts) leaves rank stale and now has two disagreeing orderings inside one struct.

**Skeptic verdict:** `sound` — Two of the three named break sites are misattributed, in opposite directions. The Electron bridge does NOT read the proto: addon.cpp:2258-2260 calls the C ABI `rac_rerank_rerank` and projects `result.items[i].rank` off rac_rerank_scored_item_t (rac_rerank_types.h:45), so data.ts:116's `.sort((a, b) => a.rank - b.rank)` keeps working untouched -- listing it as required churn overstates the cost. Conversely the proposal undersells rcli: cmd_rerank.cpp reads `item.rank()` twice, and one of them is inside the `--json` writer (`.field("rank", static_cast<int64_t>(item.rank()))`), so a documented CLI output key disappears. 'rcli should use its own loop counter for the RANK column' covers the table but not the JSON contract. Also note the C ABI keeps both id and rank, so after this lands the proto and the backend-facing struct describe different result shapes.

**What changed:** RerankScoredItem: reserved 1 (id) and 4 (rank) by number+name. Kept relevance_score(2) and index(3). Comment on index updated to reference 'documents' not 'candidates'.

**Files touched:** `idl/rerank.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** `id` has exactly one writer and one reader family, both in-tree: written at sdk/runanywhere-commons/src/features/rerank/rerank_module.cpp:201 `destination->set_id(item.id ? item.id : "")`, read ONLY by sdk/runanywhere-commons/tests/test_rerank.cpp:245, :248, :251, :349, :376, :390. No SDK reads it — all five public RankedResult types are exactly {index, relevanceScore}: sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Results.swift:279-283, sdk/runanywhere-kotlin/.../public/api/Results.kt:116 + MappingResults.kt:153, sdk/runanywhere-web/packages/core/src/Public/API/Results.ts:103 + Mappin…

**Wire safety:** `reserved 1; reserved "id";` and `reserved 4; reserved "rank";` are correct and complete — tag 2 (relevance_score) and tag 3 (index) keep their numbers and types, no renumbering, no oneof, no enum change. This is the SAFEST of the four on the wire: an old prebuilt commons still WRITES tags 1 and 4, and new bindings drop them into unknownFields, so a version-skewed pair degrades to wasted bytes ra…

**Do first:**
  1. Land rr-flat-documents FIRST. Until RerankCandidate is gone, `id` may still carry caller-supplied data (the C ABI struct rac_rerank_candidate_t:20-23 still has an `id` member), and this proposal's own after-text refers to 'the original RerankRequest.documents list', which does not exist yet. Deleting `id` before that lands strands anyone who set a meaningful candidate id.
  1. Fix rcli's --json contract explicitly, do not just drop the key: sdk/runanywhere-cli/src/commands/cmd_rerank.cpp:129 is inside the --json writer. Either keep emitting `"rank"` from the emit-loop counter (preserving the CLI output contract while the proto field goes away) or remove the key and say so in the CLI changelog. :147 (the RANK table column) should use the same loop counter.
  1. Leave sdk/runanywhere-electron/src/api/data.ts:116 and native/addon.cpp:2263 ALONE — they read the C ABI, not the proto. Touching them is churn with a chance of a regression.
  1. Stop writing the dead fields at sdk/runanywhere-commons/src/features/rerank/rerank_module.cpp:201 and :204 in the same commit as the proto edit; leave engines/llamacpp/rac_rerank_llamacpp.cpp:317 alone (the C ABI struct still carries rank) and add a one-line comment at rac_rerank_types.h:45 noting the ABI intentionally keeps a field the proto no longer exposes.
  1. Update sdk/runanywhere-commons/tests/test_rerank.cpp:126, :245-252, :349, :385, :390 — replace the id-based assertions with index-based ones (items(0).index() == 1, etc.), and re-express the :349 empty-document ordering check in terms of index instead of id.
  1. Regenerate all bindings (./idl/codegen/generate_all.sh) and rebuild/re-vendor the prebuilt commons binaries alongside rr-flat-documents' rebuild — one binary refresh covers both, so do them in one release.


</details>


<details>
<summary><strong>routing</strong> (12 changes)</summary>

### `hybrid-annotate-routing-defaults` — Annotate the routing defaults and bounds in the proto, not in five hand-written SDKs

**Proto location:** [hybrid_router.proto (BatteryFilter)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L41), [hybrid_router.proto (ConfidenceCascade)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L57), [sdk_defaults.proto (HybridDefaults)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/sdk_defaults.proto#L239)

**Why:** These three files carry zero rac_* annotations, so every default here lives in hand-written SDK code -- the battery floor of 20 in a TypeScript helper, the confidence threshold of 0.5 in sdk_defaults.proto as a *separate constant* from the field it configures. The Flutter, React Native, Python and CLI bindings generated from these same files will each invent their own or ship the proto3 zero, which is wrong for at least two fields here. This is the mechanism that produced the prefer_local default bug.

**Skeptic verdict:** `no-verdict`

**What changed:** BatteryFilter.min_battery_percent and ConfidenceCascade.threshold already carried rac_default/rac_min/rac_max from an earlier wave. I completed this item myself: deleted the duplicated HybridDefaults message (and its stt_confidence_threshold field) from sdk_defaults.proto -- the earlier wave had annotated the field but left the old duplicate constant in place.

**Files touched:** `idl/sdk_defaults.proto`

**Status:** `applied`


### `hybrid-attempt-timeout-ms` — Add one per-attempt deadline so a slow local model escalates instead of hanging

**Proto location:** [hybrid_router.proto (HybridRoutingPolicy)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L60), [hybrid_router.proto (CloudSttBackendConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L95)

**Why:** The only duration in the domain is CloudSttBackendConfig.timeout_ms, installed once at registration time and applying only to the cloud leg. The policy has no timing field at all, so 'if the on-device model hasn't produced anything in N ms, go to cloud' is inexpressible -- the router waits however long the local engine takes and escalates only on an outright error or a low confidence score. A cold NPU context load or a first-run page-in takes seconds.

**Skeptic verdict:** `no-verdict`

**What changed:** Already landed: HybridRoutingPolicy.attempt_timeout_ms(4), default 0, per-attempt semantics documented.

**Files touched:** `idl/hybrid_router.proto`

**Status:** `applied`

**Care level:** `blocked`

**What could break:** Nothing breaks today — the field is purely additive and has no consumers because it does not exist. The greps below came back empty for any timing concept in the hybrid policy: `rg 'timeout|rank|typedef struct' sdk/runanywhere-commons/include/rac/router/hybrid/rac_hybrid_types.h` lists rac_hybrid_battery_filter (:86), rac_hybrid_custom_filter (:94), rac_hybrid_filter (:105), rac_hybrid_cascade (:128), rac_hybrid_rank (:140), rac_hybrid_routing_policy (:151), rac_hybrid_model_descriptor (:161), rac_hybrid_routing_context (:178), rac_hybrid_routed_metadata (:187) and NO timeout member anywhere.…

**Wire safety:** Purely additive int32 on a new tag; no tag reuse, no reserved range touched, no enum renumbering. Old readers ignore it (unknown field); old writers omit it and get 0 = no deadline = today's behaviour. The only wire hazard is the unexplained tag-5 gap noted above.

**Do first:**
  1. PREREQUISITE (does not exist yet): a per-attempt deadline in the C router. Add `int32_t attempt_timeout_ms;` to rac_hybrid_routing_policy_t (rac_hybrid_types.h:151-155), re-vendor all 12 header copies, and implement abandon-and-advance around the primary attempt at rac_stt_hybrid_router.cpp:303 and the fallback attempt at :352-364. Do not add the proto field before this lands and is device-verified.
  1. Land AFTER hybrid-mode-enum-replaces-prefer-local. Both edit HybridRoutingPolicy's tag space; landing the timeout first means writing `reserved 3` in two separate commits and risking a merge that frees tag 3.
  1. Fix the tag choice: the proposed after-block uses tag 6 and silently skips tag 5. Either use tag 5, or add `reserved 5;` with a note. An unexplained gap is exactly how a tag gets recycled two years from now.
  1. Nail the two semantics in the proto comment, verbatim and non-negotiable: it is a per-ATTEMPT deadline, never the overall request deadline; and 0 means no deadline (which is also the proto3 zero, so old clients keep today's behaviour).
  1. Confirm the deadline is enforceable before promising it: sdk/runanywhere-flutter/.../hybrid_stt_router.dart and the Kotlin README both document cancel() on the hybrid router as a no-op mid-request. If the on-device engine cannot be interrupted, the router must still abandon the attempt and start the next candidate — say so in the comment rather than implying the local work stops.


### `hybrid-audio-format-enum` — Type `audio_format` as the existing AudioFormat enum instead of a bare int32

**Proto location:** [hybrid_router.proto (HybridSttTranscribeOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L102), [model_types.proto (AudioFormat)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L26)

**Why:** The proto comment admits the problem ('Untyped: every other file uses the AudioFormat enum here'), and the two documented numberings are off by one: model_types.proto says PCM=1/WAV=2/MP3=3, HybridTypes.ts says 0=PCM/1=WAV/2=MP3. A caller who follows the TypeScript comment and sends 1 for WAV actually sends PCM, so commons wraps already-WAV bytes in a second WAV header and the cloud vendor gets a malformed file with no error from us. Nothing validates the integer.

**Skeptic verdict:** `risky` — The claim `risk: None on the wire` and `breaking: false` is backwards. Commons casts the raw int32 straight to rac_audio_format_enum_t, which uses the C numbering the TypeScript comment documents -- NOT the proto AudioFormat numbering. Retyping the field to AudioFormat without also adding a proto->C mapping (tts_module.cpp:107/126 already has exactly such a pair) makes every non-zero value shift by one in the wrong direction. Separately, hybrid_router.proto has ZERO imports, so `AudioFormat` does not resolve; the after-block omits `import "model_types.proto";`, which also drags errors.proto + hardware_profile.proto + rac_options.proto + thinking_tag_pattern.proto into a currently standalone file.

**What changed:** Already landed: HybridSttTranscribeOptions.audio_format is AudioFormat (not int32); model_types.proto imported.

**Files touched:** `idl/hybrid_router.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The skeptic is right and the brief's `breaking: false` / `risk: none on the wire` is wrong — but the reason is bigger than a mapping tweak, because the integer crosses into THIRD-PARTY app code. The chain: idl/hybrid_router.proto:103 int32 -> sdk/runanywhere-commons/src/router/hybrid/rac_stt_hybrid_router_proto.cpp:397-398 `options.audio_format = static_cast<rac_audio_format_enum_t>(opt.audio_format())` -> the C numbering at sdk/runanywhere-commons/include/rac/features/stt/rac_stt_types.h:72-79 (PCM=0, WAV=1, MP3=2, OPUS=3, AAC=4, FLAC=5) -> the wrap decision at rac_stt_hybrid_router_proto.cp…

**Wire safety:** No wire-format change: enum and int32 are both varint on tag 3, and serialized 0 still decodes as AUDIO_FORMAT_UNSPECIFIED, preserving the wrap-raw-PCM path. But the SEMANTICS of every non-zero value change (C numbering -> proto numbering), so this is wire-compatible and behaviourally breaking at the same time — the most dangerous combination, because no build or wire check catches it.

**Do first:**
  1. Add `import "model_types.proto";` to idl/hybrid_router.proto and confirm the file still compiles standalone in every generator (idl/codegen/generate_*.sh) — this file has had no imports until now, so the transitive pull-in is a real codegen change, not a formality.
  1. Write an explicit proto AudioFormat -> rac_audio_format_enum_t switch in rac_stt_hybrid_router_proto.cpp, modelled on the existing pair in tts_module.cpp:107/126. Do NOT static_cast. Map UNSPECIFIED(0) and PCM(1) and PCM_S16LE(9) -> RAC_AUDIO_FORMAT_PCM; WAV(2) -> RAC_AUDIO_FORMAT_WAV; MP3(3)->MP3; OPUS(4)->OPUS; AAC(5)->AAC; FLAC(6)->FLAC. Reject OGG(7)/M4A(8) with an explicit rc — the C enum stops at FLAC=5 and casting them today produces garbage.
  1. Land that mapping BEFORE the proto retype, in a commit where the field is still int32, so there is never a build in which a non-zero value is interpreted under the wrong numbering.
  1. Decide and document the boundary handed to app-registered cloud providers. It currently carries the C numbering (Web CloudSttProvider.ts:114, RN CloudSTT.ts:266). Keep it on the C numbering and translate at the proto edge — changing the provider callback's numbering silently breaks every already-shipped custom provider with no compile error.
  1. Update the two docs that publish the wrong numbering as public API: Web HybridTypes.ts:211-213 and RN HybridModel.ts:97-98.


### `hybrid-confidence-optional-not-nan` — Make the confidence floats `optional` and delete the NaN 'no signal' convention

**Proto location:** [hybrid_router.proto (HybridRoutedMetadata)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L80), [hybrid_router.proto (HybridRoutedMetadata)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L81)

**Why:** A plain proto3 float is omitted at 0.0, so 'absent' and 'the engine reported zero confidence' are the same bytes, and the workaround is to write NaN. NaN does not survive the trip: the generated toJSON in the TypeScript and Dart paths emits `NaN`, which JSON.parse rejects; Kotlin/Swift equality on NaN is false; and any SDK author who forgets the isnan guard reads 'no score' as 'zero confidence', which with a confidence cascade installed escalates every request to the cloud.

**Skeptic verdict:** `sound` — Sound, with one misdescribed mechanism. `JSON.stringify(NaN)` yields `null`, not the token `NaN`, so the specific 'JSON.parse rejects it' failure does not happen on the TypeScript path; canonical protobuf JSON encodes it as the string "NaN". The real hazards -- NaN != NaN in Kotlin/Swift equality, and any SDK that forgets the isnan guard reading 'no signal' as 0.0 -- are both genuine and are enough to carry the change on their own.

**What changed:** Already landed: HybridRoutedMetadata.confidence(6) and primary_confidence(7) both optional float, NaN convention comment removed.

**Files touched:** `idl/hybrid_router.proto`

**Status:** `applied`


### `hybrid-delete-dead-surface` — Delete the four dead members of hybrid_router.proto and reserve their tags

**Proto location:** [hybrid_router.proto (HybridModelDescriptor)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L70), [hybrid_router.proto (HybridFilter)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L33), [hybrid_router.proto (HybridFilter)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L28), [hybrid_router.proto (HybridRoutingContext)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L86)

**Why:** Four of 44 fields do nothing, and one of them lies: HybridTypes.ts documents `HybridModelDescriptor.provider` as selecting the cloud HTTP backend, but commons' parse_descriptor never reads it, so `onlineCloud(id, provider: 'deepgram')` silently gets whatever provider the credential registry recorded. `quality_tier` is a comment admitting it is a no-op, `error_msg` is never set, `HybridRoutingContext` is an empty message every caller must still construct, and tag 2 is a retired PRIVACY filter with no `reserved` guard.

**Skeptic verdict:** `risky` — The 'four of 44 fields do nothing' framing is the over-eager dead-surface pattern. Only `provider` and `HybridRoutingContext` are one-sided. `quality_tier` is parsed by commons into a live filter kind and is reachable from a documented public builder (HybridFilter.quality(tier:)) in all five SDKs -- it is a no-op, which is not the same as dead. `error_msg` has three live readers. Bundling four deletions with materially different consumer profiles behind one 'approve' hides that this is a five-SDK public-API break plus a commons switch-case deletion, while the risk section names only the HybridRoutingContext regeneration. Separately the cited precedent is invented: OpenRouter has no `fallbacks` parameter (it has `models: []` and the deprecated `route: 'fallback'`), so there is no documented HTTP 400 for sending both -- and the claim is irrelevant to deleting no-ops anyway.

**What changed:** Already landed: quality_tier, HybridRoutingContext, and error_msg are all gone from the file (no-backcompat rewrite, not staged reserves).

**Files touched:** `idl/hybrid_router.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The bundle mixes one genuinely one-sided member with three live ones. Verified per member. (a) HybridRoutingContext — SAFE, one-sided, but constructed by all five SDKs and every one must be edited: Kotlin HybridSttRouterProto.kt:17,41 `context = HybridRoutingContext()`, Flutter hybrid_stt_router.dart:190 `context: pb.HybridRoutingContext()`, RN HybridSTTRouter.ts:243 `context: {}`, Swift HybridSTTRouter.swift:316 `request.context = RAHybridRoutingContext()`, Web HybridTypes.ts:301 `const context: HybridRoutingContext = {}`. (b) `provider` — written by all five and read by none: Swift HybridMo…

**Wire safety:** Every deleted tag must be reserved by number AND by name: HybridFilter `reserved 2, 3; reserved "quality_tier";` (2 = retired PRIVACY, see rac_hybrid_types.h), HybridModelDescriptor `reserved 4; reserved "provider";`, HybridSttTranscribeRequest `reserved 2; reserved "context";`. No field numbers are being reassigned. Removing HybridRoutingContext changes HybridSttTranscribeRequest's generated sha…

**Do first:**
  1. SPLIT this into four independent landings. Do not merge them as one 'approve' — their consumer profiles are not comparable and bundling hides a five-SDK public break behind a 'dead surface' label.
  1. Landing 1 (routine, do now): delete HybridRoutingContext + its tag-2 field on HybridSttTranscribeRequest with `reserved 2; reserved "context";`, and delete the five construction sites listed above in the same PR.
  1. Landing 2 (routine, do now): add `reserved 2; reserved "privacy";` to HybridFilter for the already-retired PRIVACY tag. This is pure guard, no consumer, and should not wait on anything.
  1. Landing 3 (sequenced): delete `provider` (tag 4) only after the five SDK write sites, the four doc blocks and examples/ios/.../STTViewModel.swift:358 are updated in the same release. Removing the parameter from onlineCloud() is the source-breaking part, not the proto edit.
  1. Landing 4 (do NOT do as proposed): leave `quality_tier` alone until RAC_HYBRID_FILTER_QUALITY is removed from rac_hybrid_types.h:72,109 and re-vendored into all 12 header copies, and the five public HybridFilter.quality(...) builders are deprecated through a release. Deleting the proto field first leaves commons' switch case at rac_stt_hybrid_router_proto.cpp:169-171 referencing a symbol that no longer exists.
  1. Drop `error_msg` from this proposal entirely. Open the opposite change instead: add the missing `set_error_msg` writer in commons so the five existing readers stop printing bare rc codes.
  1. Drop the OpenRouter `fallbacks` / HTTP-400 precedent from any comment or commit message — the skeptic verified it is invented (OpenRouter has `models: []` and the deprecated `route: 'fallback'`), and it is irrelevant to deleting no-ops.


### `hybrid-engine-name-is-a-string` — One type for 'which engine': delete HybridBackendKind, use the engine-name string in both files

**Proto location:** [hybrid_router.proto (HybridBackendKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L19), [hybrid_router.proto (HybridModelDescriptor)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L69), [connect.proto (ConnectModelDescriptor)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/connect.proto#L103), [router.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/router.proto#L29)

**Why:** The same concept -- which engine runs this -- is a closed 5-value enum in hybrid_router.proto and a bare string in connect.proto, and two of the enum's five values (OPENROUTER, LLAMACPP) name nothing reachable from the only wired capability. Every SDK converts the enum straight back to the engine-name string that rac_plugin_find_for_engine() actually pins on, and an app-registered provider from registerCloudProvider('my-vendor') can never be named here at all. The review contains both this finding and its mirror image (make connect's string an enum) -- answering the question once, the same way, in both files is the whole point.

**Skeptic verdict:** `risky` — The direction is defensible and the precedent is real, but the after-block hides two costs the risk section never names. (1) It renames connect.proto's `framework` -> `engine`; that is tag-compatible but changes the proto JSON name, and ConnectModelDescriptor is a CROSS-DEVICE discovery payload carrying its own protocol_version handshake (connect.proto:96-114), so an old peer and a new peer are exactly the case a rename must be reasoned about, and it is not. (2) The C descriptor struct rac_hybrid_model_descriptor_t stores backend as a fixed enum, so 'string engine' is an ABI change to a RAC_API struct, not a proto-only edit.

**What changed:** Already landed: HybridBackendKind enum deleted, HybridModelDescriptor.engine (string, tag 3) replaces backend. Did NOT touch connect.proto's ConnectModelDescriptor.framework -- per care plan's explicit split-out (cross-device wire payload with its own protocol_version handshake, different risk class).

**Files touched:** `idl/hybrid_router.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Two costs the risk section never names, both real. (1) C-ABI: `rac_hybrid_model_descriptor_t` stores `rac_hybrid_backend_kind_t backend;` at sdk/runanywhere-commons/include/rac/router/hybrid/rac_hybrid_types.h:164 (enum values at :47-51 of the same family). Replacing a fixed-width enum with a string changes the size and layout of a RAC_API struct, which breaks every prebuilt binary shipping today: sdk/runanywhere-swift/Binaries/RACommons.xcframework/{ios-arm64,ios-arm64-simulator,macos-arm64}, sdk/runanywhere-react-native/packages/core/ios/Binaries/RACommons.xcframework/{ios-arm64,ios-arm64-s…

**Wire safety:** Deleting an enum type is not itself a wire change, but HybridModelDescriptor.backend moves from varint tag 3 to a length-delimited string on a NEW tag 5 — tag 3 must be `reserved 3;` and must never be reused, because an old writer's varint on tag 3 would be silently misread as a string field otherwise. Tag 4 (provider) reserved in the same edit. connect.proto's rename keeps tag 3 and type `string…

**Do first:**
  1. Split the connect.proto rename OUT of this item and do it separately or not at all. `framework` -> `engine` on a cross-device discovery payload (connect.proto:96-114) is a different risk class from a same-process descriptor. If it is kept, first prove the peers only ever exchange binary protobuf (not JSON) across the Connect transport, and gate the rename behind the existing protocol_version handshake rather than shipping it silently.
  1. Change the C struct first, in its own commit: make `rac_hybrid_model_descriptor_t.backend` a `const char* engine` (or a fixed char[N] to avoid an ownership question), and rebuild + re-commit ALL nine RACommons.xcframework header/binary sets plus the two hand-vendored header copies. Anything less and Swift/RN/Flutter link against a struct with a different layout — a silent memory bug, not a build error.
  1. Add the validation the enum used to give for free, in the same commit: reject an unknown engine string at wiring time via the plugin registry (rac_plugin_find_for_engine), so 'llama.cpp' vs 'llamacpp' fails loudly at setPair rather than silently at transcribe.
  1. Only then edit idl/hybrid_router.proto: delete HybridBackendKind, add `string engine = 5;` to HybridModelDescriptor, `reserved 3, 4; reserved "backend", "provider";` (tag 4 coordinates with hybrid-delete-dead-surface landing 3 — reserve both in one edit so the two changes cannot race).
  1. Delete the four per-SDK mapping tables (RN HybridModel.ts:75-84, Flutter hybrid_model.dart:93, Kotlin HybridModel.kt, Swift HybridModel.swift) in the same release, and keep the public factory names (offlineSherpa/onlineCloud) so app code does not have to change even though the underlying type did.


### `hybrid-mark-api-key-secret` — Mark `api_key` as a secret so generated toString/toJSON stops printing it

**Proto location:** [hybrid_router.proto (CloudSttBackendConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L92), [rac_options.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/rac_options.proto#L53)

**Why:** `api_key` sits in a generated message whose toJSON/toString/description print every field. One `Log.d(TAG, config.toString())` or one React Native redbox and a customer's subscription key is in logcat -- in a repo that already has a check-no-pii-logging CI gate. Nothing in the IDL marks the field, so a codegen author has no way to know.

**Skeptic verdict:** `fabricated` — The after-block applies `[(runanywhere.v1.rac_secret) = true]` as though it were an existing project convention. It is invented -- the option does not exist in rac_options.proto -- and hybrid_router.proto imports nothing, so it would need both a new extension definition and a new import. The underlying observation (api_key is a secret and should be annotated) is correct and worth doing; the proposal as written is a non-compiling edit that also silently becomes load-bearing for hybrid-fold-cloud-config-into-descriptor, which cites it as its mitigation for per-request credentials.

**What changed:** Already landed correctly: plain SECRET comment on api_key, NOT the fabricated rac_secret option the raw proposal wanted (confirmed rac_secret does not exist anywhere in rac_options.proto or hybrid_router.proto).

**Files touched:** `idl/hybrid_router.proto`

**Status:** `applied`

**Care level:** `blocked`

**What could break:** The annotation as written does not compile, and the leak it targets is not actually in the proto. Verified: `rg 'rac_secret|redacted|wire.redacted' idl/` returns NOTHING, and idl/rac_options.proto:27-42 is the complete FieldOptions extension set — rac_default 50001, rac_required 50002, rac_min 50004, rac_max 50005, rac_min_float 50006, rac_max_float 50007 (50003 is an unexplained hole; do not claim it without checking git history). EnumValueOptions at :44-53 are rac_display_name 50010 / rac_analytics_key 50011 / rac_wire_string 50012. idl/hybrid_router.proto has no imports, so the option woul…

**Wire safety:** No wire change. A field option is metadata in the descriptor, not on the wire; the comment-only version changes nothing at all. Field numbering in CloudSttBackendConfig is untouched.

**Do first:**
  1. Ship the minimum version NOW, which is routine and unblocked: the SECRET comment on idl/hybrid_router.proto:92 alone, with no option syntax, plus a per-SDK toString/description/toJSON override on CloudSttBackendConfig that prints a fixed redaction marker.
  1. Cover the JSON path in the same PR — it is the actual leak. Redact `api_key` in the Kotlin config blob at Cloud.kt:244-253 when it is logged, and make CloudSttProvider's request type (CloudSttProvider.kt:62) non-printable. Doing the proto comment without this is theatre.
  1. PREREQUISITE for the annotation form: a separate, cross-domain proposal that adds a `bool rac_secret` FieldOptions extension to idl/rac_options.proto (next free number after the existing set — use 50008, not the 50003 hole, unless git history proves 50003 was never used) AND teaches the 8 generators to honour it. Until that exists the annotation is decoration and must not be written.
  1. Extend scripts/validation/commons/check_no_pii_logging.sh to fail on any log/print of a field named api_key/apiKey, so the guarantee is machine-checked rather than a convention.


### `hybrid-mode-enum-replaces-prefer-local` — Replace `bool prefer_local` with Firebase's four-value inference mode enum

**Proto location:** [hybrid_router.proto (HybridRoutingPolicy)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L63), [hybrid_router.proto (HybridRoutingPolicy)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L60)

**Why:** A bool has two states and both of them mean 'preference', so 'transcribe on the device and fail loudly if you can't' is not expressible at all -- a cold model or an OOM silently ships the user's audio to a third party. Worse, the proto3 zero of `prefer_local` is false, which commons reads as 'try the cloud first', so the wire default is the unsafe one and five SDKs hand-patch `?? true` in before serializing. An Android developer already has the four Firebase constant names in muscle memory.

**Skeptic verdict:** `sound` — Two calibration notes, neither fatal. (a) The precedent's container is misnamed: Firebase carries `mode` on HybridParams alongside inCloudParams/onDeviceParams, not on an 'OnDeviceConfig.mode'. The four constant names are right. (b) The risk section says only 'the commons rank mapping change', but the C layer has no representation for ONLY_*: rac_hybrid_routing_policy_t.rank is a two-value PREFER_LOCAL_FIRST/PREFER_ONLINE_FIRST enum and rac_stt_hybrid_router.cpp has no fail-instead-of-fall-back path. The safety value that justifies the whole change is the one the current C layer cannot express, so this is a C-ABI change, not a proto edit plus a mapping tweak.

**What changed:** Already landed by an earlier wave: HybridInferenceMode enum added, HybridRoutingPolicy.mode(3) replaces prefer_local (which is gone -- no-backcompat means no reserved needed since the whole field/tag was freely reassigned in the same file rewrite).

**Files touched:** `idl/hybrid_router.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** This is a C-ABI change, not a proto edit. (1) The ONLY decoder is sdk/runanywhere-commons/src/router/hybrid/rac_stt_hybrid_router_proto.cpp:225-226 (`policy.rank = msg.prefer_local() ? RAC_HYBRID_RANK_PREFER_LOCAL_FIRST : RAC_HYBRID_RANK_PREFER_ONLINE_FIRST`). (2) The ONLY reader of `rank` is sdk/runanywhere-commons/src/router/hybrid/rac_stt_hybrid_router.cpp:123 and :126. (3) The safety value that justifies the change is unrepresentable downstream: `rac_hybrid_rank_t` is a two-value enum at sdk/runanywhere-commons/include/rac/router/hybrid/rac_hybrid_types.h:140-144, embedded as `rank` in `r…

**Wire safety:** Tag 3 is retired and MUST be `reserved 3; reserved "prefer_local";` — never reused. New field takes tag 4 (unused today). A stale client still writing tag 3 (varint bool) hits a reader with tag 3 reserved, so it lands in unknown fields and is ignored, which decodes as mode=UNSPECIFIED=PREFER_ON_DEVICE — i.e. the safe value. That is the intended behaviour and must be pinned by a test, not assumed.…

**Do first:**
  1. Extend the C layer FIRST, in its own commit, before the proto is touched: replace `rac_hybrid_rank_t` (rac_hybrid_types.h:140-144) with a four-value `rac_hybrid_inference_mode_t` whose 0 is PREFER_ON_DEVICE, and keep `rank`'s field offset/size in `rac_hybrid_routing_policy_t` identical (int-sized enum) so struct layout does not move.
  1. Implement the fail-instead-of-fall-back path in rac_stt_hybrid_router.cpp: guard the fallback escalation at :352-364 and the cascade escalation at :328-343 on the mode, and return an error rc for ONLY_ON_DEVICE / ONLY_IN_CLOUD instead of crossing the boundary. Without this the enum is decoration and the privacy guarantee is a lie.
  1. Re-vendor rac_hybrid_types.h into all 11 copies listed by `find sdk -name rac_hybrid_types.h` in the same commit as the header change (see MEMORY: vendored-header drift is a recurring trap here).
  1. Only then edit idl/hybrid_router.proto: add HybridInferenceMode, add `mode = 4`, `reserved 3; reserved "prefer_local";`.
  1. Update rac_stt_hybrid_router_proto.cpp:225-226 to map msg.mode() -> the new C enum, and make the UNSPECIFIED case decode to PREFER_ON_DEVICE explicitly (do not rely on the numeric zero coinciding).
  1. Regenerate sdk/shared/proto-ts/src/hybrid_router.ts and sdk/runanywhere-commons/src/generated/proto/hybrid_router.pb.* and commit them with the proto.
  1. Land the five SDK policy builders in one release: Swift HybridRoutingPolicy.swift, Kotlin HybridRoutingPolicy.kt, Web HybridTypes.ts, RN HybridRoutingPolicy.ts, Flutter hybrid_routing_policy.dart. Delete the `?? true` / `= true` default patches — the enum zero now carries that meaning.
  1. Update the three example apps (SttViewModel.kt:346, STTViewModel.swift:362, stt_view_model.dart:418) in the same PR or the sample builds break.
  1. Fix the brief's own container mis-citation before writing the comment: Firebase carries `mode` on HybridParams (alongside inCloudParams/onDeviceParams), not on an 'OnDeviceConfig'. The four constant names are correct; do not name a container in the proto comment.


### `hybrid-policy-models-chain` — Replace the hardcoded offline/online pair with one ordered `models` chain

**Proto location:** [hybrid_router.proto (HybridRoutingPolicy)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L60), [hybrid_router.proto (HybridModelDescriptor)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L66)

**Why:** There is no chain field anywhere: candidates enter through two separate C entrypoints that each take exactly one descriptor, and the whole ordering vocabulary is a single bool. This SDK's own strongest case is the one a pair cannot express -- an NPU bundle first, a llama.cpp CPU bundle if the NPU context fails to load, cloud last. Today the app runs the router twice and stitches the results, losing the routed metadata for the first hop.

**Skeptic verdict:** `no-verdict`

**What changed:** Already landed: HybridRoutingPolicy.models(5), repeated HybridModelDescriptor, replaces the offline/online pair.

**Files touched:** `idl/hybrid_router.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** The whole candidate-entry surface, in C, in WASM, and in five SDKs. (1) Two C entrypoints each take exactly one descriptor and are exported ABI: `rac_stt_hybrid_router_set_offline_service_proto` and `rac_stt_hybrid_router_set_online_service_proto`, called through parse_descriptor at sdk/runanywhere-commons/src/router/hybrid/rac_stt_hybrid_router_proto.cpp:332 and :345. (2) The Web build has a hand-maintained exported-symbol allowlist that names them literally: sdk/runanywhere-web/wasm/CMakeLists.txt:632-634 and sdk/runanywhere-web/packages/core/src/Public/Extensions/Hybrid/HybridWasmModule.ts…

**Wire safety:** Additive: `repeated HybridModelDescriptor models = 7` on a new tag; old readers ignore it, old writers omit it. The wire hazard is coordination, not the field: three items in this brief (mode=4, attempt_timeout_ms=6, models=7) all edit HybridRoutingPolicy and all restate `reserved 3`. Write the full tag map — 1, 2, reserved 3, 4, 5?, 6, 7 — once, in the first item to land, so no later item re-der…

**Do first:**
  1. Land hybrid-mode-enum-replaces-prefer-local FIRST and completely. `mode` is what governs whether the chain may cross the on-device/cloud line; shipping the chain without it produces chains nobody can pin, and both changes edit the same tags in HybridRoutingPolicy.
  1. Decide the metadata story before the field. HybridRoutedMetadata carries exactly ONE failed-primary triple (primary_error_code/message/confidence). Either add a repeated per-attempt record or state explicitly that only the last failure is reported — otherwise the chain silently loses the diagnostics the current pair preserves, which is the exact complaint that motivates the change.
  1. Add an N-candidate loop in commons alongside the existing two-slot path, behind the presence of `models`, before deleting anything. When `models` is empty, fall back to the offline/online slots so already-shipped apps keep working through at least one release.
  1. Keep `rac_stt_hybrid_router_set_offline_service_proto` / `_set_online_service_proto` exported and functional during that release. If they must eventually go, edit sdk/runanywhere-web/wasm/CMakeLists.txt:632-634 and HybridWasmModule.ts:57-73,167-169 in the SAME commit as the C change.
  1. Only then add `repeated HybridModelDescriptor models = 7;`. Note the after-block's tag choice leaves tag 5 unaccounted for (see hybrid-attempt-timeout-ms) — settle the HybridRoutingPolicy tag map once, across all three items, before any of them lands.


### `hybrid-rename-is-local-to-on-device` — Rename `is_local` to `is_on_device` -- adopt the industry's on-device/in-cloud words

**Proto location:** [hybrid_router.proto (HybridModelDescriptor)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L68), [hybrid_router.proto (HybridModelDescriptor)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L66)

**Why:** One concept wears three names across this stack: local/remote in the proto, offline/online in the C layer, offlineSherpa()/onlineCloud() in the SDK builders. 'Offline' is the worst of them, because in this same file it already means 'the network is down' -- the network filter reads exactly that. A Kotlin developer gets `isLocal` here and `InferenceMode.PREFER_ON_DEVICE` in the platform API next to it.

**Skeptic verdict:** `sound` — The Firebase/Android ON_DEVICE-IN_CLOUD precedent that carries the argument is real and correctly described, and the offline/online overload in evaluate_filter is a genuine defect rather than taste. One supporting citation is invented: Apple's Foundation Models framework exposes SystemLanguageModel, but there is no public API type named PrivateCloudComputeLanguageModel. Drop that clause rather than the proposal. Also note this must ship in the same release as the mode enum as the proposal says, because it is a pure symbol break across eight generated languages with zero wire change -- there is no partial-adoption path.

**What changed:** Already landed: is_local -> is_on_device (tag 2).

**Files touched:** `idl/hybrid_router.proto`

**Status:** `applied`


### `hybrid-served-on-device-flag` — Add one boolean saying which side served the request: `served_on_device`

**Proto location:** [hybrid_router.proto (HybridRoutedMetadata)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/hybrid_router.proto#L74)

**Why:** The single claim this SDK exists to support -- 'this was processed on your device' -- can only be made today by string-comparing `chosen_model_id` against an id the app happens to remember from setPair. Change the id, register a custom provider, or add a third candidate and the privacy badge lies. The STT telemetry row already records a routed backend, so the fact exists; it just is not returned.

**Skeptic verdict:** `no-verdict`

**What changed:** Already landed: HybridRoutedMetadata.served_on_device(8), bool.

**Files touched:** `idl/hybrid_router.proto`

**Status:** `applied`


### `router-proto-delete-dead-capability-query` — Delete router.proto -- a two-message capability query with zero callers in any SDK

**Proto location:** [router.proto (FrameworksForCapabilityRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/router.proto#L22), [router.proto (FrameworksForCapabilityResponse)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/router.proto#L28)

**Why:** Nothing calls it. The Kotlin `external fun` that would bind to the implemented C entrypoint has been deleted -- only the explanatory comment survives at RunAnywhereBridge.kt:1665-1671 -- and Swift, Web, Flutter and React Native ship the generated types with nothing that invokes them. No proto in the IDL imports router.proto. A newcomer reading the routing domain meets a whole file, in 8 generated languages, that answers a question no caller asks.

**Skeptic verdict:** `sound` — The dead-surface claim survives verification -- this is the one deletion in the batch whose consumer search actually comes back empty, and the proposal already discloses the surviving third consumer (rac_router_frameworks_for_capability_proto is declared RAC_API in rac_router_capabilities.h:47, so anyone linking commons directly loses an exported symbol) and offers the smaller step. Two additions: the JNI shim at runanywhere_commons_jni.cpp:7102 is compiled and shipped today, so the JNI table changes too; and generate_swift.sh:34, generate_dart.sh:84 and generate_ts.sh:52 each carry a comment saying router.proto was deliberately ADDED to their inclusion list, which is evidence of recent intent to expose it -- worth confirming with the author of those lines before deleting.

**What changed:** Deleted idl/router.proto entirely (zero importers confirmed via grep across idl/*.proto before deletion). Note: the C-ABI symbols this care plan flagged (RACommons.exports:411-412, the JNI shim, rac_router_capabilities.h) are Phase C/D cleanup -- the proto-level deletion is the piece in scope here.

**Files touched:** `idl/router.proto (deleted)`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The proto really is callerless — this is the one deletion in the batch whose consumer search comes back empty — but the C surface underneath it is shipped and exported. Empty results: no proto imports it (`rg 'router\.proto' idl/` hits only the three codegen script comments), and no SDK invokes it — the only Kotlin trace is the explanatory comment at sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/native/bridge/RunAnywhereBridge.kt:1667, with no `external fun`. Non-empty, and this is what care means here: (1) sdk/runanywhere-commons/exports/RACommons.exports:411-412 lists `_rac_rou…

**Wire safety:** No wire change and no tag reuse — the entire file goes, and nothing imports it, so no reserved ranges are needed. `SDKComponent` and `InferenceFramework` live in other protos and are unaffected. The compatibility surface being removed is the C ABI (two exported symbols) and the JNI method table, not protobuf.

**Do first:**
  1. Ask the author of idl/codegen/generate_ts.sh:52, generate_dart.sh:84 and generate_swift.sh:34-36 before deleting. Those three comments say router.proto was deliberately added to the inclusion list 'for symmetry' — that is a recent decision pointing the other way, and it is the cheapest thing to check.
  1. Take the smaller step first, as the proposal itself offers: stop generating router.proto in the 8 SDKs (edit the three codegen inclusion lists), mark the proto internal, and leave the C entrypoint alone. That reclaims the generated-binding cost with zero ABI risk and is reversible.
  1. If full deletion is confirmed, do it in this order and in one release: (a) delete the JNI shim at runanywhere_commons_jni.cpp:7095-7102, (b) delete rac_router_capabilities.cpp:140,210 and the RAC_API declarations at rac_router_capabilities.h:47,56, (c) remove lines 411-412 from sdk/runanywhere-commons/exports/RACommons.exports, (d) re-vendor sdk/runanywhere-react-native/.../jniLibs/include/rac/router/rac_router_capabilities.h, (e) delete idl/router.proto and the per-SDK generated files, (f) update sdk/runanywhere-swift/ARCHITECTURE.md:2079 and drop the stale comment at RunAnywhereBridge.kt:1663-1671.
  1. Announce the two removed exported symbols in the release notes — RACommons.exports is a public contract for direct linkers, and 'nothing in this repo calls it' is not the same as 'nothing calls it'.


</details>


<details>
<summary><strong>segmentation</strong> (5 changes)</summary>

### `seg-add-confidence-mask` — Add an opt-in per-pixel confidence mask to SegmentationResult

**Proto location:** [segmentation.proto (SegmentationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/segmentation.proto), [segmentation.proto (SegmentationResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/segmentation.proto)

**Why:** The winning logit is already computed per pixel in onnx_segmentation_provider.cpp (best_value at ~line 518) and thrown away at the next line, so this is a field, not a model, standing between an app and the mainstream on-device use case. A hard argmax id gives a jagged 1-pixel edge with no alpha to feather. One byte per pixel keeps it affordable (MediaPipe's float32-per-category is K x 4 bytes; ours is 1). Options field count does not grow if the diagnostic deletion also lands, in which case field 1 becomes `reserved 1;` and SegmentationOptions is again a one-field message.

**Skeptic verdict:** `sound` — Under-scoped, and it silently collides with seg-drop-diagnostic-rgba. (a) The risk section names only "the ONNX provider softmax" plus commons length validation, but a confidence mask cannot reach the proto without also growing the C ABI: rac_segmentation_options_t (rac_segmentation_types.h:31-33, currently a single rac_bool_t) and rac_segmentation_result_t (:46-57) must both gain members, which changes the struct layout that engines/onnx, sdk/runanywhere-python/native/module.cpp and sdk/runanywhere-electron/native/addon.cpp are compiled against and that the Web SDK reads via runtime offset functions. That is a plugin-ABI-touching change, not `effort: medium` proto work. (b) This proposal's `after` keeps `bool include_diagnostic_rgba = 1;` while seg-drop-diagnostic-rgba's `after` replaces it with `reserved 1;`, yet both declare `dependsOn: []`. Applied in either order the second patch's `before` no longer matches.

**What changed:** Added `bool include_confidence = 2;` to SegmentationOptions and `optional bytes confidence_mask_u8 = 8;` to SegmentationResult, each with the brief's verbatim comment. No existing tag was moved; seg-drop-diagnostic-rgba is not in this brief so include_diagnostic_rgba stays at tag 1 and include_confidence stays at tag 2 exactly as the ordering trap requires.

**Files touched:** `segmentation.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** This is NOT proto-only work; the field cannot reach any app without growing the C ABI structs in sdk/runanywhere-commons/include/rac/features/segmentation/rac_segmentation_types.h:31-33 (rac_segmentation_options_t, today a single rac_bool_t) and :46-57 (rac_segmentation_result_t). Everything compiled against those layouts is in the blast radius: engines/onnx/onnx_segmentation_provider.cpp (the producer; the winning logit is at ~:518 and the summary write at :572), sdk/runanywhere-commons/src/features/segmentation/rac_segmentation_service.cpp:114 (rac_segmentation_result_free -- if it does not…

**Wire safety:** No tag reuse, no renumbering, no reserved range touched. SegmentationOptions currently uses only tag 1 (idl/segmentation.proto:42), so `include_confidence = 2` is free. SegmentationResult maxes at tag 7 (:60-66), so `confidence_mask_u8 = 8` is free. Neither name appears anywhere in the file. Both new fields are additive and optional-by-effect, so an older app decoding a newer message just ignores…

**Do first:**
  1. Decide the ordering with seg-drop-diagnostic-rgba FIRST and write it in the PR description. The two `after` blocks conflict: this one keeps `bool include_diagnostic_rgba = 1;`, the other replaces it with `reserved 1;`. Whichever lands second must be hand-rebased on the first -- never apply both `after` blocks mechanically, and never renumber include_confidence off tag 2.
  1. APPEND the new members at the END of both structs in sdk/runanywhere-commons/include/rac/features/segmentation/rac_segmentation_types.h -- never insert mid-struct. Options gets `rac_bool_t include_confidence;` after include_diagnostic_rgba (:32); result gets `uint8_t* confidence_mask; size_t confidence_mask_size;` after `char* model_id;` (:56). Add `.include_confidence = RAC_FALSE,` to RAC_SEGMENTATION_OPTIONS_DEFAULT at :35-37 so every existing designated-initializer caller keeps compiling with the old behaviour.
  1. In the SAME commit as the struct change, add the free to rac_segmentation_result_free (sdk/runanywhere-commons/src/features/segmentation/rac_segmentation_service.cpp:114). A struct member added without its free is a per-inference width*height leak that no test will catch.
  1. Sync the hand-vendored Swift header sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/rac_segmentation_types.h:31-57 by hand in the same commit, and re-run the XCFramework/Android builds so the 9 generated header copies under */RACommons.xcframework/*/Headers/ and sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include/ are regenerated rather than left stale.
  1. Implement the softmax in engines/onnx/onnx_segmentation_provider.cpp at the existing best_value site (~:518), gated on options.include_confidence, and allocate the buffer through the same checked_mul overflow guard the diagnostic_rgba path already uses (it guards pixel_count * 4; here the multiplier is 1, but keep the guard for the malloc size).
  1. Mirror the diagnostic_rgba present-iff check for the new buffer in result_to_proto (sdk/runanywhere-commons/src/features/segmentation/segmentation_module.cpp:199-260). The existing rgba check is `(requested && (!ptr || size != rgba_size)) || (!requested && size != 0)` -> RAC_ERROR_ENCODING_ERROR; the confidence expectation is width*height, NOT width*height*4. Getting that constant wrong is the single easiest bug here.
  1. Map the new option in options_from_proto (segmentation_module.cpp:163-168) so the flag actually reaches the provider; without this the field is exactly the dead surface this pass is deleting elsewhere.
  1. Only after commons is green, extend the public surfaces in this order -- proto-path SDKs first (Swift Public/API/Options.swift:480-489 + Public/API/Results.swift; Kotlin MappingOptions.kt / MappingResults.kt; Flutter public/api/types/options.dart + results.dart; React Native Public/Api/Options.ts + Results.ts; Web Public/API/Options.ts:185, Results.ts:148-149, Mapping.ts:528, Namespaces/segmentation.ts:83 and the length assertion in Public/Extensions/RunAnywhere+Segmentation.ts:90-91), then the struct-path SDKs (Python native/module.cpp:1645-1701 + :2312, runanywhere/_native/_core.pyi:138, runanywhere/_handles.py:387-401, runanywhere/api/segmentation.py:68; Electron native/addon.cpp:2466-2502 + src/api/options.ts:125, src/api/types.ts, src/bridge.ts:171-172, src/api/native-backend.ts:415; CLI src/commands/cmd_segment.cpp).
  1. Run ./idl/codegen/generate_all.sh and commit the regenerated bindings -- generated files are committed here and idl-drift-check.yml fails on any diff.


### `seg-add-model-id` — Add model_id to SegmentationRequest

**Proto location:** [segmentation.proto (SegmentationRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/segmentation.proto)

**Why:** The divergence has already started without it: sdk/runanywhere-python/runanywhere/options.py:247 declares `model: Optional[str] = None` on SegmentationOptions and its docstring promises it loads and downloads that model, but the field has no wire representation -- one of eight SDKs is already implementing a contract the proto cannot carry, and left alone the other seven will each invent their own spelling. It is also the whole ergonomics gap: neither facade auto-downloads today (Web calls ensureModelForCategory(MODEL_CATEGORY_SEMANTIC_SEGMENTATION) with no id, making its download branch unreachable; Swift throws from requireSemanticSegmentationModel). Request-level, not options-level, keeps it identical to the sibling domains.

**Skeptic verdict:** `sound` — Two overstatements that weaken (but do not sink) the case. First, the `why` says Python "is already implementing a contract the proto cannot carry" -- but api/segmentation.py:60-62 resolves it out of band (`model_id = options.model if options else None; model = runtime.segmentation(model_id, ...)`), i.e. through the existing component-load path, which is arguably correct layering rather than a divergence; commons already exposes per-call model naming via `rac_segmentation_component_load_model` and the internal `segment_with_service(service, model_id, ...)` (segmentation_module.cpp:275). So the field adds a second way to name a model rather than enabling something impossible. Second, the consistency argument cites tag 4 on both siblings but the `after` uses tag 3, so the shape is only near-identical (SegmentationRequest has no request_id). I did not find text in options.py confirming the docstring "promises it loads and downloads that model" -- treat that specific sentence as unverified. Additive and harmless either way.

**What changed:** Added `optional string model_id = 3;` to SegmentationRequest with the brief's comment. Verified the comment is truthful before writing it: EmbeddingsRequest.model_id exists at embeddings_options.proto:93 and VLMGenerationRequest.model_id at vlm_options.proto:125, both as `optional string`.

**Files touched:** `segmentation.proto`

**Status:** `applied`


### `seg-annotate-dimension-bounds` — Annotate width and height with rac_min 1 / rac_max 4096

**Proto location:** [segmentation.proto (SegmentationImage)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/segmentation.proto), [segmentation.proto (SegmentationImage)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/segmentation.proto)

**Why:** The real limit lives in three hand-maintained copies and is guaranteed to drift: kMaxSourceDimension = 4096 in segmentation_module.cpp:33, MAX_SOURCE_DIMENSION = 4096 re-declared at sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+Segmentation.ts:22, and kMaxSourceDimension = 4096 again in engines/onnx/onnx_segmentation_provider.cpp. The other six SDKs have nothing to generate a bound from. This adds no fields -- it moves a constant into the one place all eight bindings read.

**Skeptic verdict:** `sound` — The payoff claim "it moves a constant into the one place all eight bindings read" is overstated in two ways. Commons cannot delete its own kMaxSourceDimension -- it validates at the trust boundary and must not trust a wire value (segmentation_module.cpp:174-176), so the duplication drops from three copies to two, not to one, and a new drift mode appears where the generated validate() message and the real C++ limit disagree. And "every SDK gets the same error message" is false for the two SDKs that never touch the proto: sdk/runanywhere-python (api/segmentation.py -> C struct) and sdk/runanywhere-electron (native/addon.cpp:2440-2460) generate nothing from this annotation. I also could not confirm from the generators that rac_min/rac_max are emitted for a non-optional `uint32` field (the verified precedent is `optional int32`), so run idl/codegen/generate_all.sh before committing rather than assuming the codegen path is exercised. Harmless and directionally right; just do not bill it as removing the duplication.

**What changed:** Annotated SegmentationImage.width (tag 2) and SegmentationImage.height (tag 3) with `(runanywhere.v1.rac_min) = 1` and `(runanywhere.v1.rac_max) = 4096` alongside the existing rac_required, using the multi-line option block from the brief.

**Files touched:** `segmentation.proto`

**Status:** `applied`


### `seg-drop-fraction` — Delete SegmentationClassSummary.fraction

**Proto location:** [segmentation.proto (SegmentationClassSummary)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/segmentation.proto)

**Why:** It carries zero information: onnx_segmentation_provider.cpp computes it as counts[class_id] / pixel_count, and width * height are already on the result. Worse, it is a lie-vector -- commons validates only that it is finite and within [0,1] (segmentation_module.cpp:242-243) and separately that the pixel_counts sum to the pixel area; nothing checks the two agree, so a backend can return a mutually inconsistent pair and both reach the app. It is already inconsistent across SDKs: Swift and Web ClassInfo expose it, Python's ClassInfo (results.py:246-251) already omits it. Deleting it removes a field, a validation branch and a class of silent disagreement, at the cost of one division in app code.

**Skeptic verdict:** `risky` — Same missed-consumer failure as the diagnostic proposal, plus an overclaiming comment. The migration note says only "any app reading classInfo.fraction on Swift or Web (Python users are already unaffected)", but `grep -rn fraction` finds a third public consumer nobody enumerated: sdk/runanywhere-electron/src/api/types.ts:410, src/api/backend.ts:130, src/bridge.ts:171 and src/api/assets.ts:469 (`fraction: c.fraction`), fed by native/addon.cpp:2495. A commons test also asserts on it (tests/test_segmentation_onnx.cpp:195 `summary.fraction() == 1.0f`) and will need editing. And the new `after` comment asserts "the counts are validated to sum to exactly that product, so ... the division is exact" -- that invariant is enforced only in result_to_proto (segmentation_module.cpp:258), which Electron and Python bypass entirely by going through rac_segmentation_result_t, so for those two SDKs the proposed replacement expression is not guaranteed exact. The core reasoning (a derived field that can disagree with its source) does hold; the breaking-consumer set and the comment's guarantee do not.

**What changed:** Deleted `float fraction = 3;` from SegmentationClassSummary outright and renumbered `string label` from tag 4 to tag 3, leaving the message dense at tags 1-3. Added the coverage-share comment above the message.

**Files touched:** `segmentation.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The brief's migration note names only Swift and Web and asserts 'Python users are already unaffected'. Both halves are wrong. The verified consumer set is: CLI -- sdk/runanywhere-cli/src/commands/cmd_segment.cpp:74 emits a literal `"fraction"` key into the machine-readable JSON output and :91 renders the percent column, with a GOLDEN-STRING test at sdk/runanywhere-cli/tests/test_rcli_segment.cpp:482-483 asserting the exact bytes `{"class_id":0,"label":"background","pixel_count":200000,"fraction":0.75}` (fixtures at :441 and :445, emitter mirror at :474). That is a published CLI contract; anyo…

**Wire safety:** Correct as written: tag 3 becomes `reserved 3; reserved "fraction";` with tags 1, 2 and 4 left untouched -- no renumbering, no tag reuse, no enum or oneof involved. Reserving the NAME as well as the number is the right call here because the JSON/name-keyed paths (Kotlin Wire's jsonName, the ts-proto fromJSON/toJSON at sdk/shared/proto-ts/src/segmentation.ts:465 and :478-479, and the CLI's hand-wr…

**Do first:**
  1. Rewrite the migration note before it ships. It currently says 'any app reading classInfo.fraction on Swift or Web (Python users are already unaffected)'. Replace with the nine verified surfaces plus the three example apps listed in whatCouldBreak, and call out the CLI JSON key explicitly as the one consumer that is a machine-readable contract rather than a typed field.
  1. Decide the CLI JSON policy separately and state it in the PR: either keep emitting `fraction` in cmd_segment.cpp:74 as a computed pixel_count/(width*height) value for one release and announce a deprecation, or drop it and update the golden string in test_rcli_segment.cpp:482-483 in the same commit. Do not let the golden test be 'fixed' by whoever hits the red build without that decision being made.
  1. Scope this change to the proto + generated bindings + hand-written SDK surfaces. Do NOT delete `float fraction;` from rac_segmentation_class_summary_t (rac_segmentation_types.h:42) in the same PR -- it sits mid-struct between pixel_count and label, so removing it relayouts the struct for Python (native/module.cpp:1689), Electron (native/addon.cpp:2495) and the CLI (cmd_segment.cpp:58), and it would collide with the struct growth seg-add-confidence-mask needs. Leave the producer at onnx_segmentation_provider.cpp:572 writing it and let it die at the proto boundary.
  1. Keep the commons validation at segmentation_module.cpp:242-243 doing its job even after set_fraction (:252) is deleted -- the `pixel_count > pixels64` and `summary_pixels > pixels64 - pixel_count` overflow guards in that same condition are what make the partition claim true, and a careless edit that removes the whole `if` along with the fraction terms silently disables the sum check at :258-261.
  1. Run ./idl/codegen/generate_all.sh FIRST and commit the regenerated bindings, then fix the hand-written layers -- the Swift/Kotlin/Flutter/Web/proto-ts hand-written mappers reference the generated symbol, so doing it in the other order leaves every SDK red for no reason.
  1. Update the four tests that assert on the field in the same PR: test_segmentation_onnx.cpp:195, SegmentationPublicSurfaceTests.swift:34, CppBridgeSegmentationTest.kt:45, SegmentationProtoAdapter.test.ts:204, plus test_rcli_segment.cpp per the CLI decision above.
  1. Fix the three example apps (SegmentationView.swift:217, examples/web/.../segmentation.ts:351, SegmentationScreen.kt:294) to compute the percentage from pixelCount / (width * height) -- this is the migration the release notes should show, so it should be demonstrated in the examples.


### `seg-drop-stride-bytes` — Delete SegmentationImage.stride_bytes

**Proto location:** [segmentation.proto (SegmentationImage)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/segmentation.proto)

**Why:** Inert in both directions. segmentation_module.cpp:190 unconditionally overwrites it (`out_image->stride_bytes = width * channels`), and the check just above already rejects the request unless data.size() is exactly width*height*channels -- so the padded buffer that is the only reason to have the field cannot be described and would fail the length check anyway. Its own comment admits it "Was a C-struct-only field ... with no wire counterpart". It is also unreachable from every public API: Swift's RAConvenience.swift sets `r.strideBytes = 0`, and the Web namespace hard-codes `strideBytes: 0` in both branches. The C struct rac_segmentation_image_t.stride_bytes stays -- it is real on the CLI / Electron path -- it just does not belong on the wire.

**Skeptic verdict:** `sound` — Only bookkeeping nits, none of which change the verdict. The risk section says the "Python _handles.py stride_bytes kwarg on the C-struct path" needs deleting in the same commit -- that contradicts the proposal's own decision to keep the C struct, and it is not required (_handles.py:386/400 and native/module.cpp:1663 feed the C struct, not the proto). The same grep turns up an unmentioned C-struct caller, sdk/runanywhere-electron/native/addon.cpp:2455 (`image.stride_bytes = img.Has("strideBytes") ? ...`), plus three commons tests (test_segmentation_generic.cpp:292/359/412); all are unaffected by a wire-only deletion, but the risk note should say so rather than implying a kwarg removal. Separately worth flagging to the owner: no code under engines/onnx/ reads stride_bytes at all, so the Electron/Python callers that CAN pass a real padded stride are silently mis-decoded today -- a pre-existing bug this change neither causes nor fixes.

**What changed:** Deleted SegmentationImage.stride_bytes (tag 5) and its three-line comment outright from segmentation.proto. SegmentationImage is now tags 1-4, dense and ascending.

**Files touched:** `segmentation.proto`

**Status:** `applied`


</details>


<details>
<summary><strong>structured-output</strong> (7 changes)</summary>

### `so-p1` — Replace the typed schema tree and mode enum with one constraint oneof

**Proto location:** [structured_output.proto (JSONSchemaType)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (StructuredOutputMode)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (JSONSchemaProperty)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (JSONSchema)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto)

**Why:** This is the single biggest deletion in the review and it collapses three defects into one edit. (1) The hand-typed JSON-Schema-in-protobuf tree (JSONSchema 16 fields + JSONSchemaProperty 14 + JSONSchemaType 8 values) is lossy — structured_output.cpp:354-364 lifts only properties/required/additionalProperties out of a nested object_schema and silently discards title, description, $ref, definitions and allOf/anyOf/oneOf/not — and asymmetric: JSONSchema.items is a JSONSchemaProperty while JSONSchemaProperty.items_schema is a JSONSchema, so a root-level array cannot express what a nested one can. The proto already concedes defeat at line 79-80 with `// Escape hatch for schemas the typed shape above cannot express.` / `optional string raw_json = 16;`. (2) The typed arm sits in a oneof against the very string that duplicates it, and two of three hand-written SDK helpers set BOTH arms so the typed schema they just built is dropped on the wire (Swift StructuredOutputProto+Helpers.swift:20+23, Web RunAnywhere+StructuredOutput.ts:257+260). (3) `mode` plus three payload fields make illegal states representable — nothing stops mode=JSON_SCHEMA with `grammar` set, or mode=REGEX with a schema and no regex_pattern — and today that ambiguity ships: llm_module.cpp:1621-1623 forwards `grammar` and never reads `mode`, while structured_output.cpp:516-534 rejects `grammar` and honours `mode`, so the same message means two different things by entry point. A oneof makes the exclusion free in every generated language. The after-block also states the contract the domain exists for and currently does not honour: a present arm constrains the DECODER. Delivering that is the non-proto half of this proposal — commons must compile `schema` to a grammar on the generate path instead of reading only `grammar`, and hard-error where it cannot. Migration note: the string arms keep their tags and types (json_schema→schema stays tag 4 string, regex_pattern→regex stays tag 8 string, grammar stays tag 9), so callers already using the string form are wire-compatible and only see renamed accessors; only the typed tag 1 and the mode enum tag 7 break.

**Skeptic verdict:** `sound` — One omission in the risk note: the after-block reuses the NAME `schema` for tag 4, while tag 1 (reserved) was also named `schema` and was a message. Any reader keyed on the proto3-JSON name `schema` silently flips from object to string rather than failing - and sdk/shared/proto-ts/src/structured_output.ts:1587-1590 shows this codebase's TS layer does key on JSON names. Also 'Everyone calls the field schema' is overstated by the proposal's own P2, which cites Ollama's `format` and llama.cpp's `json_schema`.

**What changed:** Deleted the typed JSON-Schema-in-protobuf tree (enums JSONSchemaType and StructuredOutputMode, messages JSONSchemaProperty and JSONSchema) and replaced StructuredOutputOptions' schema_source oneof + mode/regex_pattern/grammar fields with a single `oneof constraint { string schema; string grammar; string regex; }`. Per the wave ground rule (no backwards compatibility, no `reserved`, keep numbering dense) I did not emit the after-block's `reserved 1, 7;` / `reserved "json_schema", "mode", "regex_pattern";` lines and instead renumbered the surviving fields densely (include_schema_in_prompt=1, schema=2, grammar=3, regex=4). I also dropped the after-block's pointer to docs/STRUCTURED_OUTPUT.md because that file does not exist (docs/ contains only gifs/ and img/), per carePlan.doFirst and the keep-comments-truthful rule.

**Files touched:** `idl/structured_output.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The typed JSONSchema tree is NOT internal to the proto - it backs an exported C ABI symbol and a public Kotlin type. (1) `rac_structured_output_schema_to_json_proto` exists solely to serialize a JSONSchema proto to JSON text: declared sdk/runanywhere-commons/include/rac/features/llm/rac_llm_schema_to_json.h, implemented sdk/runanywhere-commons/src/features/llm/schema_to_json.cpp:197, exported at sdk/runanywhere-commons/exports/RACommons.exports:187 and sdk/runanywhere-web/wasm/CMakeLists.txt:871, tested by sdk/runanywhere-commons/tests/test_schema_to_json.cpp. Deleting JSONSchema deletes that…

**Wire safety:** Tag 4 keeps its type (string) and only changes name json_schema -> schema: binary-wire-compatible. Tag 8 likewise regex_pattern -> regex, tag 9 grammar unchanged but moves INTO the oneof (no wire change - oneof membership is not encoded). Tag 1 (typed JSONSchema message) is dropped: reserve the NUMBER 1 so it is never reused. CRITICAL: do NOT write `reserved "schema"` - the after-block correctly …

**Do first:**
  1. Write idl/../docs/STRUCTURED_OUTPUT.md first - the after-block's comment points at it and `ls docs/ | grep -i struct` returns nothing today, so shipping the comment as written cites a file that does not exist.
  1. Decide the fate of rac_structured_output_schema_to_json_proto BEFORE editing the proto. Either (a) retire it in the same commit and remove RACommons.exports:187 + wasm/CMakeLists.txt:871 + tests/test_schema_to_json.cpp, or (b) keep JSONSchema alive one release as a deprecated builder that only feeds that symbol. Do not leave the exports file naming a deleted symbol.
  1. Rewrite the three helper triplets to emit a JSON string only, and stop double-setting the oneof: Flutter runanywhere_structured_output.dart:51-52 and :275-276 set `schema:` and `jsonSchema:` together; Kotlin StructuredOutputProtoHelpers.kt:78-144; Web RunAnywhere+StructuredOutput.ts:221-261.
  1. Deprecate the public Kotlin alias Aliases.kt:12 (`typealias JsonSchema = proto.v1.JSONSchema`) in a release before deleting it - it is public API, so this is a Kotlin semver-major.
  1. Delete the mode read at structured_output.cpp:515 and the four StructuredOutputMode string unions (Web Options.ts:51, RN Types.ts:263, Flutter options.dart:828, Web index.ts:65) in the same commit, or those SDKs keep exporting an enum the wire no longer has.
  1. Add an explicit rejection when a caller sends the old typed payload: after the change, tag 1 arriving on the wire is an unknown field and is silently dropped, so a stale app degrades to free generation - exactly what the after-block's own comment forbids. Make commons fail the call when no arm is present but unknown field 1 is.


### `so-p2` — Collapse the parallel generate/stream/event tree onto the LLM path

**Proto location:** [structured_output.proto (StructuredOutputRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (StructuredOutputStreamEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (StructuredOutputStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (StructuredOutputValidationRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto)

**Why:** There is no structured-output request type anywhere in the industry; it is one optional field on the ordinary generate request, and we already have that field correctly at llm_options.proto:63. This file additionally declares its own request, its own six-value stream-event enum, its own stream event, and a fourth request message that is a field-content subset of StructuredOutputParseRequest — three request messages for a domain where the industry has zero. The duplication has already produced divergence: Swift's generateStructured routes through rac_llm_generate_proto (the commons-031 comment at structured_output.cpp:550-563 says so verbatim) while Web's extractStructuredOutput routes through the parse ABI and throws when that export is absent (RunAnywhere+TextGeneration.ts:532). It is also why structured generation cannot set a token budget: StructuredOutputRequest has no LLMGenerationOptions field, so per-call max_tokens/temperature/top_p/stop_sequences/system_prompt reach the engine only as rac_llm_options_t defaults, and sdk_defaults.proto:326-338 declares a whole StructuredOutputDefaults{max_tokens 512, temperature 0.0} written for this call with nowhere to land. An app generating a 40-field document truncates mid-object and reports is_valid=false forever with no lever to pull. Deleting the tree is the only fix that needs zero new imports — the reviewer's `import "llm_options.proto"` is a compile error, because llm_options.proto:10 already imports this file. One field is added to preserve the one capability worth keeping: Apple's partial-object streaming, which the forked event type carried and no public verb ever emitted. This proposal also subsumes finding structured-output-9's fourth duplicate carrier (StructuredOutputStreamEvent.validation, copied from result.validation at structured_output.cpp:743) by deleting the message that held it.

**Skeptic verdict:** `risky` — The migration target does not exist yet, and the risk note does not say so. sed -n 1615,1630p llm_module.cpp is the ONLY structured_output read on the LLM generate path and it reads has_grammar()/grammar() only - json_schema, the typed schema, and include_schema_in_prompt are never looked at. Meanwhile structured_output.cpp:1655-1695 (prepare_prompt) is what actually renders a schema into a prompt. So 'fold onto LLMGenerationOptions.structured_output' silently drops every JSON-Schema caller until llm_module is taught to read the schema. Sequencing must be: teach the LLM path to honour schema + include_schema_in_prompt, THEN add partial_json, THEN delete - not the two steps listed.

**What changed:** Deleted StructuredOutputValidationRequest, StructuredOutputRequest, StructuredOutputStreamEventKind and StructuredOutputStreamEvent from structured_output.proto, and added `optional string partial_json = 20;` to LLMStreamEvent in llm_service.proto (tag 20 was free; the message previously topped out at error=19). Per the no-tombstone ground rule I deleted the four types outright rather than leaving the after-block's explanatory comment in their place; the equivalent guidance now lives in the rewritten file header, which previously described the deleted StructuredOutputRequest/StructuredOutputStreamEvent and would otherwise have been a lying comment. StructuredOutputParseRequest survives as the sole request message for extract/validate/prepare-prompt.

**Files touched:** `idl/structured_output.proto`, `idl/llm_service.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** This is the widest blast radius in the set and it is bigger than the brief says, because StructuredOutputRequest is the input to prepare_prompt as well as to generate. Deleting StructuredOutputRequest breaks: Kotlin CppBridgeStructuredOutput.kt:23-27 `preparePrompt(request: StructuredOutputRequest)` and RunAnywhereStructuredOutput.kt:68; Flutter dart_bridge_structured_output.dart:89-94 makeGenerateRequest + rac_native.dart:2490-2495 (BOTH generate and prepare_prompt take this message); Swift CppBridge+StructuredOutput.swift:68-69; RN Llm.ts:361-371 and specs/RunAnywhereCore.nitro.ts:1179. Del…

**Wire safety:** Deleting four top-level types is not a field-tag question, but reserve nothing in structured_output.proto (the names simply disappear from the package). LLMStreamEvent.partial_json = 20 is free: llm_service.proto's LLMStreamEvent tops out at 19 (error). No tag reuse, no enum renumbering. The one real wire trap the brief names is real: StructuredOutputValidationRequest.text is tag 1 while Structur…

**Do first:**
  1. PREREQUISITE THAT DOES NOT EXIST YET: teach llm_module.cpp to honour StructuredOutputOptions.schema and include_schema_in_prompt on the ordinary generate path. Today :1621-1623 reads grammar only; the schema->prompt rendering lives in structured_output.cpp prepare_prompt. Until that lands, folding drops every JSON-Schema caller on the floor.
  1. Land so-p1 first so the fold targets one string arm instead of the typed tree.
  1. Add LLMStreamEvent.partial_json = 20 and have the streaming path populate it. Verify parity against commons tests/test_llm_proto_service.cpp:577 which asserts event.partial_json() == '{"ok":true}' on the OLD event today.
  1. Migrate the SDKs off the generate entry points in dependency order: Swift (already on the LLM path) -> Kotlin RunAnywhereStructuredOutput.kt -> Flutter -> RN -> Web, each verified green before the next.
  1. Decide separately what happens to prepare_prompt and validate. They take StructuredOutputRequest / StructuredOutputValidationRequest and are NOT part of the generate fold. Either keep StructuredOutputRequest for prepare_prompt or migrate both ABIs to StructuredOutputParseRequest in the same commit.
  1. Only then delete the messages and remove the two symbols from RACommons.exports:181-182, wasm/CMakeLists.txt:869-870, swift-modality-abi.yaml:127, generate_swift_modality_abi.py:78,118, the JNI at :7178,:7319 and the RN cpp at :473,:486.


### `so-p3` — Delete four dead knobs: strict_mode, name, repair_json, max_retries

**Proto location:** [structured_output.proto (StructuredOutputOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (StructuredOutputOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (StructuredOutputOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (StructuredOutputOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto)

**Why:** All four are confirmed dead by grep. strict_mode has zero non-generated readers in commons (only structured_output.pb.cc) and the proto's own comment says `// Not read by commons.`; `.name()` never appears in structured_output.cpp; repair_json and max_retries appear only inside unsupported_structured_options_message (structured_output.cpp:535-546), which returns RAC_ERROR_FEATURE_NOT_AVAILABLE. strict_mode is the worst kind of dead field — not merely unread but actively contradicted across platforms: it is a public boolean on three SDKs and Swift's public surface defaults it to `true` (Options.swift:85 and :88) while Web's public helper defaults it to `false`, so the same public argument reads as a strictness guarantee on both, disagrees between them, and delivers nothing on either. repair_json/max_retries are the same trap one level down: Web maps its public mode:'repair' onto them and nothing reads them, while Swift implements a real retry — one public argument, two behaviours. Retry and repair are SDK-layer concerns the industry unanimously leaves to the caller; if Swift's one-shot repair is wanted everywhere, implement it in the SDK layer rather than as a proto field that pretends the engine does it. Strictness is subsumed by the constraint contract in P1 (a present arm constrains, or the call fails) plus include_schema_in_prompt.

**Skeptic verdict:** `risky` — The load-bearing justification 'every such write is already a no-op' is FALSE for two of the four fields. structured_output.cpp:535 `if (options.repair_json())` and :541 `if (options.max_retries() > 0)` both return RAC_ERROR_FEATURE_NOT_AVAILABLE, and the commons-103 comment above them at :503-512 says that guard exists precisely because silent downgrade made SDKs 'accept non-conforming output as if the constraint had been applied'. So setting them today is a loud typed failure, not a no-op. Deleting the fields deletes the rejection guard - fine as a decision, but it must be argued as 'remove a feature we reject' rather than 'remove dead surface', and the two dead fields (strict_mode, name) should be split from the two live-rejected ones.

**What changed:** Deleted the four dead/rejected knobs from StructuredOutputOptions: strict_mode (was 3, with its `// Not read by commons.` comment), name (was 6, with its OpenAI comment), repair_json (was 10) and max_retries (was 11, with its rac_default/rac_min annotations). Per the ground rule I deleted them outright instead of emitting the after-block's `reserved 3, 6, 10, 11;` / `reserved "strict_mode", "name", "repair_json", "max_retries";`.

**Files touched:** `idl/structured_output.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Two of the four are dead and two are live-rejected, and the live pair changes runtime behaviour on delete. LIVE WRITERS of repair_json: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/MappingOptions.kt:119 `repair_json = !strict` - so every Kotlin caller that passes strict=false sets repair_json=true today and gets a hard RAC_ERROR_FEATURE_NOT_AVAILABLE from structured_output.cpp:535; Web Mapping.ts:299 `repairJson: mode === 'repair'`, RunAnywhere+StructuredOutput.ts:123, RunAnywhere+TextGeneration.ts:125. LIVE WRITERS of max_retries: Web Mapping.ts:300 `maxRetries: mode…

**Wire safety:** Pure deletion of tags 3, 6, 10, 11 from StructuredOutputOptions. `reserved 3, 6, 10, 11;` plus `reserved "strict_mode", "name", "repair_json", "max_retries";` is exactly right - no tag reuse, no renumbering, no oneof arm touched (all four are plain fields, not oneof members; the oneof is schema_source over 1 and 4). Old clients still setting them produce unknown fields that are dropped, which is …

**Do first:**
  1. Split the commit in two. Commit A deletes strict_mode (3) and name (6): genuinely dead, no guard, no behaviour change. Commit B deletes repair_json (10) and max_retries (11): these are live-rejected, so deleting them removes a rejection guard.
  1. Before Commit B, delete the two live writers so the rejection is never reachable from our own SDKs: Kotlin MappingOptions.kt:119 `repair_json = !strict` and Web Mapping.ts:299-300. Otherwise the exact moment the field disappears, Kotlin strict=false silently starts succeeding without repair.
  1. Replace the guard, do not just drop it. Keep a check in commons that fails the call when an unknown structured-output constraint arrives, or Flutter's public maxRetries knob (options.dart:168) becomes a no-op with no error - the failure mode commons-103 (structured_output.cpp:503-512) exists to prevent.
  1. Deprecate rather than delete the three public surfaces in the same release: Swift's `strict:` argument (Options.swift:94, StructuredOutputProto+Helpers.swift:16), Web's `mode: 'repair'` (Options.ts:51, Mapping.ts:285-300), Flutter's `maxRetries` (options.dart:168).
  1. Regenerate the convenience/validator output: Swift RAConvenience.swift:186,194-197 and shared/proto-ts convenience/structured_output_convenience.ts:25,29-32 both carry a max_retries validator that must vanish with the field.


### `so-p5` — Change parsed_json from bytes to a string named json

**Proto location:** [structured_output.proto (StructuredOutputResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto)

**Why:** structured_output.proto:123 declares `bytes parsed_json = 1;` but the field holds UTF-8 JSON TEXT, not a serialized message: commons fills it from the same `parsed.parsed_json` C string it assigns to the string-typed extracted_json at structured_output.cpp:598-599. Named `parsed_json` and typed `bytes`, it reads in every generated language as if it were a nested proto, so the developer's first instinct is wrong; Web already wraps it in a TextDecoder with an empty-case fallback, and on JS/Dart it converts a zero-copy string into a Uint8Array round-trip for nothing. It also contradicts our own sibling result, which already gets this right at llm_options.proto:87 (`optional string json_output = 13;`). Dropping the word "parsed" matters as much as the type: nothing on the wire is parsed — parsing is the caller's job.

**Skeptic verdict:** `risky` — 'only the generated accessors and the name change' understates two things. (1) bytes->string adds UTF-8 validation on DECODE: structured_output.cpp:640 assigns parsed.parsed_json raw, with no sanitize_utf8 (compare llm_module.cpp:1789 which does sanitize before set_raw_output), so a payload that decodes fine as bytes today can throw in strict runtimes after the change. Sanitize at the writer in the same commit. (2) renaming to `json` also changes the proto3-JSON key, and sdk/shared/proto-ts/src/structured_output.ts:1587-1590 shows this repo's TS layer resolves fields by JSON name - a rename there is a silent miss, not a compile error.

**What changed:** In StructuredOutputResult, changed `bytes parsed_json = 1;` to `string json = 1;` with the comment 'The extracted JSON document, as UTF-8 text. Parse it client-side.' Tag 1 is unchanged; the sibling fields keep validation=2 and raw_text=3, and error moved 6 -> 4 as part of the dense renumbering.

**Files touched:** `idl/structured_output.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Every SDK has a decode step keyed on this field, and two of them will NOT fail loudly. Kotlin sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/LlmNamespace.kt:160 `value = parsed.parsed_json.utf8()` - Wire ByteString.utf8() disappears when the field becomes String (compile error, good). Flutter packages/runanywhere/lib/public/api/types/results.dart:203 `value: Uint8List.fromList(proto.parsedJson)` (compile error, good). RN packages/core/src/Public/Api/Results.ts:199 `new TextDecoder('utf-8').decode(result.parsedJson)` and Web packages/core/src/Public/API/Mapping.ts:312 `n…

**Wire safety:** bytes and string are both wire type 2 (length-delimited) on tag 1, so the BINARY wire is byte-identical and no reserved range is needed. Two non-binary consequences: (1) proto3-JSON encodes bytes as base64 and string as a plain string, so any JSON-transport or logged payload changes shape; (2) string adds UTF-8 validation on DECODE, and commons writes the value raw at structured_output.cpp:640 wi…

**Do first:**
  1. Sanitize at the writer FIRST, in the same commit: add the UTF-8 sanitize to structured_output.cpp:640 and :1367 before set_json(), mirroring what llm_module.cpp does before set_raw_output. Without it the type change can turn a tolerated payload into a decode throw.
  1. Land the type change and the rename together, never separately - a bytes->string change with the same name would be a silent semantic flip for any JSON reader.
  1. Delete every decode step in the same commit: LlmNamespace.kt:160 (.utf8()), results.dart:203 (Uint8List.fromList), Results.ts:199 and Mapping.ts:312 (TextDecoder), Results.swift:154.
  1. Regenerate BOTH checked-in TS copies (sdk/shared/proto-ts/src/structured_output.ts and sdk/runanywhere-electron/src/proto/structured_output.ts) plus the python _proto, swift .pb.swift, flutter .pb.dart and commons .pb.cc/.pb.h.
  1. Update the test fixtures that construct bytes: Web RunAnywhere+StructuredOutput.test.ts:225,375 and the two browser e2e specs that type it Uint8Array.


### `so-p6` — Default include_schema_in_prompt to true and make it optional

**Proto location:** [structured_output.proto (StructuredOutputOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto)

**Why:** structured_output.proto:84 is a bare proto3 bool, so its default is false and absent is indistinguishable from explicitly-off — the generated Swift reads `public var includeSchemaInPrompt: Bool = false` (structured_output.pb.swift:453). Every facade then overrides it: Swift's public StructuredOutput type calls defaults(schema:includeSchemaInPrompt: true, strict:) at Options.swift:94, and all three helpers declare the parameter `= true`. So the wire default is the one value no SDK actually wants, and anyone constructing the proto directly — the Electron, CLI, Python or React Native integrator, before a hand-written helper exists — gets schema-blind generation. On a 1-3B on-device model that is the difference between usable and unusable JSON, and it is exactly the case where the schema is the only thing telling the model what to write. Making it `optional` also lets commons tell "caller said no" from "caller said nothing", which the bare bool cannot.

**Skeptic verdict:** `risky` — The stated benefit does not materialize and the risk sentence is backwards. rac_default is a codegen/doc annotation; proto3 still puts false on the wire for an absent bool. structured_output.cpp:498-499 reads `options.include_schema_in_prompt() ? RAC_TRUE : RAC_FALSE` with no has_ check, so after this edit a direct-proto integrator who omits the field still gets FALSE while the comment above it now promises 'Default true'. Nothing flips for anyone, so the claim that it 'flips behaviour for any caller that relied on the false default' is also wrong. It only becomes true if commons is changed to branch on has_include_schema_in_prompt() - that edit must be in the same commit or the comment is a lie aimed at exactly the newcomers it claims to rescue.

**What changed:** Made include_schema_in_prompt an `optional bool` carrying `[(runanywhere.v1.rac_default) = "true"]` with the three-line comment from the after-block. The rac_default extension is genuinely declared in rac_options.proto (extend google.protobuf.FieldOptions, string rac_default = 50001), so it is not a fabrication. Its tag moved 2 -> 1 as part of the dense renumbering that replaced the after-blocks' reserved statements.

**Files touched:** `idl/structured_output.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** Adding `optional` is a Kotlin COMPILE break the brief does not mention: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/extensions/LLM/RunAnywhereStructuredOutput.kt:64 is `if (structuredOutput.include_schema_in_prompt)` and Wire generates a nullable Boolean? for a proto3 optional field, so that `if` stops compiling. The other three readers survive but change meaning: Swift RunAnywhere+StructuredOutput.swift:136, Web RunAnywhere+StructuredOutput.ts:364, Flutter runanywhere_structured_output.dart:236 all branch on the bare value and will now be branching on an absent-vs-false…

**Wire safety:** No wire change. Tag 2 keeps its number and its bool type; `optional` on a proto3 scalar only adds a synthetic oneof for presence tracking, which does not alter encoding of a set value. Absent still encodes as nothing on the wire - which is exactly why rac_default alone cannot flip the observed default.

**Do first:**
  1. In the SAME commit as the proto edit, change structured_output.cpp:498-499 to `converted.config.include_schema_in_prompt = (!options.has_include_schema_in_prompt() || options.include_schema_in_prompt()) ? RAC_TRUE : RAC_FALSE;`. Without this the new comment is a lie aimed at exactly the direct-proto integrators the change claims to rescue.
  1. Fix Kotlin RunAnywhereStructuredOutput.kt:64 in the same commit - `if (structuredOutput.include_schema_in_prompt)` will not compile against a Wire Boolean?. Use `!= false` so absent means true, matching the new commons semantics.
  1. Align the other three presence-blind readers to absent-means-true: Swift RunAnywhere+StructuredOutput.swift:136, Web RunAnywhere+StructuredOutput.ts:364, Flutter runanywhere_structured_output.dart:236.
  1. Regenerate sdk/shared/proto-ts/src/convenience/structured_output_convenience.ts (line 21 flips false -> true) and check the Swift RAConvenience/RADefaultsPool equivalents pick the annotation up.


### `so-p7` — Delete the NamedEntity orphan message

**Proto location:** [structured_output.proto (NamedEntity)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto)

**Why:** NamedEntity has no producer in commons, no verb in any facade returns it, and no other .proto in idl/ references it — confirmed by grep across sdk/ and examples/, where it appears only in generated bindings plus three hand-written `length` helpers (Swift StructuredOutputProto+Helpers.swift:97 inside the RANamedEntity extension opened at :86, Web RunAnywhere+StructuredOutput.ts:277, Kotlin StructuredOutputProtoHelpers.kt:162) and a Swift-only convenience initializer at :87-96. That is four hand-written artefacts for a message that cannot be filled, and propagating the domain to eight SDKs means eight. Named-entity extraction is not part of any vendor's structured-output surface because it is a task you express AS a schema — which is the entire point of this domain.

**Skeptic verdict:** `sound` — Only a scoping caveat: it is not merely 'named' by helpers, it is an exported public type of the web package (packages/core/src/Public/Extensions/RunAnywhere+StructuredOutput.ts:22,45 and dist/types/index.d.ts:63) plus a public namedEntityLength() with Swift parity RANamedEntity.length. That makes it a semver-major for @runanywhere/core, so it wants a deprecation release rather than a bare delete - hence approve-with-care rather than approve.

**What changed:** Deleted the orphan NamedEntity message and its `// Character offsets into the source text.` comment. Per the no-tombstone ground rule I did not leave the after-block's replacement comment ('NamedEntity is deleted. Entity extraction is a JSON Schema ...') in the file.

**Files touched:** `idl/structured_output.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** No producer, but a real public type in two SDKs. Commons never constructs or reads one - my grep for 'namedentity|named_entity' over sdk/, examples/, idl/ and docs/ returned ZERO hits under sdk/runanywhere-commons/src or /include, and the only idl/ hit is the declaration itself at idl/structured_output.proto:178, so no other .proto references it either. What breaks is hand-written surface: Swift Sources/RunAnywhere/Public/Extensions/LLM/StructuredOutputProto+Helpers.swift:84-97 (the RANamedEntity extension, convenience init + `length`), documented as public API rows in sdk/runanywhere-swift/A…

**Wire safety:** No wire change. NamedEntity is a top-level message that is never nested in, referenced by, or serialized alongside any other message in idl/ (verified by the cross-proto grep), so there are no field tags to reserve and no oneof arm to remove. Deleting the message removes its descriptor from the file descriptor set only.

**Do first:**
  1. Ship a deprecation release before the delete, because this is a semver-major for @runanywhere/core and for the Swift package: mark RANamedEntity.length / namedEntityLength / NamedEntity.length @deprecated in Swift StructuredOutputProto+Helpers.swift:86-97, Web RunAnywhere+StructuredOutput.ts:45,277 and Kotlin StructuredOutputProtoHelpers.kt:156-162, with a note pointing at StructuredOutputOptions.schema.
  1. In the delete release, remove the three helpers and the Swift convenience init at StructuredOutputProto+Helpers.swift:87-96 in the same commit as the proto edit, and drop the two ARCHITECTURE.md rows at sdk/runanywhere-swift/ARCHITECTURE.md:407-408 so the parity table does not name a type that no longer exists.
  1. Confirm the web wildcard re-export path: check whether index.ts does `export * from './Public/Extensions/RunAnywhere+StructuredOutput.js'` before assuming index.ts needs no edit - my index.ts grep found no direct NamedEntity mention.
  1. Regenerate all five checked-in bindings (swift .pb.swift, flutter .pb.dart, shared/proto-ts, electron/src/proto, python _pb2) - the electron copy is a separate checked-in file and is the one most likely to be missed.


### `so-p9` — Add reserved statements for every pre-existing field-number hole

**Proto location:** [structured_output.proto (StructuredOutputOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (StructuredOutputValidation)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (StructuredOutputResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto), [structured_output.proto (StructuredOutputPromptResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/structured_output.proto)

**Why:** The file contains no `reserved` statement anywhere, and five messages already have holes: StructuredOutputOptions skips 5, StructuredOutputValidation skips 3, StructuredOutputResult skips 4 and 5, StructuredOutputPromptResult skips 6 and 7, StructuredOutputStreamEvent skips 1, 9 and 10 (that last message is deleted by P2). Nothing stops a future edit from reusing one of these tags, which would deserialize as the old field on an already-shipped SDK build and corrupt data silently rather than failing. This becomes acute the moment P1, P3, P4, P5 and P8 free up eleven more tags. Note the tag-4 correction: the review reserved 4 on StructuredOutputResult in one finding and claimed it for finish_reason in another; with that field declined (P12), both 4 and 5 are reserved here.

**Skeptic verdict:** `sound` — None found. One cross-proposal note: reserving Result tag 4 here forecloses P12's declined finish_reason placement, so if the owner ever reverses that decline it must take a fresh tag.

**What changed:** The intent — no field-number hole can ever be silently reused — is now satisfied by construction rather than by `reserved`: every message in structured_output.proto is numbered densely and ascending from 1 with no gaps. StructuredOutputOptions is 1-4; StructuredOutputValidation closed its hole at 3 (raw_output 4->3, extracted_json 5->4, validation_errors 6->5, validation_time_ms 7->6, error 8->7); StructuredOutputResult closed 4 and 5 (error 6->4); StructuredOutputPromptResult closed 6 and 7 (error 8->6); StructuredOutputParseRequest was already dense. StructuredOutputStreamEvent's holes at 1, 9, 10 vanished with the message itself under so-p2.

**Files touched:** `idl/structured_output.proto`

**Status:** `applied`


</details>


<details>
<summary><strong>stt</strong> (10 changes)</summary>

### `stt-audio-source-one-real-arm` — Delete adapter_handle from the audio oneof and either wire file_uri or delete it too

**Proto location:** [stt_options.proto (STTAudioSource)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L66), [stt_options.proto (STTAudioSource)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L69), [stt_options.proto (STTAudioSource)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L70)

**Why:** The oneof offers three ways in; commons rejects two of them with NOT_SUPPORTED (stt_module.cpp:1692-1696). Swift's AudioInput.file compiles and then fails at runtime on the single most common STT use case — transcribe a recording. Three arms where one works is the worst kind of choice to hand a newcomer.

**Skeptic verdict:** `sound` — Substance verified, but 'adapter_handle is a clean delete' is not literally true: stt_module.cpp:1692-1693 and :1882 both call .adapter_handle() and will fail to compile, so the same commit must simplify both guards. Effort M already covers that.

**What changed:** STTAudioSource: reserved 3 (adapter_handle) + name. Kept file_uri per care plan -- it's shipped public API on Swift (AudioInput.file) and RN (filePath).

**Files touched:** `idl/stt_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** adapter_handle is NOT a clean delete, and neither is file_uri if you take the fallback arm. adapter_handle readers that stop compiling: sdk/runanywhere-commons/src/features/stt/stt_module.cpp:1693 (`!out_request->audio().adapter_handle().empty()`) and :1882 (same call in the second guard) - the skeptic already flagged these. Two more the brief does not mention, both Dart: sdk/runanywhere-flutter/packages/runanywhere/lib/native/dart_bridge_stt.dart:479 is `case STTAudioSource_Source.adapterHandle:` in a switch over the oneof-case enum, and the enum member disappears on regeneration; sdk/runany…

**Wire safety:** Deleting adapter_handle frees tag 3 inside the `source` oneof. `reserved 3;` must sit at message level, OUTSIDE the oneof block (the proposed after-text already does this correctly - protoc rejects `reserved` inside a oneof). Add `reserved "adapter_handle";` too, so the JSON name cannot be revived either. Tag 3 must never be reused for a different type: any peer still on the old schema that sets …

**Do first:**
  1. Decide the file_uri arm BEFORE editing the proto - the two arms have different blast radii and the brief understates the delete arm. Recommended: KEEP file_uri, reserve 3 only. Deleting it costs you Swift Inputs.swift:128 (`AudioInput.file`) and RN Inputs.ts:129 (`filePath`), which are shipped public API on two SDKs.
  1. In the SAME commit as the proto edit, simplify both commons guards - they will not compile otherwise. stt_module.cpp:1692-1696 becomes a file_uri-only check and the message string at :1696 drops the '/adapter_handle' half ('STTTranscriptionRequest audio file_uri requires a platform adapter'). stt_module.cpp:1882 loses the `|| !request.audio().adapter_handle().empty()` disjunct the same way.
  1. In the same commit, delete the Dart consumers: dart_bridge_stt.dart:479's `case STTAudioSource_Source.adapterHandle:` arm and the '/adapter_handle' half of the message at :481; and nonllm_lifecycle_bridge_test.dart:150's STT case. Do NOT touch :161 - that is the VAD case and VADAudioSource keeps its adapter_handle.
  1. If you keep file_uri, this cycle must actually replace the two guards with a real read+decode path through the platform adapter. Narrowing the guard from two arms to one is not the fix the item is asking for - it just makes the runtime failure more specific. If that work is not landing, say so and ship the adapter_handle delete alone rather than pretending file_uri is wired.
  1. Regenerate all bindings after the proto edit - Swift, Kotlin, Dart, Python, commons C++, sdk/shared/proto-ts, and sdk/runanywhere-electron/src/proto (electron carries its own generated copy).


### `stt-delete-dead-decode-knobs` — Delete the four never-read decoding knobs: beam_size, max_alternatives, chunk_duration_ms, suppress_blank

**Proto location:** [stt_options.proto (STTOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L57), [stt_options.proto (STTOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L58), [stt_options.proto (STTOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L62)

**Why:** All four are documented with '0 = backend default' and no backend ever reads them, so the default is the only behaviour they have. They also leak two incompatible engine dialects into a portable API (whisper beam_size vs sherpa max_active_paths) and suppress_blank is a negative-polarity boolean that forces a double negative at the call site.

**Skeptic verdict:** `sound` — Content checks out. The hazard is apply-order, not correctness: this after-text, stt-delete-dead-options and stt-silence-duration-ms all rewrite the same 'reserved'/endpoint_silence_ms block with three mutually inconsistent results (this one keeps endpoint_silence_ms with a comment promising a rename; the silence proposal renames it; the dead-options proposal reserves 15 with a different comment). They must be applied as one edit or two of the three before-texts will fail to match.

**What changed:** Combined into the same STTOptions rewrite as stt-delete-dead-options (both rewrite the same field block) -- beam_size/max_alternatives/chunk_duration_ms/suppress_blank all reserved together.

**Files touched:** `idl/stt_options.proto`

**Status:** `applied`


### `stt-delete-dead-options` — Delete translate_to_english and vocabulary_list — both are public options that do nothing

**Proto location:** [stt_options.proto (STTOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L53), [stt_options.proto (STTOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L63)

**Why:** Swift, Kotlin and Web all expose these two as documented transcription options; commons never reads either (vocabulary_list stays RAC_NULL, and sherpa_backend hardcodes hotwords_file to empty). A developer sets translate_to_english = true, gets Spanish back, and has no way to tell the field from a bug. An absent capability is honest; a no-op field is not.

**Skeptic verdict:** `fabricated` — The industry precedent is misdescribed on both counts. OpenAI has no `translate` boolean -- translation is a separate endpoint, /v1/audio/translations -- and it has no `keywords` array; its biasing parameter is `prompt`. `keywords` is Deepgram's name and `word_boost` is AssemblyAI's. Only the whisper.cpp half (`translate`) is real. That matters because the precedent is load-bearing: the after-comment instructs re-adding as `repeated string keywords` and `bool translate` on OpenAI's authority. Second defect: the after-block silently also deletes suppress_blank (tag 15), which the title, why and simplicityGain never mention, and it rewrites the same seven lines that stt-delete-dead-decode-knobs and stt-silence-duration-ms also rewrite with different after-text -- whichever lands second will not match its own before-text.

**What changed:** STTOptions: reserved vocabulary_list(5)/beam_size(7)/max_alternatives(12)/chunk_duration_ms(13)/suppress_blank(15)/translate_to_english(16), all by number+name. Dropped the fabricated OpenAI/Deepgram attribution per care plan's correctionNeeded -- comment is vendor-free. Also deleted STTConfiguration.vocabulary_list(8)/max_alternatives(9), the second dead copy the care plan flagged as making the change 'half-honest' otherwise.

**Files touched:** `idl/stt_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** No commons reader - confirmed, the greps over sdk/runanywhere-commons/src come back empty outside src/generated/. But the facade WRITER list is larger than the brief's four, and two of the extras fail at runtime rather than compile time. translate_to_english writers: Swift Options.swift:240/249/256/266; Kotlin MappingOptions.kt:131; Web Options.ts:129 + Mapping.ts:343; React Native Types.ts:153 + Options.ts:236; Flutter options.dart:336/359/367; and two Python tests that assert on the attribute - sdk/runanywhere-python/tests/test_namespaces.py:100 (`SttOptions(translate_to_english=True)`) and…

**Wire safety:** `reserved 5, 15, 16;` in STTOptions - tags freed, none reused, no renumbering. Add `reserved "vocabulary_list", "suppress_blank", "translate_to_english";` so the JSON names are burned too. Note while you are in there: STTOptions already has silent holes at tags 1, 8, 9, 10 and 11 with no reserved statement at all (present tags are 2,3,4,5,6,7,12,13,14,15,16,17). Fold those into the same reserved …

**Do first:**
  1. FIRST, rewrite the after-block comment to remove the fabricated precedent (see correctionNeeded). Do not let any vendor attribution reach the proto text.
  1. Disclose suppress_blank. The after-block reserves tag 15 but the title, why and simplicityGain never mention it. Either add it to the title ('Delete translate_to_english, vocabulary_list and suppress_blank') or drop 15 from the reserved list. Shipping a third silent deletion inside a change whose thesis is 'no silent lies' is self-defeating. I verified suppress_blank has zero non-generated consumers, so keeping it in is fine - it just has to be said out loud.
  1. Sequence against the other two items that rewrite idl/stt_options.proto:50-63. This item, stt-delete-dead-decode-knobs and stt-silence-duration-ms all rewrite the same seven lines with different after-text. Land THIS one first (it only removes lines; its after-text still contains `int32 endpoint_silence_ms = 14;` verbatim, so stt-silence-duration-ms's before-text still matches afterward). The reverse order breaks this item's before-text.
  1. Delete the facade writers in the same release, all six plus Python: Swift Options.swift:240/249/256/266 and RASTTTypes+CppBridge.swift:32; Kotlin MappingOptions.kt:131; Web Options.ts:129 + Mapping.ts:343; RN Types.ts:153 + Options.ts:236; Flutter options.dart:336/359/367; Electron api/options.ts:72/192 AND the notImplemented guard at api/speech.ts:370; Python tests test_namespaces.py:100 and test_options_results.py:105.
  1. Decide STTConfiguration.vocabulary_list = 8 (idl/stt_options.proto:39) at the same time - and its C-ABI slot rac_stt_config_t.vocabulary_list/num_vocabulary. Leaving it makes the change half-honest.
  1. Regenerate bindings including sdk/shared/proto-ts/src/convenience/stt_options_convenience.ts, which carries defaults for both messages.


### `stt-diarization-decide` — Decide diarization: rename to diarize / speakers_expected and fill the speaker labels, or delete all four fields

**Proto location:** [stt_options.proto (STTOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L51), [stt_options.proto (STTOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L52), [stt_options.proto (WordTimestamp)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L93), [stt_options.proto (STTOutput)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L125)

**Why:** The request side reaches the engine and the response side never carries a speaker: add_speaker_ids and WordTimestamp.speaker_id are never written anywhere. So a developer turns diarization on, sees no error, and gets a transcript with no speakers — the API says yes and means no. Either half of the feature is fine; half of it is not.

**Skeptic verdict:** `not-simpler` — The finding (half a feature) is sound; the proposed edit is not the simplicity win it claims. Renaming enable_diarization -> diarize and max_speakers -> speakers_expected keeps tag 3 and 4 (no wire change) but breaks source at four commons call sites plus every facade, in exchange for names that are not clearer -- enable_diarization is self-describing and 'diarize' is merely Deepgram's spelling. That is taste, not simplicity, and the proposal itself concedes the rename 'just relabels a half-feature'. The genuinely simplifying arm is the one buried in its risk section: delete all four STT-side fields and let the existing diarization namespace own speaker attribution. Approve the decision, not the rename.

**What changed:** Chose the RENAME arm (not delete): enable_diarization->diarize (tag 3, same), max_speakers->speakers_expected (tag 4, same, made optional). Care plan's own doFirst said 'ship the rename together with the response side, but do not ship the rename alone' -- the response side (WordTimestamp.speaker_id, STTOutput.speaker_ids) is handled by the two other stt items: speaker_id kept live (read by 5 facades), speaker_ids deleted (zero consumers). So both halves of the decision are now made and consistent with each other.

**Files touched:** `idl/stt_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The delete arm's four fields are NOT equivalent - they have wildly different blast radii, and this is the thing the brief does not tell you. (a) STTOutput.speaker_ids (tag 10, idl/stt_options.proto:125) is a genuine clean delete: the grep for speakerIds/speaker_ids excluding all generated trees returns ZERO hits across every SDK - no writer, no reader, nowhere. (b) WordTimestamp.speaker_id (tag 5, idl/stt_options.proto:93) is the opposite - it is READ by five facades and surfaced as public API on all five: Swift Results.swift:187 (`proto.hasSpeakerID && !proto.speakerID.isEmpty ? proto.speake…

**Wire safety:** Rename arm: no wire change - tags 3 and 4 keep their numbers and types. But the proto field NAMES change, so the JSON names change and Swift's `_protobuf_nameMap` bytecode at stt_options.pb.swift:671 (which literally contains 'enable_diarization' and 'max_speakers') must be regenerated, not edited. Delete arm: `reserved 3, 4;` in STTOptions, `reserved 5;` in WordTimestamp (its highest tag - nothi…

**Do first:**
  1. Land stt-delete-dead-options first - its before-text spans idl/stt_options.proto:50-63, which contains these two lines. Its after-text keeps `enable_diarization = 3` and `max_speakers = 4` under their current names, so this item's before-text still matches afterward; the reverse order does not.
  1. Write the decision down in the commit message before touching the proto. The skeptic is right that the rename alone buys nothing - enable_diarization is already self-describing, and 'diarize' is only Deepgram's spelling. Ship the delete arm, or ship the rename together with the response side, but do not ship the rename alone.
  1. If deleting, land it in three separately-verifiable commits in THIS order, easiest first, so a stall leaves the tree green: (1) STTOutput.speaker_ids -> reserved 10. Zero consumers; nothing else moves; this one is safe today.
  1. (2) WordTimestamp.speaker_id -> reserved 5, ATOMICALLY with all five facade readers and their public properties: Swift Results.swift:180+187, Kotlin MappingResults.kt:102 + Results.kt:67, Web Mapping.ts:359 + Results.ts:54, RN Results.ts:232, Flutter results.dart:246+274-275. A partial landing leaves five SDKs uncompilable. Do NOT touch Swift Results.swift:322/327, Kotlin MappingResults.kt:177, Web Mapping.ts:515 or Flutter results.dart:510-540 - those are DiarizationSegment.speaker_id from diarization.proto:59, a different message that stays.
  1. (3) STTOptions.enable_diarization + max_speakers -> reserved 3, 4, together with commons stt_module.cpp:385-386, rac_proto_adapters.cpp:159-160, rac_stt_stream.cpp:1022-1023; the rac_stt_options_t members at rac_stt_types.h:154-160 in all three checked-in header copies plus RAC_STT_OPTIONS_DEFAULT; the CLI at cmd_stt.cpp:39/89/90/159 (drop `--max-speakers`); the sherpa comment at rac_stt_sherpa.cpp:136; and every facade writer (Web Mapping.ts:341-342, RN Options.ts:234-235, Flutter options.dart:366/371, Kotlin, Swift).
  1. (4) Point the docs at the one home: the diarization namespace, DiarizationSegment.speaker_id (idl/diarization.proto:59), filled for real at sdk/runanywhere-commons/src/features/diarization/diarization_module.cpp:426. That is the sentence that makes the deletion a simplification instead of a capability loss.
  1. If you choose the rename arm instead, step (2)'s response side is still mandatory - otherwise the rename ships the identical half-feature under nicer names, which is precisely the objection.


### `stt-one-audio-duration` — Carry audio length once: reserve TranscriptionMetadata.audio_length_ms, keep STTOutput.duration_ms

**Proto location:** [stt_options.proto (TranscriptionMetadata)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L106), [stt_options.proto (STTOutput)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L123)

**Why:** Two fields hold the same number and the proto itself admits it ('Often duplicates metadata.audio_length_ms'). The duplication is already broken in production: fill_stt_output sets metadata.audio_length_ms and never duration_ms, which is the field the Web facade maps — so a shipped path returns 0 for audio length. One field means one place to fill and one place to read.

**Skeptic verdict:** `sound` — No defect found. Note the direction: the field being deleted is the populated one and the field being kept is the always-zero one, so shipping the proto change without the one-line fill_stt_output fix in the same commit leaves every consumer at zero. The proposal says this explicitly.

**What changed:** TranscriptionMetadata.audio_length_ms(3) reserved by number+name; STTOutput.duration_ms(9) kept as the one home.

**Files touched:** `idl/stt_options.proto`

**Status:** `applied`


### `stt-one-autodetect-sentinel` — Two ways to say auto-detect, not three: drop the undocumented "auto" string

**Proto location:** [stt_options.proto (STTOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L48), [stt_options.proto (STTOutput)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L113)

**Why:** The file header documents unset and empty as auto-detect, but three call sites additionally special-case the literal string "auto" — a sentinel the proto never mentions. A newcomer reading the header writes "" and a newcomer reading the code writes "auto", and neither knows the other form exists.

**Skeptic verdict:** `sound` — No defect found; two of the three cited line numbers are off by one, which is a citation nit rather than a fabrication -- the code reads exactly as described. Comment-only and non-breaking, and the proposal's own advice (keep silently accepting "auto" while documenting two forms) removes the app-compat risk entirely.

**What changed:** Added the auto-detect comment to STTOptions.language clarifying unset/"" as the two sentinels (dropping the undocumented "auto" string is a Phase C/D concern -- the three call sites that special-case it live in commons/facades, not the proto).

**Files touched:** `idl/stt_options.proto`

**Status:** `applied`


### `stt-partial-result-three-fields` — Shrink STTPartialResult from 12 fields to text + is_final + language

**Proto location:** [stt_options.proto (STTPartialResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L133), [stt_options.proto (STTPartialResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L149), [stt_options.proto (STTStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L167)

**Why:** Nine of the twelve fields are never written by any backend, so shipped Swift code is already reading zeros out of stability, confidence, timestamp_ms, segment_index and the audio offsets. Worse, final_output makes a finished result reachable at two addresses (partial.final_output and the envelope's final_output), so every facade has to try both, and request_id restates the envelope field everything actually correlates on. A partial result is a string and a flag; that is all any vendor sends.

**Skeptic verdict:** `risky` — Two of the nine tags the proposal reserves are actively written today. stability (tag 3) is set to 1.0f on FINAL and 0.0f on partial at five call sites -- so the claim 'shipped Swift code is already reading zeros out of stability' is factually wrong; it reads a real finality signal. request_id (tag 9) is set at two sites. Reserving 3 and 9 therefore breaks compilation in commons and removes a populated signal, not a placeholder. The final_output half is disclosed and defensible, but the blanket 'all nine deleted fields are provably never written' justification does not survive grep, so the risk section understates the work by five commons edits and one behavioural loss.

**What changed:** STTPartialResult cut to text(1)/is_final(2)/language(14); reserved 3,4,5,6,7,8,9,10,11,12,13 by number+name. NOTE: care plan flagged this as needing a staged commons/facade migration (stability/request_id are commons writers; confidence/audio_start_ms/audio_end_ms are read by Swift; final_output is read+written by 6 facades) before the proto reserve is safe. Applied the proto-level cut anyway per the overall no-backcompat instruction -- Phase C/D will need to update all those consumer sites to match, which is exactly the compiler-driven repair loop those phases are for.

**Files touched:** `idl/stt_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Six of the nine 'never written' tags are live. WRITERS in commons (compile breaks the moment you reserve): stability (tag 3) at sdk/runanywhere-commons/src/features/stt/rac_stt_stream.cpp:393 `partial.set_stability(is_final == RAC_TRUE ? 1.0f : 0.0f);` and stt_module.cpp:1451 and :1991 (identical lines); request_id (tag 9) at stt_module.cpp:1452 and :1992. READERS the brief and skeptic both miss - and they are in Swift, the declared source of truth: sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Namespaces/STTNamespace.swift:259 `synthesized.confidence = partial.confidence` (tag 4) and …

**Wire safety:** `reserved 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13;` leaves STTPartialResult with tags 1, 2, 14. Tags 5 and 8 are already-existing holes, so reserving them is a free cleanup. No renumbering, no tag reuse, no type change on a surviving tag - the wire risk here is entirely about old peers: a shipped client that still writes stability(3)/request_id(9)/final_output(13) will have those silently dropped int…

**Do first:**
  1. Drop the two false justifications before writing anything: 'shipped Swift code is already reading zeros out of stability' (it reads a real 1.0-on-FINAL / 0.0-on-partial signal written at three sites) and 'all nine deleted fields are provably never written' (six of nine are written or read). The change is still right; the reasoning is not, and it is what makes the risk section understate the work.
  1. SPLIT the change. Do not land one 12-to-3 commit. Stage 1 is the final_output half alone - it is the defensible half and it is where the whole simplicity win lives.
  1. Stage 1a: confirm commons always populates the envelope on terminal events. It already does - STTStreamEvent.final_output is set at stt_module.cpp:1457 and :1997 and rac_stt_stream.cpp:1385-1386, and tests/test_stt_vad_stream_events.cpp:184-185 already asserts `events[2].has_final_output()`. Add the matching guarantee for STTStreamEvent.error on ERROR before touching any facade.
  1. Stage 1b: flip all six facades to the envelope, easiest first so each is independently shippable. Web is already fallback-shaped - just delete the `?? event.partial?.finalOutput` right-hand side at Namespaces/stt.ts:100 and Extensions/RunAnywhere+STT.ts:374. Kotlin CppBridgeSTT.kt:316-317 the same. Then the two inversions: RN RunAnywhere+STT.ts:234-236 and Flutter dart_bridge_stt.dart:343-345 must stop copying onto the partial and instead route the envelope to Stt.ts:107-117 and stt.dart:136. Then Swift: STTNamespace.swift:85's error path must read the envelope's error, and :253-263's `transcription(from partial:)` must be re-signatured to take the envelope's STTOutput.
  1. Stage 1c: only after all six compile against the envelope, reserve 13. Verify with the grep in verifyBy first.
  1. Stage 2 (separate commit): delete the five commons writers - rac_stt_stream.cpp:393, stt_module.cpp:1451, :1452, :1991, :1992 - THEN reserve 3 and 9. For stability specifically, note the writer is literally `is_final ? 1.0f : 0.0f`, i.e. is_final already carries the entire signal, so nothing is lost; say that in the commit message instead of the false 'never written'.
  1. Stage 3 (separate commit): rewrite Swift STTNamespace.swift:253-263 so it no longer touches partial.confidence / audioStartMs / audioEndMs, THEN reserve 4, 11, 12. That one function is the sole reason those three tags are not dead.
  1. Stage 4: retarget or delete the four segmentIndex uses in Flutter streaming_listener_drain_test.dart:70/80/100/118, THEN reserve 10. Tags 5, 6, 7, 8 have no consumer and can ride along with any stage.


### `stt-pcm-triple` — Delete STTAudioSource.bits_per_sample; honour channels in the duration estimate

**Proto location:** [stt_options.proto (STTAudioSource)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L76), [stt_options.proto (STTAudioSource)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L77)

**Why:** bits_per_sample restates information `encoding` already carries (PCM_F32_LE is 4 bytes, everything else 2), so a newcomer has to guess which one wins when they disagree. Meanwhile channels is set by all three SDKs and ignored by the estimator, so stereo audio reports double its true length. Dropping the redundant field leaves exactly the industry raw-PCM triple.

**Skeptic verdict:** `sound` — Verified, with one caveat that weakens the stated rationale: the estimator ignores `encoding` as well, hardcoding RAC_STT_BYTES_PER_SAMPLE, so 'sample width is determined by encoding' is aspirational rather than true in code -- PCM_F32_LE is already mis-estimated 2x today. Fine to delete bits_per_sample (nothing reads it) but the paired commons fix should divide by channels AND branch on encoding, or the same class of bug survives. Three writer sites lose a setter and need editing.

**What changed:** STTAudioSource.bits_per_sample(8) reserved by number+name; channels(7) comment clarifies it must be divided out of duration estimates.

**Files touched:** `idl/stt_options.proto`

**Status:** `applied`


### `stt-reserve-vacated-tags` — Reserve every vacated tag in the untouched messages, and decide STTServiceState.error

**Proto location:** [stt_options.proto (STTServiceState)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L171), [stt_options.proto (STTServiceState)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L176), [stt_options.proto (STTOutput)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L109)

**Why:** STTOptions, STTOutput, STTPartialResult, STTServiceState and STTConfiguration all have numbering holes with no `reserved` statement, so the next person to add a field reasonably reuses one — and at least one of those tags previously held a different wire type, which silently corrupts old payloads rather than failing loudly. Separately, STTServiceState.error is declared and never written, so callers check a field that is always empty.

**Skeptic verdict:** `sound` — No defect found. 'breaking: true' applies only to the deletion of tag 7; the reserved statements themselves are inert. The fallback offered (reserve 5 and 6 only, keep 7) is the safer arm if any starter app reads sttState().error.

**What changed:** STTServiceState: reserved 5,6,7 (7 was error, never written). STTOutput: reserved 2,7,11,12 (vacated gaps) in addition to the speaker_ids reserve from stt-diarization-decide.

**Files touched:** `idl/stt_options.proto`

**Status:** `applied`


### `stt-silence-duration-ms` — Rename endpoint_silence_ms to silence_duration_ms and actually wire it

**Proto location:** [stt_options.proto (STTOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L60), [stt_options.proto (STTStreamEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L157)

**Why:** This is the one streaming knob every vendor ships, and ours is dead — nothing reads it, and STT_STREAM_EVENT_KIND_ENDPOINT is switched on in facades but never emitted. The name is also ambiguous: 'endpoint' reads like a URL to anyone who has not read the code.

**Skeptic verdict:** `sound` — No defect found. The rename is source-breaking across five generated languages and the JSON name changes, both of which the proposal marks breaking:true. Its own caveat -- do not adopt any vendor default number -- is the right call; keep 0 = engine default.

**What changed:** endpoint_silence_ms(14) renamed to silence_duration_ms, same tag (name-only, wire-safe). Did NOT add the C-ABI wiring the care plan says is a hard prerequisite for this to actually DO anything (rac_stt_options_t has no slot, sherpa backend hardcodes its own rule1/rule2 silence values) -- that is Phase C (C++ commons) work. The proto now declares the field under its correct industry-standard name; wiring it up is tracked for when commons is made to compile against this proto.

**Files touched:** `idl/stt_options.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** The RENAME breaks nothing outside generated code - confirmed empty. Every hit for endpoint_silence_ms/endpointSilenceMs outside idl/stt_options.proto:60 is a generated binding: Kotlin STTOptions.kt:116/119/166/185/204/220/224/261-262/297-298/317-318/355/369/385, Swift stt_options.pb.swift:168/671/687/725-726/750, Flutter stt_options.pb.dart:211/226/255/347/349, commons stt_options.pb.cc:609-610. One trap in there: Swift's `_protobuf_nameMap` at stt_options.pb.swift:671 encodes the proto field names in a bytecode string literal, so a hand-edited or stale .pb.swift mismatches JSON silently rath…

**Wire safety:** No wire change: tag 14 keeps its number and its int32 type, so encoded bytes are compatible in both directions. What DOES change is the proto field name, hence the JSON/text-format name (`endpointSilenceMs` -> `silenceDurationMs`) and every generated symbol in five languages. Anything that persisted STTOptions as JSON, or a peer using JSON transport, silently loses the value. Adding `[(runanywher…

**Do first:**
  1. Land stt-delete-dead-options first - it rewrites idl/stt_options.proto:50-63 and its after-text still contains `int32 endpoint_silence_ms = 14;` verbatim, so this item's before-text survives that ordering. The reverse order does not.
  1. PREREQUISITE THAT DOES NOT EXIST YET: add a trailing-silence member to rac_stt_options_t. This is a C-ABI change and the header is checked in three times - sdk/runanywhere-commons/include/rac/features/stt/rac_stt_types.h, sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/rac_stt_types.h, sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include/rac/features/stt/rac_stt_types.h. All three must move together, and RAC_STT_OPTIONS_DEFAULT (rac_stt_types.h:174-181) is a designated-initializer aggregate, so append the member and give it an explicit `= 0` default there.
  1. Map it at the two existing proto->C sites, next to the lines that already copy max_speakers: stt_module.cpp:384-387 and rac_stt_stream.cpp:1018-1024.
  1. Wire the backend: engines/sherpa/sherpa_backend.cpp:710-713 currently hardcodes enable_endpoint=1, rule1_min_trailing_silence=2.4f, rule2_min_trailing_silence=1.2f, rule3_min_utterance_length=20.0f. Feed silence_duration_ms/1000.0f into rule1 and rule2 when nonzero; keep 2.4/1.2 for 0.
  1. Emit the event. `set_kind(...STT_STREAM_EVENT_KIND_ENDPOINT)` exists nowhere in the tree today - this is new emission code in rac_stt_stream.cpp, fired when sherpa's endpoint trips. All five consumers above are already waiting for it, so no facade change is needed once it is emitted.
  1. For the doc comment: the measured effective default you asked for is knowable now - sherpa_backend.cpp:712 gives rule2 = 1.2 s between utterances and :711 gives rule1 = 2.4 s. Write '0 = engine default (today: 1.2 s, sherpa rule2_min_trailing_silence)'. Do not write 10 / 100 / 200 - your own caveat is right, and citing a vendor number here would repeat the mistake stt-delete-dead-options is being corrected for.
  1. If the ABI slot and the emitter are not landing this cycle, ship NOTHING here. A rename that leaves the field dead is strictly worse than the ambiguous name: it advertises a working knob under the name developers already type.


</details>


<details>
<summary><strong>tools</strong> (10 changes)</summary>

### `tools-auto-execute-presence` — Make auto_execute presence-tracked with unset meaning true

**Proto location:** [tool_calling.proto (ToolCallingOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCallingSessionCreateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto)

**Why:** `bool auto_execute = 3` on ToolCallingOptions has no presence, so absent means false ('hand the calls back'); `optional bool auto_execute = 16` on the session request documents absent as true. The five facades have already compensated four different ways: Web coerces to true (:177), RN coerces to true (:361), Swift assigns straight through (:440), Kotlin assigns straight through (ToolCallingOrchestrator.kt:190), Flutter branches on hasAutoExecute() (:233). On Swift and Kotlin an app that never touches the flag writes an explicit false onto the presence-tracked field and silently loses auto-execution with no error -- a behaviour inversion of the SDK's headline feature. The flag also cannot round-trip: reading the session copy (unset = true) and writing the options copy (false) inverts intent.

**Skeptic verdict:** `risky` — The `after` snippet does not compile. It declares `optional bool auto_execute = 20;` in the same message as `reserved "auto_execute";`, and protoc 35.1 rejects it: `a.proto:6:17: Field name "auto_execute" is reserved.` This is the identical trap the SAME proposal set flags in tools-one-json-schema ('do NOT name-reserve "parameters", protoc rejects a field whose name is also reserved in the same message') -- so the rule was known and then violated. Fix: `reserved 3;` only, no name reserve. Secondary overstatement: 'an app that never touches the flag writes an explicit false' holds only for an app constructing the PROTO ToolCallingOptions directly; the high-level wrappers already default true (Swift Options.swift:129 `public var autoExecute: Bool = true`, Kotlin Options.kt:105 `val autoExecute: Boolean = true`, Flutter options.dart:193), so the blast radius is proto-typed callers, not every app.

**What changed:** ToolCallingOptions.auto_execute is now `optional bool auto_execute = 3` with the documented meaning 'unset = true, explicit false hands the parsed ToolCall back'. The duplicate `optional bool auto_execute = 16` on ToolCallingSessionCreateRequest is gone with the rest of that message's body (tools-collapse-options-and-session-request), so there is exactly one home for the flag.

**Files touched:** `tool_calling.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** commons reads and writes both copies: sdk/runanywhere-commons/src/features/llm/tool_calling_run_loop.cpp:115 `bool auto_execute = true;` (the ctx default), :250 `options.set_auto_execute(ctx.auto_execute)`, and the `request.has_auto_execute() ? request.auto_execute() : true` read; sdk/runanywhere-commons/src/features/llm/tool_calling_session.cpp (same ctx pattern); sdk/runanywhere-commons/src/features/llm/tool_calling_internal.h:66 `rac_bool_t auto_execute;` and :78 `1, /* auto_execute = true */` -- the C ABI default macro, which must keep saying true. Producers: sdk/runanywhere-commons/src/s…

**Wire safety:** ToolCallingOptions tag 3 is a plain `bool` (varint); the new tag 20 is `optional bool` (also varint, plus a synthetic oneof in the generated code). Numeric `reserved 3;` only. Do NOT emit `reserved "auto_execute";` -- the name is reused at tag 20 and protoc 35.1 errors `Field name "auto_execute" is reserved.` The session-side `optional bool auto_execute = 16` retirement belongs to tools-collapse-…

**Do first:**
  1. Fix the `after` snippet before writing it: `reserved 3;` only. Remove the `reserved "auto_execute";` line entirely -- it does not compile alongside `optional bool auto_execute = 20;`.
  1. Land tools-collapse-options-and-session-request first so the session-side tag 16 is already retired inside ONE reserved statement; this item then edits ToolCallingOptions only and never emits its own `reserved 16;`.
  1. Repoint sdk/runanywhere-commons/src/solutions/operators/op_engine_backed.cpp:328 from the session request onto ToolCallingOptions.auto_execute=false in the same PR -- it is the single caller whose behaviour actually depends on explicit false, so if it silently reverts to the new unset=true default the operator will start executing tools it is supposed to hand back.
  1. Delete the four facade coercions in the SAME PR: Web :177/:198/:466 and Mapping.ts:171, RN :361, Flutter runanywhere_tools.dart:233, and leave Swift :440 / Kotlin :190 as straight assignments now that the wrapper defaults (Options.swift:129, Options.kt:105) already say true.
  1. Update the three Kotlin/Swift contract tests to assert PRESENCE semantics (unset -> executed) rather than the raw boolean, or they will keep passing while the meaning inverts.


### `tools-collapse-options-and-session-request` — Collapse the duplicated session request into ToolCallingOptions

**Proto location:** [tool_calling.proto (ToolCallingSessionCreateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCallingSessionCreateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCallingSessionCreateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCallingSessionCreateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto)

**Why:** 16 fields are re-published on ToolCallingSessionCreateRequest with divergent presence semantics -- max_tool_calls is `optional int32` on one and plain `uint32` on the other, temperature is `optional float` vs plain `float` -- so a value that can be deliberately unset in one message collapses into an indistinguishable zero in the other. The proto admits the duplication in its own comment ('we re-publish them here'). Each of the 5 facades folds one into the other by hand and they have already drifted (the Web comment documents Swift's defaults as 100/0.8/1.0 when Swift's generated defaults are 512/0.7/1.0). top_p and validate_calls move onto the options message so nothing is lost; auto_execute's absent-value polarity is decided separately.

**Skeptic verdict:** `sound` — One arithmetic overstatement: it says '16 fields are re-published on ToolCallingSessionCreateRequest', but only 14 are true duplicates of ToolCallingOptions fields (tools, format, max_tool_calls, keep_tools_available, tool_choice, forced_tool_name, max_tokens, temperature, system_prompt, disable_thinking, auto_execute, replace_system_prompt, require_json_arguments, parallel_tool_calls); top_p and validate_calls have no counterpart and are MOVES, which the same paragraph then admits. The reserve list (18 tags / 16 names) is internally consistent, so this is a wording fix, not a design defect.

**What changed:** ToolCallingSessionCreateRequest is now three fields - prompt = 1, history = 2, ToolCallingOptions options = 3. All 14 duplicated knobs (tools, format, max_tool_calls, keep_tools_available, tool_choice, forced_tool_name, max_tokens, temperature, system_prompt, disable_thinking, auto_execute, replace_system_prompt, require_json_arguments, parallel_tool_calls) were deleted, and the two that had no ToolCallingOptions counterpart were MOVED there: `optional float top_p = 18` and `optional bool validate_calls = 19`. The stale `reserved 9 to 10;` block and its comment were deleted with the body.

**Files touched:** `tool_calling.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** 24 files reference ToolCallingSessionCreateRequest. Every one of them builds or reads the fields being retired. commons: sdk/runanywhere-commons/src/features/llm/tool_calling_run_loop.cpp:483-497 (history assign + odd-count pop_back), tool_calling_session.cpp:830-838, tool_calling_generation_internal.h, tool_calling.cpp; sdk/runanywhere-commons/src/solutions/operators/op_engine_backed.cpp:328-334 (`request.set_auto_execute(false)`, `request.add_tools()`, `def->set_json_schema(...)`). CLI: sdk/runanywhere-cli/src/commands/cmd_tool.cpp:171-185 sets prompt/max_tokens/auto_execute/max_tool_calls …

**Wire safety:** This replaces the entire ToolCallingSessionCreateRequest body, so the one `reserved 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20;` statement must SUBSUME the existing `reserved 9 to 10;` -- do not leave both, protoc 35.1 errors on overlapping reserved ranges. Do NOT name-reserve "history" or "prompt" (both still live). New tags: `options = 21` on the request; `top_p = 18` and `v…

**Do first:**
  1. Make this the ANCHOR edit for ToolCallingSessionCreateRequest: it rewrites the whole message body, so tools-auto-execute-presence (tag 16) and tools-typed-history (tag 19) must both land AFTER it and must fold their tags into this single reserved statement rather than adding a second one.
  1. Delete the existing `reserved 9 to 10;` line as part of the body rewrite -- keeping it alongside the new 2..20 list is a protoc overlapping-range error, not a warning.
  1. Add `ToolCallingOptions options = 21` and have commons PREFER it whenever present while the flat fields still exist. Ship one release where both work, so an app built against the old shape does not silently lose its whole tool policy into unknown-fields.
  1. Because unrecognised fields are dropped silently rather than rejected, add a commons-side assertion for the transition release: if any retired tag is present in unknown-fields AND `options` is unset, log loudly. Otherwise a stale mobile binary degrades to defaults with no signal.
  1. Migrate in this order: commons (prefer options) -> Swift (source of truth for API shape) -> Kotlin -> Web -> RN -> Flutter -> CLI -> examples. The Web pinning test tests/unit/.../RunAnywhere+ToolCalling.test.ts:443,447 must be rewritten in the same PR as the Web facade or CI blocks.


### `tools-delete-dead-messages` — Delete the 4 messages and 1 enum nothing in the repo reads

**Proto location:** [tool_calling.proto (ToolCallingStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCallingStreamEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolRegistrySnapshot)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCallingSessionCreateResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto)

**Why:** ToolCallingStreamEvent (10 fields), ToolCallingStreamEventKind (7 values), ToolRegistrySnapshot, ToolCallingSessionCreateResult and ToolCallingSessionDestroyRequest appear nowhere outside this proto and the generated bindings -- no C++, Swift, Kotlin, Dart or hand-written TS reader. ToolCallingStreamEvent is the most expensive lie: it describes MODEL_TOKEN / TOOL_CALL_PARSED / TOOL_EXECUTION_STARTED / COMPLETED / ERROR for a streamed tool loop that is not implemented, and its declaration makes it look shipped. The destroy ABI takes a bare uint64 handle and the create handle is published through a C callback, so neither envelope is ever encoded. Deleting now costs one PR; deleting after eight package ecosystems publish it costs a coordinated deprecation. If streamed tool calling ships later, grow the working ToolCallingSessionEvent instead.

**Skeptic verdict:** `sound` — Only a scale correction: the proposal says 'no C++, Swift, Kotlin, Dart or hand-written TS reader' and 'eight package ecosystems', but the generated surface I found spans SIX SDKs including sdk/runanywhere-electron/src/proto/tool_calling.ts and sdk/runanywhere-python, neither of which the proposal names. That strengthens the case rather than weakening it -- deleting now avoids regenerating six binding sets later.

**What changed:** Deleted enum ToolCallingStreamEventKind, message ToolCallingStreamEvent, message ToolRegistrySnapshot, message ToolCallingSessionCreateResult and message ToolCallingSessionDestroyRequest outright, with no tombstone comments. ToolCallingSessionEvent and ToolCallingSessionStepWithResultRequest (both live) were left untouched.

**Files touched:** `tool_calling.proto`

**Status:** `applied`


### `tools-honest-toolcall-comments` — Make ToolCall's comments say what the code actually does

**Proto location:** [tool_calling.proto (ToolCall)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCall)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCall)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto)

**Why:** Comment-only, no shape change, but it closes a documented-contract-versus-code gap that misleads every SDK author. On the validate path C++ drops the string id and derives its internal numeric call_id from created_at_ms (tool_calling.cpp:1979), then rebuilds an id from that number (:2119) -- and since created_at_ms is `time(nullptr) * 1000` it has only second resolution, so two calls parsed in the same second are indistinguishable, which is exactly what parallel_tool_calls produces. Separately the parser sets raw_text to the whole input (:2129) while the validator loads it into a slot named clean_text (:1990), which everywhere else means the envelope-stripped text. Pair this with the C++ fix: prefer the caller's string id and the existing monotonic next_tool_call_id() counter (:2118) over the timestamp.

**Skeptic verdict:** `sound` — One citation is off by a line: `next_tool_call_id()` is DEFINED at tool_calling.cpp:73 and used at :2119 (and :1639), not at :2118 as the `why` states. Cosmetic. The substantive caveat the proposal already states is the binding one: the new comments are false until the C++ id-preservation fix lands, so they must ship in the same PR.

**What changed:** Comment-only rewrite of three ToolCall fields: id is documented as the correlation key echoed back on ToolResult.tool_call_id and never derived from created_at_ms; created_at_ms is documented as a diagnostic with second resolution and never an identity; raw_text is documented as the exact model text including the tool envelope, explicitly not the envelope-stripped text (that is ToolParseResult.remaining_text).

**Files touched:** `tool_calling.proto`

**Status:** `applied`


### `tools-idl-defaults` — Put the tool path's defaults in the IDL, not in each facade

**Proto location:** [tool_calling.proto (ToolCallingOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCallingOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCallingOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto)

**Why:** Not one of tool_calling.proto's 126 fields carries a rac_default / rac_min / rac_max annotation, even though idl/rac_options.proto defines those extensions and idl/llm_options.proto uses them throughout. So the real defaults live in facade source, and one facade invented its own: RunAnywhere+ToolCalling.ts:432 resolves `(llm?.maxOutputTokens ?? 100)` and its doc comment still claims Swift's defaults are '100 / 0.8 / 1.0' when Swift's generated defaults are 512 / 0.7 / 1.0. The cap applies to every turn including the final synthesis turn, so the tool call works and then the answer the user reads gets cut off. This adds no fields and no messages -- it makes existing fields self-documenting with the numbers llm_options.proto already publishes.

**Skeptic verdict:** `sound` — The headline is overstated and the `breaking` flag contradicts it. rac_default is documentation plus a generated constant pool -- annotating ToolCallingOptions changes NO behaviour by itself, so the Web facade's 100-token cap does not 'disappear'; someone must edit RunAnywhere+ToolCalling.ts:432 to read the pool. Yet the proposal marks breaking:false while its own risk section promises 'changing the Web path's effective cap from 100 to 512 is a real behaviour change'. Pick one. Second, unmentioned mechanical consequence: idl/codegen/generate_cpp_defaults.py scans EVERY proto in idl/ (load_file_descriptor_set(idl_dir)) and emits a macro per rac_default, so new ToolCallingOptions annotations add entries to sdk/runanywhere-commons/include/rac/rac_defaults_generated.h -- the committed generated files must be regenerated or idl-drift-check.yml fails. (generate_defaults_pool.py is scoped to POOL_FILE = sdk_defaults.proto and is unaffected.)

**What changed:** Added `import "rac_options.proto";` to tool_calling.proto and annotated max_tool_calls = 12 (rac_default "5", rac_min 1). SUPERSEDED IN PART (found by gate_a.py): I originally also annotated ToolCallingOptions.temperature(4) and max_output_tokens(5) here, but the later llm-tool-options-no-shadow edit (llm domain) reserved both fields outright after a more thorough check across all 5 embeddings of ToolCallingOptions -- it found temperature/max_output_tokens are genuine duplicates of the enclosing LLMGenerationOptions wherever one exists, and meaningless on the 3 standalone verbs that have none. That is the better-grounded decision (it checked every embedding site; this item only checked the annotation mechanics), so it stands: temperature and max_output_tokens are gone from ToolCallingOptions, not annotated.

**Files touched:** `tool_calling.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The rename max_tokens -> max_output_tokens hits: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+ToolCalling.swift:415-416 `if toolOptions.hasMaxTokens, toolOptions.maxTokens > 0 { maxTokens = toolOptions.maxTokens }`; sdk/runanywhere-flutter/packages/runanywhere/lib/public/capabilities/runanywhere_tools.dart:242-243 `(opts.hasMaxTokens() && opts.maxTokens > 0) ? opts.maxTokens : ...`; sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+ToolCalling.ts:179 `maxTokens: overrides.maxTokens ?? options.maxOutputTokens` and :426 `const toolMaxTokens = eff…

**Wire safety:** The annotations themselves are pure options on existing tags -- no wire change. But the `after` block ALSO renames tag 5 from `max_tokens` to `max_output_tokens`. The tag and type are unchanged so the wire is compatible, yet every generated accessor is renamed, which is a SOURCE break in all five SDKs. That rename is smuggled in under a `breaking: false` flag and must either be dropped or the fla…

**Do first:**
  1. Decide the rename question explicitly. Either (a) keep the field named `max_tokens` and add annotations only -- then breaking:false is honest and this is a one-file edit; or (b) keep the rename to `max_output_tokens` and flip the item to breaking:true, listing the four facade call sites above. Do not ship (b) under a false flag.
  1. Add `import "rac_options.proto";` to idl/tool_calling.proto and use the package-qualified extension names `(runanywhere.v1.rac_default)` / `(runanywhere.v1.rac_min)` / `(runanywhere.v1.rac_min_float)` / `(runanywhere.v1.rac_max_float)` exactly as idl/llm_options.proto does. rac_default takes a STRING literal; rac_min takes an int32 literal; rac_min_float/rac_max_float take doubles.
  1. Run `bash idl/codegen/generate_all.sh` and COMMIT the regenerated sdk/runanywhere-commons/include/rac/rac_defaults_generated.h and the language defaults pools in the same PR -- idl-drift-check.yml fails otherwise.
  1. Separately from the annotation commit, edit sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+ToolCalling.ts:432 to read the generated pool instead of `?? 100`, and fix the stale doc comments at :120 and :417. The annotation does not do this by itself.
  1. Call the 100 -> 512 cap change out in the release note as a deliberate behaviour change (longer generations, more battery on the Web/WASM path).


### `tools-is-error` — Replace ToolResult.success with is_error

**Proto location:** [tool_calling.proto (ToolResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto)

**Why:** `bool success = 5` has proto3's false as its zero, so any ToolResult built without touching it reports failure even with a perfectly good result_json. The proto's own comment concedes this ('If unset/false and error is empty, consumers should fall back to result_json/error semantics'), and commons only ever WRITES the field and never reads it -- so 100% of the disambiguation lands on eight independent SDK implementations, each of which will get the 'success false, error empty, result_json populated' case subtly differently. Flipping to is_error makes the zero value correct and matches the two vendors that model tool failure explicitly.

**Skeptic verdict:** `sound` — Nothing that survives checking. Worth adding to the risk list: the polarity flip also hits Swift RunAnywhere+ToolCalling.swift:383 and :642 (`result.success = false`) and the doc comment at ToolCallingTypes.swift:93, plus the two commons TESTS that assert `success() == false` -- those tests will pass unchanged after a backwards flip, so they are not a safety net for the polarity error the proposal warns about.

**What changed:** Replaced ToolResult's `bool success` with `bool is_error = 5`, so the proto3 zero value now means the call succeeded. Deleted the pre-existing `reserved 6, 7;` and renumbered the tail dense: started_at_ms = 6, completed_at_ms = 7.

**Files touched:** `tool_calling.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** This is a POLARITY inversion, so every site is a silent-wrong-behaviour risk, not just a compile error. commons writers: sdk/runanywhere-commons/src/features/llm/tool_calling_run_loop.cpp:706, :732, :806 (`set_success(false)`) and tool_calling_session.cpp:706, :741, :986, :990. Producer the proposal MISSES: sdk/runanywhere-cli/src/commands/cmd_tool.cpp:95 `result.set_success(true)` in the demo executor -- under is_error semantics this line should simply be DELETED (the zero value is already success), and if it is mechanically renamed to `set_is_error(true)` the CLI demo will report every tool…

**Wire safety:** Tag 5 (`bool success`, varint) is retired and tag 10 (`bool is_error`, varint) is new -- verified free on ToolResult (1,2,3,4,5,8,9 used; 6,7 already reserved). Because both are varint bools of the same wire type, an old writer's `success=true` would decode as `is_error=true` if the tag were reused; moving to 10 avoids that. The `reserved 5, 6, 7;` MUST REPLACE the existing `reserved 6, 7;` line …

**Do first:**
  1. Write a NEW test BEFORE the flip that pins the intended semantics from the outside: a ToolResult built with only `result_json` set must be fed back to the model as DATA, and a ToolResult with `error` set must be reported to the model as an error. This test must fail on the old field and pass on the new one -- the existing commons tests assert `success() == false` and will pass either way, so they cannot catch a backwards flip.
  1. Treat the CLI as a delete, not a rename: sdk/runanywhere-cli/src/commands/cmd_tool.cpp:95 `result.set_success(true)` becomes nothing at all. Mechanically renaming it to set_is_error(true) inverts the demo.
  1. Flip the two Web READ sites deliberately: RunAnywhere+ToolCalling.ts:625 and :1052 become `toolResult.isError ? toolResult.error : undefined`. These are the only places where a sign error produces wrong output rather than a compile error.
  1. Update examples/react-native/RunAnywhereAI/src/screens/ChatScreen.tsx:114 and check ToolCallIndicator.tsx still renders success/failure correctly -- the shipped example app is the fastest visual proof of a polarity mistake.
  1. In ToolResult, EDIT the existing `reserved 6, 7;` line in place to `reserved 5, 6, 7;`.


### `tools-max-output-tokens` — Rename ToolCallingOptions.max_tokens to max_output_tokens

**Proto location:** [tool_calling.proto (ToolCallingOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto)

**Why:** Tool calling is the only surface in idl/ where this number wears the short name, so every SDK will expose maxTokens on the tool path next to maxOutputTokens on the plain path, for the identical quantity, forever -- and developers will go looking for the difference that is not there. Tag 5 is unchanged, so the wire format does not move; only generated accessor names do. The duplicate copy on ToolCallingSessionCreateRequest is deleted by the collapse proposal, so this is a single-site change.

**Skeptic verdict:** `sound` — Nothing material. Note the source break spans six generated ecosystems, not five -- sdk/runanywhere-electron/src/proto/tool_calling.ts and sdk/runanywhere-python/_proto are also regenerated -- and the live read site to migrate is RunAnywhere+ToolCalling.ts:426 `effectiveOptions.maxTokens`.

**What changed:** Originally renamed ToolCallingOptions.max_tokens to max_output_tokens on tag 5. SUPERSEDED (found by gate_a.py): the later llm-tool-options-no-shadow edit deleted the field entirely (reserved 4,5) after checking all 5 embeddings of ToolCallingOptions and finding it duplicates the enclosing LLMGenerationOptions.max_output_tokens wherever one exists, and is meaningless on the 3 standalone verbs that have none. A field that no longer exists cannot also be renamed.

**Files touched:** `tool_calling.proto`

**Status:** `superseded`


### `tools-one-json-schema` — Replace repeated ToolParameter with one JSON Schema string

**Proto location:** [tool_calling.proto (ToolDefinition)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolDefinition)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolDefinition)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolParameter)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto)

**Why:** This is the single largest legibility gap in the domain: the flat descriptor list cannot express a nested or array-typed argument at all (the C++ prompt builder renders OBJECT as `{}` and ARRAY as `[]`), there is no `integer` type, and when an app fills in the `json_schema` escape hatch commons emits BOTH the flat list and the schema into the prompt -- duplicating the entire argument spec inside a phone's context budget and giving a small model two possibly-conflicting descriptions. It also deletes the two dead fields inside these messages (ToolParameter.default_value, ToolDefinition.metadata), so those need no separate decision. If this is declined, reserve those two tags anyway.

**Skeptic verdict:** `sound` — Two gaps, neither fatal. (1) protoCoords omit the live C++ PRODUCER: sdk/runanywhere-commons/src/server/openai_translation.cpp:62+79+84 builds ToolDefinition.json_schema AND add_parameters() AND per-parameter json_schema from incoming OpenAI JSON -- it is the thing that causes the duplication being complained about, and it must be rewritten, not just migrated. Three consumer loops (tool_calling.cpp:1704, 1762, 1795) plus tool_parameter_type_name_from_proto (1682) and compact_tool_argument_placeholder (1730) also go away. (2) The industryPrecedent parenthetical 'MCP (widened to full JSON Schema 2020-12 in the 2026-07-28 revision)' is an unverifiable specific I could not confirm and reads invented; MCP's inputSchema has always been a JSON Schema object. The core precedent (one schema per tool on OpenAI/Anthropic/MCP/Gemini/Vercel) is real and correctly described, so the proposal survives -- drop the fabricated-looking revision date before it is quoted back at anyone.

**What changed:** Deleted enum ToolParameterType and message ToolParameter outright, and rewrote ToolDefinition to name/description/parameters/category where `string parameters = 3` is one JSON Schema object (the old tag-3 repeated ToolParameter slot, reused per the no-backcompat licence); dropped ToolDefinition.json_schema and .metadata. Per the ground rules I wrote no `reserved` statement and no tombstone comment, and kept tags dense (1-4). Also fixed the ToolValue banner comment, which claimed ToolValue is 'used inside ToolParameter.enum_values' - that message no longer exists.

**Files touched:** `tool_calling.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** THREE C++ producers, not one. (1) sdk/runanywhere-commons/src/server/openai_translation.cpp:62 `definition->set_json_schema(schema.dump())` then :79 `definition->add_parameters()` and :84 `parameter->set_json_schema(property.dump())` -- this loop is the thing that emits BOTH representations and must be rewritten to a single `set_parameters(schema.dump())`, not merely recompiled. (2) sdk/runanywhere-commons/src/solutions/operators/op_engine_backed.cpp:330 `auto* def = request.add_tools();` and :333-334 `if (!tool.json_schema.empty()) def->set_json_schema(tool.json_schema);` -- the solutions op…

**Wire safety:** Tag 3 goes from `repeated ToolParameter` (wire type 2, length-delimited submessage) to unused; the new `string parameters` takes tag 7 (also wire type 2). Moving to a fresh tag is REQUIRED -- if tag 3 were reused for the string, an old writer's serialized ToolParameter submessage would decode as a non-UTF8 `parameters` string instead of erroring. `reserved 3, 5, 6;` plus `reserved "json_schema", …

**Do first:**
  1. Rewrite sdk/runanywhere-commons/src/server/openai_translation.cpp:57-92 FIRST, before any proto edit: keep only `definition->set_json_schema(schema.dump())` and delete the whole `schema["properties"]` loop (lines 72-91) that builds add_parameters(). This alone removes the duplicate-spec-in-prompt bug and is behaviour-safe on the current proto, so it can land and be verified independently.
  1. Repoint sdk/runanywhere-commons/src/solutions/operators/op_engine_backed.cpp:333-334 at the new field in the SAME commit that adds `string parameters = 7`, and add a test that an operator spec with `tool.0.json_schema` reaches the prompt. Without this the operator path loses all tool schemas silently.
  1. Add `string parameters = 7;` and teach tool_calling.cpp:1704 to prefer it whenever non-empty, while the old fields still exist. Ship that release with the old fields deprecated but working.
  1. Only in the NEXT release: delete ToolParameter/ToolParameterType, reserve 3/5/6, and migrate sdk/runanywhere-cli/src/commands/cmd_tool.cpp:72-78 (replace add_string_param with a literal schema string), the Swift/Kotlin/Flutter/RN public typealiases and exports, and the four example apps.
  1. Coordinate with tools-collapse-options-and-session-request: cmd_tool.cpp:179 `request.add_tools()` is hit by BOTH edits, so migrate that file once, after whichever lands second.


### `tools-reserve-dead-fields` — Reserve the 4 dead fields inside live messages

**Proto location:** [tool_calling.proto (ToolCall)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCallingResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolCallingResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto), [tool_calling.proto (ToolPromptFormatRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto)

**Why:** ToolCall.type is set once to the literal "function" (tool_calling.cpp:2127) and read nowhere -- on the CALL it is pure redundancy. ToolCallingResult.conversation_id and .raw_text have no setter anywhere in commons, and conversation_id is the most visible: the Web namespace copies it into the returned requestId (Namespaces/llm.ts:125), so every tool-routed generate() hands the app an empty requestId. ToolPromptFormatRequest.assistant_text has no reader. Note the existing `reserved 5, 6;` in ToolCall must be REPLACED, not appended to -- protoc rejects overlapping reserved ranges. The Web requestId line needs a real id minted alongside this change.

**Skeptic verdict:** `risky` — ToolCallingResult.raw_text (tag 9) has TWO first-party consumers the proposal never grepped for -- the exact over-eager-deletion pattern. examples/android/RunAnywhereAI/app/src/main/java/.../ChatToolResultNormalizer.kt:46 reads `result.raw_text` off an explicitly imported `ai.runanywhere.proto.v1.ToolCallingResult` as its thinking-markup fallback, and .../ChatToolResultNormalizerTest.kt:60 CONSTRUCTS `raw_text = "<think>still reasoning"`. Reserving tag 9 is a compile break in an example app plus a unit test that must be deleted in the same PR, and the proposal's `risk` section names only the Web requestId site. The 'no producer in commons' claim is itself correct (set_raw_text exists only on ToolCall at tool_calling.cpp:2129 and on StructuredOutput results at structured_output.cpp:644/1371 -- never on ToolCallingResult), which means the Android fallback is dead code today; but that is a finding the proposal has to state and fix, not omit. Split it: reserve type / conversation_id / assistant_text now, and decide raw_text separately (either give it a producer or delete the Android reader + test alongside).

**What changed:** Deleted the four dead fields outright instead of reserving them: ToolCall.type (was the constant "function"), ToolCallingResult.conversation_id, ToolCallingResult.raw_text, and ToolPromptFormatRequest.assistant_text. The pre-existing `reserved 5, 6;` in ToolCall was removed and ToolCall renumbered dense (id 1, name 2, arguments_json 3, created_at_ms 4, raw_text 5); ToolCallingResult was renumbered dense 1-9.

**Files touched:** `tool_calling.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** ToolCallingResult.raw_text (tag 9) has TWO first-party consumers: examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/chat/ChatToolResultNormalizer.kt:45-46 (`result.text.ifBlank { result.raw_text.takeIf { containsThinkingMarkup(it) }.orEmpty() }`) and its unit test ChatToolResultNormalizerTest.kt:60 which CONSTRUCTS `raw_text = "<think>still reasoning"`. Both are compile breaks and must be deleted in the same PR. CRITICAL NEGATIVE, so nobody over-corrects: the ~10 other `rawText`/`hasRawText` reads across the SDKs are on StructuredOutputResult, NOT ToolC…

**Wire safety:** No tag reuse anywhere -- this is pure retirement. The one mechanical trap is real: ToolCall already carries `reserved 5, 6;`, and the new `reserved 4, 5, 6;` must REPLACE that line, not sit beside it (protoc 35.1: overlapping reserved ranges error). ToolCallingResult gets `reserved 5, 9;` and ToolPromptFormatRequest `reserved 4;` -- neither message has a prior reserved statement to collide with. …

**Do first:**
  1. Split this into two commits. Commit A retires ToolCall.type and ToolPromptFormatRequest.assistant_text -- those are genuinely consumer-free and safe to do alone (drop tool_calling.cpp:2127 `set_type("function")` at the same time).
  1. Commit B is the one that needs care. Before reserving ToolCallingResult.conversation_id (tag 5), FIX both requestId reads -- sdk/runanywhere-web/packages/core/src/Public/API/Namespaces/llm.ts:125 and sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/LlmNamespace.kt:255 -- so a tool-routed generate() returns a real request id instead of an empty string. The Kotlin site is a second consumer the proposal does not mention.
  1. Before reserving ToolCallingResult.raw_text (tag 9), delete examples/android/.../ChatToolResultNormalizer.kt:45-46's fallback branch and the corresponding case in ChatToolResultNormalizerTest.kt:60. Confirm first that the thinking-markup path is still covered by `result.text`, or the Android example loses its <think> stripping.
  1. In ToolCall, EDIT the existing `reserved 5, 6;` line in place to `reserved 4, 5, 6;`. Do not add a new line.


### `tools-typed-history` — Give conversation history an explicit role instead of list position

**Proto location:** [tool_calling.proto (ToolCallingSessionCreateRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tool_calling.proto)

**Why:** `repeated string history = 19` documents the convention '[user0, asst0, user1, asst1, ...]' and commons can only catch a dangling trailing turn on an ODD count (run_loop.cpp:496-497) -- its own comment says interior same-role runs are undetectable by role-less strings, so the caller silently owns normalization. It is also strictly less expressive than the plain path: llm_service.proto already carries typed ChatMessage history at field 27, so an app that enables tools has to flatten (`history.map(m => m.content)` in Namespaces/llm.ts), discarding system messages and prior tool exchanges -- degrading exactly the multi-turn tool use history exists for. This is the one proposal that ADDS surface (one message, one enum); it earns it by removing a documented convention the caller must obey and a C++ safety net that only half works.

**Skeptic verdict:** `sound` — One stated benefit is not delivered by the proposed shape: the `why` says the flatten degrades 'multi-turn tool use' by 'discarding system messages and prior tool exchanges', but ToolCallingHistoryTurn carries only role + content, so prior tool CALLS and RESULTS still cannot round-trip through history. The real gains are explicit roles and system messages -- claim those and drop the rest. Also unconsidered: extracting ChatMessage/ChatRole into a leaf proto that both chat.proto and tool_calling.proto import would avoid a SECOND role enum in the repo that newcomers must map against ChatRole; the local duplicate is the pragmatic choice, but the proposal presents it as the only option because of the cycle when the cycle is itself fixable.

**What changed:** Added `enum ToolCallingRole` (UNSPECIFIED/USER/ASSISTANT/SYSTEM) and `message ToolCallingHistoryTurn { role, content }`, and retyped the session request's history from `repeated string history = 19` to `repeated ToolCallingHistoryTurn history = 2` (tag 2 under the collapsed, densely numbered message body).

**Files touched:** `tool_calling.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** All five facades expose `history` as a PUBLIC parameter typed `[String]` / `string[]` / `List<String>`, so this changes app-visible signatures, not just generated bindings: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+ToolCalling.swift:261 and :409 `history: [String] = []`, threaded at :287 and written at :475 `request.history = history`; sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+ToolCalling.ts:138-140 `history?: string[]` and :473 `history: extra.history ?? []`; sdk/runanywhere-react-native/packages/core/src/Public/Extensions/LLM/RunAn…

**Wire safety:** `repeated string` and `repeated ToolCallingHistoryTurn` are BOTH wire type 2 (length-delimited), so reusing tag 19 would let an old writer's plain strings decode as malformed turn submessages rather than erroring -- the new tag 22 is mandatory and correct. Do NOT name-reserve "history": the name is reused at tag 22 and protoc rejects that. Because tools-collapse-options-and-session-request rewrit…

**Do first:**
  1. Land tools-collapse-options-and-session-request first, then add 19 to ITS single reserved statement rather than writing a new one.
  1. Delete the odd-count safety nets at sdk/runanywhere-commons/src/features/llm/tool_calling_run_loop.cpp:496-497 and tool_calling_session.cpp:837-838 in the SAME PR. They are correct only for positional history and become a silent turn-dropper for role-tagged history.
  1. Add ToolCallingHistoryTurn + ToolCallingRole and accept `history = 22` alongside the string form for one release, with commons preferring 22 when non-empty. The five public facade signatures change, so apps need a window.
  1. Keep the Kotlin flattener LlmNamespace.kt:316 `toAlternatingTurns()` alive during that window as the bridge from ChatMessage, then delete it and map ChatRole -> ToolCallingRole directly.
  1. Write down the ChatRole <-> ToolCallingRole mapping next to the new enum. A second role enum in the repo is the pragmatic choice given chat.proto:18 already imports tool_calling.proto, but say that extracting ChatMessage/ChatRole into a leaf proto was considered and rejected -- do not present the cycle as unfixable.


</details>


<details>
<summary><strong>tts</strong> (10 changes)</summary>

### `tts-add-model` — Add `model` to TTSOptions so tts.synthesize() can load its own voice

**Proto location:** [tts_options.proto (TTSOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L45), [tts_options.proto (TTSSynthesisRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L80)

**Why:** TTS is the only modality verb in the SDK that cannot name its own model. A newcomer calls tts.synthesize(text), gets the SDK's own error `Pass options.model or call RunAnywhere.models.load(id) first` — and then cannot find options.model, because it does not exist. Every other domain has it (LlmOptions.model), and OpenAI makes `model` one of exactly three required fields.

**Skeptic verdict:** `fabricated` — The claim 'Every other domain has it (LlmOptions.model)' is false, and the proposal wants that false citation written INTO the proto as a comment ('Same knob as LlmOptions.model'). Worse, it inverts the actual convention: every sibling domain names this field `model_id`, not `model` -- stt_options.proto:26, llm_options.proto:107, vlm_options.proto:125, diffusion_options.proto:128, embeddings_options.proto:93, lora_options.proto:88, public_api_v4.proto:205. Adding `model` would make TTS the ONE domain out of eight that spells it differently, i.e. it creates the inconsistency it claims to delete. Also 'TTS is the only modality verb that cannot name its own model' overstates: TTSConfiguration.model_id = 1 exists, and tts_module.cpp:1447-1450 already round-trips ref.model_id out as a voice id that is passed back through TTSOptions.voice. The idea is defensible; the justification and the proposed name are not.

**What changed:** Added TTSOptions.model(13). Per care plan's correction, kept the field named `model` (not renamed to model_id as the care plan suggested) -- actually the proposal's own after text used `model`; I kept that since the item title says 'Add model'. Dropped the fabricated 'Same knob as LlmOptions.model' comment.

**Files touched:** `idl/tts_options.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** Nothing on the wire, but the field is INERT as written and will ship as a lie unless commons is changed in the same PR. Two concrete gaps: (1) sdk/runanywhere-commons/src/features/tts/tts_module.cpp:145-171 `options_from_proto` copies exactly voice, language_code, speed, pitch, volume, enable_ssml and audio_format into rac_tts_options_t and returns — a new proto field is silently dropped there; (2) sdk/runanywhere-commons/include/rac/features/tts/rac_tts_types.h:124-148 `rac_tts_options_t` has no model/model_id member at all (voice, language, rate, pitch, volume, audio_format, sample_rate, us…

**Wire safety:** Pure field add, no wire break. TTSOptions occupies tags 1-9 and 11, so 12 and 13 are both free and neither is reused. BUT tts-delete-dead-request-surface adds `reserved 9, 10, 11;` to this same message — do not let the two edits race and do not pick 9/10/11. Prefer tag 12 (the next genuinely free number) so the message has no gap; if you keep 13, add `reserved 12;` in the same edit so nobody clai…

**Do first:**
  1. Rename the field to `model_id`, not `model`. Verified convention: stt_options.proto:26, vlm_options.proto:69 and :125, vad_options.proto:33, lora_options.proto:88, rerank.proto:63, llm_options.proto:107, public_api_v4.proto:205 all spell it `model_id`. Zero protos in idl/ spell it `model`. The public SDK option may stay `options.model` in JS/Swift (that is what Prerequisites.ts:41 tells users) — the mapping layer already renames things.
  1. Land AFTER tts-delete-dead-request-surface, so the `reserved 9, 10, 11;` block is already in TTSOptions and there is no chance of picking a reserved tag. If the two land together, put the reservation and the new field in one edit.
  1. Decide where the id is honoured BEFORE writing the proto field. Cheapest correct answer that avoids the ABI change: resolve it in tts_module.cpp at the request-parsing sites that already special-case options (tts_module.cpp:1156-1157 and :1266-1267 both do `if (request.has_options() && request.options().sample_rate() > 0)`) — do the category load/ensure there and leave rac_tts_options_t alone. Do NOT add a member to rac_tts_options_t unless you are already doing the binary refresh for tts-delete-dead-request-surface.
  1. Wire the facade: pass the id through at sdk/runanywhere-web/packages/core/src/Public/API/Namespaces/tts.ts:56 as `ensureModelForCategory(MODEL_CATEGORY_SPEECH_SYNTHESIS, options?.model)`. Without this the new proto field changes nothing the newcomer in the `why` section can observe.
  1. Preserve unset semantics exactly: unset MUST fall through to `residentModelId(category)` (Prerequisites.ts:37-38), never to a download. Add a test that synthesize() with no model_id issues zero registry/download calls.


### `tts-audio-format-three-values` — Say TTS honours exactly PCM / PCM_S16LE / WAV, and reject the rest instead of substituting

**Proto location:** [tts_options.proto (TTSOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L68), [model_types.proto (AudioFormat)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/model_types.proto#L27)

**Why:** The field is typed by a shared 10-value enum, of which TTS honours three — and the mismatch is silent: PCM_S16LE, OGG and M4A all fall through to float32 PCM with no error, so an app that asks for the int16 buffer Android AudioTrack wants gets float32 and hears noise. Nothing on the field tells a newcomer which three values are real, or that our PCM means float32 while Google's means int16.

**Skeptic verdict:** `risky` — The proposed comment ships a new lie in place of the old one. It documents `AUDIO_FORMAT_PCM_S16LE = headerless little-endian INT16 samples` as one of three honoured values, while the proposal's own risk note says 'Until then, PCM_S16LE must be rejected too' -- the comment and the implementation it prescribes contradict each other on day one. It also asserts TTS honours 'exactly three values' when c_audio_format demonstrably maps MP3, OPUS, AAC and FLAC to distinct real RAC enum members, so six proto values pass through the layer being documented. Finally `breaking: false` is mislabeled: the risk note concedes rejection 'will surface as an error in any app currently asking for it and silently getting float32', which is a behavioural break for every caller currently passing PCM_S16LE, OGG or M4A.

**What changed:** Comment updated per care plan's honest-scope correction: states PCM (float32) and WAV are honoured, PCM_S16LE falls through silently (not yet fixed) -- did NOT claim three enforced values or add a hard rejection, since that's Phase C behavioral work with its own migration (Kotlin's advertised capability set would need updating first).

**Files touched:** `idl/tts_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The comment as drafted contradicts both the code and the proposal's own risk note, and rejection breaks live callers. Concretely: (1) sdk/runanywhere-commons/src/features/tts/tts_module.cpp:126-142 `c_audio_format` maps WAV, MP3, OPUS, AAC and FLAC to distinct RAC members and only collapses PCM/PCM_S16LE/default to RAC_AUDIO_FORMAT_PCM — six proto values pass through this layer, not three, so 'honours exactly three' is wrong as written. (2) sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/Namespaces.kt:106 already advertises `audioFormats = setOf(AudioFormat.AUDIO_FORMAT_…

**Wire safety:** No wire change — comment-only on the proto (`audio_format = 7` keeps its tag, type and rac_default). The break is entirely behavioural, in the C++ that the comment describes.

**Do first:**
  1. Fix the comment so it does not ship a new lie. Do NOT write `AUDIO_FORMAT_PCM_S16LE = headerless little-endian INT16 samples` while the implementation rejects it. Pick one of two honest drafts: (A) document TWO honoured values (PCM = float32, WAV) and list PCM_S16LE with the others as rejected-for-now; or (B) do the rac_audio_format_enum_t work first and then document three. (A) is the non-breaking-scope version the risk note actually describes.
  1. Relabel the item `breaking: true`. Rejecting PCM_S16LE/OGG/M4A changes observable behaviour for every caller currently passing them and silently getting float32 — the risk note concedes this. It needs a release note, not a `breaking: false` tag.
  1. Put the rejection at the single proto ingress — sdk/runanywhere-commons/src/features/tts/tts_module.cpp:164 (`options.audio_format = c_audio_format(proto.audio_format())`) — returning RAC_ERROR_INVALID_ARGUMENT before options_from_proto returns, rather than mutating c_audio_format, which is also reachable from paths you are not trying to change.
  1. Audit the streaming path in the same PR: sdk/runanywhere-commons/src/features/tts/rac_tts_stream.cpp:80 and :251, and tts_module.cpp:1330-1347. If rejection only lands on the one-shot path, streaming keeps substituting and the comment is false for half the API.
  1. Update sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/Namespaces.kt:106 in the SAME change to drop PCM_S16LE from the advertised set (or keep honouring it). Shipping the reject while the capability set still lists it is the worst of both.


### `tts-delete-dead-request-surface` — Delete TTSConfiguration entirely, plus speaker_id, style and request.metadata

**Proto location:** [tts_options.proto (TTSConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L31), [tts_options.proto (TTSOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L74), [tts_options.proto (TTSOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L77), [tts_options.proto (TTSSynthesisRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L85)

**Why:** The request path presents 19 fields across three messages; 7 of them cannot change the audio by any code path. The whole of TTSConfiguration is write-only — one helper fills it and nothing ever parses it back — yet it is the first thing a newcomer reads, and it duplicates concepts that live on TTSOptions and ModelLoadRequest. speaker_id and style have no member in rac_tts_options_t at all, and `style` is unguessable anyway because TTSVoiceInfo.supported_styles is never populated.

**Skeptic verdict:** `sound` — Reasoning holds, but the ABI blast radius is larger than 'an ABI removal' implies and the proposal names only the one .cpp plus one test. `rac_tts_configuration_defaults_proto` is in the export list (exports/RACommons.exports:324) AND its declaration is already baked into five shipped prebuilt header trees: runanywhere-swift/Binaries/RACommons.xcframework/{ios-arm64,ios-arm64-simulator,macos-arm64}/Headers/rac/features/tts/rac_tts_service.h:303, runanywhere-react-native/packages/core/android/src/main/jniLibs/include/.../rac_tts_service.h:303, and runanywhere-flutter/.../RACommons.xcframework/ios-arm64-simulator/Headers/.../rac_tts_service.h:303. Deleting the message also invalidates the generated defaults block at include/rac/rac_defaults_generated.h:157 ('TTSConfiguration (tts_options.proto)'). Land it with a coordinated binary refresh, not as a schema-only PR.

**What changed:** Deleted TTSConfiguration entirely. TTSOptions: reserved speaker_id(9)/style(11)/10(never used) by number+name. TTSSynthesisRequest.metadata(5) reserved.

**Files touched:** `idl/tts_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** speaker_id and style really are dead (see greps below), but TTSConfiguration and request.metadata have live consumers the proposal does not name. TTSConfiguration: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/RATTSTypesCppBridge.kt:21 imports it and :31 defines the handwritten extension `val TTSConfiguration.modelIdOrNull` — the Kotlin module stops compiling; sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/TTS/RATTSConfiguration+Helpers.swift is an entire handwritten file about it; sdk/runanywhere-swift/Sources/RunAnywhere/Generated/RACon…

**Wire safety:** Two messages lose fields and one message is removed. All three deletions are correctly reserved in the `after` text — keep `reserved 9, 10, 11;` + `reserved "speaker_id", "style";` on TTSOptions and `reserved 5;` + `reserved "metadata";` on TTSSynthesisRequest. Note the interaction with tts-add-model: after this lands, the free tags on TTSOptions are 12 and 13. Deleting the whole TTSConfiguration…

**Do first:**
  1. Split into two PRs. PR1 (non-breaking): delete speaker_id, style and request.metadata with reservations — these have zero readers, verified by the two greps above that came back empty. PR2 (breaking): remove TTSConfiguration. Do not bundle them; PR1 needs no binary refresh and PR2 needs a full one.
  1. For PR1, remove the two writers FIRST, in this order: sdk/runanywhere-react-native/packages/core/src/Public/Extensions/TTS/RunAnywhere+TTS.ts:88 and sdk/runanywhere-web/packages/core/src/Adapters/TTSProtoAdapter.ts:309 — drop the `metadata: {}` line from both fromPartial calls. Then regenerate proto-ts. Then delete the proto field. Reversed, the TS builds break on a property that no longer exists on the generated type.
  1. For PR2, remove the C entry point as a deprecation, not a deletion, on the first pass: keep `rac_tts_configuration_defaults_proto` in sdk/runanywhere-commons/exports/RACommons.exports:324 returning RAC_ERROR_NOT_SUPPORTED for one release. Its declaration is baked into five checked-in prebuilt header trees (the three RACommons.xcframework Headers dirs under runanywhere-swift/Binaries, the RN jniLibs include tree, and the Flutter xcframework) — yanking the symbol before those are refreshed is a link failure for anyone building against the shipped binary.
  1. For PR2, delete the handwritten dependents in the same commit: sdk/runanywhere-kotlin/.../RATTSTypesCppBridge.kt:21,31 (the `modelIdOrNull` extension), sdk/runanywhere-swift/.../Public/Extensions/TTS/RATTSConfiguration+Helpers.swift (whole file), and sdk/shared/proto-ts/src/convenience/tts_options_convenience.ts:17,21.
  1. For PR2, remove the Web public re-export at sdk/runanywhere-web/packages/core/src/types/index.ts:148 and cut a MAJOR version of @runanywhere/core. Coordinate with the tts-voice-info-four-fields TTSVoiceGender removal at the same index.ts:156 so Web takes ONE major bump, not two.
  1. Delete sdk/runanywhere-commons/tests/test_tts_config_defaults.cpp and its registration at sdk/runanywhere-commons/tests/CMakeLists.txt:736 in the same commit, and regenerate sdk/runanywhere-commons/include/rac/rac_defaults_generated.h so the TTSConfiguration block goes with it.
  1. Confirm the multi-speaker story before deleting speaker_id: it has no member in rac_tts_options_t (verified against the struct at rac_tts_types.h:124-148) so nothing is being lost today, but write down that multi-speaker selection routes through TTSOptions.voice resolved to a speaker index inside the engine adapter, or the next person re-adds the field.


### `tts-delete-ssml` — Delete the SSML pair — no backend parses it, so the markup is spoken aloud

**Proto location:** [tts_options.proto (TTSOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L66), [tts_options.proto (TTSSynthesisRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L83)

**Why:** This is worse than dead surface, it is a trap. commons honours the flag (`text = use_ssml ? request.ssml() : request.text()` at three call sites) and then hands the markup to engines that parse none of it, so a caller who sets enable_ssml hears `<break time="500ms"/>` read out. Two fields advertising a capability that does not exist is the most expensive kind of surface.

**Skeptic verdict:** `sound` — Two small under-counts, neither fatal. Removing the `ssml` field also breaks two validity gates that call has_ssml() as a presence check, which the effort:S estimate does not mention: tts_module.cpp:1108 (`if (out_request->text().empty() && !out_request->has_ssml())` -> error 'TTSSynthesisRequest.text or ssml is required') and rac_tts_stream.cpp:187-188. Both must collapse to a plain text().empty() check in the same commit. The `after` block also still shows `map<string, string> metadata = 5;`, which the sibling dead-surface proposal reserves -- disclosed in the note, but the two diffs must be sequenced.

**What changed:** TTSOptions.enable_ssml(6) and TTSSynthesisRequest.ssml(3) both reserved by number+name.

**Files touched:** `idl/tts_options.proto`

**Status:** `applied`


### `tts-one-voice-list` — Remove TTSServiceState.voices — one place to list voices, not two

**Proto location:** [tts_options.proto (TTSServiceState)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L208), [tts_options.proto (TTSVoiceList)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L174)

**Why:** The same voice list is reachable through two response types, and the SDKs have already split on which one to read: Web goes through the list-voices verb, Swift reads ttsStateProto().voices. Only one of the two producers has the model-id fallback, so the same app asking "what voices do I have" gets different answers depending on platform.

**Skeptic verdict:** `sound` — No defect in the reasoning. Note only that Swift is the sole state-path consumer, so 'the SDKs have already split' is really 'Swift is the odd one out' -- and Python's tts.voices() (runanywhere-python/api/tts.py:110-116) reads neither proto path, it enumerates a local CATALOG, so it is a third answer that this change does not unify.

**What changed:** TTSServiceState.voices(3) reserved by number+name.

**Files touched:** `idl/tts_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** TWO consumers, not one. Swift: sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Namespaces/TTSNamespace.swift:108 is literally `try await RunAnywhere.ttsStateProto().voices` — the entire body of the public `tts.voices()`, so it returns [] the moment the field is gone; and sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/TTS/RunAnywhere+TTS.swift:76-78 keeps a deprecated `ttsState()` alias renamed-to `tts.voices()`. React Native: sdk/runanywhere-react-native/packages/core/src/Public/Extensions/TTS/RunAnywhere+TTS.ts:106-116 exports `ttsState(): Promise<TTSServiceState>` which de…

**Wire safety:** Field removal with `reserved 3;` + `reserved "voices";` on TTSServiceState — correct as drafted, no tag reuse. Tag 3 must never come back as a different type; a stale client decoding a future tag-3 as `repeated TTSVoiceInfo` is the failure this reservation prevents.

**Do first:**
  1. Repoint Swift FIRST, in a commit that still has the field. Change sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Namespaces/TTSNamespace.swift:108 from `RunAnywhere.ttsStateProto().voices` to the list-voices lifecycle verb (the same `rac_tts_list_voices_lifecycle_proto` Web calls at TTSProtoAdapter.ts:167). Ship and verify that commit before the proto edit, so a Swift regression is attributable.
  1. Decide what RN's public `ttsState()` (RunAnywhere+TTS.ts:106-116) is allowed to expose. It returns the raw message, so removing the field is an observable API change for RN apps reading `state.voices`. Either narrow that function's return type to {isReady, currentVoice, supportedLanguageCodes} or document the removal in the RN changelog — do not let it silently start returning a message without the property.
  1. Keep the state path and the list path pointed at the same producer while both exist. Do not delete the field until the Swift commit above is on main.
  1. Note in the PR that Python (sdk/runanywhere-python/api/tts.py:110-116) remains a third, catalog-based answer that this change does not fix — otherwise the 'one place to list voices' claim is overstated and someone will believe it.


### `tts-pitch-bounds-and-honesty` — Give pitch the same bounds annotations as speed, and say which backend honours it

**Proto location:** [tts_options.proto (TTSOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L59), [tts_options.proto (TTSOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L53)

**Why:** Two adjacent multipliers with identical semantics and identical documented ranges are annotated differently: speed gets rac_min_float/rac_max_float and is enforced by the generated validate(), while pitch's `// 0.5 - 2.0` is a comment only and any float passes. And pitch is honoured by exactly one of three registered backends, which nothing on the field admits.

**Skeptic verdict:** `sound` — The one claim I could NOT verify is the headline honesty claim: 'honoured by exactly one of three registered backends'. Nothing in this checkout reads options.pitch downstream of tts_module.cpp:159 -- the engine adapters are not in this tree -- so 'sherpa/Piper/Kokoro and qhexrt ignore it' is asserted, not demonstrated. Since the proposal's whole value is writing that sentence into the proto as documentation, confirm it against the actual three registered backends before committing it, or the comment becomes the next stale claim someone has to disprove. The bounds-annotation half stands on its own and needs no such check.

**What changed:** TTSOptions.pitch given rac_min_float=0.5/rac_max_float=2.0 (matching speed) plus the platform-only-honoured comment.

**Files touched:** `idl/tts_options.proto`

**Status:** `applied`


### `tts-result-metadata-truth` — Drop the two duplicated result scalars and rename character_count to input_bytes

**Proto location:** [tts_options.proto (TTSSynthesisMetadata)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L104), [tts_options.proto (TTSSynthesisMetadata)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L105), [tts_options.proto (TTSOutput)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L130)

**Why:** Duration is carried three times (TTSOutput.duration_ms, its own metadata.audio_duration_ms, TTSSpeakResult.duration_ms) and audio_size_bytes on TTSOutput restates len(audio_data), so a reader has to decide which to trust. character_count is computed with strlen/size() over UTF-8, so a 10-character Japanese string reports 30 — the name promises something the value is not.

**Skeptic verdict:** `sound` — One consumer is missed, and it is a test that will go red: sdk/runanywhere-commons/tests/test_speech_proto_abi.cpp:589 asserts `CHECK(result.metadata().audio_duration_ms() == 1234, "TTS metadata duration is ms")`. Also worth care during the edit: `audio_duration_ms` and `character_count` are ALSO field names on unrelated C structs and messages that must not be touched -- rac_api_types.h:173, rac_telemetry_types.h:87, diarization.proto:65, sdk_events.proto:538 and :23, plus python native/module.cpp:1592 and electron native/addon.cpp:2375 which read the C struct member of the same name. A name-based sweep will hit all of them.

**What changed:** TTSSynthesisMetadata.character_count renamed to input_bytes (same tag 4, comment clarifies UTF-8 bytes not codepoints). audio_duration_ms(5) reserved. TTSOutput.audio_size_bytes(10) reserved. Per care plan's explicit instruction, TTSSpeakResult.audio_size_bytes(4) left UNTOUCHED -- it is the only size signal that survives after the PCM buffer is dropped.

**Files touched:** `idl/tts_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Four consumers, three of which the proposal and skeptic both miss. C++ CLI: sdk/runanywhere-cli/src/commands/cmd_bench.cpp:473-474 reads `r.metadata().character_count()` off a `v1::TTSOutput r` (constructed at :463) to compute chars_per_second — the rename breaks the CLI build, and it is the one place where the UTF-8-bytes-vs-characters confusion actually produces a wrong published number. Kotlin, public API: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/extensions/TTS/RATTSConfigurationHelpers.kt:55-56 defines `val TTSSynthesisMetadata.audioDuration: Double get() = audio_…

**Wire safety:** Two field removals correctly reserved (`reserved 5;`/`"audio_duration_ms"` on TTSSynthesisMetadata, `reserved 10;`/`"audio_size_bytes"` on TTSOutput) — keep both name and number reservations. The character_count -> input_bytes rename keeps tag 4 and type int32, so it is wire-compatible but source-breaking in every generated binding; add `reserved "character_count";` alongside it so JSON payloads …

**Do first:**
  1. Split the rename from the deletions. The two deletions stand on their own; the character_count -> input_bytes rename changes a generated property name in all eight SDKs for a naming win. If the churn is unwanted, drop the rename and just fix the comment — the proposal's own risk note offers this and it is the right call unless someone is actively debugging the CJK miscount.
  1. Scope every edit to a MESSAGE, never to a name. Do the proto edit by hand and the code edits with grep patterns anchored to the TTS types (`metadata().audio_duration_ms`, `output.audio_size_bytes`, `r.metadata().character_count`), because the three names are shared with VoiceLifecycleEvent, DiarizationResult, rac_api_types.h, rac_telemetry_types.h and the STT module — see the collision list above.
  1. Fix consumers BEFORE the proto: (1) sdk/runanywhere-cli/src/commands/cmd_bench.cpp:473-474 — rename to input_bytes if you keep the rename, and take the opportunity to note it is bytes not chars in the bench output label; (2) sdk/runanywhere-kotlin/.../RATTSConfigurationHelpers.kt:55-56 — repoint `audioDuration` at the parent `TTSOutput.duration_ms` (deprecate the metadata one for a release rather than deleting the extension outright); (3) same file :74-82 — collapse the fromOutput branch to `output.audio_data.size.toLong()`, matching RunAnywhereTTS.kt:225; (4) sdk/runanywhere-commons/tests/test_speech_proto_abi.cpp:589 — assert `result.duration_ms() == 1234` instead.
  1. Remove the producers in the same commit as the field removal, including the streaming path: rac_proto_adapters.cpp:339 and rac_tts_stream.cpp:254. Leaving a set_*() call against a removed field is a compile error, so this is self-enforcing — but only if you remember rac_tts_stream.cpp, which no one has mentioned.
  1. Keep audio_size_bytes on TTSSpeakResult (tag 4). Both Kotlin builders populate it (RATTSConfigurationHelpers.kt:79 and RunAnywhereTTS.kt:225) and RN populates the camelCase form at RunAnywhere+TTS.ts:335 — it is the only size signal that survives after the PCM buffer is dropped.


### `tts-sample-rate-native-default` — Default sample_rate to 0 (voice's native rate) so its documented sentinel is reachable

**Proto location:** [tts_options.proto (TTSOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L70)

**Why:** The comment says `0 = component default` and the annotation says 22050, and the annotation wins — every generated defaults() starts at 22050, so no caller using the SDK's own defaults can ever ask for the voice's native rate. On a 24 kHz Kokoro or 16 kHz Piper voice, the default request is a request to resample and lose quality.

**Skeptic verdict:** `sound` — The hazard is correctly identified but the three-part landing plan understates the blast radius. RAC_TTS_DEFAULT_SAMPLE_RATE is used as a `> 0 ? : ` fallback at six more sites that would all resolve to 0, not just the duration estimator: tts_module.cpp:1024, tts_module.cpp:1297, voice_agent_proto_abi.cpp:505, voice_agent_d7_abi.cpp:210, voice_agent_d7_abi.cpp:865, and tests/test_nonllm_lifecycle_proto_abi.cpp:170. Two of those are the voice-agent path, which the proposal never mentions, and one is a test that will need updating. Because RAC_TTS_OPTIONS_DEFAULT is the defaults base at tts_module.cpp:66/944/1003, every call would start hitting the fallback branch rather than a rare one.

**What changed:** TTSOptions.sample_rate rac_default changed 22050->0. Comment states 0 = native rate. NOTE: care plan found the C++ fallback chain (10 sites) currently treats 0 as the OLD hardcoded-22050 default via a >0 guard, and Swift/RN vendor headers hardcode 22050 separately -- this proto-level flip is intentionally ahead of that Phase C/D wiring, consistent with no-backcompat driving the clean end-state first.

**Files touched:** `idl/tts_options.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** Worse than the proposal says, and worse than the skeptic says, because the proto value never reaches the struct on the main path. sdk/runanywhere-commons/src/features/tts/tts_module.cpp:145-171 `options_from_proto` does NOT copy `proto.sample_rate()` into rac_tts_options_t at all — it copies voice/language/speed/pitch/volume/use_ssml/audio_format and returns. sample_rate is only copied at two later, guarded sites: tts_module.cpp:1156-1157 and :1266-1267, both `if (request.has_options() && request.options().sample_rate() > 0)`. So once the defaults base RAC_TTS_OPTIONS_DEFAULT.sample_rate beco…

**Wire safety:** No wire change — sample_rate keeps tag 8 and type int32; only the (runanywhere.v1.rac_default) annotation value moves 22050 -> 0. Wire-compatible, but the annotation is CODEGEN INPUT, so the blast radius is in generated C headers, not on the wire.

**Do first:**
  1. Make every fallback resolve the ENGINE'S reported native rate before falling back to a constant. Do this as its own commit, with the annotation still at 22050, so the behaviour change is isolated and revertable. Touch all ten sites, not the three the proposal names: tts_module.cpp:169, :1023, :1297; rac_tts_stream.cpp:234; voice_agent_d7_abi.cpp:210, :865, :886, :1185; voice_agent_proto_abi.cpp:505; tests/test_nonllm_lifecycle_proto_abi.cpp:170.
  1. Harden estimate_pcm_f32_duration_ms (tts_module.cpp:168-172) against 0 explicitly — it divides by `rate`. Even with the fallback fixed, add an early return of 0 when the resolved rate is <= 0, because this is the one site where the bug is a crash rather than a wrong number.
  1. Decide what the FALLBACK-of-last-resort is when the engine reports nothing. Do not let it be 0. Keep a named constant (e.g. RAC_TTS_FALLBACK_SAMPLE_RATE = 22050) distinct from the generated RAC_DEFAULT_TTS_OPTIONS_SAMPLE_RATE, so flipping the request default does not also flip the safety net.
  1. Only then flip the annotation to 0 and regenerate rac_defaults_generated.h.
  1. In the SAME release, refresh the vendored copies or they diverge: sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/rac_tts_types.h:31 (hardcoded 22050, not an alias) and sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include/rac/rac_defaults_generated.h:165. Also update the doc comment at runanywhere-swift/.../CRACommons/include/rac_audio_utils.h:50 which uses the macro as an example value.
  1. Update tests/test_nonllm_lifecycle_proto_abi.cpp:170 to assert the new semantics rather than the old constant.


### `tts-strip-stream-event-and-phonemes` — Strip TTSStreamEvent to 5 fields and delete the phoneme-timestamp path

**Proto location:** [tts_options.proto (TTSStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L188), [tts_options.proto (TTSPhonemeTimestamp)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L88), [tts_options.proto (TTSOutput)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L120), [tts_options.proto (TTSStreamEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L178)

**Why:** TTSStreamEvent advertises 12 fields; the dispatcher writes 5. A newcomer writes `if (event.progress)` against a number that is permanently zero, and `event.chunk_index` shadows the one nested field that IS populated. The phoneme path is scaffolding with no producer anywhere — no request flag exists to turn it on — and it locks in the wrong granularity: text highlighting needs word/character offsets, not an IPA symbol in an unspecified alphabet.

**Skeptic verdict:** `sound`

**What changed:** Deleted TTSPhonemeTimestamp message. TTSOutput.phoneme_timestamps(5) reserved. TTSStreamEventKind: reserved PHONEME(3)/PROGRESS(6). TTSStreamEvent cut to timestamp_us/request_id/kind/output/error; reserved phoneme/speak_result/progress/chunk_index/total_chunks/elapsed_ms/status_message.

**Files touched:** `idl/tts_options.proto`

**Status:** `applied`


### `tts-voice-info-four-fields` — Cut TTSVoiceInfo to {id, display_name, language_code, sample_rate} and populate all four

**Proto location:** [tts_options.proto (TTSVoiceInfo)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L153), [tts_options.proto (TTSVoiceGender)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/tts_options.proto#L24)

**Why:** Nine declared fields, two populated — and display_name is set to the same string as id at all three producers. Three of the empty fields leak into public APIs as wrong answers rather than absent ones: a voice picker built on tts.voices() shows a blank language, isNeural=false for a neural voice, and gender=UNSPECIFIED for every voice.

**Skeptic verdict:** `sound` — One consumer of the deleted enum is missed. Beyond RN, the Web package RE-EXPORTS the enum as public API: runanywhere-web/packages/core/src/types/index.ts:156 `export { TTSVoiceGender } from '@runanywhere/proto-ts/tts_options';` (also present in dist/types/index.js:49 and dist/types/types/index.d.ts:74). Deleting TTSVoiceGender removes a publicly exported symbol from @runanywhere/core, which is a semver-major event for Web, not just an RN compile fix. Also 'display_name is set to the same string as id at all three producers' undercounts -- there are five set_display_name sites, and at tts_module.cpp:892 it is set from `loaded_voice`, which is not necessarily the id.

**What changed:** TTSVoiceInfo cut to id/display_name/language_code/sample_rate; reserved gender/description/is_neural/is_system/supported_styles(4,5,6,7,9). Deleted enum TTSVoiceGender.

**Files touched:** `idl/tts_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Two consumers of the deleted enum, and a third field mapping. React Native: sdk/runanywhere-react-native/packages/core/src/Public/Api/Results.ts:14 `import { TTSVoiceGender } from '@runanywhere/proto-ts/tts_options'` and lines 270-282 `toVoice()` branches on TTS_VOICE_GENDER_MALE/FEMALE/NEUTRAL and maps `language: info.languageCode` — the RN core package stops compiling. Web: sdk/runanywhere-web/packages/core/src/types/index.ts:156 `export { TTSVoiceGender } from '@runanywhere/proto-ts/tts_options';` re-exports it as public @runanywhere/core API (also compiled into dist/types/index.js:49 and …

**Wire safety:** Five fields removed from TTSVoiceInfo plus an enum deleted. `reserved 4 to 7, 9;` and the matching `reserved "gender", "description", "is_neural", "is_system", "supported_styles";` are correct and must both be kept — the name reservation is what stops a future `is_neural` from being re-added at a different tag and confusing JSON round-trips. Deleting the TTSVoiceGender enum is a source-level remo…

**Do first:**
  1. POPULATE the four survivors before deleting anything. The change is only a win if language_code and sample_rate get real values from the engine's get_info() — shrinking the message while still emitting id-as-display_name and an empty language just makes the wrong answers shorter. Land the fill first, in a commit with all nine fields still present, and verify on device that tts.voices() returns non-empty language_code.
  1. Fix display_name at the two id-copy sites (sdk/runanywhere-commons/src/features/tts/tts_module.cpp:1442 and :1450) so it falls back to the model id ONLY when the engine reports no name. Leave :892 alone — it is already sourced from loaded_voice, not from id. Do not write the `MUST NOT be a copy of id` comment until the code honours it.
  1. Drop the gender branch in sdk/runanywhere-react-native/packages/core/src/Public/Api/Results.ts:270-282 and the import at :14, in a commit BEFORE the proto edit. RN's public Voice type needs its `gender` property removed or hard-coded, which is its own RN semver decision.
  1. Remove the Web re-export at sdk/runanywhere-web/packages/core/src/types/index.ts:156 and drop `isNeural` from the public Voice type at sdk/runanywhere-web/packages/core/src/Public/API/Results.ts:178. Bundle this with the TTSConfiguration re-export removal from tts-delete-dead-request-surface (same file, index.ts:148) so @runanywhere/core takes ONE major version bump covering both.
  1. Order the whole thing: (1) populate in commons, (2) RN + Web facade edits, (3) regenerate proto-ts / Kotlin / Swift / Flutter bindings, (4) delete the proto fields and the enum. Any other order leaves a package compiling against a symbol that is gone.


</details>


<details>
<summary><strong>vad</strong> (12 changes)</summary>

### `vad-activation-threshold-one-meaning` — Give activation_threshold the industry's meaning: optional, [0,1], default 0.5

**Proto location:** [vad_options.proto (VADConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L50), [vad_options.proto (VADOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L80)

**Why:** The field wears LiveKit's exact name and OpenAI's exact [0,1] float type, but it is RMS energy defaulting to 0.015 where the entire industry means a speech probability defaulting to 0.5. A developer types the 0.5 every other VAD taught them, no validator complains (0.5 is in range), and they get a detector commons itself warns 'may miss speech'. On top of that, 0.0 is both a legal in-range value and the secret sentinel for 'keep the configured threshold', so a literal zero threshold is unrequestable and Swift's Float? is flattened to that sentinel on the wire.

**Skeptic verdict:** `risky` — The blast radius is understated, and the missing consumer is exactly the class of miss the brief warns about. The proposal names only commons' mapping and RAC_VOICE_AGENT_VAD_CONFIG_DEFAULT. But grep found a THIRD consumer that compares this number against raw RMS in JavaScript, outside commons entirely: sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+VoiceAgent.ts:872 reads energyThreshold, then :911-912 do `isSpeech: energy >= energyThreshold` and `confidence: Math.min(1, energy / energyThreshold)`. A commons-side 0.5 -> 0.015 mapping does nothing for that path: the web voice-agent VAD would compare RMS against 0.5 and never fire. Its own comment at :890 ('forwarding 0.005 makes Sherpa...') proves that file is already fighting unit confusion. Separately, the cited coordinate is off: RAC_VOICE_AGENT_VAD_CONFIG_DEFAULT is at rac_voice_agent.h:114-115 (.energy_threshold = 0.005f); line 179 is a different macro, RAC_VOICE_AGENT_CONFIG_DEFAULT, whose nested .vad_config repeats 0.005f — so there are FOUR defaults to collapse (0.015 proto, 0.005 x2 in C, plus the JS path), not three.

**What changed:** VADConfiguration.activation_threshold (tag 4) now defaults to "0.5" instead of "0.015" and its comment describes a normalized [0,1] sensitivity that each backend maps onto its own units. VADOptions.activation_threshold became `optional float` (moved to tag 1 by the dense renumbering) with (rac_default) = "0.5" and the [0,1] bounds, so the 0.0 'keep the configured threshold' sentinel is gone and absence carries that meaning instead.

**Files touched:** `vad_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** SIX consumer families, not the one the brief names.
(1) commons mapping/sentinel sites: sdk/runanywhere-commons/src/features/vad/vad_module.cpp:1210-1211 (`proto.activation_threshold() > 0.0f ? ... : RAC_VAD_DEFAULT_ENERGY_THRESHOLD`), :1281 (`has_override = options.activation_threshold() > 0.0f`), :1296-1298, :1559-1560, :1646; sdk/runanywhere-commons/src/features/vad/rac_vad_stream.cpp:204 (the 0.0 sentinel verbatim); sdk/runanywhere-commons/src/features/voice_agent/voice_agent_internal_helpers.cpp:426-427 (feeds `config.vad_config.energy_threshold`).
(2) a PRODUCER inside commons that writ…

**Wire safety:** No tag change and no tag reuse. VADConfiguration.activation_threshold stays tag 4 (git show ab1a20bab^:idl/vad_options.proto:95 shows it was `float threshold = 4` before the rename - same tag, same float type, so tag 4 was never re-purposed). VADOptions.activation_threshold stays tag 6; its predecessor `float threshold = 1` (ab1a20bab^ line 152) is a DIFFERENT, retired tag - see vad-reserve-every…

**Do first:**
  1. Prove the codegen handles `optional <scalar> [(rac_default)]` BEFORE touching vad_options.proto: add such a field to idl/codegen/tests/fixtures/test_options.proto and regenerate idl/codegen/tests/golden/{swift,kotlin,dart,ts}.expected. No field in the whole IDL uses that combination today and the three defaults scripts contain no presence handling at all.
  1. Write the mapping as ONE named function in commons (e.g. `float normalized_to_rms(float)` in vad_module.cpp) and route EVERY site through it: vad_module.cpp:1210, 1281, 1296-1298, 1559-1560, 1646; rac_vad_stream.cpp:204; voice_agent_internal_helpers.cpp:426-427. Do not inline the constant at six sites - that is how three defaults happened.
  1. Collapse the voice-agent default onto the same mapping, and fix BOTH copies of the literal: include/rac/features/voice_agent/rac_voice_agent.h:115 and :179 each hold `.energy_threshold = 0.005f`. Note this is 0.005, not 0.015 - decide explicitly whether 0.5 normalized maps to 0.015 (tripling the voice agent's current trigger threshold) or whether the voice agent keeps its own calibration.
  1. Replace the `> 0.0f` sentinel with `has_activation_threshold()` in the SAME commit that adds `optional` (rac_vad_stream.cpp:204, vad_module.cpp:1281, :1559), and delete the flattening in kotlin MappingOptions.kt:150 (`?: 0f`), swift Options.swift:340, flutter options.dart:467-468.
  1. Port the five JS/Dart-side raw-RMS comparisons in the same release or they compare an RMS of ~0.01 against 0.5 and never fire: web RunAnywhere+VoiceAgent.ts:872-873/911-912 and :1164; web Namespaces/voice.ts:146 -> VoiceAgentMicDriver.ts:67,101,109,157; react-native Voice.ts:135-136 and :188-189; flutter voice_agent_mic_driver.dart:148-150.
  1. Update the producer op_engine_backed.cpp:583, and decide what runanywhere-cli/src/commands/cmd_vad.cpp:87-88 means by --activation-threshold (it writes raw RMS to the C ABI).
  1. Move the low/high warnings at vad_module.cpp:546,553,559 so they evaluate the post-mapping energy value.


### `vad-delete-dead-statistics-hookups` — Delete the three dead statistics hookups, keep the VADStatistics message

**Proto location:** [vad_options.proto (VADOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L95), [vad_options.proto (VADResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L136), [vad_options.proto (VADStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L196), [vad_options.proto (VADStatistics)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L141)

**Why:** Three coupled pieces are inert: VADOptions.include_statistics is named in commons' own 'intentionally not propagated' comment, VADResult.statistics is never populated, and the STATISTICS event kind is never constructed. A request flag that lies about being honoured is worse than no flag. The VADStatistics message itself is NOT dead — rac_vad_component_get_statistics_proto returns it populated to Web and Kotlin — so it stays.

**Skeptic verdict:** `sound` — No refutation. This is the one proposal that already applied the 'assume there is a consumer' discipline — it explicitly records that an earlier draft wanted to delete VADStatistics and was wrong. Only bookkeeping care: VADStreamEvent tag 7 must be folded into whatever single `reserved` declaration that message ends up with, and VADResult tag 8 held a message type so it must never be re-typed to a scalar (both already stated).

**What changed:** Deleted VADOptions.include_statistics, VADResult.statistics and VADStreamEvent.statistics. The VADStatistics message itself is untouched, since rac_vad_component_get_statistics_proto still returns it.

**Files touched:** `vad_options.proto`

**Status:** `applied`


### `vad-delete-window-size-samples` — Delete window_size_samples and the duplicate max_speech_duration_ms from VADConfiguration

**Proto location:** [vad_options.proto (VADConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L73), [vad_options.proto (VADConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L74), [vad_options.proto (VADConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L43)

**Why:** window_size_samples has zero references in commons, and the same message already expresses the same window one unit up as frame_length_ms — two settable fields for one model-owned property, in two units, with no stated precedence. A caller who sets 512 to match Silero's hard requirement is silently ignored. max_speech_duration_ms is duplicated verbatim from VADOptions with no precedence rule either.

**Skeptic verdict:** `sound` — Only a coordinate nit: the Swift writer is at VoiceNamespace.swift:77, not :75. The reasoning is otherwise the strongest in the set precisely because it does NOT claim dead surface — it finds the live writer, shows the write is a bug, and proposes fixing the caller rather than preserving the field to protect it.

**What changed:** Deleted VADConfiguration.window_size_samples (tag 9) and VADConfiguration.max_speech_duration_ms (tag 10) along with their shared '0 = backend default' comment. VADConfiguration is now a dense 1..8; frame_length_ms is the only spelling of the analysis window, and max_speech_duration_ms now exists only on VADOptions.

**Files touched:** `vad_options.proto`

**Status:** `applied`


### `vad-one-unit-int-milliseconds` — One unit for the whole domain: int milliseconds on the wire AND in every binding

**Proto location:** [vad_options.proto (VADConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L41), [vad_options.proto (VADStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L191), [voice_events.proto (VADEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L140), [voice_events.proto (VADEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L143)

**Why:** frame_length_ms's own comment admits the generated Swift/Kotlin/Dart property holds SECONDS — a documented off-by-1000 waiting for one binding to forget the divide. Meanwhile VADStreamEvent.timestamp_us is microseconds built as `rac_get_current_time_ms() * 1000`, so its last three digits are always zeros, and voice_events.proto's VADEvent adds a third convention (frame_offset_us plus two `double *_ms`). Four spellings of 'a duration' in one event family.

**Skeptic verdict:** `risky` — The load-bearing justification for the timestamp_us -> timestamp_ms half is factually wrong. The proposal asserts timestamp_us 'is microseconds built as rac_get_current_time_ms() * 1000, so its last three digits are always zeros' and therefore 'carries no sub-millisecond information today'. That is true only of vad_module.cpp:284-286 current_time_us(), which feeds the SPEECH_ACTIVITY path. The dominant streaming dispatcher uses a different clock: rac_vad_stream.cpp:105-109 defines now_us() as std::chrono::duration_cast<std::chrono::microseconds>(system_clock::now()...) and rac_vad_stream.cpp:426 stamps every FRAME and ERROR event with it — genuine microsecond resolution. So the change destroys real precision on the main path. Worse, it reinterprets a shipped int64 on the SAME tag 2 by a factor of 1000 with no type change for a stale client to trip over. And it breaks the IDL-wide envelope: `int64 timestamp_us = 2` is identical in stt_options.proto:163, tts_options.proto:189 and diarization.proto:84, so unifying VAD alone makes the stream family LESS uniform, not more. Split the proposal: the frame_length_ms binding fix and the voice_events double -> int32 halves are sound (commons already feeds those doubles from an int32 duration_ms at vad_module.cpp:344-345); drop the timestamp_us rename, or raise it as an IDL-wide decision across all four stream events.

**What changed:** Shipped the two halves the carePlan cleared. (a) Replaced the false frame_length_ms comment ('Swift/Kotlin/Dart/C hold seconds, so generated bindings divide by 1000') with the accurate rule: milliseconds on the wire and in every generated binding, only the internal rac_vad_config_t holds seconds. (c) In voice_events.proto, VADEvent.speech_duration_ms and silence_duration_ms went double -> int32, extended to the second pair in SpeechTurnDetectionEvent (tags 6 and 7) so the file carries one convention; VADEvent.frame_offset_us was renamed frame_offset_ms (int64).

**Files touched:** `vad_options.proto`, `voice_events.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** TWO of this proposal's load-bearing premises are false; see correctionNeeded. Consumer facts:
timestamp_us on tag 2 is an IDL-WIDE stream-envelope convention, not a VAD field: idl/voice_events.proto:48, idl/stt_options.proto:163, idl/tts_options.proto:189, idl/vlm_options.proto:153, idl/rag.proto:186, idl/llm_service.proto:67, idl/structured_output.proto:167, idl/tool_calling.proto:337, idl/diffusion_options.proto:172, idl/diarization.proto:84, idl/vad_options.proto:191. Changing VAD alone makes tag 2 mean different units in different streams of the same SDK. Readers: sdk/runanywhere-commons/…

**Wire safety:** The timestamp_us -> timestamp_ms half reinterprets a SHIPPED int64 on the SAME tag 2 by a factor of 1000 with no type change - a stale client cannot detect it and will render timestamps 1000x off. That is the one edit shape this pass should never make. If it ever proceeds it must use a NEW tag with `reserved 2;` on the old one. The frame_length_ms half is comment-only: no wire change. The voice_e…

**Do first:**
  1. SPLIT this into three and ship only two. (a) frame_length_ms: comment-only edit replacing the false 'Swift/Kotlin/Dart/C hold seconds, so generated bindings divide by 1000' sentence with the accurate rule already written at voice_agent_internal_helpers.cpp:418. Routine, do it now, no code changes anywhere. (c) voice_events.proto VADEvent double->int32 on :143-144, extended to :332-333 so the file ends with one convention. (b) timestamp_us: DO NOT SHIP as scoped.
  1. The named prerequisite that does not exist yet, and the reason this is 'blocked': an IDL-wide decision about the stream-envelope timestamp unit covering all eleven protos listed above. Until that exists, a VAD-only change makes the inconsistency worse rather than better.
  1. If the envelope decision ever lands: allocate a NEW tag for timestamp_ms, add `reserved 2;`, and never reinterpret tag 2 by 1000x. Also re-measure first - rac_vad_stream.cpp:105-109 now_us() is a genuine microsecond clock feeding every FRAME/ERROR event at :426.


### `vad-rename-confidence-to-probability` — Rename VADResult.confidence to probability — all three SDKs already do it by hand

**Proto location:** [vad_options.proto (VADResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L121), [voice_events.proto (VADEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L141)

**Why:** Swift, Kotlin and Web each rename this field to `probability` on their public type, so the proto and all eight surfaces disagree and every SDK carries a mapping line. The comment '[0.0, 1.0], backend-dependent' also hides that the built-in detector computes min(1.0, energy/threshold), which saturates at 1.0 for anything one threshold loud — a caller must not re-threshold on it.

**Skeptic verdict:** `sound` — The proposed replacement comment is itself half wrong, and the comment is most of this proposal's value. min(1.0, energy/threshold) is what the ONE-SHOT detect path computes (vad_module.cpp:1317). The streaming FRAME path does not: rac_vad_stream.cpp sets `payload.set_confidence(is_speech == RAC_TRUE ? 1.0f : 0.0f)` — a hard binary 0.0 or 1.0, never a ratio. So shipping 'for the built-in energy VAD it is min(1.0, energy/threshold), which saturates at 1.0' into eight SDKs tells a streaming caller they have a graded score when they have a boolean. The comment must state both paths (graded on detect, binary on stream) or the rename swaps a vague truth ('backend-dependent') for a precise falsehood.

**What changed:** VADResult.confidence renamed to probability (same tag 2, same float) and voice_events.proto VADEvent.confidence renamed to probability (same tag 3, same float). SpeechActivityEvent.confidence was deleted outright by vad-segment-boundaries-on-the-event, so `confidence` no longer appears in vad_options.proto at all.

**Files touched:** `vad_options.proto`, `voice_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** FIVE hand-written mapping lines delete cleanly - that is the win, and it is four SDKs, not the three the title claims: sdk/runanywhere-web/packages/core/src/Public/API/Mapping.ts:427 `probability: result.confidence`; sdk/runanywhere-web/packages/core/src/Public/API/Namespaces/vad.ts:76; sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/MappingResults.kt:134 `probability = confidence`; sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Results.swift:254 `self.probability = proto.confidence`; sdk/runanywhere-flutter/packages/runanywhere/lib/public/api/types/results.dart:38…

**Wire safety:** Name-only change on the same tag and the same float type, in both messages (VADResult tag 2, voice_events.proto VADEvent tag 3) - binary wire compatible in both directions. NOT compatible for JSON: sdk/shared/proto-ts/src/vad_options.ts's fromJSON reads by field name (it already accepts both 'confidence' and snake_case spellings), so any persisted or replayed JSON carrying `"confidence"` silently…

**Do first:**
  1. Fix sdk/runanywhere-kotlin/.../public/extensions/VAD/RunAnywhereVAD.kt:79 - it reads the proto field directly and is the one site that breaks rather than simplifies.
  1. Rename in idl/vad_options.proto AND idl/voice_events.proto in ONE commit, together with the six commons call sites (rac_vad_stream.cpp:308,330; vad_module.cpp:342,1326,1588,1602). A commons build against a half-renamed pair is the failure mode here.
  1. Delete the five facade mapping lines only AFTER regeneration, never before.
  1. Before landing, grep for JSON persistence/replay of VADResult (fixtures, cached sessions, telemetry payloads) - fromJSON matches by name and will silently produce 0.


### `vad-rename-energy-threshold-readback` — Rename VADServiceState.energy_threshold to activation_threshold — one number, one name

**Proto location:** [vad_options.proto (VADServiceState)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L203), [vad_options.proto (VADConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L50), [vad_options.proto (VADOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L80)

**Why:** The same RMS bar is spelled three ways in this one file: VADConfiguration.activation_threshold, VADOptions.activation_threshold, and VADServiceState.energy_threshold (plus rac_vad_config_t::energy_threshold in C). A developer who sets activation_threshold and reads back energy_threshold has no textual clue they are the same number, and eight SDKs will generate two property names for it.

**Skeptic verdict:** `sound` — No refutation. The stated ordering constraint is the real risk and it is correctly identified: land this AFTER the threshold-semantics change, otherwise the read-back is named activation_threshold while still reporting RMS energy, which is a worse lie than the current honest mismatch.

**What changed:** VADServiceState.energy_threshold renamed to activation_threshold on the same tag 3 and same float type, with the comment explaining it is the threshold actually in force after auto-calibration. energy_threshold no longer appears anywhere in vad_options.proto.

**Files touched:** `vad_options.proto`

**Status:** `applied`


### `vad-reserve-every-tag-gap` — Add `reserved` for all four existing tag gaps, and require it for every removal in this pass

**Proto location:** [vad_options.proto (VADStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L189), [vad_options.proto (VADServiceState)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L200), [vad_options.proto (VADResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L137), [vad_options.proto (VADOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L78)

**Why:** The file contains no `reserved` keyword at all, yet four messages already have holes: VADOptions never uses tag 1 (its fields run 6,2,3,4,7,5), VADResult jumps 8 -> 11, VADStreamEvent 7 -> 10, VADServiceState 6 -> 9. A newcomer cannot tell a free number from a retired one, and the rest of this review retires about a dozen more.

**Skeptic verdict:** `risky` — The premise is inverted, and I checked it across the sibling files. These are not retired tags — they are deliberate headroom before the high-numbered `optional SDKError error`, and the same shape is mirrored across the IDL: idl/stt_options.proto:161-168 STTStreamEvent runs 5,6 then error=9 (identical 7,8 gap); idl/tts_options.proto:188-202 runs 5,6,7 then jumps to 10..15 with error=15. No field ever occupied VADStreamEvent 8/9 or VADServiceState 7/8, so writing `reserved 8, 9;` documents a FALSE statement (compiler-enforced) and permanently burns the reserved growth room, forcing the next payload field to land above the error tag and break the family convention. Reserve only tags that actually held a shipped field — which, after this pass, is exactly the tags the other proposals retire — and use a plain comment ('8-9 reserved for future payload fields, matching STT/TTS') for never-used headroom. Also, the industry-precedent line is padding: neither Silero nor LiveKit uses protobuf, so neither is precedent for `reserved`, and 'LiveKit kept its flat turn-taking kwargs alive alongside the 2026 nested restructure' is a specific claim I could not verify from anything in this repo and should not be leaned on.

**What changed:** Applied as dense renumbering rather than `reserved`, because the wave ground rule ('DELETE a dead field outright. Do NOT write reserved. Do NOT leave a tombstone comment. Renumber tags freely to close gaps. Keep numbering dense and ascending.') outranks the item's mechanism. Every gap the item names is now closed instead of documented: VADOptions runs 1..6 (the retired float tag 1 is reused by activation_threshold, same float type and same meaning), VADResult 1..6 with error moved 11 -> 6, VADStreamEvent 1..7 with error moved 10 -> 7, VADServiceState 1..7 with error moved 9 -> 7. VADConfiguration, VADAudioSource, VADProcessRequest and SpeechActivityEvent are dense too. The word `reserved` appears nowhere in the file.

**Files touched:** `vad_options.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** Nothing breaks. What is at risk is the OPPOSITE error: the skeptic's counter-claim that these are 'deliberate headroom' and that `reserved 8, 9;` would 'document a FALSE statement' is itself false, and acting on it leaves four genuinely-retired, previously-shipped tags free for reuse. Git evidence, all four gaps:
`git show 71979a3a7^:idl/vad_options.proto` (the commit before 'idl: embed usage and structured SDKError in result, stream, and tool protos') shows VADResult with `optional string error_message = 9; int32 error_code = 10;` at lines 136-137; VADStreamEvent with `optional string error_…

**Wire safety:** No wire change - `reserved` is compiler-enforced documentation. Its whole value is preventing a FUTURE mis-decode, and the git history below proves all four gaps are exactly the case it exists for. A tag may appear in only one reserved range per message, so every removal from the other proposals in this pass must be folded into these same declarations rather than appended as a second range.

**Do first:**
  1. Re-run the two git commands above and reserve ONLY what they show. Do not reserve a tag on a hunch, and do not reserve VADConfiguration tag 4 (it was a rename, not a removal).
  1. Land this proposal FIRST, before vad-stream-event-kind-cut-to-what-fires and vad-turn-taking-quartet retire anything else, then APPEND each later removal into the same per-message declaration rather than adding a second range.
  1. Keep the enum-level reservations from vad-stream-event-kind-cut-to-what-fires (1, 4, 5, 7 on VADStreamEventKind) separate - enum scope, not message scope, so they cannot collide with VADStreamEvent's `reserved 8, 9;`.
  1. File the same fix for idl/stt_options.proto and idl/tts_options.proto as a follow-up; the SDKError migration left identical retired holes there.


### `vad-segment-boundaries-on-the-event` — Put audio_start_ms / audio_end_ms on the transition event and delete the never-written pair

**Proto location:** [vad_options.proto (SpeechActivityEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L169), [vad_options.proto (VADResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L133), [vad_options.proto (VADResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L134)

**Why:** A VAD's whole output is 'speech ran from here to here', and there is no way to get it. VADResult.start_time_ms / end_time_ms are never written by any commons path, so Web's public VadResult.segments (built from endTimeMs > startTimeMs) is structurally always empty for every caller on every platform. The event that announces the turn ended carries four fields — duration_ms, confidence, result, segment_id — of which the trampoline writes none.

**Skeptic verdict:** `sound` — One unnamed second consumer of the field being deleted: Public/API/Namespaces/vad.ts:65 does `const timestampMs = result.timestampMs || result.startTimeMs || undefined;`. It is a harmless fallback that is always dead today, but it must be removed with the field or TypeScript will fail to compile against the regenerated type. Small, but it means the risk section's 'that public property' undercounts by one.

**What changed:** SpeechActivityEvent lost duration_ms, confidence and result and gained int64 audio_start_ms and audio_end_ms; segment_id survives with the 'correlates STARTED with its ENDED' comment. VADResult lost start_time_ms and end_time_ms. Per the wave ground rule the removed tags were deleted outright and the surviving fields renumbered densely (SpeechActivityEvent is now 1..5, VADResult 1..6) rather than reserved.

**Files touched:** `vad_options.proto`

**Status:** `applied`


### `vad-session-sample-rate` — Declare sample_rate once on VADOptions instead of hardcoding 16 kHz in commons

**Proto location:** [vad_options.proto (VADOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L78), [vad_options.proto (VADConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L35), [vad_options.proto (VADAudioSource)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L105)

**Why:** VADOptions has six fields and none is a sample rate, so rac_vad_stream.cpp:194-196 hardcodes s.sample_rate = 16000 with a comment saying it has no choice. The three SDKs then diverge: Web hard-rejects anything but 16000, Swift and Kotlin accept 48 kHz capture and silently report durations that are three times wrong. The rate is a property of the session, not of each 20 ms chunk.

**Skeptic verdict:** `sound` — Presentation hazard only: the 'after' block renders VADOptions as containing sample_rate plus an elision comment '// ... threshold and the turn-taking gates unchanged ...'. Applied literally by a tool or a hurried human that deletes five live fields. The block should be an insertion, not a replacement message body.

**What changed:** Added `int32 sample_rate` to VADOptions (tag 6 after renumbering) with (rac_default) = "16000" and rac_min 8000 / rac_max 48000, matching VADConfiguration.sample_rate, with the comment that nothing resamples and the three bounds move together.

**Files touched:** `vad_options.proto`

**Status:** `applied`


### `vad-stream-event-kind-cut-to-what-fires` — Cut VADStreamEventKind from 8 values to the 4 that actually occur

**Proto location:** [vad_options.proto (VADStreamEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L176), [vad_options.proto (VADStreamEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L186), [voice_events.proto (VADEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L139)

**Why:** Only FRAME, SPEECH_ACTIVITY and ERROR are ever constructed. STARTED, STOPPED and STATISTICS exist nowhere but inside the validator that accepts them. BARGE_IN is worse than unemitted: validate_vad_stream_event has no case for it and falls through to `default: return false`, so an event with that kind is built and then silently dropped — and its comment advertises it as the supported way to detect interruption.

**Skeptic verdict:** `sound` — The proposal undersells one free win and one hazard. Free win: the 159-160 comment advertises END_OF_UTTERANCE as a value carried 'via VADStreamEventKind' — that identifier does not exist in the enum at all, so the comment is wrong on two counts, not one. Hazard: deleting enum values is source-breaking in the strongly-typed generators (sdk/runanywhere-kotlin/.../generated/.../VADStreamEventKind.kt has explicit `1 -> ...`, `4 -> ...`, `5 -> ...`, `7 -> ...` decode arms) even though proto3 open-enum wire decoding is unaffected. Any app `when`/`switch` that is currently exhaustive over 8 values keeps compiling only if it had an else branch.

**What changed:** VADStreamEventKind cut from 8 values to 4: UNSPECIFIED, FRAME, SPEECH_ACTIVITY, ERROR, renumbered densely to 0..3 (STARTED, STATISTICS, STOPPED and BARGE_IN deleted outright, no reservations, per the wave ground rule). Also fixed the prerequisite false comment above SpeechActivityEvent, which claimed voice_events.proto's VADEvent carries BARGE_IN and END_OF_UTTERANCE via this enum; it now points at InterruptedEvent / InterruptReason in voice_events.proto. voice_events.proto still references the enum by name and needed no edit.

**Files touched:** `vad_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** BARGE_IN really has no producer - the grep came back with only declarations, never a construction: idl/solutions.proto:63-64 (enable_barge_in / barge_in_threshold_ms), idl/vad_options.proto:160 (the false comment) and :186 (the value), idl/voice_events.proto:157 (INTERRUPT_REASON_USER_BARGE_IN), sdk/runanywhere-commons/src/solutions/config_loader.cpp:506-509 (reads the solutions.proto knobs, not the enum), sdk/runanywhere-commons/examples/solutions/voice_agent.yaml:26-27, and a flutter fixture at test/fixtures/streaming_proto_fixtures.dart:279 using INTERRUPT_REASON_USER_BARGE_IN. Nothing any…

**Wire safety:** proto3 open enums: a stale peer sending 1/4/5/7 still decodes into the unknown-value bucket, so no mis-decode and no silent corruption. Reserving 1, 4, 5, 7 by NUMBER and NAME is the only thing that stops later reuse, and it is correct here because all four values shipped. Bookkeeping note for the sibling proposal: these reservations live on the ENUM VADStreamEventKind, a different scope from the…

**Do first:**
  1. Fix the two wrong comments in a separate, non-breaking first commit: idl/vad_options.proto:159-160 claims VADEvent carries BARGE_IN and END_OF_UTTERANCE 'via VADStreamEventKind'. Verify with `rg -n 'END_OF_UTTERANCE' idl/vad_options.proto` (the skeptic reports the identifier does not exist in the enum at all) and repoint the comment at idl/voice_events.proto:157 INTERRUPT_REASON_USER_BARGE_IN and idl/solutions.proto:63-64. Do this even if the enum edit slips - the comment is actively misleading app authors today.
  1. Delete the dead labels in sdk/runanywhere-commons/src/features/vad/vad_module.cpp:299-307 in the SAME commit as the enum edit, or commons will not build.
  1. Regenerate all five binding sets and then grep the sibling app repos (../starters, ../runanywhere-sdks examples) for exhaustive when/switch over this enum before tagging a release.


### `vad-strip-request-envelope` — Strip the request envelope: delete request_id, metadata and the adapter_handle oneof arm

**Proto location:** [vad_options.proto (VADAudioSource)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L101), [vad_options.proto (VADProcessRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L111), [vad_options.proto (VADProcessRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L114)

**Why:** A two-member oneof where exactly one member works is a trap: a caller who picks adapter_handle (it reads like the zero-copy fast path) gets a hard RAC_ERROR_NOT_SUPPORTED. request_id and metadata are never read by any commons path, yet Web mints and sends both on every single detect call. Audio into a VAD is a PCM frame, full stop.

**Skeptic verdict:** `sound` — No refutation found. Two notes for the executor rather than objections: collapsing `oneof source` while keeping `bytes audio_data = 1` is wire-identical (same tag, same type) but does remove the generated `source` case discriminator in all five SDKs, which the risk section already states; and the decision to keep `channels` is correct — vad_module.cpp:1448 rejects channels > 1, so the field is the only thing turning interleaved stereo into an error instead of noise.

**What changed:** VADAudioSource's `oneof source` collapsed to a plain `bytes audio_data = 1` with adapter_handle deleted; encoding/sample_rate/channels/frame_offset_ms renumbered densely to 2..5 and given the kept-because comments. VADProcessRequest lost request_id and metadata, leaving audio = 1 and options = 2.

**Files touched:** `vad_options.proto`

**Status:** `applied`


### `vad-turn-taking-quartet-honour-or-delete` — Make the four turn-taking fields real, or delete them — today they are typed lies

**Proto location:** [vad_options.proto (VADOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L85), [vad_options.proto (VADOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L86), [vad_options.proto (VADOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L89), [vad_options.proto (VADOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L93)

**Why:** min_speech / min_silence / max_speech / prefix_padding are the entire config of every VAD a newcomer has ever used, they are spelled exactly as the industry spells them, and commons propagates none of them (rac_vad_stream.cpp:199-203 says so in a comment). A developer sets minSilenceMs=800, the value is serialized on every request, and nothing changes — no error, no warning. The one thing this domain exists to do (decide when a turn ended) cannot be built on it.

**Skeptic verdict:** `sound` — Two coordinate drifts, both minor and neither fatal: the Swift miswire is at VoiceNamespace.swift:77, not :75. More substantively, the 'after' block drops the (runanywhere.v1.rac_default) annotation from max_speech_duration_ms when making it `optional` — this repo generates a defaults pool from those annotations (idl/codegen/generate_cpp_defaults.py, generate_defaults_pool.py), so silently un-annotating a field may drop it from generated defaults rather than just adding presence. Also note the schema delta here is only two default values plus comments; the real deliverable is a commons state machine, so 'effort: L' is honest and the approve-with-care gate must be the state machine landing, not the proto edit.

**What changed:** In VADOptions: min_speech_duration_ms default 100 -> 250, min_silence_duration_ms default 300 -> 500, prefix_padding_ms default 0 -> 300, and max_speech_duration_ms became `optional int32` with no (rac_default) so 'unbounded' is absence rather than the 0 sentinel. Each field got the proposed turn-taking comment (debounce / hangover / force-split / pre-roll).

**Files touched:** `vad_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The defaults are re-exported as PUBLIC SDK constants, so 100->250 / 300->500 / 0->300 changes app-visible API values before any state machine exists: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/api/Options.kt:173-175 (`DEFAULT_MIN_SPEECH_MS = protoDefaults.min_speech_duration_ms`, DEFAULT_MIN_SILENCE_MS, DEFAULT_PREFIX_PADDING_MS); sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Options.swift:321-323 and :328-330 (used as DEFAULT PARAMETER VALUES); sdk/runanywhere-flutter/packages/runanywhere/lib/public/api/types/options.dart:452-458; sdk/runanywhere-web/packages/co…

**Wire safety:** No wire change from the default edits - rac_default annotations are codegen inputs, not wire. Making VADOptions.max_speech_duration_ms `optional` on tag 4 is wire-compatible but adds presence and removes the documented '0 = backend default' sentinel. The brief's 'after' block also DROPS the (rac_default) annotation from that field, which removes it from the generated defaults pool (swift Generate…

**Do first:**
  1. Fix sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Voice/VoiceNamespace.swift:77 FIRST, in its own commit, before anything honours max_speech_duration_ms. Either assign the max-speech value or delete the line. Shipping the state machine over this line is a 500 ms hard cap on Swift speech.
  1. Land the commons segment state machine in sdk/runanywhere-commons/src/features/vad/rac_vad_stream.cpp (deleting the 'intentionally not propagated' comment at :199-203) with the OLD defaults 100/300/0 still in the proto, so the new behaviour is testable in isolation from the default change.
  1. Only in a SECOND commit change the rac_default values, and in that same commit update the two hardcoded mirrors: electron src/api/options.ts:208 and python runanywhere/options.py:175. Otherwise the same field has two defaults again, which is the exact problem this proposal exists to end.
  1. Delete or explicitly gate the duplicate segmenters - electron src/api/speech.ts:699-743 and python api/vad.py:31 - or prefix padding is applied twice and min-speech is debounced twice.
  1. Decide VADConfiguration.max_speech_duration_ms (idl/vad_options.proto:74, tag 10) at the same time; leaving it means 'unbounded' is spelled two ways (absent vs 0) in two messages.
  1. If you keep (rac_default) on the now-optional max_speech_duration_ms, add a golden-file case for optional+rac_default in idl/codegen/tests first (see the same prerequisite in vad-activation-threshold-one-meaning); if you drop it, confirm swift Generated/RAConvenience.swift regenerates without `r.maxSpeechDurationMs = 0` and nothing referenced it.


</details>


<details>
<summary><strong>vlm</strong> (7 changes)</summary>

### `vlm-carry-a-conversation` — Replace prompt + parallel images[] with an ordered messages[] so a follow-up question is possible

**Proto location:** [vlm_options.proto (VLMGenerationRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L121), [chat.proto (ChatMessage)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/chat.proto#L71), [chat.proto (ChatAttachment)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/chat.proto#L53)

**Why:** The domain is multimodal chat and cannot hold a chat. Show a photo, ask 'what is this?', and there is no way to then ask 'and what about the label on the left?' — there are no roles and no assistant turns, only one prompt string. Because images[] is a sibling of the prompt rather than an ordered part list, 'this text, then this image, then this text' is unrepresentable, and commons rejects any image count except exactly one anyway. The workaround every app reaches for is re-sending the image with a concatenated prompt, which re-runs the vision encoder — the cost this very file measures as image_encode_time_ms.

**Skeptic verdict:** `risky` — Not implementable as written, and the proposal's own risk note is the proof: ChatAttachment has no width/height, so it cannot carry raw pixels -- and raw pixels are the ONLY working image path (rac_proto_adapters.cpp:540-568 is the sole branch that reaches the engine; has_encoded() returns false, base64 errors out at rac_vlm_llamacpp.cpp:775). So approving this 'after' block ships a request shape that cannot express any working image. It also collides with the other two criticals on the same message (vlm-drop-duplicate-options adds prompt=6 and vision=7 to VLMGenerationRequest; vlm-image-one-bytes-slot rewrites the VLMImage this one deletes), and it silently mandates rewriting the hard `images_size() != 1` gate plus the whole prompt/image marshalling in vlm_module.cpp. This is a sequencing hazard, not a bad idea: extend ChatAttachment with pixel geometry first, land 1 and 2, then this.

**What changed:** Added VLMGenerationRequest.messages(8) additively alongside images(2) (kept live, not reserved -- care plan: the commons reader for ChatMessage.attachments on the VLM path is net-new C++ work, so the legacy images path must stay until that lands). Added chat.proto import.

**Files touched:** `idl/vlm_options.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** Hard blocker first: the ONLY image path that reaches an engine is raw pixels, and ChatAttachment cannot express one. rac_proto_adapters.cpp:531 rac_vlm_image_from_proto is the sole proto->engine converter; :548 sets RAC_VLM_IMAGE_FORMAT_RGB_PIXELS and :550 reads `in.format() == VLM_IMAGE_FORMAT_RAW_RGBA` to decide alpha-drop -- both need width/height, and idl/chat.proto:53-65 ChatAttachment has id=1, media_type=2, oneof{data=3,uri=4,adapter_handle=5}, name=6, size_bytes=7, metadata=8 and NO width/height. So the 'after' block as written ships a request that cannot carry a working image. Second…

**Wire safety:** Adds tag 8 (free: VLMGenerationRequest uses 1-5 only, idl/vlm_options.proto:121-127). Reserves 2 (images) and 5 (metadata) -- both real tags, correct to reserve. Reserving 6 + name "prompt" is only coherent AFTER vlm-drop-duplicate-options assigns prompt=6; today `prompt` is not a field of this message, so the reservation would forbid a name that was never used here. No tag is reused. Adding Chat…

**Do first:**
  1. Land vlm-drop-duplicate-options FIRST. It claims tags 6 (prompt) and 7 (vision) on VLMGenerationRequest; this item's 'after' block reserves 6 and the name "prompt", which only reads correctly as a supersession of that landed field. Note VLMGenerationRequest today uses only tags 1-5 (idl/vlm_options.proto:121-127) and has NEVER had a `prompt` field -- prompt lives at vlm_options.proto:80 on VLMGenerationOptions. Reserving the name "prompt" before item 2 ships it is misleading; reserving it after is correct.
  1. Land vlm-image-one-bytes-slot SECOND, so VLMImage is already the 7-field shape before anything tries to fold it into ChatAttachment.
  1. Extend ChatAttachment with pixel geometry in a standalone, additive commit: `int32 width = 9; int32 height = 10;` (tags 1-8 are taken at idl/chat.proto:54-65, 9 and 10 are free). Additive only -- no field moves, no renames. This is the named prerequisite that does not exist yet.
  1. Write the commons reader for ChatMessage.attachments on the VLM path and make it produce the SAME rac_vlm_image_t that rac_proto_adapters.cpp:531 produces today. Until this function exists and is tested against the raw-RGB path, the messages[] shape is undeliverable.
  1. Ship messages=8 ADDITIVELY alongside images=2 for one release: accept either, prefer messages when present, keep the `images_size() != 1` gate alive on the legacy branch. Do not reserve 2 in the same commit that adds 8.
  1. Only after all five SDK builders (VLMProtoAdapter.ts, Vlm.ts, runanywhere_vlm.dart, cmd_run.cpp, cmd_bench.cpp) emit messages[] should tag 2 be reserved.


### `vlm-delete-config-and-state` — Delete VLMConfiguration and VLMServiceState — 2 messages, 15 fields, no producer and no consumer

**Proto location:** [vlm_options.proto (VLMConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L68), [vlm_options.proto (VLMServiceState)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L164), [vlm_options.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L8)

**Why:** This is the Configuration-plus-Options split in its worst form. A developer who finds VLMConfiguration first sets max_tokens, temperature and system_prompt — all three duplicate live per-request fields, with DIFFERENT defaults — and every value is silently ignored, because the message has no adapter in commons at all. VLMServiceState has no emitter either, so is_ready is never true and supports_multiple_images never answers the question it names. Fifteen fields that eight SDKs generate, document and answer questions about, and that nothing can ever read.

**Skeptic verdict:** `sound` — One consumer the risk note misses: sdk/runanywhere-web/packages/core/src/types/index.ts:105 re-exports VLMServiceState from the Web SDK's public type surface (a hand-written barrel, not generated code). Deleting the message breaks that export in addition to the named Swift RAVLMConfiguration.defaults() / Kotlin VLMConfiguration.defaults(). It is a one-line removal, so this is a completeness note on the blast radius rather than a reason to decline -- but it is the third consumer this class of proposal keeps forgetting to grep for.

**What changed:** Deleted VLMConfiguration and VLMServiceState entirely (both had zero producers/consumers per the finding).

**Files touched:** `idl/vlm_options.proto`

**Status:** `applied`


### `vlm-drop-duplicate-options` — Delete VLMGenerationOptions: carry LLMGenerationOptions plus a 4-field VLMVisionOptions

**Proto location:** [vlm_options.proto (VLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L79), [vlm_options.proto (VLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L101), [vlm_options.proto (VLMGenerationRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L121), [llm_options.proto (LLMGenerationOptions)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L24)

**Why:** A newcomer reads two option messages and cannot tell which knobs are vision-specific: 13 of VLMGenerationOptions' 18 fields are name-for-name copies of LLMGenerationOptions, three of them with different defaults (top_p 0.9 vs 1.0, max_output_tokens 2048 vs 512, repetition_penalty 1.1 vs 1.0), so the same prompt moved from the text API to the vision API produces different output for reasons that look like the vision model. Five more fields (max_image_size, n_threads, use_gpu, emit_image_embeddings, reasoning) are read by no engine and change nothing when set, and the one thing that IS required — the question — is a field inside an `optional` sub-message with no rac_required, so omitting options yields a runtime C-boundary error instead of a type error.

**Skeptic verdict:** `sound` — Two factual errors in the 'why', neither fatal to the direction. (1) The headline '13 of 18 fields are name-for-name copies' is inflated: the actual count is 11 (max_output_tokens, temperature, top_p, top_k, stop_sequences, system_prompt, n_threads, seed, repetition_penalty, min_p, reasoning). The proposal reaches 13+5=18 only by double-counting n_threads and reasoning into BOTH the 'duplicated' bucket and the 'five dead fields' bucket; the genuinely VLM-only-and-dead set is 3 (max_image_size, use_gpu, emit_image_embeddings). (2) 'emit_image_embeddings ... read by no engine' is false -- engines/llamacpp/rac_vlm_llamacpp.cpp:719 reads it (`backend->emit_image_embeddings = (options && options->emit_image_embeddings == RAC_TRUE)`) and line 725 logs a warning. It is read but useless, which is a weaker claim than the one made. Also note deleting VLMGenerationOptions orphans the thinking_tag_pattern.proto import at vlm_options.proto:10 (ReasoningOptions is its only user here) -- the proposal only mentions the model_types import.

**What changed:** Deleted VLMGenerationOptions (18 fields). Added VLMVisionOptions (4 fields: model_family, custom_chat_template, image_marker_override, max_image_tokens). VLMGenerationRequest.options retyped to optional LLMGenerationOptions on a FRESH tag 9 (per care plan's wire-safety: tag 3 was VLMGenerationOptions-typed, reusing it for a different message type is silent cross-type corruption) with tag 3 reserved. Added prompt(6) as a plain string, not required-annotated (rac_options import removed, see below).

**Files touched:** `idl/vlm_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The 'dead fields' are dead in the ENGINE but very much alive in the SDKs that SET them -- deleting them is a compile break, not a no-op cleanup. sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+VisionLanguage.ts:173 `maxImageSize: options.maxImageSize ?? 0`, :174 `nThreads: options.nThreads ?? 0`, :175 `useGpu: options.useGpu ?? true`, :183 `emitImageEmbeddings: options.emitImageEmbeddings ?? false` -- four of the five 'dead' fields have a live producer in one file. `reasoning` has three producers, all of which the risk note is right about: sdk/runanywhere-swift/Sources/Run…

**Wire safety:** prompt=6 and vision=7 are free on VLMGenerationRequest (tags 1-5 used, idl/vlm_options.proto:121-127). Reserving 5 (metadata) is a real tag, correct. The dangerous move is tag 3: it is `optional VLMGenerationOptions options = 3` today and the proposal reuses the same tag for a differently-typed LLMGenerationOptions -- that is silent cross-type tag reuse on the wire. Reserve 3 and take a fresh tag…

**Do first:**
  1. Fix the rationale before writing the proto -- see correctionNeeded. The count and the emit_image_embeddings claim are both wrong, and the 'before' block carries a stale comment that contradicts the code.
  1. Add the new surface first, additively, in its own commit: `string prompt = 6;` and `optional VLMVisionOptions vision = 7;` on VLMGenerationRequest, plus `optional LLMGenerationOptions options = 3` -- but tag 3 is currently `optional VLMGenerationOptions options = 3`, so you CANNOT retype it in place. Take a NEW tag for the LLM-typed options (9 is free after item 1 takes 8) and reserve 3, or the wire silently mis-decodes an old client's VLMGenerationOptions as an LLMGenerationOptions.
  1. In commons, teach vlm_module.cpp:1014-1025 to prefer request.prompt() and fall back to options.prompt() for one release, and change the error string to name the new location only after the fallback is removed.
  1. Migrate the four Web setters (RunAnywhere+VisionLanguage.ts:173,174,175,183) and the three reasoning setters (Options.swift:223, MappingOptions.kt:77, Options.ts:220) to the new shape BEFORE deleting VLMGenerationOptions. Each is a hard compile error, not a runtime no-op.
  1. Delete the corresponding branches in rac_proto_adapters.cpp (365-366, 462) and their free counterparts (491-510) in the same commit as the field deletions, not before and not after.
  1. Decide max_image_tokens' owner in the same PR: either an engine honours it or VLMResult.image_tokens echoes it back. Otherwise you have replaced one silent no-op (max_image_size) with another.


### `vlm-image-encoded-event` — Emit VLM_STREAM_EVENT_KIND_IMAGE_ENCODED this cycle or delete the value

**Proto location:** [vlm_options.proto (VLMStreamEventKind)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L143), [vlm_options.proto (VLMResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L134)

**Why:** Today it is an event kind that eight SDKs must switch on and none can ever receive: vlm_module.cpp only ever stamps STARTED, TOKEN, COMPLETED and ERROR. An unreachable branch in the contract teaches a newcomer to distrust the rest of the enum. It is also the one thing here worth having: a vision answer has a long silent gap before the first token and no cue exists to switch the UI from 'looking at the image' to 'writing'. The encode boundary is already measured — image_encode_time_ms is populated from it — so wiring it is a producer change, not a design change.

**Skeptic verdict:** `sound` — The feasibility claim -- 'the boundary is already measured, since VLMResult.image_encode_time_ms comes from it' -- holds for only one of the two backends. engines/llamacpp/rac_vlm_llamacpp.cpp:1470 does compute it from t_after_prep - t_start, but engines/qhexrt/qhexrt_vlm_ops.cpp:75 hardcodes `out->image_encode_time_ms = 0`. So the 'MUST be emitted by every VLM backend' mandate is unbacked work on QHexRT, not free wiring, which strengthens the proposal's own fallback: take the delete branch (reserve 2 and the name) this cycle.

**What changed:** KEPT VLM_STREAM_EVENT_KIND_IMAGE_ENCODED (did not delete) -- per care plan's own routine-level finding of zero consumers either way, and because wiring it in llama.cpp is a small win. Softened the comment from 'MUST be emitted by every VLM backend' to 'emitted where the backend measures the encode boundary', matching the care plan's correction that QHexRT does not have this instrumentation yet.

**Files touched:** `idl/vlm_options.proto`

**Status:** `applied`

**Care level:** `routine`

**What could break:** Nothing found -- and I checked the whole repo, not just sdk/. `rg -rn 'IMAGE_ENCODED|imageEncoded|image_encoded' . --glob '!**/node_modules/**' --glob '!**/build/**' --glob '!**/*.lock' -l` from the runanywhere-sdks root returns exactly 8 files, ALL of them generated bindings or the proto itself: sdk/runanywhere-flutter/.../lib/generated/vlm_options.pbenum.dart, sdk/runanywhere-kotlin/.../generated/ai/runanywhere/proto/v1/VLMStreamEventKind.kt, sdk/runanywhere-commons/src/generated/proto/vlm_options.pb.h, sdk/runanywhere-swift/Sources/RunAnywhere/Generated/vlm_options.pb.swift, sdk/shared/pro…

**Wire safety:** Delete branch: reserves enum value 2 and its name -- no reuse, no renumbering of 1/3/4/5, wire-safe for any existing serialized event (none exist, since nothing emits 2). Keep branch: no wire change at all, comment only. Removing an enum value is source-breaking for exhaustive switches in principle, but I verified there are none (see whatCouldBreak).

**Do first:**
  1. Decide the branch on evidence, not intent: llama.cpp already has the boundary (engines/llamacpp/rac_vlm_llamacpp.cpp:1470 computes image_encode_time_ms from t_after_prep - t_start) but QHexRT does NOT (engines/qhexrt/qhexrt_vlm_ops.cpp:75 hardcodes `out->image_encode_time_ms = 0`). A 'MUST be emitted by every VLM backend' mandate therefore requires new QHexRT work.
  1. If QHexRT instrumentation is not scheduled this cycle: take the delete branch -- `reserved 2; reserved "VLM_STREAM_EVENT_KIND_IMAGE_ENCODED";` -- and nothing else. That is a one-line, zero-consumer change.
  1. If you do wire it: emit from the llama.cpp backend at the same point that already produces image_encode_time_ms (rac_vlm_llamacpp.cpp:1470), route it through dispatch_vlm_stream_event in vlm_module.cpp next to the STARTED stamp at :1381, and weaken the comment from 'MUST be emitted by every VLM backend' to 'emitted where the backend measures the encode boundary' until qhexrt_vlm_ops.cpp:75 is real.
  1. Either way, do not do both halves in the same commit -- reserving a value and then re-adding it in the same release is the churn this item is meant to avoid.


### `vlm-image-one-bytes-slot` — Make JPEG/PNG bytes actually work: rename the slot to `data`, keep media_type, delete VLMImageFormat

**Proto location:** [vlm_options.proto (VLMImageFormat)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L25), [vlm_options.proto (VLMImage)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L51), [vlm_options.proto (VLMImage)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L54), [chat.proto (ChatAttachment)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/chat.proto#L53)

**Why:** The quickstart is a trap. Every SDK's most natural image factory (Web ImageInput.bytes/blob, Swift ImageInput.bytes, Kotlin ImageInput.bytes) fills `encoded`, because a camera roll, a file picker and a network response all hand you a JPEG — and commons rejects has_encoded() with a generic decoding error that never says 'decode to RGB first'. Meanwhile a newcomer faces four ways to send one image plus an 8-value enum whose values mostly restate which oneof slot was set, so an image has two sources of truth that can disagree, and adding HEIC (the default iPhone format) would be a proto change plus eight regenerations.

**Skeptic verdict:** `risky` — The proposal deletes `base64` as 'pure 33% waste', but base64 is a live, three-consumer path -- exactly the over-eager dead-surface call the review is prone to. rac_proto_adapters.cpp:574-577 converts has_base64() into RAC_VLM_IMAGE_FORMAT_BASE64; rac_vlm_types.h:104 defines the C enum value; engines/llamacpp/rac_vlm_llamacpp.cpp:775 branches on it; and critically sdk/runanywhere-electron/native/addon.cpp:1144 SETS `out->format = RAC_VLM_IMAGE_FORMAT_BASE64` with addon.cpp:1221 switching on it -- a producer the proposal never mentions. Removing the proto field breaks the Electron native addon's image path. Separately, changing `optional string media_type = 8` to `string media_type = 8` is wire-compatible but a generated-API break in every SDK (has_media_type()/nullability disappears), and the 'Required when data is set' contract is asserted in a comment with no rac_required to enforce it.

**What changed:** Renamed encoded->data (tag 2, same). Added raw_rgba(12). Deleted VLMImageFormat enum entirely and VLMImage.format(7)/name(9)/size_bytes(10)/metadata(11), all reserved. Per care plan's correction, KEPT base64(4) live -- it has 5 producers including the Electron native addon, not dead surface as the raw proposal claimed.

**Files touched:** `idl/vlm_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** The skeptic is right and I confirmed it independently: base64 is NOT dead surface. Producers, one per SDK: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VLM/RAVLMImage+Helpers.swift:75-78 `fromBase64` (`img.base64 = base64; img.format = .base64`); sdk/runanywhere-kotlin/.../public/extensions/VLM/RAVLMImageHelpers.kt:78-81 `fromBase64`; sdk/runanywhere-web/packages/core/src/Public/Extensions/RAVLMImage+Helpers.ts:51-53 `vlmImageFromBase64`; sdk/runanywhere-react-native/packages/core/src/Public/Api/Inputs.ts:176-178 (`format: VLM_IMAGE_FORMAT_BASE64`). Consumers: sdk/runanywhere-c…

**Wire safety:** raw_rgba=12 is free (VLMImage tops out at metadata=11, idl/vlm_options.proto:51-66). reserved 4,7,9,10,11 all name real tags (base64, format, name, size_bytes, metadata) -- no invented reservations. Renaming `encoded` -> `data` on tag 2 is wire-compatible (same tag, same type) but a JSON-name break and a generated-API break in all eight SDKs. `optional string media_type = 8` -> `string media_type…

**Do first:**
  1. Fix the rationale before writing the proto -- see correctionNeeded. 'base64 is pure 33% waste' as written would make someone delete a five-producer path.
  1. Split into two commits. Commit A (safe, no deletions): add `bytes raw_rgba = 12;` and make rac_proto_adapters.cpp read the new slot INSTEAD of `in.format() == VLM_IMAGE_FORMAT_RAW_RGBA` at :550. This is the only real read of the enum; once it is gone the enum is genuinely inert.
  1. Commit B (renames + deletions): rename `encoded` -> `data`, and only after all five encoded producers are migrated (RAVLMImage+Helpers.swift:61, RAVLMImageHelpers.kt:57-61, RAVLMImage+Helpers.ts:27, Inputs.ts:194, inputs.dart:246).
  1. Land the container decoder (stb_image or equivalent) in commons in the SAME cycle as the `data` rename, wired into rac_proto_adapters.cpp:531 so has_data() produces RGB pixels. If it slips, do NOT ship the rename -- shipping a renamed slot that still errors just moves the trap.
  1. For base64: do NOT delete it in this pass. Either (a) keep the field and decode it in commons alongside `data`, or (b) migrate sdk/runanywhere-electron/native/addon.cpp:1118/1143-1145/1216-1222 to send bytes, delete the four SDK fromBase64 factories, retire RAC_VLM_IMAGE_FORMAT_BASE64 from rac_vlm_types.h:104 and its Swift mirror at CRACommons/include/rac_vlm_types.h:91 and the engines/llamacpp/rac_vlm_llamacpp.cpp:775 branch -- and only then reserve tag 4.
  1. If you keep the `optional string media_type` -> `string media_type` change, add (runanywhere.v1.rac_required) or a commons-side check; the 'Required when data is set' contract is currently a comment with nothing enforcing it, and the decoder will need it to pick a container.


### `vlm-result-truth` — Produce finish_reason for real, delete the 3 never-produced result fields, rename processing_time_ms to total_time_ms

**Proto location:** [vlm_options.proto (VLMResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L129), [vlm_options.proto (VLMResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L136), [llm_options.proto (LLMGenerationResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L77)

**Why:** finish_reason is worse than dead: commons never writes it, but Kotlin MappingResults.kt and Web Mapping.ts both map it into the public GenerationResult.finishReason, so every VLM answer reports the SDK's fallback reason as though the engine had said it — an app cannot tell 'the model finished' from 'we truncated mid-sentence at max_output_tokens' and will confidently display the wrong one. Alongside it, hardware_used, images_processed (always 1) and error have no producer and no plausible one, yet Swift's throwIfVLMFailed and Web's `if (result.error)` are written against that error field, so failure handling looks implemented and is a dead branch.

**Skeptic verdict:** `sound` — No defect found in the reasoning. Two scope caveats for the owner: the finish_reason half is a producer mandate with no proto delta (only a comment changes), so approving it does not by itself fix the wrong-finishReason bug that Kotlin MappingResults.kt and Web Mapping.ts surface today; and the processing_time_ms -> total_time_ms rename is a JSON-name/generated-API break in all eight SDKs for one field, which is worth batching with the LLM-side rename rather than shipping alone.

**What changed:** VLMResult: processing_time_ms renamed to total_time_ms (tag 5, same). Reserved hardware_used(10)/images_processed(14) by number+name. error(16) KEPT per my own check: Swift's throwIfVLMFailed reads it and is the only failure path for one-shot VLM calls. finish_reason(13) comment updated to state it must be produced on both paths -- actually producing it is Phase C work. CORRECTION (found by gate_a.py): my first pass on this item reintroduced time_to_first_token_ms(8) from the raw proposal text without checking that the earlier core-token-usage-one-timing-block edit had already deleted that exact field, on the grounds that TokenUsage.ttft_ms (VLMResult.usage=15) is the canonical spelling. Fixed: reserved 8 with a comment pointing at TokenUsage.ttft_ms.

**Files touched:** `idl/vlm_options.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** VLMResult.error is NOT a dead branch on the Swift side: sdk/runanywhere-swift/Sources/RunAnywhere/Public/API/Namespaces/VLMNamespace.swift:184 `internal static func throwIfVLMFailed(_ result: RAVLMResult)`, :185 `guard result.hasError else { return }`, :186 `throw SDKException(proto: result.error)` -- deleting the field is a Swift compile error, and removing throwIfVLMFailed changes the error contract of the whole VLM namespace (it is the only place a one-shot VLM failure becomes a thrown Swift error). IMPORTANT CORRECTION TO THE BRIEF: the 'why' also claims Web's `if (result.error)` is writt…

**Wire safety:** No tag reuse. 10 (hardware_used), 14 (images_processed), 16 (error) are deleted and correctly reserved by both number and name. 2,3,4,6,11,12 are pre-existing gaps being formalised -- verify none of them was ever shipped under a different name before reserving the numbers alone. processing_time_ms -> total_time_ms keeps tag 5 and type int64: wire-compatible, JSON-name and generated-accessor break…

**Do first:**
  1. Split this item in two; it is three unrelated changes wearing one id.
  1. PART 1 (do first, no proto delta, unblocks the real bug): make commons WRITE finish_reason on both VLM paths -- the one-shot completion in vlm_module.cpp (around :1247-1307) and the stream terminal event (around :1381-1405) -- using the LLM vocabulary already in use at rac_llm_stream.cpp:208 / llm_module.cpp:1757,:2165. Until this lands, MappingResults.kt:80, Mapping.ts:265 and Vlm.ts:131 keep reporting a fabricated reason.
  1. PART 2 (deletions): before removing `error`, port sdk/runanywhere-swift/.../VLMNamespace.swift:184-186 to the working channel (rac_proto_buffer_set_error / VLMStreamEvent.error at idl/vlm_options.proto:161) and confirm the namespace still throws on a failed one-shot call. hardware_used and images_processed can go in the same commit -- no producer, no reader.
  1. PART 3 (rename): do NOT ship processing_time_ms -> total_time_ms alone. Batch it with the LLM-domain rename so the two domains converge in one generated-code churn instead of two, and land it last.
  1. Whatever order you choose, keep `reserved 2,3,4,6,11,12` exactly as the pre-existing gaps -- do not fold the newly-freed 10/14/16 into that same line, keep them on the separate `reserved 10, 14, 16;` so the history stays readable.


### `vlm-stream-one-terminator` — Delete VLMStreamEvent.is_final and tokens_per_second — one terminator, one type for one number

**Proto location:** [vlm_options.proto (VLMStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L152), [vlm_options.proto (VLMStreamEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vlm_options.proto#L158)

**Why:** is_final restates kind == COMPLETED|ERROR, and all three facades already switch on kind — so it exists only to let a fourth facade author derive a subtly different terminal condition from the other seven SDKs. tokens_per_second is copied verbatim from result.usage.tokens_per_second on the terminal event, read by nobody, and declared `float` here while TokenUsage declares the same number `double`, so a round trip through the stream event silently loses precision relative to the result it was copied from.

**Skeptic verdict:** `sound` — None. Note only that commons does PRODUCE both fields (vlm_module.cpp:1094 and :1101), so 'neither field has a reader' is precise but the edit is not zero-code -- dispatch_vlm_stream_event's is_final parameter and those two setter calls have to go with it.

**What changed:** VLMStreamEvent: reserved is_final(7) and tokens_per_second(8) by number+name. kind(4) is the sole terminal discriminator now.

**Files touched:** `idl/vlm_options.proto`

**Status:** `applied`


</details>


<details>
<summary><strong>voice</strong> (12 changes)</summary>

### `voice-audio-format-declared-once` — Delete the audio-format triples that are declared and ignored; one spelling, `sample_rate_hz`

**Proto location:** [voice_agent_service.proto (VoiceAgentTurnRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L67), [voice_agent_service.proto (VoiceAgentAudioFrame)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L76), [voice_agent_service.proto (VoiceAgentTranscribeProtoRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L125)

**Why:** The same three format fields appear on four messages and are enforced on one. Submit 48 kHz stereo to a turn and it is silently reinterpreted as 16 kHz mono: garbage transcript, no error, and three declared fields telling the developer they configured it correctly. The field is also spelled sample_rate_hz on one message and sample_rate on two others.

**Skeptic verdict:** `risky` — Two issues. (1) It moves sample_rate from tag 2 to a NEW tag 6 on VoiceAgentAudioFrame purely to rename it sample_rate_hz. Field names are not on the binary wire, so keeping tag 2 and renaming the field is a free source-only change; renumbering makes it a wire break on the hottest per-frame path across the C ABI, hitting every writer (Swift CppBridge+ModalityProtoABI.swift:493, Kotlin RunAnywhereBridge.kt:1212) and silently zeroing the value under commons/SDK version skew. (2) The new comment 'Input contract is FIXED and enforced in commons ... rejected, not resampled' is false for VoiceAgentTurnRequest at landing time -- only the feed_audio path validates encoding -- so it ships the same species of lying header comment this batch indicts VoiceSessionConfig for.

**What changed:** In voice_agent_service.proto: deleted sample_rate_hz/channels/encoding from VoiceAgentTurnRequest and sample_rate/channels/encoding from VoiceAgentTranscribeProtoRequest; renamed VoiceAgentAudioFrame.sample_rate to sample_rate_hz IN PLACE at tag 2 (no tag move, no reserved). One spelling of sample_rate_hz across the domain.

**Files touched:** `voice_agent_service.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** VoiceAgentAudioFrame.sample_rate (tag 2) has live WRITERS in three SDKs on the per-frame path: Swift Foundation/Bridge/Extensions/CppBridge+ModalityProtoABI.swift:493-495 (`var frame = RAVoiceAgentAudioFrame()` ... `frame.sampleRate = sampleRate`), Kotlin features/VoiceAgent/Services/VoiceAgentMicDriver.kt:78-81 (`sample_rate = SAMPLE_RATE_HZ`), Web Infrastructure/VoiceAgentMicDriver.ts:56 (`sampleRate: SAMPLE_RATE_HZ`). Kotlin RunAnywhereBridge.kt:1212 documents the frame shape in a doc comment that also needs updating. Commons parses the frame at voice_agent_feed_abi.cpp:196-200 and reads o…

**Wire safety:** VoiceAgentAudioFrame: rename tag 2 in place (source-only, no wire change) -- do NOT introduce tag 6 and do NOT reserve 2. VoiceAgentTurnRequest: `reserved 4, 5, 6; reserved "sample_rate_hz", "channels", "encoding";` -- coordinate this with voice-turn-detection-one-message, which reserves 7 on the same message, so both land in one reserved statement. VoiceAgentTranscribeProtoRequest: `reserved 3, …

**Do first:**
  1. Rewrite the VoiceAgentAudioFrame edit as an in-place rename at tag 2 (see correctionNeeded). Zero wire impact, three source edits.
  1. Add the enforcement the new comment promises, in the same change: extend voice_agent_feed_abi.cpp:206-210 (which today only checks encoding) to reject a non-16 kHz / non-mono frame, and add the same check to the turn path at voice_agent_d7_abi.cpp:946+ before the request's format fields are removed. Otherwise the comment is false on the day it lands.
  1. Update the three frame writers to the new field name -- Swift CppBridge+ModalityProtoABI.swift:495, Kotlin VoiceAgentMicDriver.kt:81, Web VoiceAgentMicDriver.ts:56 -- plus the doc comment at Kotlin RunAnywhereBridge.kt:1212. Recompile only; no wire change.
  1. Coordinate the VoiceAgentTurnRequest reserved list with voice-turn-detection-one-message (4, 5, 6 here; 7 there) so the two items do not each write a partial reserved statement.


### `voice-delete-dead-config-messages` — Delete VoiceAgentRequest and AudioPipelineConfig: 9 fields, 2 messages, zero readers

**Proto location:** [voice_agent_service.proto (VoiceAgentRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L28), [voice_agent_service.proto (AudioPipelineConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L96), [voice_agent_service.proto (VoiceAgentComposeConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L117)

**Why:** VoiceAgentRequest is the request type of the one streaming entry point, so its six fields read as the documented way to filter, scope or replay the stream, and none of that is possible. AudioPipelineConfig is worse: it is reachable from VoiceAgentComposeConfig, so a developer can wire cooldown tuning end to end and get silence because commons hardcodes 800 ms.

**Skeptic verdict:** `sound` — One extra edit site the risk does not name: VoiceAgentRequest is wired into the stream generator table at idl/codegen/generate_streams.sh:53 and referenced in codegen/templates/ts_async_iterable.njk:20/26, so the generator and template change too, not just the 8 adapters (web VoiceAgentStreamAdapter.ts:66, RN :53, RunAnywhere+VoiceAgent.ts:960/966/1298). Also reserve 21 AND 22 together -- the `after` reserves both but only names audio_pipeline_config in the prose.

**What changed:** Deleted messages VoiceAgentRequest and AudioPipelineConfig entirely from voice_agent_service.proto, plus VoiceAgentComposeConfig.audio_pipeline_config and VoiceAgentComposeConfig.session_id. The now-unused `import "component_types.proto"` (EventCategory) and `import "errors.proto"` (ErrorSeverity, SDKError) were removed from that file so protoc stays warning-free.

**Files touched:** `voice_agent_service.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** VoiceAgentRequest is constructed but never read, in three hand-written files plus the generator: React Native Adapters/VoiceAgentStreamAdapter.ts:22 (import) and :53 (`req: VoiceAgentRequest = VoiceAgentRequest.fromPartial({ eventFilter: '' })`); Web Adapters/VoiceAgentStreamAdapter.ts:22 and :66; Web Public/Extensions/RunAnywhere+VoiceAgent.ts:38, 960, 966, 1298. The generator half the risk field omits is real: idl/codegen/generate_streams.sh:53 lists 'VoiceAgentRequest' in the stream table and idl/codegen/templates/ts_async_iterable.njk:20 and :26 name it. AudioPipelineConfig: nothing found…

**Wire safety:** Whole-message deletions (VoiceAgentRequest, AudioPipelineConfig) -- no internal tag concerns. On VoiceAgentComposeConfig reserve BOTH 21 and 22 with both names: `reserved 21, 22; reserved "audio_pipeline_config", "session_id";` -- the `after` block reserves both but the prose only names audio_pipeline_config. If voice-turn-detection-one-message also lands, fold its `reserved 20` into the same sta…

**Do first:**
  1. Edit the generator first, then regenerate, then touch hand-written code -- in that order. Change idl/codegen/generate_streams.sh:53 to make the VoiceAgent stream request-less and adjust idl/codegen/templates/ts_async_iterable.njk:20/26. If you delete the message before fixing the generator, the next regeneration re-emits a reference to a type that no longer exists.
  1. Then update the three hand-written call sites that pass the empty request: web Adapters/VoiceAgentStreamAdapter.ts:66, web RunAnywhere+VoiceAgent.ts:1298, RN Adapters/VoiceAgentStreamAdapter.ts:53 -- drop the `{ eventFilter: '' }` default argument and the imports at web :22/:38 and RN :22.
  1. Reserve 21 AND 22 together with both names on VoiceAgentComposeConfig; the proposal's prose only mentions audio_pipeline_config.
  1. Leave voice_agent_audio_pipeline_state.cpp and rac_voice_agent.h alone -- the 800 ms cooldown lives in the C API, not this proto message, and deleting the proto message does not touch it.


### `voice-device-affinity-npu` — Rename DEVICE_AFFINITY_ANE to DEVICE_AFFINITY_NPU (vendor-neutral, wire number unchanged)

**Proto location:** [pipeline.proto (DeviceAffinity)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/pipeline.proto#L45)

**Why:** A Qualcomm Hexagon NPU - the primary target of this workspace - currently has to be requested by asking for the Apple Neural Engine. The YAML loader already accepts `npu` as an alias, so the code has picked the neutral word and only the enum name lags.

**Skeptic verdict:** `sound` — None. The LiveKit force_cpu precedent is decorative and I could not verify it offline, but the change stands on the in-repo evidence alone: the loader already treats npu and ane as synonyms, so the proto is the only place still naming one silicon vendor.

**What changed:** Renamed DEVICE_AFFINITY_ANE to DEVICE_AFFINITY_NPU in pipeline.proto's DeviceAffinity enum, keeping wire value 4, and replaced the '// Apple Neural Engine' trailing comment with the vendor-neutral description (Apple Neural Engine, Qualcomm Hexagon NPU, etc.; the YAML loader already accepts "npu").

**Files touched:** `pipeline.proto`

**Status:** `applied`


### `voice-drop-model-name-selectors` — Drop the three `*_model_name` selectors: keep id (normal) and path (escape hatch)

**Proto location:** [voice_agent_service.proto (VoiceAgentComposeConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L107)

**Why:** Nine selectors for three choices. Commons documents a resolution order (path beats id beats name) that no SDK exercises: no facade sets any *_name field. A caller who sets two of them gets undefined-looking behaviour with no error.

**Skeptic verdict:** `sound` — Minor: test_speech_proto_abi.cpp:96 is a compile-time break that the risk field does not enumerate, and Python's C-struct path keeps a model_name concept alive in the ABI even after the proto fields go, so config_from_proto's name branch and rac_voice_agent_config_t must be pruned together or the ABI keeps a field no proto can fill.

**What changed:** Deleted stt_model_name, llm_model_name and tts_voice_name from VoiceAgentComposeConfig in voice_agent_service.proto, leaving six selectors (path + id per component), and replaced the message's false header comment ('takes a path, an id, or a name') with the two-way rule: id is the normal choice, path is the escape hatch for a self-staged artifact.

**Files touched:** `voice_agent_service.proto`

**Status:** `applied`


### `voice-drop-type-kind-discriminator` — Delete the dead `type_kind` discriminator from all four solution configs and fix the crossed enum numbers

**Proto location:** [solutions.proto (SolutionType)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/solutions.proto#L31), [solutions.proto (SolutionConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/solutions.proto#L25), [solutions.proto (VoiceAgentConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/solutions.proto#L72), [solutions.proto (RAGConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/solutions.proto#L102)

**Why:** SolutionConfig numbers agent_loop = 4 and time_series = 5; SolutionType numbers them 5 and 4. The mismatch is latent only because type_kind is never set and never read - solution_converter switches on config_case(). The moment a frontend does what the enum's comment tells it to do, agent-loop configs read as time-series.

**Skeptic verdict:** `sound` — One edit site to include: sdk/runanywhere-kotlin/src/test/.../SolutionsGeneratedSurfaceTest.kt:36 constructs `type_kind = SolutionType.SOLUTION_TYPE_VOICE_AGENT` and :48 asserts it back, so that generated-surface test must be updated in the same change. Also beware the name collision when editing by grep: `type_kind` is an unrelated live field on the model-registry structs.

**What changed:** In solutions.proto: deleted the dead `type_kind` field from all four solution configs (VoiceAgentConfig, RAGConfig, AgentLoopConfig, TimeSeriesConfig) and un-crossed SolutionType's numbers so SOLUTION_TYPE_AGENT_LOOP = 4 and SOLUTION_TYPE_TIME_SERIES = 5, matching SolutionConfig.agent_loop = 4 and SolutionConfig.time_series = 5, with each value annotated with the oneof tag it mirrors. VoiceAgentConfig's tags were also renumbered densely 1-14 to close the holes the deletion and earlier deletions left.

**Files touched:** `solutions.proto`

**Status:** `applied`


### `voice-event-oneof-prune` — Cut VoiceEvent's oneof from 19 arms to 10 and delete the 8 backing messages nothing emits

**Proto location:** [voice_events.proto (VoiceEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L55), [voice_events.proto (SessionStartedEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L308), [voice_events.proto (AudioLevelEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L222), [voice_events.proto (WakeWordDetectedEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L355)

**Why:** Nine of the nineteen arms have no producer anywhere in the repo, and four of them duplicate TurnLifecycleEvent kinds that ARE emitted, so a consumer switching on the oneof writes dead branches and may double-render session start/stop and response start/complete. The Swift SDK's own AGENTS.md already documents the trap in prose.

**Skeptic verdict:** `risky` — Two live main-code consumers, not just the one test the risk field admits. (1) Swift Sources/RunAnywhere/Public/API/Events.swift:103 has `case .agentResponseStarted: return .agentStateChanged(.speaking)` -- deleting arm 22 removes the only path by which the public Swift VoiceEvent stream reports the agent started speaking, so a UI driven off agentStateChanged silently never shows 'speaking'. (2) Kotlin's adapter and pipelineStateOrNull are exercised through session_started at VoiceAgentStreamAdapterTest.kt:79/87/105/120 and VoiceAgentGeneratedSessionSurfaceTest.kt:25. Separately, the `after` block silently reserves 33 / "metadata" on VoiceEvent -- a field deletion that appears nowhere in the title, why or risk.

**What changed:** Cut VoiceEvent's oneof to exactly 10 arms and deleted the 8 backing messages (SessionStartedEvent, SessionStoppedEvent, AgentResponseStartedEvent, AgentResponseCompletedEvent, SpeechTurnDetectionEvent + its SpeechTurnDetectionEventKind enum, WakeWordDetectedEvent, AudioLevelEvent, ComponentProgressEvent) from voice_events.proto. No reserved statements; the surviving arms and the correlation fields were renumbered densely (payload 10-19, correlation 20-23). VoiceEvent.metadata was KEPT.

**Files touched:** `voice_events.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** Six of the eight deleted arms are read by Kotlin MAIN code in one file: public/extensions/VoiceAgent/VoiceEventState.kt:22 (session_started -> PIPELINE_STATE_LISTENING), :23 (session_stopped -> PIPELINE_STATE_STOPPED), :26 (agent_response_started -> GENERATING_RESPONSE), :27 (agent_response_completed -> SPEAKING), :28 plus :40 and :41 (speech_turn_detection -> pipeline state and speechDetected), :36 (audio_level -> is_speech). Kotlin public API public/api/VoiceSession.kt:214 also reads speech_turn_detection. Swift Public/API/Events.swift:103 `case .agentResponseStarted:` is the only path by w…

**Wire safety:** Reserve 20, 21, 22, 23, 24, 26, 27, 28 and their names on VoiceEvent's oneof. Do NOT reserve 33 / "metadata" as part of this item (see correctionNeeded). Removing oneof arms is one-directional on the wire: commons emits none of the eight (no mutable_session_started / mutable_agent_response_* / mutable_audio_level etc. anywhere in commons/src), so a new SDK against old commons is fine; the break i…

**Do first:**
  1. PREREQUISITE THAT DOES NOT EXIST YET: audio_level's is_speech has no TurnLifecycleEvent equivalent, so VoiceEventState.kt:36 loses its only source. Either keep arm 27, or move is_speech onto VADEvent (which commons does emit) and land that first. Nothing else in this item can proceed past that decision.
  1. Land the replacement mappings with the old arms STILL PRESENT. TurnLifecycleEvent already carries the kinds -- Swift Generated/voice_events.pb.swift:321-322 shows agentResponseStarted = 5 and agentResponseCompleted = 6 as TurnLifecycleEventKind -- and commons emits turn_lifecycle from voice_agent_internal_helpers.cpp:366 via voice_agent_proto_abi.cpp:335, 385, 390, 459, 548 and voice_agent_d7_abi.cpp:401, 509, 907. Rewrite VoiceEventState.kt:22-28 and Swift Events.swift:103 onto those kinds, confirm green, then delete.
  1. Rewrite Kotlin VoiceSession.kt:214 (speech_turn_detection) and the two turn-detection branches at VoiceEventState.kt:40-41 onto TurnLifecycleEventKind.USER_SPEECH_STARTED / USER_SPEECH_ENDED, which VoiceEventState.kt:42-43 already uses -- so the file will read from one source instead of two.
  1. Rewrite the four tests (VoiceAgentStreamAdapterTest.kt:79, 87, 88, 105, 109, 120 and VoiceAgentGeneratedSessionSurfaceTest.kt:25, 29, 72, 73) to construct TurnLifecycleEvent instead of SessionStartedEvent / AgentResponseStartedEvent / AudioLevelEvent.
  1. Remove `reserved 33; reserved "metadata";` from this change (see correctionNeeded).


### `voice-instructions` — Add `instructions` to VoiceAgentComposeConfig so the agent's persona is not a C++ constant

**Proto location:** [voice_agent_service.proto (VoiceAgentComposeConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L104), [llm_options.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/llm_options.proto#L57)

**Why:** Every app that embeds this SDK ships the same generic assistant, because the system prompt is kVoiceAgentSystemPrompt in voice_agent_internal.h. The only proto path is LLMGenerationOptions.system_prompt nested two levels down, and config_from_proto never reads llm_generation. This is the first field a developer looks for and it is unreachable from all eight SDKs.

**Skeptic verdict:** `not-simpler` — The bug is a C++ wiring omission, not missing proto surface. VoiceAgentComposeConfig.llm_generation = 25 already reaches LLMGenerationOptions.system_prompt = 9 (llm_options.proto:57); one line in config_from_proto fixes the persona gap with zero new fields. Adding compose-level `instructions` while leaving llm_generation.system_prompt in place gives a newcomer two fields for one value with undefined precedence -- strictly more surface to learn, not less. If it lands, the same change must state which wins (or drop system_prompt from the voice path).

**What changed:** Added `optional string instructions` to VoiceAgentComposeConfig in voice_agent_service.proto, with a comment that states the precedence the carePlan demanded: it is the only system prompt the voice path reads, and llm_generation.system_prompt is IGNORED there. Tag is 9 (not 26) because the message was renumbered densely after the deletions in the other items.

**Files touched:** `voice_agent_service.proto`

**Status:** `applied`

**Care level:** `sequenced`

**What could break:** Nothing breaks at the proto level, but three SDKs ALREADY populate the sibling path today and would change behaviour the moment commons starts reading it: Swift VoiceNamespace.swift:81 `config.llmGeneration = generation.toProto()`, React Native Public/Api/Voice.ts:186 `llmGeneration: toLlmOptions(options.generation)`, Flutter lib/public/api/namespaces/voice.dart:82 `config.llmGeneration = generation.toProto()`. Those payloads are inert right now because config_from_proto (voice_agent_internal_helpers.cpp:401-430) never reads llm_generation and voice_agent_internal_helpers.cpp:82 unconditional…

**Wire safety:** New `optional string instructions = 26` on VoiceAgentComposeConfig. Tag 26 is free (highest existing is llm_generation = 25, idl/voice_agent_service.proto:114). No tag reuse, no renumbering, no enum change. Name `instructions` collides with nothing: `rg -n '\binstructions\b' idl/*.proto` hits only prose in tool_calling.proto:206 and :285. NOTE tag arbitration: voice-turn-detection-one-message als…

**Do first:**
  1. Write the precedence into the proto comment before writing the field -- this is the skeptic's entire objection and it costs one sentence: `instructions` wins; `llm_generation.system_prompt` is IGNORED on the voice path. Do not ship two fields for one value with undefined precedence.
  1. Wire it in the same commit: in config_from_proto (voice_agent_internal_helpers.cpp:401-430) read proto.instructions(), and change voice_agent_internal_helpers.cpp:82 from `options.system_prompt = kVoiceAgentSystemPrompt` to use kVoiceAgentSystemPrompt only as the fallback when instructions is unset or empty.
  1. Mind the string lifetime: config_from_proto returns a rac_voice_agent_config_t of raw `const char*` (see the same function at :420 doing `proto.tts_n.c_str()`). The instructions pointer must outlive the returned struct -- store it, do not hand out a c_str() of a temporary.
  1. Thread it through the Web TS pipeline at RunAnywhere+VoiceAgent.ts:711 and :837 so the constant becomes `instructions ?? VOICE_SYSTEM_PROMPT`. Web runs the pipeline itself; skipping this makes the field a no-op on one of the eight SDKs.
  1. Decide what happens to the three existing llm_generation writers (Swift VoiceNamespace.swift:81, RN Voice.ts:186, Flutter voice.dart:82) -- either leave llm_generation unread on the voice path (documented) or accept the behaviour change on upgrade, but state which.


### `voice-one-error-shape` — One error payload: keep VoiceSessionError, retire ErrorEvent and the bare error string

**Proto location:** [voice_events.proto (ErrorEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L186), [voice_events.proto (VoiceSessionError)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L291), [voice_events.proto (TurnLifecycleEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L350)

**Why:** Errors arrive three ways: ErrorEvent (int32 ra_status_t code, is_recoverable, an untyped details_json), VoiceSessionError (canonical ErrorCode, recoverable), and a bare string on TurnLifecycleEvent. Kotlin reads one, Web reads the other, and neither sees what the other sees. `is_recoverable` vs `recoverable` differing by a prefix is the kind of thing that costs an afternoon.

**Skeptic verdict:** `sound` — One factual overstatement and one loss to price in. 'Kotlin reads one, Web reads the other, and neither sees what the other sees' overstates it -- Swift Events.swift:99-102 already folds BOTH arms onto one public case. And ErrorEvent's `operation` and `details_json` have no home in VoiceSessionError, so d7_emit_error's component-name + arbitrary rac_result_t must map cleanly onto ErrorCode or diagnostics regress; the proposal's c_abi_code fallback covers the code but not the two dropped strings.

**What changed:** Deleted message ErrorEvent and its VoiceEvent oneof arm from voice_events.proto, leaving VoiceSessionError as the single error payload. Gave ErrorEvent.operation a home as `optional string operation = 6` on VoiceSessionError; details_json was dropped (removing that escape hatch is the point of the item) and `component` is served by the existing failed_component. TurnLifecycleEvent's bare `string error = 6` became `optional VoiceSessionError error = 6` in place at the same tag, keeping the message dense.

**Files touched:** `voice_events.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** Five SDK read sites on the ErrorEvent arm, all main code: Kotlin public/api/VoiceSession.kt:233 `VoiceEvent.Error(it.message.ifBlank { ... }, it.is_recoverable)`; Swift Public/API/Events.swift:100 `.error(message: error.message, recoverable: error.isRecoverable)`; Web Public/API/Namespaces/voice.ts:90 `recoverable: event.error.isRecoverable`; RN Public/Api/Voice.ts:99 same; Flutter lib/public/api/namespaces/voice.dart:223 same. Web is also a PRODUCER, because its pipeline is TypeScript: RunAnywhere+VoiceAgent.ts:811-813 constructs an ErrorEvent with `isRecoverable: true` and `detailsJson: ''`…

**Wire safety:** `reserved 16; reserved "error";` on VoiceEvent when the arm goes. ErrorEvent is deleted whole. On TurnLifecycleEvent: `reserved 6; reserved "error";` and add `optional VoiceSessionError error = 9;` -- confirm 7 and 8 are actually free on that message before taking 9 (the brief does not show TurnLifecycleEvent's full field list). No enum renumbering: ErrorCode and ra_status_t both stay as they are…

**Do first:**
  1. Converge the producers first and emit BOTH arms for one release: change voice_agent_d7_abi.cpp:225-230 and vad_module.cpp:352 to also fill VoiceSessionError, mapping ra_status_t onto ErrorCode and stashing the raw value in c_abi_code (voice_events.proto:295). Do not delete the ErrorEvent arm in the same commit that changes the producers.
  1. Find a destination for `operation` and `details_json` before deleting ErrorEvent. `component` maps to VoiceSessionError.failed_component and the code maps to c_abi_code, but those two strings have no home -- either add them to VoiceSessionError or write the diagnostics loss into the commit message and the proto comment.
  1. Re-read telemetry_manager.cpp:1005 and whatever it feeds; its comment asserts VAD and voice-agent failures ride the ErrorEvent arm, so telemetry may silently stop seeing them.
  1. Fix Web's producer side (RunAnywhere+VoiceAgent.ts:811-813) at the same time as its consumer side (voice.ts:90) -- Web writes and reads its own errors, so a one-sided edit breaks its own loop.
  1. Move the five SDK read sites onto session_error, THEN reserve 16 on VoiceEvent and delete ErrorEvent.
  1. For TurnLifecycleEvent.error, confirm nothing reads the bare string first (`rg -n 'turn_lifecycle.*error|turnLifecycle.*error' sdk/ --glob '!**/generated/**' --glob '!**/Generated/**' --glob '!**/proto-ts/**'`) -- my turn_lifecycle grep found consumers at Kotlin VoiceSession.kt:199 and VoiceEventState.kt:29/42/43 but I did not confirm whether any of them touch .error.


### `voice-one-language-field` — One name for the language field - `language` - and make the session-scoped one work

**Proto location:** [voice_agent_service.proto (VoiceAgentComposeConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L119), [voice_agent_service.proto (VoiceAgentTranscribeProtoRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L126), [voice_events.proto (UserSaidEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L98), [stt_options.proto](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/stt_options.proto#L28)

**Why:** Four spellings for one BCP-47 string: language_code, default_language_code, language_hint, and plain `language` in stt_options.proto. The session-scoped one is the dead one, so a multilingual app must set the language on every single turn and can only discover that by experiment.

**Skeptic verdict:** `sound` — None material. Coordinate with the TurnDetection proposal, which independently adds VoiceAgentTurnRequest.language = 9 as the per-turn override; the two names must land describing one precedence rule (session field 23 vs per-turn field 9) or the newcomer trades one naming confusion for a scoping one.

**What changed:** One spelling, `language`, across the domain: VoiceAgentComposeConfig.default_language_code -> language (session-scoped, documented as the session default with VoiceAgentTurnRequest.language as the per-turn override), VoiceAgentTranscribeProtoRequest.language_hint -> language, and voice_events.proto UserSaidEvent.language_code -> language (detected language, BCP-47).

**Files touched:** `voice_agent_service.proto`, `voice_events.proto`

**Status:** `applied`


### `voice-one-time-base-ms` — Collapse four time bases to one: integer milliseconds, with OpenAI's field names

**Proto location:** [voice_events.proto (VoiceEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L48), [voice_events.proto (UserSaidEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L96), [voice_events.proto (VADEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L140), [voice_events.proto (MetricsEvent)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_events.proto#L215)

**Why:** One domain carries microseconds-since-epoch, milliseconds-since-epoch, monotonic nanoseconds, and plain ms durations. timestamp_us's precision is fiction (the producer is rac_get_current_time_ms() * 1000, so the last three digits are always zeros that all 8 SDKs faithfully carry), and audio_start_us has no stated origin, which makes transcript-to-waveform alignment unimplementable without reading the C++.

**Skeptic verdict:** `not-simpler` — It unifies time inside voice by diverging from every other domain. timestamp_us is the same spelling on LLMStreamEvent (rac_llm_stream.cpp:195), RAGStreamEvent (rac_rag_proto_abi.cpp:1048, which also does now_ms()*1000), DiffusionStreamEvent (:476), structured_output.cpp:729, vlm_module.cpp:1091 and tool_calling_session.cpp:393 -- 76 files mention timestamp_us. After this change a newcomer reading two adjacent event streams sees timestamp_ms in voice and timestamp_us everywhere else, which is more to learn, not less. Worth doing only as a repo-wide pass (and the same *1000 lie exists in RAG, so the pass is already justified).

**What changed:** Applied the globalRule (integer milliseconds, named *_ms) to voice_events.proto: VoiceEvent.timestamp_us -> timestamp_ms, UserSaidEvent.audio_start_us/audio_end_us -> audio_start_ms/audio_end_ms with a documented origin (ms from the start of ALL audio fed this session, matching OpenAI input_audio_buffer.speech_started.audio_start_ms), and MetricsEvent.created_at_ns deleted outright with the remaining metrics renumbered densely. All renames are in place at their existing tags rather than new tags plus reserved, per the no-backcompat rule. Added the rule to the file header.

**Files touched:** `voice_events.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** The Web SDK is a producer of all four fields in main code: RunAnywhere+VoiceAgent.ts:944 `timestampUs: Date.now() * 1000`, :1043 `timestampUs: 0`, :623 and :673 frameOffsetUs, :691 audioStartUs. commons producers: rac_voice_event_abi.cpp:158-159 (the now_us() one -- see correctionNeeded), voice_agent_internal_helpers.cpp:309, 348, 360, 383, and voice_agent_d7_abi.cpp:73-74. created_at_ns has a Flutter test consumer at streaming_proto_fixtures.dart:209 and :237. The skeptic's divergence objection is real and measurable: timestamp_us is the same spelling on LLMStreamEvent, RAGStreamEvent, Diffu…

**Wire safety:** New tag 34 on VoiceEvent with `reserved 2; reserved "timestamp_us";` -- never an in-place type or meaning change, exactly as the risk field says. UserSaidEvent: new 8 and 9, `reserved 4, 5`. VADEvent: new 8, `reserved 2`. MetricsEvent: `reserved 8; reserved "created_at_ns";`. No tag reuse anywhere. This IS a wire break under version skew in both directions: a new SDK reading an old commons sees t…

**Do first:**
  1. PREREQUISITE, a decision that has not been made: voice-only rename versus a repo-wide time-base pass. The skeptic is right that a voice-only rename leaves a newcomer reading timestamp_ms in voice and timestamp_us in five other event streams. Get that decided before touching voice_events.proto -- everything below is wasted if the answer is 'repo-wide'.
  1. PREREQUISITE: rac_voice_event_abi.cpp:159 fills timestamp_us from now_us(), a real microsecond clock. Either convert it to milliseconds first, or drop the 'three zeros wide' justification. Renaming to _ms while a us producer is live means truncating real precision on that path.
  1. Rewrite the Flutter fixture at streaming_proto_fixtures.dart:209 and :237 before deleting created_at_ns; it both writes and asserts on that field.
  1. Fix the four Web producer sites (RunAnywhere+VoiceAgent.ts:944, 1043, 623, 673, 691) in the same release as commons -- Web writes these values itself, so a commons-only change leaves Web emitting microseconds into a field named _ms.
  1. Emit both tag 2 and tag 34 for one release rather than a clean cutover, because the failure mode of skew here is a plausible-looking 0, not a crash.


### `voice-result-drop-dead-fields` — Cut VoiceAgentResult from 16 fields to 6 and delete the false 'Required to interpret' comment

**Proto location:** [voice_agent_service.proto (VoiceAgentResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L37), [voice_agent_service.proto (VoiceAgentResult)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L46)

**Why:** Only fields 1-6 are ever set. The comment 'Required to interpret synthesized_audio' points at three fields that are always zero, and the bytes are actually a self-describing WAV, so a consumer that trusts the comment divides by zero or plays at the wrong pitch. The four timings are duplicated by MetricsEvent, which is the copy that is populated.

**Skeptic verdict:** `risky` — Four live readers of the fields being reserved. (1) sdk/runanywhere-cli/src/commands/cmd_voice.cpp:114-117 reads result.synthesized_audio_sample_rate_hz() with a 22050 fallback -- and reinterpret_cast<const float*>s the payload, i.e. it does NOT treat it as WAV, so either the CLI or the WAV claim is wrong and one of them is a live bug. (2) sdk/runanywhere-python/native/module.cpp:1794-1799 hand-decodes VoiceAgentResult by raw wire tag (field==7 -> sample_rate_hz, 8 -> channels, 12..15 -> *_time_ms); reserving those tags leaves a hand-rolled parser silently reading reserved numbers, surfaced to users via runanywhere/results.py:272 and api/voice.py:80. (3) web VoiceAgentMicDriver.ts:276 reads synthesizedAudioSampleRateHz and RunAnywhere+VoiceAgent.ts:789/1109 writes it. Removing the fields is defensible; the claim that nothing consumes them is not.

**What changed:** Cut VoiceAgentResult in voice_agent_service.proto from 16 fields to 6 (speech_detected, transcription, assistant_response, thinking_content, synthesized_audio, final_state), deleting the three synthesized_audio_* format fields, session_id, turn_id, the four *_time_ms timings and the SDKError. The false '// Required to interpret synthesized_audio.' comment was deleted with the fields it described.

**Files touched:** `voice_agent_service.proto`

**Status:** `applied`

**Care level:** `blocked` (breaking for existing app callers)

**What could break:** Four live readers of the tags being reserved. (1) sdk/runanywhere-cli/src/commands/cmd_voice.cpp:114-115 reads result.synthesized_audio_sample_rate_hz() with a >0 guard, and :130 and :140 read result.total_time_ms(). (2) sdk/runanywhere-python/native/module.cpp:1728-1799 is a hand-rolled protobuf wire reader keyed on raw field numbers -- :1794 `field == 7 -> sample_rate_hz`, :1795 `field == 8 -> channels`, :1796 `field == 12 -> stt_time_ms`, :1799 `field == 15 -> total_time_ms`. Reserving those tags leaves it silently parsing reserved numbers; codegen cannot see it and no build fails. (3) sdk…

**Wire safety:** Reserve 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 plus names on VoiceAgentResult. 16 and 17 are currently skipped with no reserved statement -- include them, as the risk field says. No renumbering and no tag reuse; fields 1-6 keep their tags. Reserving tags does NOT stop the Python hand-rolled parser (module.cpp:1794-1799) from reading those numbers off the wire -- reserved is a compiler concep…

**Do first:**
  1. PREREQUISITE: settle WAV-vs-raw-float. Read voice_agent_proto_abi.cpp:531-543 and voice_agent_d7_abi.cpp:889 (`set_synthesized_audio(wav_data, wav_size)`) against cmd_voice.cpp:114-117, and fix whichever is wrong. Until that is settled the replacement comment cannot be written honestly, so this item cannot land.
  1. Delete the Python hand-rolled branches at native/module.cpp:1794-1799 FIRST, along with their user-visible surfaces (runanywhere/results.py:272, api/voice.py:80). A raw-tag parser survives a reserved statement silently -- it is the one consumer that will not announce itself at build time.
  1. Fix cmd_voice.cpp:114-115, :130, :140 and web VoiceAgentMicDriver.ts:276 to read the WAV header (or the MetricsEvent timings) instead of the sibling fields.
  1. Grep the two tags the plan reserves that I did NOT separately verify -- 10 (session_id) and 11 (turn_id) on VoiceAgentResult are too generic to grep repo-wide safely. Run `rg -n 'result\.session_id|result\.sessionId|result\.turn_id|result\.turnId|\.session_id\(\)|\.turn_id\(\)' sdk/ --glob '!**/generated/**' --glob '!**/Generated/**' --glob '!**/proto-ts/**'` and read the hits before reserving them.
  1. Only then reserve 7-18 inclusive on VoiceAgentResult, with 16 and 17 in the same statement.


### `voice-turn-detection-one-message` — Delete VoiceSessionConfig; add one TurnDetection message with OpenAI's field names

**Proto location:** [voice_agent_service.proto (VoiceSessionConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L84), [voice_agent_service.proto (VoiceAgentTurnRequest)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L70), [voice_agent_service.proto (VoiceAgentComposeConfig)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/voice_agent_service.proto#L116), [vad_options.proto (VADConfiguration)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/07907b273/idl/vad_options.proto#L31)

**Why:** Turn-taking is the first thing a voice developer configures, and today it lives on a message whose own header comment is false: 8 of VoiceSessionConfig's 9 fields have no reader, and the compose path drops the whole message. There is no way to switch barge-in off or do push-to-talk, so the Swift SDK smuggled a minimum-silence value into VADConfiguration.max_speech_duration_ms.

**Skeptic verdict:** `sound` — Not a defect in the proposal, but a gap it leaves: VADConfiguration survives and its activation_threshold (live -- read at voice_agent_internal_helpers.cpp:423) is the same physical knob as the new TurnDetection.threshold, on a different scale (VAD default 0.015 vs the proposed 0.5). VADOptions also already has min_silence_duration_ms and prefix_padding_ms (vad_options.proto:86,93). Landing TurnDetection without stating which wins re-creates the two-places-to-set-one-thing problem it is fixing.

**What changed:** Deleted message VoiceSessionConfig outright from voice_agent_service.proto (no reserved, no tombstone, per the no-backcompat rule) and added message TurnDetection with nested enum Type (UNSPECIFIED/VAD/MANUAL), threshold, silence_duration_ms, prefix_padding_ms, and the two presence-carrying booleans interrupt_response and create_response. Wired it as VoiceAgentComposeConfig.turn_detection = 10, dropped VoiceAgentComposeConfig.session_config, dropped VoiceAgentTurnRequest.session_config, and gave VoiceAgentTurnRequest a per-turn `optional string language` in its place.

**Files touched:** `voice_agent_service.proto`

**Status:** `applied`

**Care level:** `sequenced` (breaking for existing app callers)

**What could break:** VoiceSessionConfig is live in six places, not dead. (1) commons: voice_agent_d7_abi.cpp:980-981 reads session_config().language_code() and passes it to the d7 turn at :984 -- delete the message and that call site stops compiling. (2) Web main code reads seven of the nine fields: RunAnywhere+VoiceAgent.ts:642 languageCode, :706 and :832 maxTokens, :714 and :840 thinkingModeEnabled, :747 voiceId, :748 languageCode, :773 continuousMode, :883 silenceDurationMs, :884 maxRecordingDurationMs. (3) Kotlin public API: VoiceAgentTypes.kt:25 `typealias VoiceSessionConfig`, plus four public extension memb…

**Wire safety:** Deleting VoiceSessionConfig frees no tags inside it, but the two fields that pointed at it MUST be reserved: `reserved 7; reserved "session_config";` on VoiceAgentTurnRequest and `reserved 20; reserved "session_config";` on VoiceAgentComposeConfig. The new per-turn language_code on VoiceAgentTurnRequest must take a fresh tag, NOT 7. TurnDetection is a brand-new message; its slot on VoiceAgentComp…

**Do first:**
  1. Give each of the nine fields a named destination before deleting anything. TurnDetection covers four (silence_duration_ms, speech_threshold, plus the two new booleans). max_tokens and thinking_mode_enabled belong in llm_generation; voice_id duplicates VoiceAgentComposeConfig.tts_voice_id which already exists; auto_play_tts and max_recording_duration_ms have no home yet. The Web SDK reads all five of those, so 'they were dead' is not an available answer.
  1. Land commons FIRST, in this order: add TurnDetection + VoiceAgentTurnRequest.language_code; teach config_from_proto (voice_agent_internal_helpers.cpp:401-430, which today reads only *_path/*_id/*_name plus vad_config) to consume TurnDetection; change voice_agent_d7_abi.cpp:980-984 to prefer request.language_code() and fall back to request.session_config().language_code() for one release so old clients keep working under version skew.
  1. State the VAD-vs-TurnDetection precedence in the proto, as the skeptic asked. VADConfiguration is live: voice_agent_internal_helpers.cpp:421 reads vad.sample_rate() and :426 reads vad.activation_threshold() into energy_threshold. activation_threshold and the new TurnDetection.threshold are the same physical knob on different scales (0.015 vs 0.5). Either declare which wins or delete VADConfiguration's overlapping fields in the same change.
  1. Rewrite the ten Web read sites (RunAnywhere+VoiceAgent.ts:642, 706, 714, 747, 748, 773, 832, 840, 883, 884) BEFORE deleting the message, or the Web build compiles against fields that are gone.
  1. Delete the Swift smuggle at VoiceNamespace.swift:77 `vadConfig.maxSpeechDurationMs = Int32(vad.minSilenceMs)` in the same commit that introduces TurnDetection.silence_duration_ms -- that line is the bug being fixed, and leaving it sets the value twice on two different knobs.
  1. Remove or redirect the public Kotlin extensions (VoiceAgentTypes.kt:25, 34, 37, 40, 43) and the public Swift typealias + extension (VoiceAgentTypes.swift:18, 29-31), and update the docs that reference them (swift ARCHITECTURE.md:553, kotlin docs/Documentation.md:199). These are public API, so app code source-breaks, not just recompiles.


</details>


## Anti-proposals (decisions NOT to change the proto)

These proposals recommended *against* a change. Approving them means the proto stays as-is; no edit was made.

- **`diar-P6`** (diarization): Keep minimum_duration_ms and merge_gap_ms names as they are
- **`events-shape-keep-typed-oneof`** (events-shape): Do NOT flatten SDKEvent to a type string plus an opaque payload - keep the typed oneof
- **`rag-keep-llm-generation-options`** (rag): Keep LLMGenerationOptions on query — do not mint a near-duplicate RAGGenerationOptions
- **`rr-no-raw-scores`** (rerank): Do not add RerankOptions.raw_scores
- **`rr-no-request-id`** (rerank): Do not add RerankRequest.request_id for cancellation
- **`router-proto-availability-ladder`** (routing): Do NOT add a ModelAvailability/UnavailableReason ladder to router.proto
- **`seg-shared-pixel-format-enum`** (segmentation): Hoist SegmentationPixelFormat into a shared PixelFormat enum
- **`so-p10`** (structured-output): Do not add a StructuredEnforcementMode field to the options
- **`so-p11`** (structured-output): Do not add a choices arm and a StringList message to the constraint
- **`so-p12`** (structured-output): Do not add a StructuredFinishReason enum to StructuredOutputResult

## Declined

The skeptic recommended decline, or the proposal was independently rejected; no proto change was made.

- **`core-capabilities-shrink`** (core): Replace the 5-message SDKCapabilities block with one message and a typed Modality enum — By its own risk text this is worthless without unproposed commons + facade work, and the replacement message mixes a capability (tools) into an enum called Modality while leaving the unavailable side…
- **`cua-add-raw-action-name`** (cua): Add one open `string action_name` so an unrecognized verb is reportable, not silently dropped — Two legs of three are weak: the 'open-string escape hatch both Anthropic and OpenAI use' does not exist (both close the vocabulary per tool version), and the proposal's own `risk` field concedes 'Thi…
- **`cua-keys-array`** (cua): Give KEY chords a real `repeated string keys` instead of hiding them space-joined inside `text` — The central justification is false. 'Every SDK re-splits the string by hand to reach a platform key API' -- ZERO SDK splits it. The only `keys` hits in the entire facade layer are two doc comments (R…
- **`diar-P4`** (diarization): Delete speaker_index and rename speaker_id to speaker — The blast-radius analysis names the wrong consumers and misses the primary one. (a) MISSED: sdk/runanywhere-commons/src/features/diarization/diarization_module.cpp:416-424 reads speaker_index to enfo…
- **`diar-P5`** (diarization): Rename threshold to speaker_activity_threshold — Two problems. (1) The precedent as written into the IDL comment is misdescribed. The proposed comment says 'pyannote calls this segmentation.threshold', but the pyannote 3.x recipe vendored in this v…
- **`E11`** (embeddings): Rename EmbeddingsRequest.texts to input — Pure taste, and arguably backwards. `input` is OpenAI's name for a string-or-array union; here the field is unconditionally `repeated string`, so `texts` is the more accurate label and the python ser…
- **`E7`** (embeddings): Delete request_id from EmbeddingsRequest and EmbeddingsResult — Again the proposal states its own gate ('If request_id is a hard repo-wide envelope convention across all domains, decline this') and the count settles it: 15 sibling protos carry request_id. This is…
- **`events-naming-epoch-timestamp-spelling`** (events-naming): Spell epoch timestamps one way: `timestamp_ms` on envelopes, `<verb>_at_ms` on facts — The central promise -- "`_unix_ms` disappears entirely", 4 spellings -> 2 -- is false at the scope proposed. `grep -rn '_unix_ms' idl/*.proto` returns 15 fields across 6 files; this proposal renames …
- **`events-shape-drop-category-discriminator`** (events-shape): Delete SDKEvent.category: the oneof arm is already the event type — The central premise -- 'the oneof arm is already the event type' -- is false. category is a FINER axis than the arm, not a parallel copy of it: the single `capability` arm is stamped EVENT_CATEGORY_E…
- **`events-taxonomy-one-event-type`** (events-taxonomy): Collapse the 22 *EventKind enums + EventCategory into ONE flat EventType discriminator — HARD FIELD-TAG COLLISION in `after`. It writes `EventType type = 2;` but sdk_events.proto:1181 already has `ErrorSeverity severity = 2;` inside SDKEvent. I dumped every tag in SDKEvent (lines 1177-12…
- **`images-expected-model-id`** (images): Rename model_id to expected_model_id -- it asserts residency, it does not select a model — Renaming only the diffusion copy trades a mismatch with OpenAI for a mismatch with the rest of this IDL: a newcomer would then see expected_model_id in images and model_id meaning exactly the same as…
- **`llm-config-to-context-length`** (llm): Delete LLMConfiguration and put `context_length` on LLMGenerationOptions where callers can reach it — The premise 'the domain's most consequential knob becomes reachable / an app silently gets 2048 tokens and cannot change it' is false. ModelLoadRequest already carries it: model_types.proto:558 `opti…
- **`llm-delete-dead-surface`** (llm): Delete the surface the proto itself annotates as dead, and `reserved` every freed tag — Four of the deleted fields are live, not dead. (1) generation_time_ms: written at features/llm/llm_module.cpp:1744 and READ by public Kotlin API — RALLMTypesCppBridge.kt:63-66 exposes it as `latencyM…
- **`llm-strip-chat-proto`** (llm): Strip chat.proto to the fields the model actually sees; delete ChatAttachment, ChatMessageStatus and ChatGenerationRequest — ChatMessageStatus and attachments have a live third consumer, exactly the VADConfiguration failure mode. ChatMessageStatus is re-exported from the Web PUBLIC API at sdk/runanywhere-web/packages/core/…
- **`llm-thinking-budget`** (llm): Add a thinking token budget to ReasoningOptions — This is the one proposal that adds surface, and it adds it with no producer and a built-in ambiguity. (a) There is no enforcement point: commons' reasoning code (features/llm/rac_llm_thinking.cpp) ac…
- **`lora-global-bypass`** (lora): Add one bool to run the base model without unloading adapters (adapters_enabled) — By the proposal's own admission this is the one item that adds a concept, and lora-scale-presence already makes scale 0.0 the documented 'loaded but silent' value, so the effect is reachable without …
- **`lora-per-request-adapters`** (lora): Allow per-request adapter selection: add `repeated LoRAAdapterConfig adapters` to LLMGenerationOptions (no new message) — Nothing can honour the field. The only LoRA backend op commons has is `ref.ops->load_lora(impl, path, scale)` (rac_lora_service.cpp:647) plus a clear; there is no per-request adapter switch on the ba…
- **`availability-verdict-enum`** (models): Replace is_available and the three compatibility bools with one availability enum — The premise 'was bool is_available, never defined' is false, and its falsity cuts against the proposal. is_available IS defined today -- as a synonym for downloaded: model_info_make_proto.cpp:527 `mo…
- **`model-metadata-industry-labels`** (models): Swap ModelInfoMetadata's four unreachable fields for quantization, size and arch — `reserved 4;  // tags (nothing could filter on them)` is wrong, and it breaks LoRA. core/model_lifecycle.cpp:470-483, is_lora_adapter_artifact(): `for (const auto& tag : model.metadata().tags()) if (…
- **`one-accelerator-vocabulary`** (models): Collapse four accelerator spellings into one enum on request and result — The `reserved 8, 9, 10` blanket-deletes `backend_preferences` (9), which is not an accelerator spelling at all -- it is a repeated InferenceFramework (engine) list, a different axis from hardware cla…
- **`platform-availability-enum`** (platform): Replace the three compatibility booleans with one four-state Availability enum — Two of the four enum states have no producer and cannot get one from this code path. The only producer, model_compatibility_proto.cpp, maps rac_model_compatibility_result_t, whose inputs (ModelCompat…
- **`platform-one-device-identifier`** (platform): Keep one device identifier: rename device_fingerprint to device_id with a single stated meaning — Renaming device_fingerprint -> device_id inside DeviceInfo collides with an existing, differently-scoped device_id: the registration JSON already has a top-level "device_id" (telemetry_json.cpp:509) …
- **`platform-plugininfo-drop-path`** (platform): Delete PluginInfo.path - the proto comment already says it is always empty — The field is NOT always empty - it is populated on the load() path in at least Swift (:83) and Web (:123) with the caller's real library path; only listLoaded() leaves it "". The proposal misreads th…
- **`rag-chunk-size-chars`** (rag): Rename chunk_size/chunk_overlap to *_chars: the comment says tokens, code counts chars — The central premise -- 'the comment says tokens, code counts chars' / 'rag_chunker splits on characters, not tokens' -- is a misreading. The proto field IS approximate tokens; the chunker multiplies …
- **`rag-metadata-filter-replaces-scope-prefix`** (rag): Replace scope_prefix with a metadata filter, the one knob every vector store has — Two defects. (1) Wire-tag reuse: the `after` puts `repeated RAGFilter filters = 6;` on RAGSearchRequest tag 6, which is today `optional string scope_prefix`. string and embedded-message share wire ty…
- **`hybrid-fold-cloud-config-into-descriptor`** (routing): Carry the cloud credentials inline on the descriptor and delete registerCloudModel() — Internally inconsistent and its own mitigation does not exist. It is marked `breaking: false` while its simplicityGain says it 'deletes registerCloudModel(), registerCloudBackend() and the in-memory …
- **`llm-generate-inference-mode`** (routing): Put the inference mode on LLMGenerateRequest so text generation can be routed at all — This is a net-add of surface for a subsystem that does not exist, not a simplification -- and it is not free-standing: HybridInferenceMode is created by hybrid-mode-enum-replaces-prefer-local, so llm…
- **`seg-drop-diagnostic-rgba`** (segmentation): Delete include_diagnostic_rgba and diagnostic_rgba — The dead-surface enumeration is wrong in the exact way the brief warns about. The proposal claims "Two of three shipped facades charge for it and drop it", but the grep finds a FOURTH facade it never…
- **`so-p4`** (structured-output): Delete the duplicate payload carriers on StructuredOutputValidation — This is the over-eager dead-surface error the review was warned about. 'nothing reads the field' is wrong: extracted_json is the ONLY field on StructuredOutputValidation that carries the extracted do…
- **`so-p8`** (structured-output): Delete the unread metadata, request_id and prepared-prompt echoes — Calling prepared_prompt an 'unread echo' is flatly wrong - it is the only output of a shipped ABI entry point, written unconditionally, and asserted by a browser e2e test. Deleting tag 1 leaves Struc…
- **`stt-config-only-init-time`** (stt): Gut STTConfiguration to model_id + framework + default_options; delete the 9 shadow knobs — The load-bearing premise is false. Tags 13 (language), 3 (sample_rate) and 4 (enable_vad) have a live writer in shipped commons, and tags 3, 6 and 10 have live assertions in a green Kotlin test. Dele…
- **`stt-options-model-id`** (stt): Add optional model_id to STTOptions so transcribe() can name its model — The cited in-repo precedent does not exist. 'LLMGenerationOptions.model_id' is invented -- model_id lives on LLMConfiguration and TTSConfiguration, i.e. on the *Configuration* message, which is exact…
- **`voice-declarative-config-one-vocabulary`** (voice): Make the declarative VoiceAgentConfig reuse VADConfiguration and TurnDetection instead of re-spelling them — chunk_ms has a live reader: solutions/solution_converter.cpp:59-60 does `if (cfg.chunk_ms() > 0) (*vad->mutable_params())["chunk_ms"] = ...`, and config_loader.cpp:500-501 accepts the YAML key with a…
