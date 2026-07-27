# RunAnywhere CLI — Releasing

Contributor and release-engineering guide for shipping `rcli` binaries.

## Control plane

Two SDK environments:

| Who | Flags | Auth | Backend |
|---|---|---|---|
| OSS / no key | `--environment development` (default) | Keyless | Baked staging backend → PUBLIC org |
| Team testing | `--environment production --base-url <https://…> --api-key $KEY` | JWT | Your team backend |
| Customers | `--environment production --api-key $KEY` | JWT | Production backend |

| Flag | Env var | Meaning |
|---|---|---|
| `--environment <development\|production>` | `RUNANYWHERE_ENVIRONMENT` | `development` (default) = keyless OSS telemetry. `production` = API key + https. |
| `--base-url <url>` | `RUNANYWHERE_BASE_URL` | Optional in development (baked staging URL in release builds). Required https for production. |
| `--api-key <key>` | `RUNANYWHERE_API_KEY` | Required for production (≥ 10 chars). Omit for keyless development. |

```console
# OSS keyless blast → staging backend (PUBLIC org)
# Unset ambient RUNANYWHERE_API_KEY or an invalid key will force a failed JWT login.
$ unset RUNANYWHERE_API_KEY RUNANYWHERE_BASE_URL
$ rcli --environment development \
    --base-url "$STAGING_BASE_URL" \
    telemetry blast --processing-ms 42.5
# Release builds can omit --base-url (baked STAGING_BASE_URL).
# CI gate (path is relative to the repo root):
#   STAGING_BASE_URL=… ./scripts/ci/oss_keyless_telemetry_blast.sh

# Team / customer authed path
$ rcli --environment production \
    --base-url https://api.example.com \
    --api-key $KEY auth login

$ rcli --environment production \
    --base-url https://api.example.com \
    --api-key $KEY telemetry blast
MODALITY      RESULT    STATUS      RECEIVED    STORED    SKIPPED
llm           ok        HTTP 200    1           1         0
…                                            (one row per modality, 12 total)
```

- `auth login` runs the authenticated handshake (`/api/v1/auth/sdk/authenticate` → `/api/v1/devices/register` → model assignments). Production only.
- `telemetry emit|blast` drive the real commons telemetry pipeline to `/api/v2/sdk/telemetry/{modality}`. Development is keyless (no JWT). Production logs in first. Modalities: `llm stt tts vlm rag imagegen embeddings vad voice lora model system`. Exit is non-zero when any POST fails or any tracked event never reached the backend.

## macOS distribution signing

`release.yml` builds the combined Swift/C++ host from the same Apple artifacts as the SDK release, imports a Developer ID Application certificate into an ephemeral keychain, signs the executable and compatibility libraries with the hardened runtime and secure timestamp, notarizes a DMG, staples and validates its ticket, then deletes the temporary keychain and credential files.

The repository stores no signing material. Configure the Developer ID secrets and one complete notarization credential set before creating a release tag:

- `RCLI_DEVELOPER_ID_CERT_P12_BASE64`
- `RCLI_DEVELOPER_ID_CERT_PASSWORD`

Preferred App Store Connect API-key notarization:

- `RCLI_NOTARY_API_KEY_P8_BASE64`
- `RCLI_NOTARY_KEY_ID`
- `RCLI_NOTARY_ISSUER_ID`

Apple ID fallback notarization:

- `RCLI_NOTARY_APPLE_ID`
- `RCLI_NOTARY_APP_SPECIFIC_PASSWORD`
- `RCLI_NOTARY_TEAM_ID`

When both notarization sets are complete, the workflow uses the App Store Connect API key. The Apple ID fallback stores its run-scoped notarytool profile only in the same ephemeral keychain as the imported Developer ID identity, passes that keychain explicitly during submission, and deletes it after the package step.

For a local or external release runner, `scripts/package-rcli.sh` accepts an already-available identity through `RCLI_CODESIGN_IDENTITY` (and optionally `RCLI_CODESIGN_KEYCHAIN`). Set `RCLI_MACOS_NOTARIZE=1` and authenticate notarytool either with `RCLI_NOTARYTOOL_PROFILE` (plus `RCLI_NOTARYTOOL_KEYCHAIN` for a profile in a non-default keychain) or the API-key path, key ID, and issuer ID variables documented at the top of that script. The normal credential-free packaging path remains ad-hoc signed for pull-request smoke.

## Windows distribution signing

The release workflow Authenticode-signs `rcli.exe`, validates the resulting signature, and only then creates the Windows ZIP. Configure these repository secrets before creating a release tag:

- `RCLI_WINDOWS_CODESIGN_PFX_BASE64`
- `RCLI_WINDOWS_CODESIGN_PFX_PASSWORD`

Pull-request builds remain credential-free and validate the same unsigned binary/package layout before the protected release job performs signing.

## CI and release workflow

- `pr-build.yml` builds macOS, Linux, and Windows rcli targets and runs unit, backend-registration, relocatable-package, and modelless smoke checks.
- `release.yml` requires all three rcli packages before publishing the GitHub Release.
- macOS GitHub Release assets include a Developer ID signed, notarized, and stapled disk image alongside the tarball.

Published release assets are platform-specific:

| Platform | Asset | Included engines |
|---|---|---|
| macOS Apple Silicon | `rcli-macos-arm64-vX.Y.Z.tar.gz` and signed/notarized DMG | llama.cpp + MLX + Sherpa-ONNX + ONNX Runtime + CoreML |
| Linux x86_64 | `rcli-linux-x86_64-vX.Y.Z.tar.gz` | llama.cpp + Sherpa-ONNX + ONNX Runtime |
| Windows x86_64 | `rcli-windows-x86_64-vX.Y.Z.zip` | llama.cpp + Sherpa-ONNX + ONNX Runtime |

The tagged macOS release packages the `RunAnywhereMLXCLI` product as `bin/rcli` together with `mlx.metallib`, its SwiftPM resource bundles, and any deployment-target Swift compatibility libraries. The CMake `rcli` binary remains the fast, credential-free pull-request smoke target; it registers llama.cpp and exposes the dual catalog but cannot execute MLX without the Swift callbacks.
