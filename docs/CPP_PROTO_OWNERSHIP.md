# C++ and Proto Ownership

This document is the source of truth for where shared behavior belongs across
the five public SDKs: Swift, Kotlin, Flutter, React Native, and Web.

## Ownership Rules

`idl/*.proto` is the canonical data-contract source. Generated protobuf types
are committed for every platform and should be exported directly from public
SDK APIs whenever the platform can use them ergonomically.

`sdk/runanywhere-commons` owns business logic. Download orchestration, model
registry state, load and unload behavior, lifecycle transitions, hardware
routing, backend selection, proto-byte stream/event encoding, tool parsing,
and shared validation must live in C++.

The five SDKs own platform adapters only. Acceptable SDK-side logic includes
HTTP transport registration, filesystem path access, permissions, platform UI
bridges, native async wrappers such as `AsyncStream`, `Flow`, Dart `Stream`,
JS `AsyncIterable`, and memory-safe conversion around C ABI calls.

No SDK should independently reimplement model lifecycle, download policy,
hardware routing, backend selection, or enum value systems that already exist
in proto or C++.

## Public API Rules

Public method names should match across Swift, Kotlin, Flutter, React Native,
and Web unless the platform has a strong naming convention that requires a
small spelling change.

Public data types should be generated proto types by default. A hand-written
public type is allowed only when the platform needs a native ergonomic wrapper,
and then it must have an explicit bridge to and from the generated proto type.

Enum values must never be re-numbered locally. If a C ABI enum starts at a
different zero value than the proto enum, the SDK adapter must use an explicit
mapping function at the C boundary.

Backward compatibility is not a design constraint for this cleanup. Prefer the
canonical proto/C++ shape over aliases or duplicated legacy wrappers.

## Current Contract Flow

```
idl/*.proto
  -> idl/codegen/generate_all.sh
  -> generated Swift / Kotlin / Dart / TypeScript / Python / C++ proto files
  -> C++ commons business logic and C ABI
  -> platform SDK adapter
  -> public SDK API
```

For TypeScript, `sdk/runanywhere-proto-ts` is the shared generated package for
React Native and Web. Neither SDK should import from `dist/` directly; use the
package export paths such as `@runanywhere/proto-ts/voice_events`.

## Verification Checklist

For any cross-SDK API/type change:

1. Update the proto under `idl/` first when the data contract changes.
2. Run `idl/codegen/generate_all.sh`.
3. Use generated proto types in all five SDK public surfaces unless a native
   wrapper is unavoidable.
4. Keep business behavior in `sdk/runanywhere-commons`; SDKs should call C ABI
   or register platform adapters.
5. Build or typecheck each touched SDK.
6. Build and run commons tests.
7. Run `idl/codegen/ci-drift-check.sh` on a clean tree before merge.

## Platform Adapter Boundaries

HTTP is a platform adapter. SDKs may keep their existing native HTTP stacks,
but those stacks should be registered into the C++ HTTP transport layer so
downloads and network policy remain centralized.

Streaming is a platform adapter. SDKs may expose idiomatic stream primitives,
but the event shape and wire encoding should come from proto-byte callbacks
owned by C++.

Hardware probing should flow through C++ where a native binding exists. If a
platform temporarily synthesizes a fallback profile, it must return the
generated `HardwareProfileResult` shape and should be replaced by the C++ ABI
binding as soon as that platform binding is available.
