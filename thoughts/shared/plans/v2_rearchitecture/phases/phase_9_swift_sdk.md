# Phase 9 — Swift SDK migration (iOS / macOS / tvOS / watchOS)

> Goal: rewire `sdk/runanywhere-swift/` onto the new commons C ABI +
> proto3 wire types. Delete every struct-passthrough. Generate
> Swift bindings from `idl/` via swift-protobuf. Update the iOS
> example app end-to-end. First frontend to migrate because Swift
> has the tightest compile-time type system and will surface shape
> mismatches fastest.

---

## Prerequisites

- Phase 0–8 complete: commons is stable; C ABI is proto3-only; plugin
  registry + engine router operational; sanitizer CI green.
- A commons tag (e.g. `commons-v2.0.0`) pinned in the Swift package's
  build scripts, so every Swift PR builds against a known commons.

---

## What this phase delivers

1. **Swift-protobuf codegen** from `sdk/runanywhere-commons/idl/*.proto`
   into generated Swift sources under `Sources/RAGenerated/`. Never
   hand-edited; regenerated on every build by a SwiftPM plugin.

2. **A new C-interop layer** `Sources/RACBridge/` — thin wrappers
   around every `ra_*` C ABI function, wrapping byte-buffer
   round-trips in `Data`. No business logic.

3. **Re-expressed public Swift API** — class-based surface
   (`RunAnywhere`, `LLMSession`, `VoiceAgent`, `RAGPipeline`, etc.)
   becomes actor-based (`actor`) with `AsyncSequence` for every
   streaming primitive. Uses Swift 6 strict concurrency with no
   `@unchecked Sendable`.

4. **Complete iOS example app rewrite** of `examples/ios/RunAnywhereAI/`
   against the new public API. No bridging code in the app layer —
   it only speaks the Swift API.

5. **CocoaPods-free** — the new SDK distributes as SPM-only. The
   existing iOS example's Podfile is retired; CocoaPods dependencies
   (TensorFlow Lite, ZIPFoundation) are either replaced with SPM
   equivalents or removed.

6. **Swift 6 language mode** on both SDK and example app.

---

## Exact file-level deliverables

### New Swift package structure

```text
sdk/runanywhere-swift/
├── Package.swift                          UPDATED — Swift 6, swift-protobuf plugin
├── Sources/
│   ├── RACCommonsStatic/                  NEW — binary target: static libcommons.a + headers
│   │   └── (xcframework)
│   ├── RACBridge/                         NEW — C interop; thin `ra_*` wrappers
│   │   ├── RABridge.swift
│   │   ├── RABridge+LLM.swift
│   │   ├── RABridge+STT.swift
│   │   ├── RABridge+TTS.swift
│   │   ├── RABridge+VAD.swift
│   │   ├── RABridge+VLM.swift
│   │   ├── RABridge+RAG.swift
│   │   ├── RABridge+VoiceAgent.swift
│   │   ├── RABridge+Session.swift
│   │   └── RABridge+Error.swift
│   ├── RAGenerated/                       NEW — codegen output (gitignored)
│   │   └── (one .swift per .proto)
│   ├── RunAnywhere/                       REWRITTEN — public Swift API
│   │   ├── RunAnywhere.swift              — top-level actor
│   │   ├── LLM/
│   │   │   ├── LLMSession.swift           actor
│   │   │   ├── LLMEvent.swift             enum w/ assoc values from proto
│   │   │   └── LLMConfiguration.swift
│   │   ├── STT/
│   │   ├── TTS/
│   │   ├── VAD/
│   │   ├── VLM/
│   │   ├── RAG/
│   │   ├── VoiceAgent/
│   │   │   ├── VoiceAgent.swift           actor; DAG lifecycle
│   │   │   └── VoiceAgentEvent.swift
│   │   ├── Download/
│   │   │   └── ModelDownloader.swift
│   │   └── Observability/
│   │       └── MetricsCollector.swift
│   └── RunAnywhereObjC/                   NEW — optional Obj-C/Swift interop shims
├── Tests/
│   ├── RACBridgeTests/                    NEW — bridge round-trip tests
│   ├── RunAnywhereTests/                  REWRITTEN — actor-based test rig
│   └── Fixtures/
│       ├── tiny-llama-q4.gguf (LFS pointer)
│       └── sample-audio.wav
├── Package.resolved
├── VERSION
└── scripts/
    ├── build-xcframework.sh               NEW — builds libcommons.a → XCFramework
    ├── codegen-proto.sh                   NEW — runs swift-protobuf on idl/
    └── release.sh
```

### `Package.swift` key shape

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RunAnywhere",
    platforms: [
        .iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8)
    ],
    products: [
        .library(name: "RunAnywhere", targets: ["RunAnywhere"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.26.0")
    ],
    targets: [
        .binaryTarget(
            name: "RACCommonsStatic",
            path: "Artifacts/RACCommonsStatic.xcframework"
        ),
        .target(
            name: "RACBridge",
            dependencies: [
                "RACCommonsStatic",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Sources/RACBridge",
            publicHeadersPath: "include"
        ),
        .target(
            name: "RunAnywhere",
            dependencies: [
                "RACBridge",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Sources/RunAnywhere",
            plugins: [
                .plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf")
            ]
        ),
        .testTarget(
            name: "RACBridgeTests",
            dependencies: ["RACBridge"]
        ),
        .testTarget(
            name: "RunAnywhereTests",
            dependencies: ["RunAnywhere"]
        )
    ],
    swiftLanguageModes: [.v6]
)
```

### Example C-bridge wrapper — `RABridge+LLM.swift`

```swift
import Foundation
import RACCommonsStatic
import SwiftProtobuf

extension RABridge {
    static func llmCreate(config: Ra_Idl_LlmConfig) throws -> OpaquePointer {
        let bytes = try config.serializedData()
        var session: OpaquePointer?
        let status = bytes.withUnsafeBytes { buf -> ra_status_t in
            guard let base = buf.baseAddress else { return RA_STATUS_INVALID_ARGUMENT }
            return ra_llm_create(
                base.assumingMemoryBound(to: UInt8.self),
                bytes.count,
                &session
            )
        }
        try RAError.check(status)
        guard let handle = session else { throw RAError.unexpectedNil }
        return handle
    }

    static func llmNext(_ handle: OpaquePointer) async throws -> Ra_Idl_LlmEvent {
        // Grow a re-usable buffer; await on a detached task so we don't
        // block the actor's executor. The pattern is one pop per iteration
        // of the AsyncSequence below.
        return try await Task.detached(priority: .userInitiated) {
            var buf = [UInt8](repeating: 0, count: 1024)
            var len: Int = buf.count
            var status = buf.withUnsafeMutableBufferPointer { ptr in
                ra_llm_next(handle, ptr.baseAddress, ptr.count, &len)
            }
            if status == RA_STATUS_BUFFER_TOO_SMALL {
                buf = [UInt8](repeating: 0, count: len)
                status = buf.withUnsafeMutableBufferPointer { ptr in
                    ra_llm_next(handle, ptr.baseAddress, ptr.count, &len)
                }
            }
            try RAError.check(status)
            return try Ra_Idl_LlmEvent(serializedBytes: Data(buf.prefix(len)))
        }.value
    }
}
```

### Public `LLMSession` actor

```swift
public actor LLMSession {
    private let handle: OpaquePointer

    public init(configuration: LLMConfiguration) async throws {
        let proto = configuration.toProto()  // LLMConfiguration → Ra_Idl_LlmConfig
        self.handle = try RABridge.llmCreate(config: proto)
    }

    deinit {
        ra_llm_destroy(handle)
    }

    public func generate(prompt: Prompt) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try RABridge.llmStart(handle, prompt: prompt.toProto())
                    while !Task.isCancelled {
                        let ev = try await RABridge.llmNext(handle)
                        if let mapped = LLMEvent(proto: ev) {
                            continuation.yield(mapped)
                            if case .end = mapped { break }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                ra_llm_cancel(self.handle)
                task.cancel()
            }
        }
    }

    public func cancel() {
        ra_llm_cancel(handle)
    }
}
```

### `LLMEvent` sum type

```swift
public enum LLMEvent: Sendable {
    case token(Token)
    case toolCall(ToolCall)
    case end
    case error(RAError)

    init?(proto: Ra_Idl_LlmEvent) {
        switch proto.body {
        case .token(let t):   self = .token(Token(proto: t))
        case .toolCall(let c): self = .toolCall(ToolCall(proto: c))
        case .control(let c) where c.kind == .end: self = .end
        case .error(let e):   self = .error(RAError(proto: e))
        default: return nil
        }
    }
}
```

### Example app rewrite — `examples/ios/RunAnywhereAI/`

```text
examples/ios/RunAnywhereAI/
├── RunAnywhereAI.xcodeproj           REWRITTEN — Swift 6, no Podfile
├── RunAnywhereAI/
│   ├── RunAnywhereAIApp.swift        @main; calls RunAnywhere.bootstrap()
│   ├── Models/
│   │   └── ChatMessage.swift
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── ChatView.swift            — consumes LLMSession.generate()
│   │   ├── VoiceAgentView.swift      — consumes VoiceAgent.events()
│   │   └── SettingsView.swift
│   └── ViewModels/
│       ├── ChatViewModel.swift       actor-backed
│       └── VoiceAgentViewModel.swift actor-backed
├── README.md                         UPDATED — build instructions without CocoaPods
├── scripts/
│   └── build_and_run.sh              UPDATED — calls xcodebuild only
└── Tests/
    └── RunAnywhereAITests/
        └── ChatViewModelTests.swift
```

### Deletions

```text
examples/ios/RunAnywhereAI/Podfile              DELETE
examples/ios/RunAnywhereAI/Podfile.lock         DELETE
examples/ios/RunAnywhereAI/fix_pods_sandbox.sh  DELETE
sdk/runanywhere-swift/Sources/*Legacy*/         DELETE (any pre-refactor directory)
sdk/runanywhere-swift/Sources/RunAnywhere/OldCallbacks/  DELETE
```

### Build-time codegen

`scripts/codegen-proto.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
COMMONS_IDL="../runanywhere-commons/idl"
OUT="Sources/RAGenerated"
rm -rf "$OUT" && mkdir -p "$OUT"
for p in "$COMMONS_IDL"/*.proto; do
    protoc --swift_out="$OUT" \
           --swift_opt=Visibility=Public \
           -I "$COMMONS_IDL" "$p"
done
```

The SwiftPM plugin integration runs this at `swift build` time so the
generated files stay fresh. A `.gitignore` entry covers
`Sources/RAGenerated/`.

### XCFramework build pipeline

`scripts/build-xcframework.sh`:

```bash
#!/usr/bin/env bash
# Builds libcommons.a for every Apple platform + simulator slice,
# zips them into a single .xcframework. Inputs: the commons source
# tree (checked in the sibling directory). Outputs:
# Artifacts/RACCommonsStatic.xcframework.
set -euo pipefail
PLATFORMS=(
    "iphoneos:arm64"
    "iphonesimulator:x86_64,arm64"
    "macosx:x86_64,arm64"
    "appletvos:arm64"
    "appletvsimulator:x86_64,arm64"
    "watchos:armv7k,arm64_32,arm64"
    "watchsimulator:x86_64,i386,arm64"
)
# …cmake configure + build loop per platform…
# xcodebuild -create-xcframework -library … -output …
```

All Apple builds use `-DRA_STATIC_PLUGINS=ON` per Decision 02.

### Tests

```text
Tests/RACBridgeTests/
  ├── LLMBridgeTests.swift               — create/start/next/cancel/destroy cycle
  ├── STTBridgeTests.swift
  ├── TTSBridgeTests.swift
  ├── VoiceAgentBridgeTests.swift
  └── ErrorPathTests.swift               — every ra_status_t → RAError mapping

Tests/RunAnywhereTests/
  ├── LLMSessionTests.swift              — AsyncSequence semantics, cancellation
  ├── VoiceAgentIntegrationTests.swift   — end-to-end with bundled fixtures
  ├── RAGPipelineTests.swift
  └── ConcurrencyStressTests.swift       — 100 concurrent sessions
```

---

## Implementation order

1. **Lock the commons tag** the Swift build pulls from; commit that
   SHA into `scripts/build-xcframework.sh`.

2. **Build the XCFramework once, by hand**, verify it links into a
   minimal test app that just calls `ra_status_string(RA_STATUS_OK)`.
   Confirms the C ABI is reachable from Swift at all.

3. **Run `protoc --swift_out`** against `idl/` with a throwaway
   invocation; inspect one generated type manually (e.g.
   `Ra_Idl_LlmConfig`) to confirm the Swift naming matches
   expectations.

4. **Write `RABridge` one primitive at a time**, starting with LLM
   because it's the simplest stream. Round-trip test each bridge
   before moving on.

5. **Write the public actor wrappers** one primitive at a time. The
   `AsyncThrowingStream` pattern stays identical per primitive; extract
   into a helper once verified across two primitives.

6. **Migrate the existing Tests/** to the new API shape. Where tests
   previously exercised the old callback APIs, rewrite them as
   `for try await event in session.events()` loops.

7. **Rewrite the iOS example app.** Start from a fresh Xcode project
   template, SPM-only. Drop CocoaPods. Port each screen from the old
   example to the new API.

8. **Enable Swift 6 strict concurrency** in both SDK and example app.
   Fix every warning, zero `@unchecked Sendable` tolerated.

9. **Build+run on physical device** (iPhone + Mac Catalyst at
   minimum). Profile first-audio latency on a real phone with the
   voice agent to verify the ≤80 ms number carries to device. Report
   any gap.

10. **Update `.github/workflows/ios-sdk.yml`** to build SPM + test
    matrix across iOS 15/17, macOS 12/14, Swift 5.9/6.0. Lint green.

---

## API changes

### New public Swift API

| Old | New |
| --- | --- |
| `RunAnywhereSDK.shared.configure(...)` | `try await RunAnywhere.bootstrap(configuration:)` |
| `client.generate(prompt:) { token in … }` | `for try await event in session.generate(prompt:)` |
| `VoiceAgent.start(config:)` with delegate | `let agent = try await VoiceAgent(configuration:)` + `for try await event in agent.events()` |
| `RAGPipeline.query(text: completion:)` | `let result = try await pipeline.query(text:)` |

Error type unified: `enum RAError: Error` with one case per
`ra_status_t` value plus a `.wrappedServer(String)` for message
carry-through.

### Removed

- Delegate-based protocols (`VoiceAgentDelegate`, `STTServiceDelegate`, …).
- Closure-callback generation APIs.
- `NSLock`-based synchronisation (per CLAUDE.md rule).
- Pod-installed dependencies (TensorFlow Lite, ZIPFoundation where
  no longer needed).

---

## Acceptance criteria

- [ ] `swift build` + `swift test` green on macOS with Swift 6 strict
      concurrency.
- [ ] `xcodebuild -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 15'`
      green.
- [ ] iOS example app builds from a clean checkout: no `pod install`,
      no CocoaPods, no sandbox fix scripts.
- [ ] Example app runs a chat + voice agent flow on a real iPhone
      and first-audio latency is measured ≤120 ms (loser target than
      CI gate because device is weaker than the CI runner).
- [ ] `grep -rn "NSLock\|@unchecked Sendable" sdk/runanywhere-swift/`
      returns empty.
- [ ] `swiftlint` green with the existing ruleset (plus Swift-6 rule
      additions).
- [ ] `.github/workflows/ios-sdk.yml` + `ios-app.yml` green.
- [ ] XCFramework under 80 MB zipped (includes all platform slices).

## Validation checkpoint — frontend major

See `testing_strategy.md`. Every frontend phase runs the common
frontend template (compile + lint + test + example app gate +
fix-as-you-go) plus these phase-specific checks.

- **Compilation, every target.**
  ```bash
  cd sdk/runanywhere-swift
  swift build                                                                 # host macOS
  xcodebuild -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 15'
  xcodebuild -scheme RunAnywhere -destination 'platform=iOS,name=Any iOS Device'
  xcodebuild -scheme RunAnywhere -destination 'platform=macOS'
  xcodebuild -scheme RunAnywhere -destination 'platform=tvOS Simulator,name=Apple TV'
  xcodebuild -scheme RunAnywhere -destination 'platform=watchOS Simulator,name=Apple Watch Series 9'
  ```
  All exit 0 with **zero warnings**. Fix anything surfaced; do not
  defer.
- **Swift 6 strict concurrency clean.** No `@unchecked Sendable`,
  no `@preconcurrency import`. Any newly-surfaced race is a real
  bug — fix in this PR.
- **SwiftLint green.** Existing ruleset + any Swift-6 additions.
- **swift test green.** Under sanitizers where supported by the
  Swift compiler (ASan on macOS host).
- **XCFramework build.** `scripts/build-xcframework.sh` produces a
  usable `.xcframework`; a trivial external SPM project imports
  it and calls `ra_status_string(0)` successfully.
- **Example app builds from a clean clone.** `examples/ios/` with
  no `pod install`, no sandbox fix scripts. Launch-to-first-screen
  on iOS Simulator iPhone 15.
- **Example app on physical iPhone.** Chat + voice agent flows run
  end-to-end; first-audio latency measured ≤ 120 ms on device.
- **Feature parity.** Every feature that works in the Swift SDK
  pre-Phase-9 works post-Phase-9. Checklist per L3 primitive
  attached to the PR.
- **Warning budget.** Zero new warnings across SDK + example app.
- **CI.** `.github/workflows/ios-sdk.yml` + `ios-app.yml` green.

**Sign-off**: feature parity checklist reviewed; device run
recorded; no "we'll fix the warnings later" deferrals.

---

## What this phase does NOT do

- No feature removal. Every user-facing capability from the v1 Swift
  SDK is reachable through the new actor API.
- No persistence-format change. `ModelDownloader` saves to the same
  `Application Support/runanywhere/models/` path with the same file
  layout.
- IntelliJ plugin demo untouched in this phase — it's Kotlin-based
  (Phase 10).

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| Swift-protobuf generated enum cases collide with Swift keywords | Low | `.swift_opt=ProtoFileEscapeMode=…` covers the common cases. Add a linter rule that fails the build if a generated symbol shadows a Swift stdlib type |
| swift-protobuf's `Sendable` coverage lags our Swift 6 strict mode | Medium | Wrap generated proto types inside a Sendable struct that owns them (`public struct LLMConfiguration: Sendable { let proto: Ra_Idl_LlmConfig }`). Users see only the wrapper |
| XCFramework growth: commons + protobuf-lite + plugins = ~25 MB per arch slice | Medium | Accept for now; strip symbols on Release; revisit `-Os` if size becomes a problem for App Store thin binary |
| CocoaPods removal breaks existing users who depend on Pod installs | Low | User confirmed no external consumers. If later needed, SPM's CocoaPods-compat layer is trivial to re-add |
| Device-level first-audio latency exceeds 120 ms despite CI ≤80 ms | Medium | Profile on the target device; usually the gap is GCD QoS + Core Audio buffer size, both tunable inside `VoiceAgent` without commons changes |
| Apple rejects static plugin registration if a plugin name collides with a reserved prefix | Low | Phase 1 banned collision at registry time; verified |
| Swift 6 strict concurrency surfaces real races our v1 ignored | Medium | That's the point. Fix them as found; each is a pre-existing bug |
