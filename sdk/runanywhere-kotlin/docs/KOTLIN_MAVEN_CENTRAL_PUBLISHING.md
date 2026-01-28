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

## Quick Release (CI/CD)

1. Go to **GitHub Actions** → **Publish to Maven Central**
2. Click **Run workflow**
3. Enter version (e.g., `0.17.5`)
4. Click **Run workflow**
5. Monitor progress, then verify on [central.sonatype.com](https://central.sonatype.com/search?q=io.github.sanchitmonga22)

---

## Local Release

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

Add signing config to `~/.gradle/gradle.properties`:
```properties
signing.gnupg.executable=gpg
signing.gnupg.useLegacyGpg=false
signing.gnupg.keyName=YOUR_GPG_KEY_ID
signing.gnupg.passphrase=YOUR_GPG_PASSPHRASE
```

### 3. Download Native Libraries

**Important:** Native libraries must be downloaded before publishing. Use a version that has Android binaries released on GitHub.

```bash
cd sdk/runanywhere-kotlin

# Check available releases with Android binaries
curl -s "https://api.github.com/repos/RunanywhereAI/runanywhere-sdks/releases" | grep -E '"tag_name"|"name"' | head -20

# Download native libs (use version with Android binaries, e.g., 0.17.4)
./gradlew downloadJniLibs -Prunanywhere.testLocal=false -Prunanywhere.nativeLibVersion=0.17.4

# Verify download (should show 36 .so files across 3 ABIs)
ls -la src/androidMain/jniLibs/*/
```

### 4. Publish

```bash
cd sdk/runanywhere-kotlin

# Set environment variables
export SDK_VERSION=0.17.5
export MAVEN_CENTRAL_USERNAME="<SONATYPE_USERNAME>"
export MAVEN_CENTRAL_PASSWORD="<SONATYPE_PASSWORD>"
export ANDROID_HOME="$HOME/Library/Android/sdk"

# Publish all modules (single command publishes everything)
./gradlew publishAllPublicationsToMavenCentralRepository \
  -Prunanywhere.testLocal=false \
  -Prunanywhere.nativeLibVersion=0.17.4 \
  --no-daemon
```

### 5. Verify

1. Check [central.sonatype.com](https://central.sonatype.com/search?q=io.github.sanchitmonga22) (may take 30 min to sync)
2. Verify native libs are in the AAR:
   ```bash
   unzip -l build/outputs/aar/RunAnywhereKotlinSDK-release.aar | grep "\.so$"
   ```

---

## Native Library Notes

### Version Mapping
- SDK version and native lib version can differ
- Native libs are downloaded from GitHub releases
- Use `nativeLibVersion` flag to specify which release to use
- Check GitHub releases to find versions with Android binaries (`RACommons-android-*.zip`)

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

## Consumer Usage

```kotlin
// settings.gradle.kts
repositories {
    mavenCentral()
}

// build.gradle.kts
dependencies {
    implementation("io.github.sanchitmonga22:runanywhere-sdk-android:0.17.5")
    // Optional modules:
    // implementation("io.github.sanchitmonga22:runanywhere-llamacpp-android:0.17.5")
    // implementation("io.github.sanchitmonga22:runanywhere-onnx-android:0.17.5")
}
```

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| GPG signature verification failed | Upload key to `keys.openpgp.org` AND verify email |
| 403 Forbidden | Verify namespace at central.sonatype.com |
| Missing native libs in AAR | Run `downloadJniLibs` task with correct `nativeLibVersion` |
| SDK location not found | Create `local.properties` with `sdk.dir` or set `ANDROID_HOME` |
| JNI download fails | Check GitHub releases exist for that version with Android binaries |
| 16KB alignment issues | Rebuild native libs with `-Wl,-z,max-page-size=16384` linker flag |

---

## Key URLs

- **Central Portal**: https://central.sonatype.com
- **Search Artifacts**: https://central.sonatype.com/search?q=io.github.sanchitmonga22
- **GPG Keyserver**: https://keys.openpgp.org
- **GitHub Releases**: https://github.com/RunanywhereAI/runanywhere-sdks/releases
