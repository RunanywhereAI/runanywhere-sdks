---
name: telemetry-e2e
description: Prove that what an SDK binding EMITS on the telemetry wire is correct and that it actually arrives — vocabulary compliance, presence/absence semantics, device-id stability, and a received request body / stored row as evidence. Use when touching telemetry_json.cpp, telemetry_manager.cpp, rac_telemetry_vocabulary.h, any binding's platform-adapter telemetry bridge, or when asked to verify a telemetry field isn't silently dropping.
---

# Telemetry Wire Correctness (SDK side)

This is the SDK-side counterpart to the backend's `telemetry-e2e` skill (private
`Runanywhere-monorepo` repo — proves event-to-stored-row on the server side). This one
proves the other half: that commons *serializes* a call correctly and that the bytes
*leaving* a binding are the bytes a real backend accepts. It does not cover per-starter-app
inference smoke tests — see `sdk-test-starters` for that.

## 0. The evidence bar

Compiling is not evidence. A green `telemetry_extraction_tests` run is not evidence that a
real binding's real call site reaches the wire correctly — it only proves the *serializer*
handles a hand-built payload correctly. In order of increasing strength:

1. **Unit test green** (`ctest -R telemetry_extraction_tests`) — proves the JSON builder's
   presence/vocabulary rules are still correct in isolation. Necessary, not sufficient.
2. **Received request body** — capture the actual JSON `rcli` (or a real binding) put on
   the wire and read it: right modality endpoint, right keys, no vocabulary values that
   got through that shouldn't have, measured zeros kept as `0` not `null`.
3. **Stored row matches, field-for-field** — the backend's own ingest response
   (`events_received`/`events_stored`/`events_skipped`) or a direct DB read shows the row
   landed with the values you actually sent, not just a 2xx. This is the only tier that
   also proves the vocabulary/schema on both sides still agree.

A PR description that says "sent telemetry, no errors" without quoting a request body or a
stored-row count is not evidence of anything except that a socket didn't error out.

## 1. The emit path

Every binding funnels through the same two C ABI entry points in
`core/src/infrastructure/telemetry/telemetry_manager.cpp`:

- `rac_telemetry_manager_track` — flat-struct payload (`rac_telemetry_payload_t`), used by
  `rcli`'s `telemetry emit`/`telemetry blast` and by hand-built events.
- `rac_telemetry_manager_track_proto` — the real path every language binding actually uses:
  a binding builds a protobuf `SDKEvent` (`sdk_events.pb.h`) at the real call site (e.g. an
  LLM `generate()` completing), and `proto_event_type_string()` + the per-domain extraction
  blocks in `telemetry_manager.cpp` turn it into the same flat payload. `framework_proto_to_string()`
  / `framework_to_string()` / `clean_framework()` do the backend-name normalization here —
  this is where a raw enum like `INFERENCE_FRAMEWORK_LLAMA_CPP` becomes the wire string `"llamacpp"`.
- `stamp_live_device_state()` (same file) then overwrites the SDK-origin/device-state fields
  (`sdk_binding`, `platform`, `battery_state`, memory, core count) from manager-owned state,
  not from whatever the caller passed — a binding cannot inject a platform or binding value.
- The payload is handed to `rac_telemetry_manager_payload_to_json()` in
  `core/src/infrastructure/telemetry/telemetry_json.cpp`, which does field-by-field
  serialization (see §2/§3 for the two contracts enforced there).
- `send_batch_json()` batches by modality and POSTs to `/api/v2/sdk/telemetry/{modality}`
  through whichever `rac_http_transport_ops_t` the binding registered (URLSession/OkHttp/
  `emscripten_fetch`/curl for `rcli` — see the root `AGENTS.md`'s "HTTP is platform-provided"
  rule). There is no `libcurl` fallback baked into commons itself.

If a field is going missing on the wire, the fix is almost always in
`telemetry_json.cpp` (a field never wired into the serializer) or in the call site's proto
population (a field never set on the `SDKEvent`) — not in a binding's bridge code, which
just forwards bytes.

## 2. The closed vocabularies — and the silent-drop rule

`core/include/rac/infrastructure/telemetry/rac_telemetry_vocabulary.h` is a **generated
file** (see §5) holding six closed tables, each with a `RAC_TELEMETRY_<NAME>_COUNT` and a
`RAC_TELEMETRY_<NAME>_VALUES[]` array:

| Table | Count | Wire field | Values |
|---|---|---|---|
| `RAC_TELEMETRY_EVENT_TYPE` | 106 | `event_type` | namespaced strings, e.g. `llm.generation.completed`, `auth.succeeded`, `stt.transcription.completed` |
| `RAC_TELEMETRY_BACKEND` | 22 | `backend` / `framework` | `onnx, sherpa, llamacpp, foundation_models, system_tts, fluid_audio, coreml, whisperkit_coreml, mlx, qhexrt, neurt, tflite, executorch, mediapipe, mlc, pico_llm, piper_tts, swift_transformers, cloud, builtin, none, unknown` |
| `RAC_TELEMETRY_MODEL_SOURCE` | 3 | `model_source` | `catalog, builtin, user` |
| `RAC_TELEMETRY_PLATFORM` | 9 | `platform` | `ios, android, macos, windows, linux, web, tvos, watchos, visionos` |
| `RAC_TELEMETRY_SDK_BINDING` | 9 | `sdk_binding` | `swift, kotlin, flutter, react-native, web, electron, python, cli, cpp` |
| `RAC_TELEMETRY_BATTERY_STATE` | 4 | `battery_state` | `charging, full, unplugged, unknown` |

**The rule, verbatim from `add_vocabulary_string()` in `telemetry_json.cpp`:** if a value is
non-null but not present in its table, the field is dropped to `null` and the *rest of the
event still ships*. This is by design (a bad `backend` string must not cost the whole
observation) but it means:

- The backend never sees the bad value, never 422s, never quarantines anything — there is
  no error path anywhere for this. A field just isn't there.
- The only client-side signal is a `RAC_LOG_WARNING("Telemetry", "Dropping %s: '%s' is not
  in the published vocabulary", ...)` log line — easy to miss unless you're specifically
  watching debug logs.
- `platform`, `sdk_binding`, and `battery_state` are stamped by the manager itself (§1), not
  supplied by a binding's call site, so in practice only `backend`/`framework` (from the
  engine/model layer) and `event_type` (only reachable via the proto path, checked at CI
  time — see §5) are realistic places a new value can silently disappear.
- `test_telemetry_extraction.cpp`'s vocabulary block (`"vocab-1"`/`"vocab-2"` cases) is the
  concrete regression guard: it sends `framework = "LlamaCpp"` (a real spelling that used to
  reach production) and asserts the string never appears on the wire while `model_id` still
  does. If you touch `add_vocabulary_string()` or add a new vocabulary-gated field, extend
  that test rather than trusting a manual check.

Historical motivation (from the header's own comment): before this table existed, stored
production rows had four spellings of `llama.cpp`, three of ONNX, and binding names like
`"react-native"` recorded as a `platform` — this file exists specifically to make that class
of drift fail in this repo instead of being discovered in a database nobody was watching.

## 3. Presence vs. absence: the "measured zero" contract

Before the fix documented in `telemetry_json.cpp`'s header, extractors read proto3 scalar
fields directly — which report `0` for a field that was never set — and the old serializer
(`add_int`/`add_double`) *skipped* zero values to keep payloads small. Result: a genuinely
measured `output_tokens = 0` (an empty completion) and an unmeasured `tokens_per_second`
both arrived on the wire as absent, indistinguishable from each other.

The fix is `has_x`-gated serialization. Two helper families in `telemetry_json.cpp`:

- `add_int_or_null(key, value, is_valid)` / `add_double_or_null(key, value, is_valid)` —
  emit the real value (including `0`) when `is_valid` is true, else the JSON literal `null`.
  Non-finite doubles (`NaN`/`Inf`) always degrade to `null` regardless of `is_valid`, because
  JSON has no such literal and one bad value must not corrupt the whole batch.
- The `is_valid` argument is a real `has_x`/sentinel check per field, not a blanket flag —
  e.g. `payload->has_processing_time_ms != RAC_FALSE`, `payload->total_memory > 0`,
  `payload->battery_level >= 0`.

**What to check to confirm this stayed fixed** (this is exactly what
`test_telemetry_extraction.cpp`'s presence block does — see §4): send an LLM completion
event with `output_tokens = 0` and `input_tokens = 0` explicitly set, and
`tokens_per_second`/`context_length` left unset. Assert the wire body contains
`"output_tokens":0` and `"input_tokens":0` as literal numbers, and `"tokens_per_second":null`
/ `"context_length":null` — not all four as `null`, and not all four as `0`. If a future
refactor reverts to plain `add_int`/`add_double` for any of these fields, that regression
test is the thing that catches it; grep `telemetry_json.cpp` for `add_int(` / `add_double(`
(the non-`_or_null`/non-`_always` forms) if you suspect a field regressed — those two still
silently skip zero by design and must never be used for a field where `0` is meaningful.

## 4. Build, test, and what each telemetry test asserts (macOS)

```bash
cmake --preset macos-debug
cmake --build build/macos-debug
ctest --preset macos-debug --output-on-failure -R 'telemetry|device_identity'
```

Or the non-preset form (`core/AGENTS.md`'s documented path):

```bash
cmake -B build -DRAC_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure
```

`telemetry_extraction_tests` and `device_identity_tests` are registered in
`core/tests/CMakeLists.txt`; `rcli_telemetry_live_tests` is registered separately in
`rcli/tests/CMakeLists.txt`. All three are hand-rolled assertion runners — `CHECK()` in
some files, `ASSERT_EQ`/`ASSERT_TRUE` (from `core/tests/test_common.h`) in others — never
GoogleTest:

| ctest name | Binary | What it asserts |
|---|---|---|
| `telemetry_extraction_tests` | `test_telemetry_extraction` | Full proto→JSON pipeline per modality (LLM token counts/`tokens_per_second`, STT NaN-confidence never leaks as the string `"nan"`, TTS `characters_per_second`, embeddings `total_tokens`/`batch_size`/`embedding_dimension`, LoRA failure-path fields, RAG retrieval counts, VLM image/timing fields, live device-state stamping); the presence/measured-zero contract (§3); the closed-vocabulary drop rule (§2); and an HTTP-retry backoff (a failed batch is re-sent only after >5s, never before). Requires `RAC_HAVE_PROTOBUF` — the test binary itself no-ops with exit 0 if commons wasn't built with protobuf support. |
| `device_identity_tests` | `test_device_identity` | Every branch of `rac_device_get_or_create_persistent_id()`'s resolution chain (§6) against a mocked platform adapter — cache hit, vendor-ID fallback, fresh-UUID generation, and that a `secure_set` failure doesn't silently drop the ID. |
| `rcli_telemetry_live_tests` | `test_rcli_telemetry_live` | **Opt-in, always registered but a no-op by default.** Runs only with `--live` *and* `RUNANYWHERE_BASE_URL`/`RUNANYWHERE_API_KEY` set; otherwise prints "skip" and exits 0 — a green ctest run for this target proves nothing by itself. When live, it runs `rcli::bootstrap()` (real API-key → device-register → JWT handshake), sends one real event per modality (LLM, embeddings, RAG, VLM, LoRA-failure) through the real HTTP transport, and fails on any non-2xx response — this is the test that would catch a strict-schema `422 extra_forbidden` from field drift against the real V2 endpoints. |

Run it live (§7 has the full local-backend flow):

```bash
RUNANYWHERE_BASE_URL=https://<backend-origin> RUNANYWHERE_API_KEY=<key> \
  ./build/macos-debug/rcli/tests/test_rcli_telemetry_live --live
```

`test_platform_bridge` (same `CMakeLists.txt`, adjacent target) is the wider companion
check — "every value a binding supplies must reach the wire" — covering the platform half
of the same two flat C structs (`rac_client_info_t`/`rac_device_registration_info_t`) for
every SDK at once; run it alongside if you're touching client-info fields rather than
telemetry event fields specifically.

## 5. Regenerating the vocabulary header, and the drift gate

`rac_telemetry_vocabulary.h` (§2) is generated from `idl/http/sdk-openapi.json` — the
device-facing OpenAPI subset copied in from the private backend repo. **How that file gets
updated on the backend side, and how it crosses into this repo, is the monorepo's
`openapi-contract` skill's job — read that by name in the other repo rather than
re-deriving the steps here.** From inside this repo, once `idl/http/sdk-openapi.json` is
current:

```bash
python3 idl/codegen/generate_telemetry_vocabulary.py          # regenerate the header
python3 idl/codegen/generate_telemetry_vocabulary.py --check  # CI drift check; exit 1 if stale
```

`.github/workflows/telemetry-vocabulary-drift.yml` runs three checks on every push to
`main`/`development` and on any PR touching `idl/http/**`, the codegen script, or the
telemetry source/header dirs:

1. **Generated header is current** — the `--check` command above.
2. **Every event type the core can emit is in the vocabulary** — a Python check that parses
   `proto_event_type_string()`'s body out of `telemetry_manager.cpp` via regex, unions in
   the two prefix-expansion families (`stt.model.*`/`tts.voice.*`/`llm.model.*` and
   `llm*`/`vlm*` generation suffixes), and diffs against `TelemetryEventType`'s enum in
   `idl/http/sdk-openapi.json`. Anything emittable but unpublished fails the job.
3. **Every framework string the core can emit is in the vocabulary** — same technique
   against `framework_proto_to_string()` and `framework_to_string()` vs. `TelemetryBackend`.

**A documented drift you will hit if you trust the wrong file**: `idl/http/README.md`'s own
"What it pins" table names the schema for the `framework`/`backend` field as
`TelemetryFramework` — that's stale. The actual generator
(`idl/codegen/generate_telemetry_vocabulary.py`'s `VOCABULARIES` dict) and the header it
produces both say `TelemetryBackend`. Trust the generator and the generated header's own
`// Published as X` comments over that README table.

## 6. Per-binding device identity: where it's created, where it's persisted

The resolution chain itself is centralized in commons —
`core/src/infrastructure/device/device_identity.cpp`
(`rac_device_get_or_create_persistent_id`, tested by `device_identity_tests`, §4) — and is
the same fixed order for every binding:

1. `adapter.secure_get("com.runanywhere.sdk.device.uuid")` — if found and non-empty, use it,
   full stop.
2. `adapter.get_vendor_id` (if the platform adapter provides one) — use it, then persist it
   via `secure_set` so step 1 hits next boot.
3. Generate a fresh RFC-4122 v4 UUID, persist it via `secure_set`.

What differs per binding is **only** the `secure_get`/`secure_set` backing store — an
unstable backing store (one that doesn't survive a real app restart, or that resolves to a
different physical location than the read path expects) is exactly the bug class that
inflates device counts, because step 3 fires again on every "cache miss":

| Binding | Backing store | Where |
|---|---|---|
| Swift (iOS/macOS) | Keychain, service `com.runanywhere.sdk` | `bindings/swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+PlatformAdapter.swift` (`platformSecureGetCallback`/`platformSecureSetCallback`) |
| Kotlin (Android) | Android Keystore AES-256-GCM key, ciphertext in a no-backup app file (not `SharedPreferences`) | `bindings/kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/security/AndroidKeychainManager.kt` (`NoBackupCiphertextStore`), wired through `CppBridgePlatformAdapter.PlatformSecureStorage` |
| Flutter | Native Keychain/Keystore helper via FFI symbols `ra_flutter_secure_storage_{store,retrieve,delete}` | `bindings/flutter/packages/runanywhere/lib/native/dart_bridge_secure_storage.dart`; the device-UUID key constant is duplicated (deliberately, per its own comment) as `_keyDeviceUUID = 'com.runanywhere.sdk.device.uuid'` in `dart_bridge_device.dart` |
| React Native (Android) | `SecureStorageManager` (native Android side) via `PlatformAdapterBridge.kt`'s `secureGet`/`secureSet` | `bindings/react-native/packages/core/android/src/main/java/com/margelo/nitro/runanywhere/PlatformAdapterBridge.kt` |
| Web | `localStorage`, key `rac_sdk_plaintext_com.runanywhere.sdk.device.uuid` — **plaintext**, no OS-level encryption equivalent exists in a browser; restricted by convention to non-sensitive IDs | `bindings/web/packages/core/src/runtime/PlatformAdapter.ts` (`registerSecureGet`/`registerSecureSet`); also has a separate `stableVendorId()` fallback under key `rac_sdk_plaintext_vendor_id` |
| Electron (macOS/Linux) | Flat file under a secure directory, path-traversal-guarded (`fs::path(key)` must not be absolute or contain `..`) | `bindings/electron/native/posix_platform_adapter.cpp` (`posix_secure_get`/`posix_secure_set`) |
| Electron (Windows) | Windows DPAPI (`CryptProtectData`, current-user scope, no UI) | `bindings/electron/native/win32_platform_adapter.cpp` (`win_secure_get`/`win_secure_set`) |

The key string itself — `com.runanywhere.sdk.device.uuid` — is intentionally the same
literal across Swift, Flutter, and RN (each source comments cross-reference the other two by
name), so grepping for it is a fast way to confirm a new binding is reading/writing the
*same* key it thinks it is, not a typo'd sibling.

**How to verify stability across a real restart** (not just "the code looks right"):

1. Run the binding once, capture the emitted `device_id` from a real request body (§7) or
   from `POST /api/v1/devices/register`'s response.
2. Fully terminate the process (not just background it — on mobile this matters, a
   backgrounded app can keep its in-memory device-id cache alive without ever touching
   the read path again).
3. Relaunch and repeat step 1.
4. The `device_id` must be byte-identical. If it changed, the break is almost always one of:
   the backing store not surviving process death (e.g. an in-memory-only stub used during
   development), a key-name mismatch between the write and read paths, or (Android
   specifically) `Context.deleteSharedPreferences` being invoked on the wrong file — see
   `AndroidKeychainManager.kt`'s constructor, which deletes a hardcoded *legacy* prefs name
   on every construction; if that name were ever widened to match the real store, every
   Android launch would look like a fresh device.

Two-in-one launches on the *same physical device* (e.g. two emulator instances, or a
same-device reinstall vs. a real fresh install) are a different, real-world failure mode
from a code bug — don't conflate an intentional reinstall's fresh ID with instability.

## 7. Point a local build at a local backend and prove an event landed

`rcli` is the fastest way to exercise the full wire path without a mobile/browser
toolchain — it links `rac_commons` directly and speaks real HTTP via curl.

```bash
cmake --preset rcli-macos-release   # or rcli-linux-release on Linux
cmake --build build/rcli-macos-release --target rcli -j "$(sysctl -n hw.logicalcpu)"
```

**Keyless (development environment) — no API key, works against any backend that allows
anonymous V2 telemetry:**

```bash
./build/rcli-macos-release/rcli/rcli --environment development \
  --base-url http://127.0.0.1:8000 \
  telemetry blast --processing-ms 42.5 --session-id my-check \
  --input-tokens 128 --output-tokens 256
```

This is exactly the shape `scripts/ci/oss_keyless_telemetry_blast.sh` runs in CI against the
public staging backend — `--environment development --base-url <origin> telemetry blast
...` with no `--api-key`. `telemetry blast` sends one representative event per modality (all
12) and prints a `MODALITY | RESULT | STATUS | RECEIVED | STORED | SKIPPED` table parsed
directly from the backend's own batch response — **the `STORED` column is authoritative
server-side confirmation**, not just an HTTP 2xx. `run_telemetry_blast()`'s own exit-code
logic (`rcli/src/commands/cmd_telemetry.cpp`) does fold `stored >= count` into its overall
pass/fail, so a genuine storage shortfall on any modality does make the process exit
non-zero, not just a transport error — but the exit code is one bit for all 12 modalities
combined, so a non-zero exit still requires reading the table to know *which* modality
failed and *why* (a `network error` status is a transport problem; an `HTTP 200` row with
`STORED` under `RECEIVED` is a row-level rejection, e.g. a vocabulary value the backend
didn't recognize — a real bug to chase, not the same failure class at all).

**Authenticated (production shape) — for exercising the login handshake too:**

```bash
./build/rcli-macos-release/rcli/rcli --environment production \
  --base-url https://<backend-origin> --api-key <key> \
  auth login
./build/rcli-macos-release/rcli/rcli --environment production \
  --base-url https://<backend-origin> --api-key <key> \
  telemetry emit --modality llm --count 3 --input-tokens 128 --output-tokens 256
```

`auth login` only has a path in `production` — `development`'s keyless mode has no login
step by design (see `rcli/src/commands/cmd_auth.cpp`'s own subcommand help text).

**To inspect the actual request body**, not just the summary table, add `--json` for
machine-readable CLI output and `-v` for debug logging (the debug log includes the
serialized JSON per batch before it goes on the wire) — or point `--base-url` at a throwaway
local capture endpoint (any script that logs the raw POST body) before pointing it at a real
backend, to sanity-check field shape offline first.

**If you have the private backend repo checked out locally too**, running it yourself
(`cd backend && uv run uvicorn main:app --reload`, per that repo's own README) and pointing
`--base-url` at `http://127.0.0.1:8000` gets you the strongest possible evidence: query the
SQLite/Postgres row directly after a blast and diff it field-for-field against what you sent
— the monorepo's own `telemetry-e2e` skill (its integration suite, hermetic pytest fixtures,
and `test_telemetry_conformance.py`'s vocabulary/presence/identity assertions against stored
rows) is the authoritative reference for that side; don't re-implement its DB assertions
here, just point at it.

## Evidence bar, restated

- Compiling `rcli` or a binding: **not evidence**.
- `ctest -R telemetry_extraction_tests` green: **not evidence of a real call site** — only
  of the serializer in isolation.
- `rcli telemetry blast` exiting 0: real signal (its exit code does fold in the backend's
  `stored >= count` check, §7) but still worth pairing with the per-modality
  `STORED`/`SKIPPED` table in your report — the exit code can't tell you *which* modality
  or *why* a shortfall happened.
- A captured request body showing the right endpoint, the right keys, correct
  presence/absence per §3, and no off-vocabulary values per §2 — **evidence of correct
  emission**.
- That request body's values matching a stored row (via the backend's own
  `events_stored` count at minimum, a direct DB read at best) — **evidence of correct
  end-to-end delivery**, the only tier worth reporting as "telemetry works."
