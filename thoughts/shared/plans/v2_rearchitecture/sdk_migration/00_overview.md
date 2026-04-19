# SDK migration — overview

> The legacy SDKs under `sdk/runanywhere-{swift,kotlin,flutter,react-native,web}/`
> today link against `sdk/runanywhere-commons/`. The new architecture lives
> under `core/` + `engines/` + `solutions/` and is already shipping through
> `frontends/` as thin adapter packages.
>
> This directory holds one migration plan per SDK, describing in detail
> how to swap the interop layer from legacy to new core WITHOUT breaking
> the public API each SDK currently ships.

## Deliverable principle — API stability

Every SDK keeps its **user-facing public surface identical** through the
migration. Consumers of `RunAnywhere.shared.generate(...)` don't care
that the underlying C function went from `rac_llm_generate` to
`ra_llm_generate`. The migration is invisible to app code.

Where the public surface changes at all (e.g. new capabilities becoming
available), it's additive — no breaking changes to existing method
signatures.

## Shared prerequisites (block every SDK)

1. **New core C++ must have feature parity with legacy commons** for the
   capabilities each SDK exposes. Tracked in `feature_parity_audit.md` —
   this session closed HTTP client, env/auth, audio utils, error
   taxonomy. Remaining critical gaps before full parity:
   - **Extraction** (ZIP/TAR with zip-slip protection) — needed by model
     downloader for compressed bundles.
   - **Telemetry queue** (event batching + JSON serialization).
   - **OpenAI HTTP server** (SDK ships `/v1/chat/completions` and
     `/v1/models`).
   - **Structured lifecycle enum** (UNINIT → INITIALIZING → READY → …).
   - **Tool-calling + structured-output parsers** for LLM.
2. **Native artifacts per platform**:
   - iOS / macOS / tvOS / watchOS → XCFramework containing
     `libra_core_abi.a`, `libra_core.a` + per-engine static archives.
   - Android → AAR with `jniLibs/<abi>/libra_core.so` for arm64-v8a,
     armeabi-v7a, x86_64.
   - Desktop (Flutter macOS/Linux/Windows) → shared libraries.
   - Web → `.wasm` produced from `frontends/web/wasm/`.
3. **JNI bridges** for Kotlin (and RN-Android) must be regenerated
   against `ra_*` entry points.
4. **Dart FFI bindings** regenerated from the new `ra_*` ABI headers via
   `ffigen`.
5. **TS type bindings** for RN + Web — already pointing at the new core;
   consolidation complete.

## Order of migration

1. **Swift** — smallest delta; `frontends/swift/` is already working.
   Primary lift: build the new core as an XCFramework and have
   `sdk/runanywhere-swift` link to it instead of the legacy binaries.
2. **Web** — also close to working; WASM build of new core already
   scaffolded under `frontends/web/wasm/`.
3. **Flutter** — FFI is simpler than JNI; regen bindings + ship native
   libs per platform.
4. **Kotlin** — biggest JNI lift, but the current Kotlin SDK's JNI
   bridge is stable surface.
5. **React Native** — delegates to Swift (iOS) and Kotlin (Android),
   so happens last.

## Step template per SDK

Each SDK's plan has the same 7-step structure:

1. **Survey current state** — what files compose the interop layer today.
2. **Identify C ABI calls** — every `rac_*` the SDK invokes.
3. **Map to new ABI** — every `ra_*` replacement.
4. **Native artifact** — build the core artifact this SDK links to.
5. **Wire the interop layer** — regen FFI/JNI/C-interop bridge.
6. **Run the SDK's own tests** — baseline must be preserved.
7. **Run the example app** — full smoke on the canonical example.

## Rollback safety

During the migration window (PR #485), legacy commons + legacy SDKs
continue to exist and build. A consumer can pick the old or new SDK
at the package-manager level. The legacy tree is only deleted at the
very end, after all 5 SDKs + all 5 example apps have been validated
against the new core.
