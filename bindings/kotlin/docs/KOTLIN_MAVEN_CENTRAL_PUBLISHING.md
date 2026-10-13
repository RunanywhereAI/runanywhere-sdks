# Kotlin SDK - Maven Central Publishing Guide

---

## Published Artifacts

Each AAR is self-contained with its declared component libraries. The Android
runtime sidecar `libc++_shared.so` is intentionally present in every backend
AAR; all three copies come from the same NDK runtime for a given ABI.

| Artifact | Native Libs | Description |
|----------|-------------|-------------|
| `io.github.sanchitmonga22:runanywhere-sdk` | 5 per ABI | Core SDK and cloud backend |
| `io.github.sanchitmonga22:runanywhere-llamacpp` | 4 per ABI | LlamaCPP LLM/VLM backend |
| `io.github.sanchitmonga22:runanywhere-onnx` | 9 per ABI | ONNX and Sherpa STT/TTS/VAD backends |
| `io.github.sanchitmonga22:runanywhere-qhexrt-android` | 13 host + 3 skels (arm64 only) | QHexRT Hexagon NPU backend (separate package) |

The SDK is a single-target Android library (not KMP), so there are no `-android`
variants or separate KMP metadata artifacts for the core three.

With three ABIs (`arm64-v8a`, `armeabi-v7a`, `x86_64`), the public Maven bundle
from `package-sdk.sh` contains 15 core, 12 LlamaCPP, and 27 ONNX/Sherpa entries:
**54 `.so` entries**. QHexRT is packaged separately via `package-qhexrt.sh`
(`arm64-v8a` only) and is not part of that public zip.

---

## Native Library Packaging Architecture

The canonical native release has one exact tree per ABI. `package-sdk.sh`
validates that tree, rejects undeclared or private QHexRT/QNN inputs, and routes
each component into its owning AAR.

```
runanywhere-sdk AAR                  runanywhere-llamacpp AAR             runanywhere-onnx AAR
  jni/{abi}/                           jni/{abi}/                           jni/{abi}/
    libc++_shared.so                     libc++_shared.so                      libc++_shared.so
    libomp.so                            librac_backend_llamacpp.so            libonnxruntime.so
    librac_backend_cloud.so              librac_backend_llamacpp_jni.so        librac_backend_onnx.so
    librac_commons.so                    librunanywhere_llamacpp.so            librac_backend_onnx_jni.so
    librunanywhere_jni.so                                                     librac_backend_sherpa.so
                                                                              librunanywhere_onnx.so
                                                                              librunanywhere_sherpa.so
                                                                              libsherpa-onnx-c-api.so
                                                                              libsherpa-onnx-jni.so
```

**How native libs are obtained (two modes):**

| Mode | Trigger | What happens |
|------|---------|-------------|
| **Released natives** | Existing GitHub release | Pass the three `RACommons-android-{abi}-v{version}.zip` files to `package-sdk.sh --natives-from` |
| **Local source build** | Latest C++ is required | Build one ABI at a time with `build-android.sh`, extract the same canonical trees, then call `package-sdk.sh --natives-from` |

**Canonical archive mapping:**

| Archive subtree | Maven artifact |
|-----------------|----------------|
| `{abi}/jni` | `runanywhere-sdk` |
| `{abi}/llamacpp` | `runanywhere-llamacpp` |
| `{abi}/onnx` | `runanywhere-onnx` |

---

## Publishing Lifecycle

Publishing uses the **Sonatype OSSRH Staging API**. Three explicit phases:

```
Upload (Gradle) --> Transfer to Portal --> Validate + publish to Maven Central
```

The Gradle `maven-publish` plugin only writes files to Sonatype's OSSRH
compatibility service. The deployment must then be transferred to the Central
Publisher Portal. Using `publishing_type=automatic` validates and publishes it
without a separate Portal click.

---

## Local Release (Step-by-Step)

### 1. Prerequisites

```bash
# Android SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"

# GPG key (import if not already done)
echo "<GPG_SIGNING_KEY_BASE64>" | base64 -d | gpg --batch --import
gpg --list-secret-keys --keyid-format LONG
```

### 2. Credentials (one-time)

`~/.gradle/gradle.properties`:
```properties
# Maven Central (Sonatype Central Portal)
mavenCentral.username=YOUR_SONATYPE_USERNAME
mavenCentral.password=YOUR_SONATYPE_PASSWORD

# GPG Signing
signing.gnupg.executable=gpg
signing.gnupg.useLegacyGpg=false
signing.gnupg.keyName=YOUR_GPG_KEY_ID
signing.gnupg.passphrase=YOUR_GPG_PASSPHRASE
```

### 3. Option A: Publish with released native archives

Use a GitHub release that contains all three canonical Android archives:

```bash
# Run from the repository root.
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

export SDK_VERSION=0.20.11
export NATIVE_VERSION=0.20.11
export ANDROID_HOME="$HOME/Library/Android/sdk"
export MAVEN_CENTRAL_USERNAME="<USERNAME>"
export MAVEN_CENTRAL_PASSWORD="<PASSWORD>"
export GPG_KEY_ID="<KEY_ID>"
export GPG_SIGNING_KEY="<BASE64_ARMORED_PRIVATE_KEY>"
export GPG_SIGNING_PASSWORD="<PASSPHRASE>"

NATIVE_ARCHIVES="$(mktemp -d)"
for ABI in arm64-v8a armeabi-v7a x86_64; do
  NAME="RACommons-android-${ABI}-v${NATIVE_VERSION}.zip"
  URL="https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v${NATIVE_VERSION}"
  curl -fL "$URL/$NAME" -o "$NATIVE_ARCHIVES/$NAME"
  curl -fL "$URL/$NAME.sha256" -o "$NATIVE_ARCHIVES/$NAME.sha256"
  (cd "$NATIVE_ARCHIVES" && shasum -a 256 -c "$NAME.sha256")
done

bash bindings/kotlin/scripts/package-sdk.sh \
  --mode local \
  --natives-from "$NATIVE_ARCHIVES"

cd bindings/kotlin
./gradlew clean \
  :publishReleasePublicationToMavenCentralRepository \
  :modules:runanywhere-core-llamacpp:publishReleasePublicationToMavenCentralRepository \
  :modules:runanywhere-core-onnx:publishReleasePublicationToMavenCentralRepository \
  -Prunanywhere.useLocalNatives=true \
  -x buildLocalJniLibs \
  --no-daemon
```

### 3. Option B: Publish with locally-built native libs (VLM/latest C++)

Build the canonical native archives from source, validate their checksums,
extract the exact component trees, and let the package contract stage them:

```bash
# Run from the repository root.
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

export SDK_VERSION=0.20.11
export RAC_RELEASE_VERSION="$SDK_VERSION"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/27.3.13750724"

DIST="$REPO_ROOT/core/dist"
NATIVE_ROOT="$DIST/public-android-natives"
rm -rf "$NATIVE_ROOT"
mkdir -p "$NATIVE_ROOT"

for ABI in arm64-v8a armeabi-v7a x86_64; do
  bash core/scripts/build-android.sh "$ABI"
  ARCHIVE="$DIST/RACommons-android-${ABI}-v${SDK_VERSION}.zip"
  (
    cd "$DIST"
    shasum -a 256 -c "$(basename "$ARCHIVE").sha256"
  )
  unzip -q "$ARCHIVE" -d "$NATIVE_ROOT"
done

# Build and validate the exact public Maven bundle, and stage those validated
# natives into the three Kotlin modules.
bash bindings/kotlin/scripts/package-sdk.sh \
  --mode local \
  --natives-from "$NATIVE_ROOT"

# Publish the same staged inputs.
export MAVEN_CENTRAL_USERNAME="<USERNAME>"
export MAVEN_CENTRAL_PASSWORD="<PASSWORD>"

cd bindings/kotlin
./gradlew clean publishAllPublicationsToMavenCentralRepository \
  -Prunanywhere.useLocalNatives=true \
  -x buildLocalJniLibs \
  --no-daemon
```

### 4. Transfer the deployment to Central Portal

```bash
# Run this from the same host/IP that performed the Gradle upload. Sonatype's
# compatibility service groups Maven-like PUT requests by source IP.
CENTRAL_BEARER="$(printf '%s:%s' \
  "$MAVEN_CENTRAL_USERNAME" "$MAVEN_CENTRAL_PASSWORD" |
  base64 | tr -d '\r\n')"

curl --fail --request POST \
  -H "Authorization: Bearer $CENTRAL_BEARER" \
  'https://ossrh-staging-api.central.sonatype.com/manual/upload/defaultRepository/io.github.sanchitmonga22?publishing_type=automatic'

# This flow assumes the compatibility service was clean before the Gradle
# upload. Require exactly one repository for this client IP and namespace so a
# stale or concurrent deployment can never be selected by accident.
REPOSITORIES_JSON="$(curl --fail --silent \
  -H "Authorization: Bearer $CENTRAL_BEARER" \
  'https://ossrh-staging-api.central.sonatype.com/manual/search/repositories?ip=client&profile_id=io.github.sanchitmonga22')"
REPOSITORY_COUNT="$(jq '[.repositories[] | select(.portal_deployment_id != null)] | length' <<<"$REPOSITORIES_JSON")"
[ "$REPOSITORY_COUNT" = 1 ] || {
  echo "Expected exactly one transferred repository; found $REPOSITORY_COUNT" >&2
  exit 1
}
DEPLOYMENT_ID="$(jq -r '.repositories[] | select(.portal_deployment_id != null) | .portal_deployment_id' <<<"$REPOSITORIES_JSON")"
[ -n "$DEPLOYMENT_ID" ] && [ "$DEPLOYMENT_ID" != null ]

# Poll for at most 15 minutes. Automatic deployments normally pass through
# PENDING -> VALIDATING -> PUBLISHING -> PUBLISHED.
DEPLOYMENT_STATE=
for attempt in $(seq 1 90); do
  STATUS_JSON="$(curl --fail --silent --request POST \
    -H "Authorization: Bearer $CENTRAL_BEARER" \
    "https://central.sonatype.com/api/v1/publisher/status?id=$DEPLOYMENT_ID")"
  DEPLOYMENT_STATE="$(jq -r '.deploymentState' <<<"$STATUS_JSON")"
  case "$DEPLOYMENT_STATE" in
    PUBLISHED) break ;;
    FAILED)
      jq '.errors' <<<"$STATUS_JSON" >&2
      exit 1
      ;;
    PENDING|VALIDATING|PUBLISHING) sleep 10 ;;
    VALIDATED)
      echo "Deployment is waiting for manual publication instead of automatic release; publish it in Central Portal or use the Portal publish endpoint, then resume status polling." >&2
      exit 1
      ;;
    *)
      echo "Unexpected Central Portal state: $DEPLOYMENT_STATE" >&2
      exit 1
      ;;
  esac
done
[ "$DEPLOYMENT_STATE" = PUBLISHED ] || {
  echo "Timed out waiting for Central Portal deployment $DEPLOYMENT_ID" >&2
  exit 1
}
```

### 5. Verify

Artifacts take 10-30 minutes to propagate.

```bash
for a in runanywhere-sdk runanywhere-llamacpp runanywhere-onnx; do
  echo "$a: $(curl -s -o /dev/null -w '%{http_code}' \
    "https://repo1.maven.org/maven2/io/github/sanchitmonga22/$a/$SDK_VERSION/$a-$SDK_VERSION.pom")"
done
```

Check: [Central Portal Deployments](https://central.sonatype.com/publishing/deployments) | [Search](https://central.sonatype.com/search?q=io.github.sanchitmonga22)

---

## CI/CD Quick Release

Maven Central publishing is **manual** (not automated in GitHub Actions).
`.github/workflows/release.yml` only attaches a local Maven repository zip to
the GitHub Release. Use the local release steps above to upload to the OSSRH
compatibility service, then transfer it to Central Portal with automatic
publishing.

---

## QHexRT (Hexagon NPU) package

QHexRT is published as a **separate** artifact so the default public bundle stays
free of proprietary QAIRT/QNN redistributables.

```bash
# After staging QHexRT natives via:
#   QHexRT/tools/scripts/stage_prebuilt_for_sdk.sh ...
#   RAC_BUILD_JOBS=2 ./scripts/build/build-core-android.sh arm64-v8a

export SDK_VERSION=0.20.11
export MAVEN_CENTRAL_USERNAME="<USERNAME>"
export MAVEN_CENTRAL_PASSWORD="<PASSWORD>"
export GPG_KEY_ID="<KEY_ID>"
export GPG_SIGNING_KEY="<BASE64_ARMORED_PRIVATE_KEY>"
export GPG_SIGNING_PASSWORD="<PASSPHRASE>"

bash bindings/kotlin/scripts/package-qhexrt.sh --mode local

cd bindings/kotlin
./gradlew :modules:runanywhere-core-qhexrt:publishReleasePublicationToMavenCentralRepository \
  -Prunanywhere.useLocalNatives=true \
  -x buildLocalJniLibs \
  --no-daemon
```

Then transfer the staging repository with the same manual upload command as the
core artifacts. Consumers depend on:

```kotlin
implementation("io.github.sanchitmonga22:runanywhere-sdk:0.20.11")
implementation("io.github.sanchitmonga22:runanywhere-qhexrt-android:0.20.11")
```

---

## Consumer Usage

```kotlin
// settings.gradle.kts
repositories {
    mavenCentral()
}

// build.gradle.kts
dependencies {
    // Required: core SDK
    implementation("io.github.sanchitmonga22:runanywhere-sdk:0.20.11")

    // Optional: LLM + VLM (add only if you need text/vision generation)
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp:0.20.11")

    // Optional: STT/TTS/VAD (add only if you need speech features)
    implementation("io.github.sanchitmonga22:runanywhere-onnx:0.20.11")

    // Optional: Snapdragon Hexagon NPU (arm64-v8a only)
    implementation("io.github.sanchitmonga22:runanywhere-qhexrt-android:0.20.11")
}
```

No `pickFirsts` or workarounds needed. Each AAR bundles only its own native libs.

---

## GitHub Secrets

| Secret | Description |
|--------|-------------|
| `MAVEN_CENTRAL_USERNAME` | Sonatype Central Portal token username |
| `MAVEN_CENTRAL_PASSWORD` | Sonatype Central Portal token |
| `GPG_KEY_ID` | Last 16 chars of GPG key fingerprint (e.g., `CC377A9928C7BB18`) |
| `GPG_SIGNING_KEY` | Base64-encoded full armored GPG private key |
| `GPG_SIGNING_PASSWORD` | GPG key passphrase |

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| GPG signature verification failed | Upload key to `keys.openpgp.org` AND verify email |
| 403 Forbidden | Verify namespace at central.sonatype.com |
| Missing native libs in AAR | Clean all `jniLibs/` dirs and rebuild. Check each module has its own libs. |
| `UnsatisfiedLinkError: nativeRegisterVlm` | Native libs are stale (pre-VLM). Rebuild from source with `build-android.sh`. |
| Duplicate `.so` across AARs | Stale files in module `jniLibs/`. Delete and rebuild. Check `.gitignore` covers `src/main/jniLibs/`. |
| Compatibility repository is stale or closed | Treat the compatibility repository and its Portal deployment as separate resources. Find the repository with `GET /manual/search/repositories?ip=any&profile_id=io.github.sanchitmonga22`. If `portal_deployment_id` is present, query `/api/v1/publisher/status` first: for `PUBLISHED`, verify the released artifacts and stop; for active states, wait; for `FAILED`, preserve the deployment when requesting support; for a retryable `VALIDATED` or `FAILED` deployment, explicitly delete it through `/api/v1/publisher/deployment/{id}`. Only when retrying a non-published deployment should you delete the compatibility repository with `DELETE /manual/drop/repository/{repository_key}` before re-uploading. |
| Deployment never appears in Central Portal | Call `POST /manual/upload/defaultRepository/io.github.sanchitmonga22` from the same IP as the Gradle upload. |

---

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 0.20.11 | 2026-07-27 | Public QHexRT package (`runanywhere-qhexrt-android`), NVIDIA/Magpie/Cosmos catalog, re-cut tag from HEAD |
| 0.20.10 | 2026-07 | Core + LlamaCPP + ONNX on Maven Central |
| 0.20.9 | 2026-06 | One-off `runanywhere-qhexrt-android` publish (then excluded from public train) |
| 0.20.6 | 2026-02-16 | Self-contained AARs (zero duplicate .so), VLM-enabled, native libs rebuilt from source |
| 0.20.5 | 2026-02-16 | Removed stale .so from module dirs (Option B: SDK bundles everything) |
| 0.20.4 | 2026-02-16 | Native libs rebuilt from source with VLM (llama.cpp b8011 + mtmd) |
| 0.20.3 | 2026-02-16 | VLM graceful degradation (UnsatisfiedLinkError catch in registerVLM) |
| 0.20.2 | 2026-02-16 | Added `org.json:json` JVM dependency, fixed staging close/release |
| 0.20.1 | 2026-02-15 | Partial native libs (arm64-v8a commons only) |
| 0.16.1 | 2026-01-18 | First stable release via Central Portal bundle upload |

---

## Key URLs

- **Central Portal**: https://central.sonatype.com
- **Deployments**: https://central.sonatype.com/publishing/deployments
- **Search**: https://central.sonatype.com/search?q=io.github.sanchitmonga22
- **Maven Central Repo**: https://repo1.maven.org/maven2/io/github/sanchitmonga22/
- **GPG Keyserver**: https://keys.openpgp.org
- **GitHub Releases**: https://github.com/RunanywhereAI/runanywhere-sdks/releases
- **OSSRH Staging API**: https://ossrh-staging-api.central.sonatype.com
- **OSSRH compatibility-service guide**: https://central.sonatype.org/publish/publish-portal-ossrh-staging-api/
