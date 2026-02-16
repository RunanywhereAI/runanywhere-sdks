# Kotlin SDK - Maven Central Publishing Guide

Quick reference for publishing RunAnywhere Kotlin SDK to Maven Central.

---

## Published Artifacts

| Artifact | Description |
|----------|-------------|
| `io.github.sanchitmonga22:runanywhere-sdk-android` | Core SDK (AAR with native libs) |
| `io.github.sanchitmonga22:runanywhere-llamacpp-android` | LLM backend (AAR with native libs) |
| `io.github.sanchitmonga22:runanywhere-onnx-android` | ONNX/STT/TTS backend (AAR with native libs) |
| `io.github.sanchitmonga22:runanywhere-sdk` | KMP metadata module |
| `io.github.sanchitmonga22:runanywhere-llamacpp` | LlamaCPP KMP metadata |
| `io.github.sanchitmonga22:runanywhere-onnx` | ONNX KMP metadata |

---

## Publishing Architecture

Publishing uses the **Sonatype OSSRH Staging API** (compatibility layer on the new Central Portal).
The full lifecycle requires three explicit phases:

```
Upload → Close (triggers validation) → Release (promotes to Maven Central)
```

**Key files involved:**

| File | Purpose |
|------|---------|
| `build.gradle.kts` | Main SDK publishing & signing config, `downloadJniLibs` task |
| `modules/runanywhere-core-llamacpp/build.gradle.kts` | LlamaCPP module publishing config |
| `modules/runanywhere-core-onnx/build.gradle.kts` | ONNX module publishing config |
| `gradle/maven-central-publish.gradle.kts` | Shared publishing configuration (reference only) |
| `.github/workflows/publish-maven-central.yml` | CI/CD workflow |
| `~/.gradle/gradle.properties` | Local credentials & signing config |

---

## Quick Release (CI/CD)

1. Go to **GitHub Actions** → **Publish to Maven Central**
2. Click **Run workflow**
3. Enter version (e.g., `0.20.2`)
4. Click **Run workflow**
5. Monitor progress, then verify on [central.sonatype.com](https://central.sonatype.com/search?q=io.github.sanchitmonga22)

> **Important:** The CI workflow currently only uploads to the OSSRH staging repo.
> The staging repo is auto-closed by Sonatype after ~10 minutes of inactivity,
> then auto-released if validation passes. If this doesn't happen, see
> [Manual Staging Lifecycle](#manual-staging-lifecycle-closereleaseossrh) below.

---

## Local Release (Full Process)

### 1. Prerequisites

#### Android SDK
Create `local.properties` in the SDK root if it doesn't exist:
```properties
sdk.dir=/Users/YOUR_USERNAME/Library/Android/sdk
```

Or set the environment variable:
```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
```

#### GPG Key Import
If you have a base64-encoded GPG key, import it:
```bash
echo "<GPG_SIGNING_KEY_BASE64>" | base64 -d | gpg --batch --import

# Verify import
gpg --list-secret-keys --keyid-format LONG
```

### 2. Setup Credentials (One-Time)

Add signing + Maven Central config to `~/.gradle/gradle.properties`:
```properties
# Maven Central (Sonatype Central Portal)
mavenCentral.username=YOUR_SONATYPE_USERNAME
mavenCentral.password=YOUR_SONATYPE_PASSWORD

# GPG Signing - using local gpg keyring
signing.gnupg.executable=gpg
signing.gnupg.useLegacyGpg=false
signing.gnupg.keyName=YOUR_GPG_KEY_ID
signing.gnupg.passphrase=YOUR_GPG_PASSPHRASE
```

> **Avoid duplicates.** Each property should appear exactly once in the file.

### 3. Clean & Download Native Libraries

**Important:** Native libraries must be downloaded before publishing. Use a version that
has per-ABI Android binaries released on GitHub (e.g., `v0.17.5`).

```bash
cd sdk/runanywhere-kotlin

# Clean any existing partial JNI libs
rm -rf src/androidMain/jniLibs

# Check available releases with Android binaries
curl -s "https://api.github.com/repos/RunanywhereAI/runanywhere-sdks/releases" \
  | grep -E '"tag_name"|"name"' | head -20

# Download native libs for all 3 ABIs (arm64-v8a, armeabi-v7a, x86_64)
./gradlew downloadJniLibs \
  -Prunanywhere.testLocal=false \
  -Prunanywhere.nativeLibVersion=0.17.5

# Verify download (should show 36 .so files: 12 per ABI x 3 ABIs)
find src/androidMain/jniLibs -name "*.so" | wc -l
```

The download task fetches from GitHub releases with per-ABI naming convention:
```
https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v{version}/
  RACommons-android-{abi}-v{version}.zip
  RABackendLLAMACPP-android-{abi}-v{version}.zip
  RABackendONNX-android-{abi}-v{version}.zip
```

### 4. Upload Artifacts to OSSRH Staging

```bash
cd sdk/runanywhere-kotlin

# Set environment variables
export SDK_VERSION=0.20.2
export MAVEN_CENTRAL_USERNAME="<SONATYPE_USERNAME>"
export MAVEN_CENTRAL_PASSWORD="<SONATYPE_PASSWORD>"
export ANDROID_HOME="$HOME/Library/Android/sdk"

# Publish all modules (uploads to OSSRH staging repository)
./gradlew publishAllPublicationsToMavenCentralRepository \
  -Prunanywhere.testLocal=false \
  -Prunanywhere.nativeLibVersion=0.17.5 \
  --no-daemon
```

This uploads artifacts for all 3 modules (main SDK, LlamaCPP, ONNX) to the OSSRH
staging repo. JVM publications are automatically skipped (only Android release +
KMP metadata are published).

### 5. Close & Release the Staging Repository

**Critical:** After Gradle uploads artifacts, the OSSRH staging repo must be explicitly
closed (triggers validation) and then released (promotes to Maven Central). The Gradle
`maven-publish` plugin does **not** do this automatically.

The staging repo may auto-close after ~10 min of inactivity, but it's more reliable
to do this explicitly:

```bash
# Check the staging repo exists and is "open"
curl -s -u "$MAVEN_CENTRAL_USERNAME:$MAVEN_CENTRAL_PASSWORD" \
  "https://ossrh-staging-api.central.sonatype.com/service/local/staging/profile_repositories/io.github.sanchitmonga22" \
  -H "Accept: application/json"
# Look for: "type": "open"

# Close the staging repo (triggers GPG/POM/sources validation)
curl -X POST -u "$MAVEN_CENTRAL_USERNAME:$MAVEN_CENTRAL_PASSWORD" \
  "https://ossrh-staging-api.central.sonatype.com/service/local/staging/bulk/close" \
  -H "Content-Type: application/json" \
  -d '{"data":{"stagedRepositoryIds":["io.github.sanchitmonga22--default-repository"],"description":"Release SDK","autoDropAfterRelease":true}}'
# Wait ~30 seconds for close to complete

# Verify repo is now "closed" (validation passed)
curl -s -u "$MAVEN_CENTRAL_USERNAME:$MAVEN_CENTRAL_PASSWORD" \
  "https://ossrh-staging-api.central.sonatype.com/service/local/staging/profile_repositories/io.github.sanchitmonga22" \
  -H "Accept: application/json"
# Look for: "type": "closed"

# Release to Maven Central
curl -X POST -u "$MAVEN_CENTRAL_USERNAME:$MAVEN_CENTRAL_PASSWORD" \
  "https://ossrh-staging-api.central.sonatype.com/service/local/staging/bulk/promote" \
  -H "Content-Type: application/json" \
  -d '{"data":{"stagedRepositoryIds":["io.github.sanchitmonga22--default-repository"],"description":"Release SDK","autoDropAfterRelease":true}}'

# Verify repo is now "released"
curl -s -u "$MAVEN_CENTRAL_USERNAME:$MAVEN_CENTRAL_PASSWORD" \
  "https://ossrh-staging-api.central.sonatype.com/service/local/staging/profile_repositories/io.github.sanchitmonga22" \
  -H "Accept: application/json"
# Look for: "type": "released" or empty data (repo auto-dropped)
```

### 6. Verify on Maven Central

Artifacts take **10-30 minutes** to propagate after release.

```bash
# Check if artifacts are available
for artifact in runanywhere-sdk runanywhere-sdk-android runanywhere-llamacpp-android runanywhere-onnx-android; do
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://repo1.maven.org/maven2/io/github/sanchitmonga22/$artifact/0.20.2/$artifact-0.20.2.pom")
  echo "$artifact: HTTP $http_code"
done

# Verify native libs are in the AAR
unzip -l build/outputs/aar/RunAnywhereKotlinSDK-release.aar | grep "\.so$"
```

Also check:
- [Central Portal Deployments](https://central.sonatype.com/publishing/deployments) (should show as PUBLISHED)
- [Artifact Search](https://central.sonatype.com/search?q=io.github.sanchitmonga22)

---

## Alternative: Central Portal Bundle Upload

If the OSSRH staging API has issues, you can upload a bundle directly via the
Central Portal API. This bypasses the staging repo entirely.

### 1. Publish to Maven Local first

```bash
export SDK_VERSION=0.20.2
export ANDROID_HOME="$HOME/Library/Android/sdk"

./gradlew publishToMavenLocal \
  -Prunanywhere.testLocal=false \
  -Prunanywhere.nativeLibVersion=0.17.5 \
  --no-daemon
```

### 2. Generate checksums

```bash
cd ~/.m2/repository/io/github/sanchitmonga22

find . -path "*$SDK_VERSION*" -type f \
  \( -name "*.jar" -o -name "*.aar" -o -name "*.pom" -o -name "*.module" -o -name "*.json" \) \
  ! -name "*.asc" | while read f; do
  md5sum "$f" | awk '{print $1}' > "${f}.md5"
  sha1sum "$f" | awk '{print $1}' > "${f}.sha1"
  sha256sum "$f" | awk '{print $1}' > "${f}.sha256"
  sha512sum "$f" | awk '{print $1}' > "${f}.sha512"
done
```

### 3. Create bundle ZIP

```bash
cd ~/.m2/repository
zip -r /tmp/runanywhere-bundle-$SDK_VERSION.zip \
  io/github/sanchitmonga22/*/0.20.2/ \
  -x "*/maven-metadata*"
```

### 4. Upload to Central Portal

```bash
# AUTOMATIC publishing (validates + publishes automatically)
curl -X POST \
  "https://central.sonatype.com/api/v1/publisher/upload?publishingType=AUTOMATIC&name=runanywhere-sdk-$SDK_VERSION" \
  -H "Authorization: Bearer $(echo -n '<USERNAME>:<PASSWORD>' | base64)" \
  -F "bundle=@/tmp/runanywhere-bundle-$SDK_VERSION.zip"

# Returns a deployment ID, e.g.: ba65d4cd-644a-4f30-9790-4e40b7dc28d3

# Check status
curl -s \
  "https://central.sonatype.com/api/v1/publisher/status?id=<DEPLOYMENT_ID>" \
  -H "Authorization: Bearer $(echo -n '<USERNAME>:<PASSWORD>' | base64)"
```

---

## Manual Staging Lifecycle (Close/Release/Drop)

### OSSRH Staging API Reference

All endpoints use basic auth with your Sonatype Central Portal token credentials.
Base URL: `https://ossrh-staging-api.central.sonatype.com`

| Action | Endpoint | Description |
|--------|----------|-------------|
| List staging repos | `GET /service/local/staging/profile_repositories/io.github.sanchitmonga22` | Shows open/closed/released repos |
| Close repo | `POST /service/local/staging/bulk/close` | Triggers validation (GPG, POM, sources) |
| Release repo | `POST /service/local/staging/bulk/promote` | Promotes to Maven Central |
| Drop repo | `POST /service/local/staging/bulk/drop` | Deletes a staging repo (use to clean up) |

**Staging repo lifecycle:**
```
open → close (validation) → closed → release (promote) → released → auto-dropped
```

### Drop a stale staging repo

If a previous publish failed or left artifacts behind, drop the stale repo first:

```bash
curl -X POST -u "$MAVEN_CENTRAL_USERNAME:$MAVEN_CENTRAL_PASSWORD" \
  "https://ossrh-staging-api.central.sonatype.com/service/local/staging/bulk/drop" \
  -H "Content-Type: application/json" \
  -d '{"data":{"stagedRepositoryIds":["io.github.sanchitmonga22--default-repository"],"description":"Drop stale","autoDropAfterRelease":true}}'
```

Then re-upload with `publishAllPublicationsToMavenCentralRepository`.

---

## Native Library Notes

### Version Mapping
- SDK version and native lib version can differ
- Native libs are downloaded from GitHub releases
- Use `nativeLibVersion` flag to specify which release to use
- Check GitHub releases to find versions with Android per-ABI binaries (`RACommons-android-{abi}-v*.zip`)
- As of Feb 2026, `v0.17.5` is the latest release with per-ABI Android binaries

### Expected native libraries per ABI (12 total)

| Library | Module | Description |
|---------|--------|-------------|
| `libc++_shared.so` | Shared | C++ STL |
| `libomp.so` | Shared | OpenMP |
| `librac_commons.so` | Commons | RAC infrastructure |
| `librunanywhere_jni.so` | Commons | JNI bridge |
| `librac_backend_llamacpp.so` | LlamaCPP | LLM inference |
| `librac_backend_llamacpp_jni.so` | LlamaCPP | LLM JNI bridge |
| `librac_backend_onnx.so` | ONNX | ONNX backend |
| `librac_backend_onnx_jni.so` | ONNX | ONNX JNI bridge |
| `libonnxruntime.so` | ONNX | ONNX Runtime |
| `libsherpa-onnx-c-api.so` | ONNX | Sherpa C API |
| `libsherpa-onnx-cxx-api.so` | ONNX | Sherpa C++ API |
| `libsherpa-onnx-jni.so` | ONNX | Sherpa JNI |

### 16KB Page Alignment (Android 15+)
Verify native libraries support 16KB page sizes:
```bash
for so in src/androidMain/jniLibs/arm64-v8a/*.so; do
  name=$(basename "$so")
  alignment=$(objdump -p "$so" 2>/dev/null | grep -A1 "LOAD" | grep -oE "align 2\*\*[0-9]+" | head -1 | grep -oE "[0-9]+$")
  page_size=$((2**alignment))
  if [ "$page_size" -ge 16384 ]; then
    echo "✅ $name: 16KB aligned"
  else
    echo "❌ $name: NOT 16KB aligned ($page_size bytes)"
  fi
done
```

---

## GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `MAVEN_CENTRAL_USERNAME` | Sonatype Central Portal token username |
| `MAVEN_CENTRAL_PASSWORD` | Sonatype Central Portal token |
| `GPG_KEY_ID` | Last 16 chars of GPG key fingerprint (e.g., `CC377A9928C7BB18`) |
| `GPG_SIGNING_KEY` | Base64-encoded full armored GPG private key |
| `GPG_SIGNING_PASSWORD` | GPG key passphrase |

### Exporting GPG Key for CI
```bash
# Export and base64 encode for GitHub secrets
gpg --armor --export-secret-keys YOUR_KEY_ID | base64
```

---

## CI/CD Workflow Reference

**File:** `.github/workflows/publish-maven-central.yml`

The CI workflow performs these steps:
1. Checkout code
2. Setup JDK 17, Gradle 8.13, Android SDK (platform 35, NDK 27)
3. Download native libraries via `downloadJniLibs` task
4. Import GPG key from `GPG_SIGNING_KEY` secret
5. Configure `~/.gradle/gradle.properties` with signing config
6. Publish main SDK: `publishAllPublicationsToMavenCentralRepository`
7. Publish LlamaCPP module: `:modules:runanywhere-core-llamacpp:publishAllPublicationsToMavenCentralRepository`
8. Publish ONNX module: `:modules:runanywhere-core-onnx:publishAllPublicationsToMavenCentralRepository`

> **Note:** The CI uploads all modules in one Gradle invocation via step 6 (the root
> `publishAllPublicationsToMavenCentralRepository` task publishes submodules too).
> Steps 7-8 are kept as fallback in case step 6 doesn't pick up submodules.

> **Known issue:** The CI does not explicitly close/release the OSSRH staging repo.
> It relies on Sonatype's auto-close (~10 min after last upload). If a publish appears
> stuck, manually close/release via the staging API commands in this guide.

---

## Consumer Usage

```kotlin
// settings.gradle.kts
repositories {
    mavenCentral()
}

// build.gradle.kts
dependencies {
    implementation("io.github.sanchitmonga22:runanywhere-sdk-android:0.20.2")
    // Optional modules:
    // implementation("io.github.sanchitmonga22:runanywhere-llamacpp-android:0.20.2")
    // implementation("io.github.sanchitmonga22:runanywhere-onnx-android:0.20.2")
}
```

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| GPG signature verification failed | Upload key to `keys.openpgp.org` AND verify email |
| 403 Forbidden | Verify namespace at central.sonatype.com |
| Missing native libs in AAR | Clean `src/androidMain/jniLibs/` and re-run `downloadJniLibs` with correct `nativeLibVersion` |
| SDK location not found | Create `local.properties` with `sdk.dir` or set `ANDROID_HOME` |
| JNI download fails | Check GitHub releases exist for that version with per-ABI Android binaries |
| 16KB alignment issues | Rebuild native libs with `-Wl,-z,max-page-size=16384` linker flag |
| `Unresolved reference 'json'` (JVM) | Add `implementation("org.json:json:20240303")` to `jvmAndroidMain` dependencies |
| Staging repo "No objects found" | Drop the stale repo and re-upload (see staging lifecycle section) |
| Deploy shows on portal but 404 on Maven Central | Wait 10-30 min for sync; check staging repo was actually released |
| Duplicated entries in `gradle.properties` | Clean up `~/.gradle/gradle.properties` to have each property exactly once |
| OSSRH staging never auto-closes | Manually close/release via the staging API commands in this guide |

---

## Version History

| Version | Date | Native Libs | Notes |
|---------|------|-------------|-------|
| 0.20.2 | 2026-02-16 | v0.17.5 (36 .so, 3 ABIs) | Full native libs, explicit staging close/release |
| 0.20.1 | 2026-02-15 | arm64-v8a only (4 .so) | Partial native libs (commons only) |
| 0.20.0 | 2026-02-15 | arm64-v8a only (4 .so) | Partial native libs |
| 0.16.1 | 2026-01-18 | Bundle upload | First stable release via Central Portal |
| 0.16.0 | 2026-01-17 | Bundle upload | Initial release |

---

## Key URLs

- **Central Portal**: https://central.sonatype.com
- **Deployments Page**: https://central.sonatype.com/publishing/deployments
- **Search Artifacts**: https://central.sonatype.com/search?q=io.github.sanchitmonga22
- **GPG Keyserver**: https://keys.openpgp.org
- **GitHub Releases**: https://github.com/RunanywhereAI/runanywhere-sdks/releases
- **OSSRH Staging API**: https://ossrh-staging-api.central.sonatype.com
- **Maven Central Repo**: https://repo1.maven.org/maven2/io/github/sanchitmonga22/
