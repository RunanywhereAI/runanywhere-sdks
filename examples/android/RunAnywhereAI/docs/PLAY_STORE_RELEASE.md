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

`bundleRelease` enforces the following environment variables:

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
```

## Engineering gates

- [ ] Clean QHexRT static build and clean Android native SDK build use the pinned
  QAIRT version documented for this release.
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
