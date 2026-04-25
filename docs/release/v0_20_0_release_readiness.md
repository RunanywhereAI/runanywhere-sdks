# v0.20.0 Release Readiness Checklist

_Checklist only. Do not tag, publish, or bump versions until every blocking
gate below has a checked evidence artifact and the release owner signs off._

Related docs:

- [`v0_20_0_release_plan.md`](./v0_20_0_release_plan.md)
- [`verification/2026-04-24/MATRIX.md`](../../verification/2026-04-24/MATRIX.md)

## Release Decision

- [ ] Release owner assigned.
- [ ] Target tag confirmed as `v0.20.0`.
- [ ] Source branch confirmed as `feat/v2-architecture` or its approved
  merge candidate.
- [ ] No P0/P1 blockers remain open for the v2 structural close-out.
- [ ] Known caveats below are accepted as non-blocking and assigned to
  follow-up work.

## Pre-tag Code Gates

Each gate must be re-run from the release candidate commit. Attach logs under
`verification/<release-date>/` or link CI runs before tagging.

- [ ] C++ macOS configure/build/ctest: `cmake --preset macos-debug`,
  `cmake --build --preset macos-debug`, and `ctest --preset macos-debug
  --output-on-failure` all pass. Exit criterion: `67/67` tests passing. If the
  test total differs, document the added/removed tests and why the release gate
  still maps to the v2 close-out matrix.
- [ ] Android core all ABIs: `scripts/build-core-android.sh` succeeds for the
  release ABI set and stages `librac_commons.so`, `librunanywhere_jni.so`, and
  engine libraries into every Android consumer package that vendors native
  artifacts.
- [ ] WASM core: `scripts/build-core-wasm.sh` succeeds and exports the
  required `rac_http_*`, streaming, model-registry, and solution symbols.
- [ ] Apple xcframeworks: `scripts/build-core-xcframework.sh` succeeds and
  produces the Swift/Flutter-consumable native artifacts.
- [ ] Swift package: `scripts/sync-swift-headers.sh`, `swift package resolve`,
  and `swift build --package-path .` pass from repo root.
- [ ] Kotlin SDK: `./gradlew compileKotlinJvm jvmTest` passes from
  `sdk/runanywhere-kotlin/`.
- [ ] React Native core: `yarn tsc --noEmit` passes from
  `sdk/runanywhere-react-native/packages/core/`.
- [ ] Flutter SDK: `flutter analyze --no-fatal-infos` passes for all four
  Flutter packages and `flutter test` passes where package tests exist. Use the
  Flutter-bundled Dart version validated by the reconciliation matrix.
- [ ] Web SDK: use npm workspace commands from `sdk/runanywhere-web/`, not
  nested Yarn. `core`, `llamacpp`, and `onnx` typecheck/build gates all pass.
- [ ] iOS sample app: `xcodebuild` simulator build passes for
  `examples/ios/RunAnywhereAI`.
- [ ] Android sample app: `./gradlew :app:assembleDebug` passes for
  `examples/android/RunAnywhereAI`.
- [ ] React Native Android sample: `./gradlew :app:assembleDebug` passes under
  `examples/react-native/RunAnywhereAI/android`.
- [ ] React Native iOS sample: `pod install` and `xcodebuild` pass with the
  documented RN iOS `fmt` workaround, if still required by the active Xcode
  toolchain.
- [ ] Flutter sample app: `flutter build apk --debug` and
  `flutter build ios --simulator --debug --no-codesign` pass for
  `examples/flutter/RunAnywhereAI`.
- [ ] Web sample app: `npm --prefix examples/web/RunAnywhereAI run build`
  passes from repo root.

## Harness Gates

Release readiness requires the cross-SDK streaming harness to prove byte-level
parity, cancellation behavior, and decode-performance sanity across the public
frontends.

- [ ] C++ parity/cancel/perf: `ctest --preset macos-debug -R
  "parity|cancel|perf"` passes, including `parity_test_cpp_check`,
  `llm_parity_test_cpp_check`, `cancel_producer_cpp`, `cancel_aggregate`,
  `perf_producer_cpp`, and `perf_aggregate`.
- [ ] Swift parity/cancel/perf: Swift package tests that include the
  repo-level streaming fixtures pass. Any xcframework environmental issue must
  be resolved or explicitly approved by the release owner before tagging.
- [ ] Kotlin parity/cancel/perf: `./gradlew jvmTest` passes, including
  `StreamingParityTests`, `CancelParityTest`, and `PerfBenchTest`.
- [ ] Dart parity/cancel/perf: Dart/Flutter harness tests pass against the
  shared `tests/streaming/` fixtures and auto-resolved golden paths.
- [ ] React Native parity/cancel/perf: Jest tests wired to
  `tests/streaming/**` pass for `*.rn.test.ts`.
- [ ] Web parity/cancel/perf: Vitest tests wired to `tests/streaming/**` pass
  for `*.web.test.ts`.

## Version Bump Tasks

Perform the bump atomically from `0.19.13` to `0.20.0`. Do not tag if any
manifest below still reports `0.19.13`.

- [ ] `sdk/runanywhere-commons/VERSION`
- [ ] `sdk/runanywhere-commons/VERSIONS`
- [ ] `Package.swift`
- [ ] `sdk/runanywhere-flutter/packages/runanywhere/pubspec.yaml`
- [ ] `sdk/runanywhere-flutter/packages/runanywhere_llamacpp/pubspec.yaml`
- [ ] `sdk/runanywhere-flutter/packages/runanywhere_onnx/pubspec.yaml`
- [ ] `sdk/runanywhere-flutter/packages/runanywhere_genie/pubspec.yaml`
- [ ] `sdk/runanywhere-web/package.json`
- [ ] `sdk/runanywhere-web/packages/core/package.json`
- [ ] `sdk/runanywhere-web/packages/onnx/package.json`
- [ ] `sdk/runanywhere-web/packages/llamacpp/package.json`
- [ ] `sdk/runanywhere-react-native/package.json`
- [ ] `sdk/runanywhere-react-native/packages/core/package.json`
- [ ] `sdk/runanywhere-kotlin/gradle.properties`

After the bump:

- [ ] Run the version-sync script or equivalent validation and verify the 14
  manifests are the only intentional version-manifest changes.
- [ ] Re-run relevant lockfile updates for npm/yarn and pub packages, then
  review that lockfile changes only reflect `0.20.0` package metadata.
- [ ] Re-scan auth/build metadata files that carry SDK version literals and
  confirm they were updated consistently or intentionally left unchanged.

## Publish Tasks

Publishing begins only after the tag and GitHub release exist and all pre-tag
gates remain green on the tagged commit.

- [ ] Create annotated tag `v0.20.0`.
- [ ] Create the GitHub release using the approved release notes.
- [ ] Build Swift binary artifacts with
  `scripts/release-swift-binaries.sh 0.20.0`.
- [ ] Upload `RACommons-ios-v0.20.0.zip`,
  `RABackendLLAMACPP-ios-v0.20.0.zip`, and
  `RABackendONNX-ios-v0.20.0.zip` to the GitHub release.
- [ ] Update and commit SPM binary checksums in `Package.swift`.
- [ ] Smoke-test SPM from a fresh clone: `swift package resolve` and
  `swift build -c release` download all three binary targets and verify
  checksums.
- [ ] Publish npm packages:
  `sdk/runanywhere-react-native/packages/core`,
  `sdk/runanywhere-web/packages/core`,
  `sdk/runanywhere-web/packages/onnx`, and
  `sdk/runanywhere-web/packages/llamacpp`.
- [ ] Publish pub.dev packages:
  `runanywhere`, `runanywhere_llamacpp`, `runanywhere_onnx`, and
  `runanywhere_genie`.
- [ ] Publish Kotlin artifacts to Maven Central through the signed staging
  flow and verify the release is visible after close/release.
- [ ] Update docs install snippets to use `0.20.0` across SDK docs and README
  surfaces.
- [ ] Validate sample apps against published artifacts rather than local
  workspace packages.

## Known Non-blocking Caveats

These caveats must be acknowledged in release notes or follow-up tracking, but
they do not block `v0.20.0` if every blocking gate above passes.

- [ ] Genie SDK vendor integration remains optional. The `genie` engine entry
  and routing shell exist; without `RAC_GENIE_SDK_ROOT` and
  `RAC_GENIE_SDK_AVAILABLE=1`, Genie returns backend-unavailable rather than
  silently claiming hardware execution.
- [ ] Full diffusion quality is optional for this release. The
  `diffusion-coreml` backend owns CoreML lifecycle, metadata, cancel, cleanup,
  and routing paths; the complete Stable Diffusion denoising loop remains
  follow-up work.
- [ ] React Native iOS may require the documented `fmt` / Xcode workaround.
  This is acceptable only if the RN iOS sample still builds and the workaround
  is captured in the release evidence.
- [ ] Web bootstrap `fetch` carve-outs are allowed for no-module-yet downloads,
  WASM binary loading, helper text loading, and pre-`rac_init` telemetry. No
  steady-state Web SDK HTTP/download path may bypass the commons HTTP adapter.

## Security and Compliance

- [ ] Run `gitleaks` with the repository configuration and resolve or document
  every finding before tag.
- [ ] Run `pre-commit run --all-files` and resolve all blocking hook failures.
- [ ] Run `idl/codegen/generate_all.sh` and verify `git diff --exit-code`
  reports no generated-code drift.
- [ ] Run the IDL/codegen drift check used by CI, including generated Swift,
  Kotlin, Dart, TypeScript, React Native streams, Web streams, and C++ outputs.
- [ ] Confirm vendored release artifacts are intentionally tracked or ignored
  according to `.gitattributes` and `.gitignore`.
- [ ] Confirm no secrets, local machine paths, signing credentials, or registry
  tokens were added to tracked files during release preparation.

## Final Sign-off

- [ ] Release notes call out the C ABI v3 plugin break, deleted voice-session
  APIs, Flutter facade migration, Web `VoiceAgent` stub deletion, and package
  install changes.
- [ ] Rollback plan reviewed: package yanks/retractions, GitHub release
  rollback, and `release/0.20.x` hot-fix branch path are understood.
- [ ] Release owner has reviewed all evidence artifacts and approved tagging.
