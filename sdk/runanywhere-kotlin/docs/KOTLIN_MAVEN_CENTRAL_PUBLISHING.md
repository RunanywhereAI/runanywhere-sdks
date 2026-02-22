# Kotlin SDK - Maven Central Publishing Guide

---

## Published Artifacts

Each AAR is **self-contained** with only its own native libraries. Zero duplicates across AARs.

| Artifact | Native Libs | Description |
|----------|-------------|-------------|
| `io.github.sanchitmonga22:runanywhere-sdk-android` | 4 per ABI | Core SDK: `librac_commons.so`, `librunanywhere_jni.so`, `libc++_shared.so`, `libomp.so` |
| `io.github.sanchitmonga22:runanywhere-llamacpp-android` | 2 per ABI | LLM backend (with VLM): `librac_backend_llamacpp.so`, `librac_backend_llamacpp_jni.so` |
| `io.github.sanchitmonga22:runanywhere-onnx-android` | 6 per ABI | STT/TTS/VAD: `librac_backend_onnx*.so`, `libonnxruntime.so`, `libsherpa-onnx-*.so` |
| `io.github.sanchitmonga22:runanywhere-sdk` | - | KMP metadata |
| `io.github.sanchitmonga22:runanywhere-llamacpp` | - | KMP metadata |
| `io.github.sanchitmonga22:runanywhere-onnx` | - | KMP metadata |

With 3 ABIs (arm64-v8a, armeabi-v7a, x86_64): SDK=12, LlamaCPP=6, ONNX=18 = **36 total .so files**.

---

## Native Library Packaging Architecture

Each module downloads and bundles **only its own** backend `.so` files. No `pickFirsts` needed.

```
runanywhere-sdk-android AAR          runanywhere-llamacpp-android AAR     runanywhere-onnx-android AAR
  jni/{abi}/                           jni/{abi}/                           jni/{abi}/
    librac_commons.so                    librac_backend_llamacpp.so           librac_backend_onnx.so
    librunanywhere_jni.so                librac_backend_llamacpp_jni.so       librac_backend_onnx_jni.so
    libc++_shared.so                                                          libonnxruntime.so
    libomp.so                                                                 libsherpa-onnx-c-api.so
                                                                              libsherpa-onnx-cxx-api.so
                                                                              libsherpa-onnx-jni.so
```

**How native libs are obtained (two modes):**

| Mode | Trigger | What happens |
|------|---------|-------------|
| **Remote** (`testLocal=false`) | Default for CI/publishing | Each module's `downloadJniLibs` task downloads its own package from GitHub releases |
| **Local** (`testLocal=true`) | `build-kotlin.sh --setup` | Script builds C++ from source and copies to each module's `src/androidMain/jniLibs/` |

**Remote download mapping:**

| Module | Downloads | Keeps only |
|--------|-----------|------------|
| Root SDK | `RACommons-android-{abi}-v{ver}.zip` | `librac_commons.so`, `librunanywhere_jni.so`, `libc++_shared.so`, `libomp.so` |
| LlamaCPP | `RABackendLLAMACPP-android-{abi}-v{ver}.zip` | `librac_backend_llamacpp.so`, `librac_backend_llamacpp_jni.so` |
| ONNX | `RABackendONNX-android-{abi}-v{ver}.zip` | `librac_backend_onnx*.so`, `libonnxruntime.so`, `libsherpa-onnx-*.so` |

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

### 3. Option A: Publish with pre-built native libs (remote download)

Use a GitHub release that has per-ABI Android binaries (e.g., `v0.17.5`):

```bash
cd sdk/runanywhere-kotlin

# Clean all jniLibs
rm -rf src/androidMain/jniLibs
rm -rf modules/runanywhere-core-llamacpp/src/androidMain/jniLibs
rm -rf modules/runanywhere-core-onnx/src/androidMain/jniLibs

# Set version and publish (each module downloads its own libs)
export SDK_VERSION=0.20.6
export MAVEN_CENTRAL_USERNAME="<USERNAME>"
export MAVEN_CENTRAL_PASSWORD="<PASSWORD>"
export ANDROID_HOME="$HOME/Library/Android/sdk"

./gradlew clean publishAllPublicationsToMavenCentralRepository \
  -Prunanywhere.testLocal=false \
  -Prunanywhere.nativeLibVersion=0.17.5 \
  --no-daemon
```

### 3. Option B: Publish with locally-built native libs (VLM/latest C++)

Build native libs from source first, then publish:

```bash
# 1. Build C++ native libs (all backends, all ABIs)
cd sdk/runanywhere-commons
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/27.0.12077973"
./scripts/build-android.sh all arm64-v8a,armeabi-v7a,x86_64

# 2. Distribute libs to each module's jniLibs (self-contained)
cd ../runanywhere-kotlin
for ABI in arm64-v8a armeabi-v7a x86_64; do
  # Root SDK: commons only
  mkdir -p src/androidMain/jniLibs/$ABI
  cp ../runanywhere-commons/dist/android/commons/$ABI/librac_commons.so src/androidMain/jniLibs/$ABI/
  cp ../runanywhere-commons/dist/android/jni/$ABI/librunanywhere_jni.so src/androidMain/jniLibs/$ABI/
  cp ../runanywhere-commons/dist/android/jni/$ABI/libc++_shared.so src/androidMain/jniLibs/$ABI/
  cp ../runanywhere-commons/dist/android/jni/$ABI/libomp.so src/androidMain/jniLibs/$ABI/

  # LlamaCPP module: backend only
  mkdir -p modules/runanywhere-core-llamacpp/src/androidMain/jniLibs/$ABI
  cp ../runanywhere-commons/dist/android/llamacpp/$ABI/librac_backend_llamacpp.so modules/runanywhere-core-llamacpp/src/androidMain/jniLibs/$ABI/
  cp ../runanywhere-commons/dist/android/llamacpp/$ABI/librac_backend_llamacpp_jni.so modules/runanywhere-core-llamacpp/src/androidMain/jniLibs/$ABI/

  # ONNX module: backend only
  mkdir -p modules/runanywhere-core-onnx/src/androidMain/jniLibs/$ABI
  cp ../runanywhere-commons/dist/android/onnx/$ABI/librac_backend_onnx.so modules/runanywhere-core-onnx/src/androidMain/jniLibs/$ABI/
  cp ../runanywhere-commons/dist/android/onnx/$ABI/librac_backend_onnx_jni.so modules/runanywhere-core-onnx/src/androidMain/jniLibs/$ABI/
  cp ../runanywhere-commons/dist/android/onnx/$ABI/libonnxruntime.so modules/runanywhere-core-onnx/src/androidMain/jniLibs/$ABI/
  cp ../runanywhere-commons/dist/android/onnx/$ABI/libsherpa-onnx-c-api.so modules/runanywhere-core-onnx/src/androidMain/jniLibs/$ABI/
  cp ../runanywhere-commons/dist/android/onnx/$ABI/libsherpa-onnx-cxx-api.so modules/runanywhere-core-onnx/src/androidMain/jniLibs/$ABI/
  cp ../runanywhere-commons/dist/android/onnx/$ABI/libsherpa-onnx-jni.so modules/runanywhere-core-onnx/src/androidMain/jniLibs/$ABI/
done

# 3. Publish
export SDK_VERSION=0.20.6
export MAVEN_CENTRAL_USERNAME="<USERNAME>"
export MAVEN_CENTRAL_PASSWORD="<PASSWORD>"

./gradlew clean publishAllPublicationsToMavenCentralRepository \
  -Prunanywhere.testLocal=true \
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
| Duplicate `.so` across AARs | Stale files in module `jniLibs/`. Delete and rebuild. Check `.gitignore` covers `src/androidMain/jniLibs/`. |
| Staging repo "No objects found" | Drop the stale repo and re-upload |
| OSSRH staging never auto-closes | Manually close/release via staging API |
| `Unresolved reference 'json'` (JVM) | `org.json:json:20240303` is in `jvmAndroidMain` dependencies |

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
