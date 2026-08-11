# runanywhere-minimal (Swift)

A ~40-line SwiftPM command-line executable that streams one LLM completion to
stdout. It is the contributor test harness for the Swift SDK: *"does my
C++/Swift change still work?"* — not a showcase app.

It consumes the SDK **from local source** via `.package(path: "../../..")`
against the repo-root `Package.swift`.

## Prerequisites

The root manifest is **fail-closed**: with `RUNANYWHERE_USE_LOCAL_NATIVES`
unset it resolves the checksum-verified XCFrameworks from the GitHub release
instead of your working tree (see `Package.swift:42-47`). To test local native
changes you must stage the XCFrameworks and export the variable.

```bash
# From the repo root — builds RACommons + RABackend* into
# bindings/swift/Binaries/ (slow; skip if they are already staged).
./bindings/swift/scripts/build-core-xcframework.sh
```

## Run

```bash
cd examples/swift/minimal

# Build
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift build

# Run (any arguments are joined into the prompt)
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift run runanywhere-minimal "Name three colours."
```

With no arguments the prompt defaults to `"Name three colours."`.

> `RUNANYWHERE_USE_LOCAL_NATIVES=1` must be exported for **every** SwiftPM
> invocation (`build`, `run`, `test`). Dropping it on any one of them makes
> SwiftPM re-resolve to the remote release binaries.

## What it exercises

| Step | API |
|------|-----|
| Backend registration | `LlamaCPP.register()` |
| SDK bring-up | `RunAnywhere.initialize(environment: .development)` |
| Catalog entry | `RunAnywhere.models.register(.url(...))` |
| Streaming generation | `RunAnywhere.llm.generateStream(prompt:options:)` |

`initialize` is single-phase; there is no `completeServicesInitialization()`
call to make. **Download and load are automatic** — passing `options.model` is
enough. The catalog is *not* auto-seeded, though: `ensureLoaded` rejects an
unknown id with `Model '…' is not registered`, so the one `models.register`
call above is required. To try a different model, change `modelId`/`modelURL`
in `Sources/main.swift` (the canonical ids and URLs live in
`apps/rcli/src/catalog/catalog.cpp`).

Deliberately absent: model catalogs, download/load calls, theming, UI. Those
either live in the SDK already or belong in a full example app.

## Known limitation — macOS Keychain

As of 0.20.15 this builds and links cleanly and gets as far as backend
registration (`rac_plugin_register succeeded for 'llamacpp'`), then aborts
inside `initialize()`:

```
[RAC][ERROR][DeviceIdentity] Secure storage read failed (rc=-333); refusing new device id
Fatal error: SDKException[internal.secureStorageFailed]: Secure storage operation failed
```

`KeychainManager` calls `SecItemAdd`/`SecItemCopyMatching` against the legacy
file keychain under service `com.runanywhere.sdk`. A bare SwiftPM executable is
not a signed `.app` bundle with a `keychain-access-groups` entitlement, so
macOS rejects the access. Ad-hoc `codesign` does not help (adding the
entitlement ad-hoc gets the process SIGKILLed instead).

Per the repo's layering rules this is an **SDK-side gap, not something to work
around here** — the fix belongs in the Swift SDK's secure-storage adapter (a
non-Keychain fallback for unbundled macOS hosts, of the kind
`core/src/desktop/desktop_secure_store.cpp` already provides
for the C++ `rcli` host). Until that lands, this example verifies **compile and
link** against local SDK source; end-to-end generation needs an app bundle
([RunanywhereAI/runanywhere-ios](https://github.com/RunanywhereAI/runanywhere-ios)) or the C++ CLI.
