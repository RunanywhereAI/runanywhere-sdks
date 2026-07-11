# Play Store release gate

Run this checklist from a clean checkout and a clean target device. A release is
not publishable until every required item is checked and its evidence is retained.

## Required publisher inputs

- [ ] Production HTTPS SDK base URL and a public, restricted mobile credential.
- [ ] HTTPS web-search proxy with server-side Brave/HMAC credentials, an explicit
  release-key allowlist, installation/organization/global limits, alerting,
  retention terms, and a tested real-result response contract. A client-supplied
  device UUID and extractable APK key do not replace Play Integrity or equivalent
  attestation for a larger public rollout.
- [ ] Final public HTTPS privacy-policy URL and completed policy placeholders.
- [ ] Play App Signing enrollment plus upload keystore, alias, passwords, and
  expected upload-certificate SHA-256.
- [ ] Unique version code confirmed against every Play track.
- [ ] Developer identity/contact verification, support email, target audience,
  ads declaration, IARC rating, Data safety answers, and reviewer instructions.
- [ ] Backend retention schedule and an operational, tested deletion-request SOP
  with a reliable installation-record lookup method.
- [ ] Publisher/privacy determination on Play's in-flow prominent-disclosure and
  affirmative-consent rule for automatic pre-UI diagnostics; a Settings link is
  not an in-flow disclosure.
- [ ] Raw telemetry error strings are either comprehensively redacted and tested
  or disclosed under the applicable Play user-content category without an
  absolute "content is never collected" claim.
- [ ] Reviewer instructions include an entitled non-personal Hugging Face test
  token, the exact small models to install, and steps for private HNPU access.
- [ ] Every shipped library, font, model, adapter, and native binary has a
  reviewed redistribution license and an entry in
  [`MODEL_LICENSE_REVIEW.md`](MODEL_LICENSE_REVIEW.md) plus the archived notices
  inventory. Resolve every external approval in
  [`THIRD_PARTY_NOTICES_AUDIT.md`](THIRD_PARTY_NOTICES_AUDIT.md).

The Gradle `bundleRelease` gate enforces the backend and signing inputs below.
The wrapper also requires `SDK_VERSION` and rejects a snapshot or any value that
does not exactly match the app version in the produced AAB:

```text
RUNANYWHERE_BASE_URL
RUNANYWHERE_API_KEY
RUNANYWHERE_PRIVACY_POLICY_URL
RUNANYWHERE_WEB_SEARCH_URL
KEYSTORE_PATH
KEYSTORE_PASSWORD
KEY_ALIAS
KEY_PASSWORD
UPLOAD_CERT_SHA256
SDK_VERSION
```

Use the secret-safe release wrapper rather than invoking `bundleRelease`
directly:

```bash
cd examples/android/RunAnywhereAI
./scripts/build-play-aab.sh
```

The wrapper disables shell tracing, uses a private umask, fails before native
or Gradle build work when an input is missing, and passes every value to Gradle
through its environment rather than command-line arguments. Environment values
win. On macOS, missing values are read from Keychain service
`com.runanywhere.android.release`, with an account name exactly matching each
variable above. Create or update an item without putting its value in the
command line by leaving `-w` last and entering the value at the prompt, for
example:

```bash
security add-generic-password -U \
  -s com.runanywhere.android.release \
  -a KEYSTORE_PASSWORD \
  -w
```

Use `--no-keychain` for an environment-only CI run. The default workflow removes
the ignored QHexRT and SDK Android native build directories, rebuilds the private
QHexRT static libraries, stages them into the SDK, rebuilds the arm64 Android
native layer, and rebuilds/stages every release AAR before the guarded AAB
build. `--skip-native-rebuild` is only for a repeat signing/archive run after
those native outputs have already been validated; it still validates the staged
runtime set and rebuilds/stages the release AARs.

Both SDK and QHexRT worktrees must be clean, including untracked files. The
`--allow-dirty` override is only for traceable development validation; its
archive is explicitly labeled not Play-ready. A default run also cleans the SDK
and app Gradle outputs, runs app unit tests and release lint, and pins QAIRT
2.47.0 build 260601114230 plus Android NDK 27.3.13750724.

The wrapper uses only the checksum-pinned official bundletool jar cached under
the ignored app `build/` directory. It verifies complete JAR-signature coverage,
the actual upload certificate, exact arm64 native contents, every packaged ELF
`LOAD` alignment, exact V75/V79/V81 DSP-skel placement, and
`PAGE_ALIGNMENT_16K`. It then creates a private timestamped directory under
`build/play-release/` containing:

- the upload-signed AAB;
- R8 `mapping.txt` and native debug symbols;
- the release CycloneDX SBOM;
- bundletool config and merged manifest dumps;
- native ELF-alignment and QHexRT-skel-layout reports;
- an arm64-only native-debug-symbol archive and its reviewed layout;
- SDK/QHexRT Git provenance (including untracked-file dirtiness), pinned QAIRT
  and NDK versions, AAB metadata, SHA-256 checksums, and the actual upload
  certificate SHA-256.

Both Gradle wrapper distributions have pinned SHA-256 checksums. Maven/Google
dependency verification metadata and dependency lockfiles are not yet present,
so a successful local wrapper run is not by itself byte-for-byte dependency
reproducibility evidence; resolve that before calling the supply chain fully
pinned.

## Engineering gates

- [ ] Clean QHexRT static build and clean Android native SDK build use the pinned
  QAIRT version documented for this release.
- [ ] Gradle dependency verification metadata and release dependency locks are
  reviewed and committed; wrapper-distribution checksums alone are insufficient.
- [ ] Clean release AARs are staged; unit tests and minified release build pass.
- [ ] Release catalog exposes only architecture/runtime-compatible HNPU models.
- [ ] No model download plan contains `.dex`, `.jar`, or executable `.so` files.
- [ ] Web-search instrumentation returns at least one real source through the
  configured proxy; provider secrets are absent from the APK and source tree.
- [ ] The synthetic forbidden-executable resolver test passes and production
  network inspection confirms the runtime rejection is fail-closed.
- [ ] Signed AAB certificate matches `UPLOAD_CERT_SHA256`; APK derived from the
  same bundle installs and launches on a fresh device.
- [ ] `bundletool dump config` reports `PAGE_ALIGNMENT_16K`.
- [ ] `zipalign -c -P 16 -v 4` succeeds and every arm64 ELF `LOAD` alignment is
  at least `0x4000`, including third-party libraries.
- [ ] Bundletool compressed download size is below the current Play limit for
  every relevant device configuration.
- [ ] R8 mapping, native debug symbols, AAB SHA-256, upload certificate, dependency
  report, SBOM, and test reports are archived with the release.
- [ ] `./scripts/audit-release-notices.sh --strict --apk <exact-release-apk>`
  passes, and its SBOM and notice inventory match the artifacts archived for
  this release. A mechanical pass does not replace publisher/legal approval.
- [ ] Play pre-launch report and policy/SDK warnings are clean.

## Device acceptance

Hybrid (Beta) transcription, including cloud-provider setup and unconfigured
provider paths, is optional and non-blocking. Exclude it from release acceptance
unless a tester explicitly supplies a cloud STT provider. Only Batch and Live STT
are required for release acceptance.

- [ ] Remove every prior RunAnywhere package/data set from the chosen device.
- [ ] Verify cold start, retry/error path, relaunch, rotation, background/restore,
  offline behavior, and loss of network during download/generation.
- [ ] Verify immediate startup with automatic production diagnostics, then exercise Ask, history/details, model lifecycle, settings/storage,
  tools, Talk, photo/live vision, documents/RAG, TTS, Batch/Live STT, VAD,
  solutions, benchmarks/export, and permission grant/deny/permanent-deny paths.
- [ ] Run multiple V81 QHexRT models across LLM, thinking LLM, STT, TTS, VLM,
  embedding, and inpainting; require architecture and QHexRT provenance gates.
- [ ] Confirm logcat has no crash, ANR, native fatal, credential, prompt, document,
  transcript, or generated-content leakage.

## Store assets and rollout

- [ ] Final app name, short description, full description, support contact, icon,
  feature graphic, and at least four truthful current-device screenshots.
- [ ] Screenshot permission/status bars and sample content contain no secrets or
  personal data; alt text is prepared.
- [ ] Internal/closed test and production-access requirements for the developer
  account are satisfied.
- [ ] Upload to an internal track first, install Play's delivered split build,
  repeat the smoke suite, then promote through a staged production rollout.
