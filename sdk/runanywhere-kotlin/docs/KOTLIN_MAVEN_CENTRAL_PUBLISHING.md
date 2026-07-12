# Kotlin SDK - Maven Central Publishing Guide

---

## Published Artifacts

Each AAR is self-contained with its declared component libraries. The Android
runtime sidecar `libc++_shared.so` is intentionally present in every backend
AAR; all three copies come from the same NDK runtime for a given ABI.

| Artifact | Native Libs | Description |
|----------|-------------|-------------|
| `io.github.sanchitmonga22:runanywhere-sdk-android` | 5 per ABI | Core SDK and cloud backend |
| `io.github.sanchitmonga22:runanywhere-llamacpp-android` | 4 per ABI | LlamaCPP LLM/VLM backend |
| `io.github.sanchitmonga22:runanywhere-onnx-android` | 9 per ABI | ONNX and Sherpa STT/TTS/VAD backends |
| `io.github.sanchitmonga22:runanywhere-sdk` | - | KMP metadata |
| `io.github.sanchitmonga22:runanywhere-llamacpp` | - | KMP metadata |
| `io.github.sanchitmonga22:runanywhere-onnx` | - | KMP metadata |

With three ABIs (`arm64-v8a`, `armeabi-v7a`, `x86_64`), the Maven bundle
contains 15 core, 12 LlamaCPP, and 27 ONNX/Sherpa entries: **54 `.so` entries**.

---

## Native Library Packaging Architecture

The canonical native release has one exact tree per ABI. `package-sdk.sh`
validates that tree, rejects undeclared or private QHexRT/QNN inputs, and routes
each component into its owning AAR.

```
runanywhere-sdk-android AAR          runanywhere-llamacpp-android AAR     runanywhere-onnx-android AAR
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
| `{abi}/jni` | `runanywhere-sdk-android` |
| `{abi}/llamacpp` | `runanywhere-llamacpp-android` |
| `{abi}/onnx` | `runanywhere-onnx-android` |

---

## Publishing Lifecycle

Publishing uses the **Sonatype OSSRH Staging API**. Three explicit phases:

```
Upload (Gradle) --> Close (validation) --> Release (promotes to Maven Central)
```

The Gradle `maven-publish` plugin only does the upload. Close and release must be done separately.

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

export SDK_VERSION=0.20.6
export NATIVE_VERSION=0.20.6
export ANDROID_HOME="$HOME/Library/Android/sdk"
export MAVEN_CENTRAL_USERNAME="<USERNAME>"
export MAVEN_CENTRAL_PASSWORD="<PASSWORD>"

NATIVE_ARCHIVES="$(mktemp -d)"
for ABI in arm64-v8a armeabi-v7a x86_64; do
  NAME="RACommons-android-${ABI}-v${NATIVE_VERSION}.zip"
  URL="https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v${NATIVE_VERSION}"
  curl -fL "$URL/$NAME" -o "$NATIVE_ARCHIVES/$NAME"
  curl -fL "$URL/$NAME.sha256" -o "$NATIVE_ARCHIVES/$NAME.sha256"
  (cd "$NATIVE_ARCHIVES" && shasum -a 256 -c "$NAME.sha256")
done

bash sdk/runanywhere-kotlin/scripts/package-sdk.sh \
  --mode local \
  --natives-from "$NATIVE_ARCHIVES"

cd sdk/runanywhere-kotlin
./gradlew clean publishAllPublicationsToMavenCentralRepository \
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

export SDK_VERSION=0.20.6
export RAC_RELEASE_VERSION="$SDK_VERSION"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/27.3.13750724"

DIST="$REPO_ROOT/sdk/runanywhere-commons/dist"
NATIVE_ROOT="$DIST/public-android-natives"
rm -rf "$NATIVE_ROOT"
mkdir -p "$NATIVE_ROOT"

for ABI in arm64-v8a armeabi-v7a x86_64; do
  bash sdk/runanywhere-commons/scripts/build-android.sh "$ABI"
  ARCHIVE="$DIST/RACommons-android-${ABI}-v${SDK_VERSION}.zip"
  (
    cd "$DIST"
    shasum -a 256 -c "$(basename "$ARCHIVE").sha256"
  )
  unzip -q "$ARCHIVE" -d "$NATIVE_ROOT"
done

# Build and validate the exact public Maven bundle, and stage those validated
# natives into the three Kotlin modules.
bash sdk/runanywhere-kotlin/scripts/package-sdk.sh \
  --mode local \
  --natives-from "$NATIVE_ROOT"

# Publish the same staged inputs.
export MAVEN_CENTRAL_USERNAME="<USERNAME>"
export MAVEN_CENTRAL_PASSWORD="<PASSWORD>"

cd sdk/runanywhere-kotlin
./gradlew clean publishAllPublicationsToMavenCentralRepository \
  -Prunanywhere.useLocalNatives=true \
  -x buildLocalJniLibs \
  --no-daemon
```

### 4. Close and Release Staging Repo

```bash
# Drop any stale staging repo first (if previous publish failed)
curl -s -X POST -u "$MAVEN_CENTRAL_USERNAME:$MAVEN_CENTRAL_PASSWORD" \
  "https://ossrh-staging-api.central.sonatype.com/service/local/staging/bulk/drop" \
  -H "Content-Type: application/json" \
  -d '{"data":{"stagedRepositoryIds":["io.github.sanchitmonga22--default-repository"],"description":"Clean","autoDropAfterRelease":true}}'

# ... then re-run the publish command above if needed ...

# Close (triggers validation)
curl -X POST -u "$MAVEN_CENTRAL_USERNAME:$MAVEN_CENTRAL_PASSWORD" \
  "https://ossrh-staging-api.central.sonatype.com/service/local/staging/bulk/close" \
  -H "Content-Type: application/json" \
  -d '{"data":{"stagedRepositoryIds":["io.github.sanchitmonga22--default-repository"],"description":"Release","autoDropAfterRelease":true}}'

# Wait ~30s, verify "type": "closed"
curl -s -u "$MAVEN_CENTRAL_USERNAME:$MAVEN_CENTRAL_PASSWORD" \
  "https://ossrh-staging-api.central.sonatype.com/service/local/staging/profile_repositories/io.github.sanchitmonga22" \
  -H "Accept: application/json"

# Release (promote to Maven Central)
curl -X POST -u "$MAVEN_CENTRAL_USERNAME:$MAVEN_CENTRAL_PASSWORD" \
  "https://ossrh-staging-api.central.sonatype.com/service/local/staging/bulk/promote" \
  -H "Content-Type: application/json" \
  -d '{"data":{"stagedRepositoryIds":["io.github.sanchitmonga22--default-repository"],"description":"Release","autoDropAfterRelease":true}}'
```

### 5. Verify

Artifacts take 10-30 minutes to propagate.

```bash
for a in runanywhere-sdk-android runanywhere-llamacpp-android runanywhere-onnx-android; do
  echo "$a: $(curl -s -o /dev/null -w '%{http_code}' \
    "https://repo1.maven.org/maven2/io/github/sanchitmonga22/$a/$SDK_VERSION/$a-$SDK_VERSION.pom")"
done
```

Check: [Central Portal Deployments](https://central.sonatype.com/publishing/deployments) | [Search](https://central.sonatype.com/search?q=io.github.sanchitmonga22)

---

## CI/CD Quick Release

1. Go to **GitHub Actions** > **Publish to Maven Central**
2. Enter version (e.g., `0.20.6`) and run
3. CI uploads to OSSRH staging. Auto-close happens after ~10 min.
4. If stuck, manually close/release via the staging API commands above.

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
    implementation("io.github.sanchitmonga22:runanywhere-sdk-android:0.20.6")

    // Optional: LLM + VLM (add only if you need text/vision generation)
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp-android:0.20.6")

    // Optional: STT/TTS/VAD (add only if you need speech features)
    implementation("io.github.sanchitmonga22:runanywhere-onnx-android:0.20.6")
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
| Staging repo "No objects found" | Drop the stale repo and re-upload |
| OSSRH staging never auto-closes | Manually close/release via staging API |

---

## Version History

| Version | Date | Notes |
|---------|------|-------|
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
