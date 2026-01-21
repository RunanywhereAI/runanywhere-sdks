# Kotlin SDK - Maven Central Publishing Guide

Quick reference for publishing RunAnywhere Kotlin SDK to Maven Central.

---

## Published Artifacts

| Artifact | Description |
|----------|-------------|
| `io.github.sanchitmonga22:runanywhere-sdk-android` | Core SDK (AAR with native libs) |
| `io.github.sanchitmonga22:runanywhere-llamacpp-android` | LLM backend (AAR with native libs) |
| `io.github.sanchitmonga22:runanywhere-onnx-android` | STT/TTS backend (AAR with native libs) |

---

## Quick Release (CI/CD)

1. Go to **GitHub Actions** → **Publish to Maven Central**
2. Click **Run workflow**
3. Enter version (e.g., `0.17.0`)
4. Click **Run workflow**
5. Monitor progress, then verify on [central.sonatype.com](https://central.sonatype.com/search?q=io.github.sanchitmonga22)

---

## Local Release

### 1. Setup (One-Time)

Copy credentials to `~/.gradle/gradle.properties`:
```properties
mavenCentral.username=YOUR_SONATYPE_USERNAME
mavenCentral.password=YOUR_SONATYPE_TOKEN
signing.gnupg.executable=gpg
signing.gnupg.useLegacyGpg=false
signing.gnupg.keyName=YOUR_GPG_KEY_ID
signing.gnupg.passphrase=YOUR_GPG_PASSPHRASE
```

### 2. Publish

```bash
cd sdks/sdk/runanywhere-kotlin

# Set version and publish
export SDK_VERSION=0.17.0
./gradlew clean publishAllPublicationsToMavenCentralRepository
./gradlew :modules:runanywhere-core-llamacpp:publishAllPublicationsToMavenCentralRepository
./gradlew :modules:runanywhere-core-onnx:publishAllPublicationsToMavenCentralRepository
```

### 3. Verify

Check [central.sonatype.com](https://central.sonatype.com/search?q=io.github.sanchitmonga22) (may take 30 min to sync).

---

## GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `MAVEN_CENTRAL_USERNAME` | Sonatype Central Portal token username |
| `MAVEN_CENTRAL_PASSWORD` | Sonatype Central Portal token |
| `GPG_KEY_ID` | Last 8 chars of GPG key fingerprint |
| `GPG_SIGNING_KEY` | Full armored GPG private key |
| `GPG_SIGNING_PASSWORD` | GPG key passphrase |

---

## Consumer Usage

```kotlin
// settings.gradle.kts
repositories {
    mavenCentral()
    maven { url = uri("https://jitpack.io") } // for transitive deps
}

// build.gradle.kts
dependencies {
    implementation("io.github.sanchitmonga22:runanywhere-sdk-android:0.17.0")
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp-android:0.17.0")
    implementation("io.github.sanchitmonga22:runanywhere-onnx-android:0.17.0")
}
```

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| GPG signature verification failed | Upload key to `keys.openpgp.org` AND verify email |
| 403 Forbidden | Verify namespace at central.sonatype.com |
| Missing native libs in AAR | Ensure `publishLibraryVariants("release")` in build.gradle.kts |

---

## Key URLs

- **Central Portal**: https://central.sonatype.com
- **Search Artifacts**: https://central.sonatype.com/search?q=io.github.sanchitmonga22
- **GPG Keyserver**: https://keys.openpgp.org
