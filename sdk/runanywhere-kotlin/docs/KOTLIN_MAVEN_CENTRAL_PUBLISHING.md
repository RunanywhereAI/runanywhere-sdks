# Kotlin SDK - Maven Central Publishing Guide

## Overview

This guide covers publishing the RunAnywhere Kotlin SDK to Maven Central via Sonatype Central Portal.

**Published Artifacts (9 total):**

| Artifact | Type | Contains Native Libs |
|----------|------|---------------------|
| `runanywhere-sdk` | KMP metadata | No |
| `runanywhere-sdk-jvm` | JAR | No |
| `runanywhere-sdk-android` | **AAR** | **Yes** |
| `runanywhere-llamacpp` | KMP metadata | No |
| `runanywhere-llamacpp-jvm` | JAR | No |
| `runanywhere-llamacpp-android` | **AAR** | **Yes** |
| `runanywhere-onnx` | KMP metadata | No |
| `runanywhere-onnx-jvm` | JAR | No |
| `runanywhere-onnx-android` | **AAR** | **Yes** |

---

## Critical: Android AAR Publishing with Native Libraries

### The Problem

By default, Kotlin Multiplatform with `androidTarget()` does **NOT** publish Android AARs. It only publishes JVM JARs, which don't contain native `.so` libraries.

### The Solution

You **MUST** add these two configurations to each `androidTarget` block:

```kotlin
kotlin {
    androidTarget {
        // 1. Enable Android AAR publishing
        publishLibraryVariants("release")

        // 2. Set correct artifact ID for Android publication
        mavenPublication {
            artifactId = "your-artifact-android"
        }

        compilations.all {
            // ... compiler options
        }
    }
}
```

### Where to Add This

**Main SDK** (`build.gradle.kts`):
```kotlin
androidTarget {
    publishLibraryVariants("release")
    mavenPublication {
        artifactId = "runanywhere-sdk-android"
    }
    // ...
}
```

**LlamaCPP Module** (`modules/runanywhere-core-llamacpp/build.gradle.kts`):
```kotlin
androidTarget {
    publishLibraryVariants("release")
    mavenPublication {
        artifactId = "runanywhere-llamacpp-android"
    }
    // ...
}
```

**ONNX Module** (`modules/runanywhere-core-onnx/build.gradle.kts`):
```kotlin
androidTarget {
    publishLibraryVariants("release")
    mavenPublication {
        artifactId = "runanywhere-onnx-android"
    }
    // ...
}
```

### Verify Native Libraries Are Included

After building, check the AAR contents:
```bash
unzip -l ~/.m2/repository/io/github/sanchitmonga22/runanywhere-sdk-android/VERSION/runanywhere-sdk-android-VERSION.aar | grep ".so"
```

Expected output:
```
jni/arm64-v8a/libc++_shared.so
jni/arm64-v8a/libomp.so
jni/arm64-v8a/librac_commons.so
jni/arm64-v8a/librunanywhere_jni.so
```

---

## Prerequisites

### 1. Sonatype Central Portal Account
1. Go to https://central.sonatype.com
2. Sign up / Log in
3. Verify your namespace: `io.github.sanchitmonga22`

### 2. Generate API Token
1. Central Portal → Settings → Generate User Token
2. Save the username and password

### 3. GPG Key Setup

```bash
# Install GPG
brew install gnupg

# Generate key (RSA 3072+)
gpg --full-generate-key

# List keys to get fingerprint
gpg --list-keys --keyid-format LONG
```

### 4. Upload GPG Key to Keyservers

**Critical: Upload to keys.openpgp.org with email verification**

```bash
# Export public key
gpg --armor --export YOUR_KEY_FINGERPRINT > public-key.asc

# Upload via API
curl -X POST "https://keys.openpgp.org/vks/v1/upload" \
  -H "Content-Type: application/json" \
  -d "{\"keytext\": $(cat public-key.asc | jq -Rs .)}"

# Request email verification (use token from response)
curl -X POST "https://keys.openpgp.org/vks/v1/request-verify" \
  -H "Content-Type: application/json" \
  -d '{"token": "YOUR_TOKEN", "addresses": ["your@email.com"]}'
```

Then **click the verification link** in your email.

Also upload to keyserver.ubuntu.com:
```bash
gpg --keyserver keyserver.ubuntu.com --send-keys YOUR_KEY_FINGERPRINT
```

---

## Local Publishing Setup

### Configure `~/.gradle/gradle.properties`

```properties
# Maven Central credentials (from Sonatype token)
mavenCentral.username=YOUR_TOKEN_USERNAME
mavenCentral.password=YOUR_TOKEN_PASSWORD

# GPG signing
signing.gnupg.executable=gpg
signing.gnupg.useLegacyGpg=false
signing.gnupg.keyName=YOUR_KEY_ID
signing.gnupg.passphrase=YOUR_GPG_PASSPHRASE
```

### Configure GPG for Non-Interactive Signing

```bash
# ~/.gnupg/gpg.conf
echo "use-agent" >> ~/.gnupg/gpg.conf

# ~/.gnupg/gpg-agent.conf
echo "pinentry-mode loopback" >> ~/.gnupg/gpg-agent.conf
echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf

# Restart agent
gpgconf --kill gpg-agent
```

---

## Publishing Steps

### Step 1: Build and Publish Locally

```bash
cd sdks/sdk/runanywhere-kotlin

# Clean and publish with specific version
SDK_VERSION=0.16.1 ./gradlew clean publishToMavenLocal
```

### Step 2: Verify Artifacts

```bash
# Check all artifacts
ls ~/.m2/repository/io/github/sanchitmonga22/

# Verify Android AARs have native libs
unzip -l ~/.m2/repository/io/github/sanchitmonga22/runanywhere-sdk-android/VERSION/*.aar | grep ".so"
```

### Step 3: Create Maven Central Bundle

```bash
# Create bundle directory
rm -rf /tmp/maven-bundle
mkdir -p /tmp/maven-bundle
cd ~/.m2/repository/io/github/sanchitmonga22

# Copy all 9 artifacts
for artifact in runanywhere-sdk runanywhere-sdk-jvm runanywhere-sdk-android \
                runanywhere-llamacpp runanywhere-llamacpp-jvm runanywhere-llamacpp-android \
                runanywhere-onnx runanywhere-onnx-jvm runanywhere-onnx-android; do
  mkdir -p /tmp/maven-bundle/io/github/sanchitmonga22/$artifact/VERSION
  find "$artifact/VERSION" -type f ! -name "maven-metadata-local.xml" \
    -exec cp {} /tmp/maven-bundle/io/github/sanchitmonga22/$artifact/VERSION/ \;
done

# Generate checksums
cd /tmp/maven-bundle
find . -type f ! -name "*.md5" ! -name "*.sha1" | while read file; do
  md5 -q "$file" > "$file.md5"
  shasum -a 1 "$file" | cut -d' ' -f1 > "$file.sha1"
done

# Create Javadoc JARs for JVM and Android artifacts
mkdir -p /tmp/empty-javadoc
echo "No Javadoc - Kotlin Multiplatform library" > /tmp/empty-javadoc/README.txt

for artifact in runanywhere-sdk-jvm runanywhere-llamacpp-jvm runanywhere-onnx-jvm \
                runanywhere-sdk-android runanywhere-llamacpp-android runanywhere-onnx-android; do
  dir="io/github/sanchitmonga22/$artifact/VERSION"
  jar_name="${artifact}-VERSION-javadoc.jar"

  cd /tmp/empty-javadoc && jar cf "/tmp/maven-bundle/$dir/$jar_name" README.txt && cd /tmp/maven-bundle

  # Sign and checksum
  gpg --batch --yes --pinentry-mode loopback -ab "$dir/$jar_name"
  md5 -q "$dir/$jar_name" > "$dir/$jar_name.md5"
  shasum -a 1 "$dir/$jar_name" | cut -d' ' -f1 > "$dir/$jar_name.sha1"
  md5 -q "$dir/$jar_name.asc" > "$dir/$jar_name.asc.md5"
  shasum -a 1 "$dir/$jar_name.asc" | cut -d' ' -f1 > "$dir/$jar_name.asc.sha1"
done

# Create zip bundle
zip -r /tmp/runanywhere-bundle-VERSION.zip io
```

### Step 4: Upload to Central Portal

```bash
AUTH=$(echo -n "USERNAME:PASSWORD" | base64)
curl -X POST "https://central.sonatype.com/api/v1/publisher/upload" \
  -H "Authorization: Bearer $AUTH" \
  -F "bundle=@/tmp/runanywhere-bundle-VERSION.zip"
```

### Step 5: Publish on Central Portal

1. Go to https://central.sonatype.com → Deployments
2. Wait for validation to pass
3. Click **Publish**

---

## Troubleshooting

### "Could not find a public key by the key fingerprint"
- **Cause**: GPG key not on keyservers or not verified
- **Fix**: Upload to `keys.openpgp.org` AND click the email verification link
- **Note**: Propagation can take up to 24 hours

### "Javadocs must be provided but not found"
- **Cause**: Maven Central requires `-javadoc.jar` for all artifacts
- **Fix**: Create empty javadoc JARs (see bundle creation above)

### "Missing md5/sha1 checksum for file"
- **Cause**: Manual bundle missing checksums
- **Fix**: Generate `.md5` and `.sha1` for every file including `.asc` signatures

### Android AAR missing native libraries
- **Cause**: `publishLibraryVariants("release")` not configured
- **Fix**: Add to each `androidTarget` block (see Critical section above)

### GPG "Inappropriate ioctl for device"
- **Cause**: GPG trying to use interactive pinentry
- **Fix**: Configure `gpg-agent.conf` with `pinentry-mode loopback`

---

## Consuming Published Artifacts

### Android (with native libraries)

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}

// build.gradle.kts
dependencies {
    // Main SDK (required)
    implementation("io.github.sanchitmonga22:runanywhere-sdk-android:0.16.1")

    // LlamaCPP backend (for LLM text generation)
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp-android:0.16.1")

    // ONNX backend (for STT/TTS)
    implementation("io.github.sanchitmonga22:runanywhere-onnx-android:0.16.1")
}
```

### JVM (without native libraries)

```kotlin
dependencies {
    implementation("io.github.sanchitmonga22:runanywhere-sdk-jvm:0.16.1")
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp-jvm:0.16.1")
    implementation("io.github.sanchitmonga22:runanywhere-onnx-jvm:0.16.1")
}
```

---

## Key URLs

- **Central Portal**: https://central.sonatype.com
- **Published Artifacts**: https://central.sonatype.com/search?q=io.github.sanchitmonga22
- **keys.openpgp.org**: https://keys.openpgp.org
- **keyserver.ubuntu.com**: https://keyserver.ubuntu.com

---

## Native Libraries Included

### runanywhere-sdk-android
- `libc++_shared.so` - C++ standard library
- `libomp.so` - OpenMP runtime
- `librac_commons.so` - RunAnywhere commons
- `librunanywhere_jni.so` - JNI bindings

### runanywhere-llamacpp-android
- `librac_backend_llamacpp.so` - LlamaCPP backend
- `librac_backend_llamacpp_jni.so` - JNI bindings

### runanywhere-onnx-android
- `libonnxruntime.so` - ONNX Runtime
- `libsherpa-onnx-c-api.so` - Sherpa ONNX C API
- `libsherpa-onnx-cxx-api.so` - Sherpa ONNX C++ API
- `libsherpa-onnx-jni.so` - Sherpa ONNX JNI
- `librac_backend_onnx.so` - ONNX backend
- `librac_backend_onnx_jni.so` - JNI bindings

---

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 0.16.1 | Jan 2026 | First complete release with Android AARs and native libraries |
| 0.16.0 | Jan 2026 | Initial release (JVM only, missing Android AARs) |
