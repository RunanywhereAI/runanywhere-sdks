# AGENTS.md — Swift minimal example

Guidance for `bindings/swift/example/`. Read the repo-root `AGENTS.md` and
`bindings/swift/AGENTS.md` first — this file only covers what's specific to this
sub-package. See [`README.md`](README.md) for the full consumer-facing writeup this
file summarizes.

## What this is

`runanywhere-minimal` is a ~40-line SwiftPM command-line executable
(`Sources/main.swift`) that streams one LLM completion to stdout. It is the
**contributor test harness for the Swift SDK** — "does my C++/Swift change still
work?" — not a showcase app. Feature-complete UI belongs in
[runanywhere-ios](https://github.com/RunanywhereAI/runanywhere-ios), not here.

It has its own `Package.swift` (separate from `bindings/swift/Package.swift`) that
consumes the SDK **from local source** via `.package(path: "../../..")` against the
repo-root manifest, so an edit to the Swift SDK or the C++ core is visible immediately
without staging or publishing anything.

## Prerequisites

The repo-root manifest is **fail-closed**: with `RUNANYWHERE_USE_LOCAL_NATIVES` unset it
resolves checksum-verified XCFrameworks from the GitHub release instead of your working
tree. To exercise local native changes, stage the XCFrameworks first:

```bash
# From the repo root — builds RACommons + RABackend* into bindings/swift/Binaries/
# (slow; skip if already staged).
./bindings/swift/scripts/build-core-xcframework.sh
```

## Build and run

```bash
cd bindings/swift/example

RUNANYWHERE_USE_LOCAL_NATIVES=1 swift build
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift run runanywhere-minimal "Name three colours."
```

Any CLI arguments are joined into the prompt; with none, it defaults to `"Name three
colours."`.

`RUNANYWHERE_USE_LOCAL_NATIVES=1` must be exported for **every** SwiftPM invocation
(`build`, `run`, `test`) — dropping it on any single one makes SwiftPM silently
re-resolve to the remote release binaries instead of your local build.

## What it exercises

| Step | API |
|------|-----|
| Backend registration | `LlamaCPP.register()` |
| SDK bring-up | `RunAnywhere.initialize(environment: .development)` |
| Catalog entry | `RunAnywhere.models.register(.url(...))` |
| Streaming generation | `RunAnywhere.llm.generateStream(prompt:options:)` |

`initialize` is single-phase from the caller's perspective — there is no separate
`completeServicesInitialization()` call to make (Phase 2 above runs internally; see
`bindings/swift/AGENTS.md`). Download and load are automatic: passing `options.model`
is enough. The catalog is **not** auto-seeded, though — `ensureLoaded` rejects an
unknown id with `Model '…' is not registered`, so the one `models.register` call in
`main.swift` is required before generation.

To try a different model, change `modelId`/`modelURL` in `Sources/main.swift`; canonical
model ids and URLs live in the [RCLI](https://github.com/RunanywhereAI/RCLI) catalog (`src/catalog/catalog.cpp`).

Deliberately absent from this example: model catalogs, download/load UI, theming.

## Known limitation — macOS Keychain

As of SDK 0.20.15 this builds and links cleanly and gets as far as backend registration
(`rac_plugin_register succeeded for 'llamacpp'`), then aborts inside `initialize()`:

```
[RAC][ERROR][DeviceIdentity] Secure storage read failed (rc=-333); refusing new device id
Fatal error: SDKException[internal.secureStorageFailed]: Secure storage operation failed
```

`KeychainManager` calls `SecItemAdd`/`SecItemCopyMatching` against the legacy file
keychain under service `com.runanywhere.sdk`. A bare SwiftPM executable isn't a signed
`.app` bundle with a `keychain-access-groups` entitlement, so macOS rejects the access.
Ad-hoc `codesign` doesn't help — adding the entitlement ad-hoc gets the process
SIGKILLed instead.

Per the repo's layering rules (see root `AGENTS.md`) **this is an SDK-side gap, not
something to work around here** — the fix belongs in the Swift SDK's secure-storage
adapter (a non-Keychain fallback for unbundled macOS hosts, of the kind
`core/src/desktop/desktop_secure_store.cpp` already provides for the C++ `rcli` host).
Until that lands, this example only verifies **compile and link** against local SDK
source; end-to-end generation needs a signed app bundle (runanywhere-ios) or the C++
CLI (`rcli`).
