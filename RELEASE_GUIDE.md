# RunAnywhere SDKs - Release Guide

**Version:** 1.0.0
**Last Updated:** October 9, 2025
**Target Audience:** Release Managers, Maintainers

This guide provides step-by-step instructions for releasing both iOS and Android SDKs to GitHub and publishing packages to their respective package managers.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Release Checklist](#pre-release-checklist)
3. [iOS SDK Release Process](#ios-sdk-release-process)
4. [Android SDK Release Process](#android-sdk-release-process)
5. [GitHub Release Creation](#github-release-creation)
6. [Post-Release Tasks](#post-release-tasks)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### General Requirements
- [ ] Git repository access with push permissions
- [ ] GitHub account with release permissions
- [ ] Changelog prepared for the release
- [ ] All CI/CD tests passing on main branch
- [ ] Code freeze implemented (no new commits during release)

### iOS SDK Requirements
- [ ] macOS with Xcode 15.0+ installed
- [ ] Swift 5.9+ toolchain
- [ ] CocoaPods installed: `sudo gem install cocoapods`
- [ ] Access to CocoaPods trunk: `pod trunk register your@email.com`
- [ ] Apple Developer account (for code signing, if needed)

### Android SDK Requirements
- [ ] JDK 17 installed and configured
- [ ] Gradle 8.11.1+
- [ ] Kotlin 2.1.21+
- [ ] Android Studio (optional, for verification)
- [ ] GPG key for signing artifacts
- [ ] Sonatype OSSRH account (for Maven Central publishing)
- [ ] GitHub Personal Access Token (for GitHub Packages)

---

## Pre-Release Checklist

### 1. Version Number Selection

Follow [Semantic Versioning 2.0.0](https://semver.org/):
- **MAJOR.MINOR.PATCH** (e.g., `1.2.3`)
- **MAJOR**: Breaking API changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

**Example versions:**
- First stable release: `1.0.0`
- Feature addition: `1.1.0`
- Bug fix: `1.0.1`
- Breaking change: `2.0.0`

### 2. Update Version Numbers

#### iOS SDK
```bash
# Update version in Package.swift
# File: sdk/runanywhere-swift/Package.swift
# No version field needed (uses Git tags)

# Update version in Podspec
# File: RunAnywhere.podspec
s.version = "0.14.0"  # Update this line
```

#### Android SDK
```bash
# Update version in build.gradle.kts
# File: sdk/runanywhere-kotlin/build.gradle.kts
group = "com.runanywhere.sdk"
version = "0.2.0"  # Update this line
```

### 3. Update Documentation

```bash
# Update README.md with new version numbers
# Update CHANGELOG.md with release notes
# Update any version-specific documentation
```

### 4. Run Full Test Suite

```bash
# iOS
cd sdk/runanywhere-swift
swift test

# Android
cd sdk/runanywhere-kotlin
./scripts/sdk.sh test
```

### 5. Build and Verify Artifacts

```bash
# iOS
cd sdk/runanywhere-swift
swift build --configuration release

# Android
cd sdk/runanywhere-kotlin
./scripts/sdk.sh build-all --clean
```

---

## iOS SDK Release Process

### Step 1: Prepare iOS Release

```bash
# Navigate to iOS SDK directory
cd sdk/runanywhere-swift

# Ensure clean working directory
git status
# Should show no uncommitted changes

# Update version in Podspec
vim RunAnywhere.podspec
# Set: s.version = "0.14.0"

# Commit version bump
git add RunAnywhere.podspec
git commit -m "chore: bump iOS SDK version to 0.14.0"
git push origin main
```

### Step 2: Create Git Tag for iOS

```bash
# Create annotated tag (recommended)
git tag -a ios/v0.14.0 -m "iOS SDK v0.14.0

Release highlights:
- Feature: Add streaming generation support
- Feature: Model unloading API
- Fix: Memory leak in model loading
- Performance: 20% faster token generation

Full changelog: https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/CHANGELOG.md#0140"

# Push tag to GitHub
git push origin ios/v0.14.0
```

### Step 3: Verify Swift Package Manager

```bash
# Test SPM resolution (from a test project)
mkdir -p /tmp/test-ios-sdk
cd /tmp/test-ios-sdk

# Create Package.swift
cat > Package.swift << 'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TestSDK",
    platforms: [.iOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", exact: "0.14.0")
    ],
    targets: [
        .target(name: "TestSDK", dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-sdks")
        ])
    ]
)
EOF

# Resolve dependencies
swift package resolve

# If successful, SPM integration is working
```

### Step 4: Publish to CocoaPods (Optional)

```bash
# Navigate to SDK directory
cd sdk/runanywhere-swift

# Validate Podspec
pod spec lint RunAnywhere.podspec --allow-warnings

# If validation passes, publish
pod trunk push RunAnywhere.podspec --allow-warnings

# Verify publication
pod search RunAnywhere
```

**Note:** CocoaPods publication is optional if you're primarily using SPM.

### Step 5: Build XCFramework (for manual distribution)

```bash
# Build XCFramework for all platforms
cd sdk/runanywhere-swift

# Create build directory
mkdir -p build/xcframework

# Build for iOS devices
xcodebuild archive \
  -scheme RunAnywhere \
  -destination "generic/platform=iOS" \
  -archivePath "build/RunAnywhere-iOS" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build for iOS Simulator
xcodebuild archive \
  -scheme RunAnywhere \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "build/RunAnywhere-Simulator" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build for macOS
xcodebuild archive \
  -scheme RunAnywhere \
  -destination "generic/platform=macOS" \
  -archivePath "build/RunAnywhere-macOS" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Create XCFramework
xcodebuild -create-xcframework \
  -archive build/RunAnywhere-iOS.xcarchive -framework RunAnywhere.framework \
  -archive build/RunAnywhere-Simulator.xcarchive -framework RunAnywhere.framework \
  -archive build/RunAnywhere-macOS.xcarchive -framework RunAnywhere.framework \
  -output build/xcframework/RunAnywhere.xcframework

# Zip XCFramework for distribution
cd build/xcframework
zip -r RunAnywhere-0.14.0.xcframework.zip RunAnywhere.xcframework
```

**XCFramework will be at:** `build/xcframework/RunAnywhere-0.14.0.xcframework.zip`

---

## Android SDK Release Process

### Step 1: Prepare Android Release

```bash
# Navigate to Android SDK directory
cd sdk/runanywhere-kotlin

# Ensure clean working directory
git status

# Update version in build.gradle.kts
vim build.gradle.kts
# Set: version = "0.2.0"

# Update version in LlamaCpp module
vim modules/runanywhere-llm-llamacpp/build.gradle.kts
# Set: version = "0.2.0"

# Commit version bump
git add build.gradle.kts modules/runanywhere-llm-llamacpp/build.gradle.kts
git commit -m "chore: bump Android SDK version to 0.2.0"
git push origin main
```

### Step 2: Build All Targets

```bash
# Clean build all targets
./scripts/sdk.sh build-all --clean

# Verify artifacts created
ls -lh build/libs/
# Should see: RunAnywhereKotlinSDK-jvm-0.2.0.jar

ls -lh build/outputs/aar/
# Should see: RunAnywhereKotlinSDK-debug.aar
#             RunAnywhereKotlinSDK-release.aar
```

### Step 3: Run Full Test Suite

```bash
# Run all tests
./scripts/sdk.sh test

# Check test results
# All tests should pass before proceeding
```

### Step 4: Publish to Local Maven (for verification)

```bash
# Publish to local Maven repository
./scripts/sdk.sh publish

# Verify publication
ls -lh ~/.m2/repository/com/runanywhere/sdk/RunAnywhereKotlinSDK-jvm/0.2.0/
# Should see:
# - RunAnywhereKotlinSDK-jvm-0.2.0.jar
# - RunAnywhereKotlinSDK-jvm-0.2.0.pom
# - RunAnywhereKotlinSDK-jvm-0.2.0-sources.jar
```

### Step 5: Test Integration (Local)

```bash
# Create test Android project
mkdir -p /tmp/test-android-sdk
cd /tmp/test-android-sdk

# Create simple build.gradle.kts
cat > build.gradle.kts << 'EOF'
plugins {
    id("com.android.application") version "8.2.0"
    kotlin("android") version "2.1.21"
}

repositories {
    mavenLocal()
    google()
    mavenCentral()
}

dependencies {
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-android:0.2.0")
    implementation("com.runanywhere.sdk:runanywhere-llm-llamacpp-android:0.2.0")
}
EOF

# Try to resolve dependencies
./gradlew dependencies
# Should successfully resolve local Maven artifacts
```

### Step 6: Create Git Tag for Android

```bash
# Return to repo root
cd /path/to/runanywhere-sdks

# Create annotated tag
git tag -a android/v0.2.0 -m "Android SDK v0.2.0

Release highlights:
- Feature: Kotlin Flow-based streaming
- Feature: SHA-256 model verification
- Feature: Model unloading API
- Fix: Memory leak in LLM component
- Performance: Optimized token generation

Full changelog: https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/CHANGELOG.md#020"

# Push tag to GitHub
git push origin android/v0.2.0
```

### Step 7: Publish to GitHub Packages

#### 7.1 Setup GitHub Packages Authentication

```bash
# Create gradle.properties (if not exists)
mkdir -p ~/.gradle
cat >> ~/.gradle/gradle.properties << 'EOF'

# GitHub Packages
gpr.user=YOUR_GITHUB_USERNAME
gpr.token=YOUR_GITHUB_PERSONAL_ACCESS_TOKEN
EOF
```

**To create GitHub Personal Access Token:**
1. Go to: https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select scopes: `write:packages`, `read:packages`
4. Copy token to gradle.properties

#### 7.2 Configure Publishing

Add to `sdk/runanywhere-kotlin/build.gradle.kts`:

```kotlin
publishing {
    repositories {
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/RunanywhereAI/runanywhere-sdks")
            credentials {
                username = project.findProperty("gpr.user") as String? ?: System.getenv("GITHUB_ACTOR")
                password = project.findProperty("gpr.token") as String? ?: System.getenv("GITHUB_TOKEN")
            }
        }
    }

    publications {
        create<MavenPublication>("jvm") {
            from(components["kotlin"])
            groupId = "com.runanywhere.sdk"
            artifactId = "RunAnywhereKotlinSDK-jvm"
            version = project.version.toString()
        }

        create<MavenPublication>("android") {
            from(components["release"])
            groupId = "com.runanywhere.sdk"
            artifactId = "RunAnywhereKotlinSDK-android"
            version = project.version.toString()
        }
    }
}
```

#### 7.3 Publish to GitHub Packages

```bash
# Publish JVM artifact
./gradlew publishJvmPublicationToGitHubPackagesRepository

# Publish Android artifact
./gradlew publishAndroidPublicationToGitHubPackagesRepository

# Or publish all at once
./gradlew publish
```

### Step 8: Publish to Maven Central (Optional)

**Prerequisites:**
- Sonatype OSSRH account
- GPG key for signing
- `gradle.properties` configured with credentials

```bash
# Sign and publish to Maven Central staging
./gradlew publishAllPublicationsToMavenCentralRepository

# After verifying artifacts:
# 1. Log in to https://oss.sonatype.org/
# 2. Go to "Staging Repositories"
# 3. Select your staging repository
# 4. Click "Close" and wait for validation
# 5. Click "Release" to publish to Maven Central
```

**Note:** Maven Central sync can take 2-4 hours.

---

## GitHub Release Creation

### Step 1: Prepare Release Assets

Collect all release artifacts:

```bash
# Create release directory
mkdir -p release-assets

# iOS XCFramework
cp sdk/runanywhere-swift/build/xcframework/RunAnywhere-0.14.0.xcframework.zip \
   release-assets/

# Android JVM JAR
cp sdk/runanywhere-kotlin/build/libs/RunAnywhereKotlinSDK-jvm-0.2.0.jar \
   release-assets/

# Android AAR
cp sdk/runanywhere-kotlin/build/outputs/aar/RunAnywhereKotlinSDK-release.aar \
   release-assets/RunAnywhereKotlinSDK-android-0.2.0.aar

# LlamaCpp module
cp sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/build/libs/runanywhere-llm-llamacpp-jvm-0.2.0.jar \
   release-assets/

# Generate checksums
cd release-assets
shasum -a 256 * > checksums.txt
```

### Step 2: Create GitHub Release (Web UI)

1. Go to: https://github.com/RunanywhereAI/runanywhere-sdks/releases
2. Click **"Draft a new release"**
3. Fill in release details:

**Tag version:** `v0.14.0` (for combined iOS/Android release)
OR
**Tag version:** `ios/v0.14.0` and `android/v0.2.0` (for separate releases)

**Release title:** `RunAnywhere SDKs v0.14.0 - iOS & Android`

**Description:**
```markdown
# RunAnywhere SDKs v0.14.0

This release includes updates to both iOS and Android SDKs.

## 📦 What's Included

### iOS SDK v0.14.0
- ✨ Feature: Streaming generation with AsyncThrowingStream
- ✨ Feature: Model unloading API
- 🐛 Fix: Memory leak in model loading service
- ⚡ Performance: 20% faster token generation
- 📚 Docs: Updated API reference

### Android SDK v0.2.0
- ✨ Feature: Kotlin Flow-based streaming generation
- ✨ Feature: SHA-256 model verification
- ✨ Feature: Model unloading API
- 🐛 Fix: Memory leak in LLM component
- ⚡ Performance: Optimized JNI bindings

## 🚀 Installation

### iOS (Swift Package Manager)
```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.14.0")
]
```

### Android (Gradle)
```kotlin
dependencies {
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-android:0.2.0")
    implementation("com.runanywhere.sdk:runanywhere-llm-llamacpp-android:0.2.0")
}
```

## 📖 Documentation
- [iOS SDK Documentation](sdk/runanywhere-swift/)
- [Android SDK Documentation](sdk/runanywhere-kotlin/)
- [Full Changelog](CHANGELOG.md)

## ⚠️ Breaking Changes
None in this release.

## 🙏 Contributors
Thanks to all contributors who made this release possible!

---

**Full Changelog**: https://github.com/RunanywhereAI/runanywhere-sdks/compare/v0.13.0...v0.14.0
```

4. **Attach binaries:**
   - Drag and drop files from `release-assets/` directory
   - Include: XCFramework ZIP, JAR, AAR, checksums.txt

5. **Select release type:**
   - Uncheck "Set as a pre-release" (for stable releases)
   - Check "Create a discussion for this release" (optional)

6. Click **"Publish release"**

### Step 3: Create GitHub Release (Command Line)

Alternatively, use GitHub CLI:

```bash
# Install GitHub CLI if needed
brew install gh

# Authenticate
gh auth login

# Create release
gh release create v0.14.0 \
  --title "RunAnywhere SDKs v0.14.0 - iOS & Android" \
  --notes-file RELEASE_NOTES.md \
  release-assets/*

# Or for separate releases
gh release create ios/v0.14.0 \
  --title "iOS SDK v0.14.0" \
  --notes "iOS SDK release notes..." \
  release-assets/RunAnywhere-0.14.0.xcframework.zip

gh release create android/v0.2.0 \
  --title "Android SDK v0.2.0" \
  --notes "Android SDK release notes..." \
  release-assets/RunAnywhereKotlinSDK-*.jar \
  release-assets/RunAnywhereKotlinSDK-android-0.2.0.aar
```

---

## Post-Release Tasks

### 1. Update Documentation

```bash
# Update README badges
vim README.md
# Update version badges to latest release

# Commit documentation updates
git add README.md
git commit -m "docs: update README for v0.14.0 release"
git push origin main
```

### 2. Announce Release

- [ ] Post announcement on Discord
- [ ] Tweet release announcement
- [ ] Update website with new version
- [ ] Send email to SDK users (if mailing list exists)
- [ ] Update SDK documentation site

### 3. Monitor Release

- [ ] Check GitHub release download stats
- [ ] Monitor issues for bug reports
- [ ] Check CocoaPods metrics (if published)
- [ ] Check Maven Central sync status (if published)
- [ ] Verify SPM resolution from GitHub

### 4. Create Release Branch (Optional)

For long-term support releases:

```bash
# Create release branch
git checkout -b release/v0.14.x

# Push release branch
git push origin release/v0.14.x

# Future patches go to this branch
```

---

## Troubleshooting

### iOS Release Issues

#### Issue: SPM resolution fails
```bash
# Solution: Clear SPM cache
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData

# Re-resolve
swift package resolve
```

#### Issue: XCFramework build fails
```bash
# Solution: Clean build directory
xcodebuild clean

# Check scheme exists
xcodebuild -list
```

#### Issue: CocoaPods push fails
```bash
# Solution: Validate locally first
pod spec lint RunAnywhere.podspec --verbose --allow-warnings

# Check trunk access
pod trunk me
```

### Android Release Issues

#### Issue: Gradle publish fails
```bash
# Solution: Check credentials
cat ~/.gradle/gradle.properties

# Test authentication
./gradlew publishToMavenLocal
```

#### Issue: AAR not generated
```bash
# Solution: Ensure Android target is configured
./gradlew tasks --all | grep assemble

# Build explicitly
./gradlew assembleRelease
```

#### Issue: JNI library missing in artifacts
```bash
# Solution: Check jniLibs directory
ls -R src/androidMain/jniLibs/

# Rebuild native components
./scripts/build-native.sh
```

### GitHub Release Issues

#### Issue: Tag already exists
```bash
# Solution: Delete and recreate tag
git tag -d ios/v0.14.0
git push origin :refs/tags/ios/v0.14.0

# Recreate tag
git tag -a ios/v0.14.0 -m "iOS SDK v0.14.0"
git push origin ios/v0.14.0
```

#### Issue: Asset upload fails
```bash
# Solution: Use GitHub CLI
gh release upload v0.14.0 release-assets/* --clobber
```

---

## Release Checklist Summary

Use this checklist for each release:

### Pre-Release
- [ ] All tests passing
- [ ] Version numbers updated (iOS + Android)
- [ ] CHANGELOG.md updated
- [ ] Documentation updated
- [ ] Code freeze announced

### iOS Release
- [ ] Version bumped in Podspec
- [ ] Git tag created (`ios/vX.Y.Z`)
- [ ] SPM resolution verified
- [ ] XCFramework built
- [ ] CocoaPods published (optional)

### Android Release
- [ ] Version bumped in build.gradle.kts
- [ ] All targets built (JVM, Android)
- [ ] Tests passing
- [ ] Local Maven publish verified
- [ ] Git tag created (`android/vX.Y.Z`)
- [ ] GitHub Packages published
- [ ] Maven Central published (optional)

### GitHub Release
- [ ] Release assets collected
- [ ] Checksums generated
- [ ] GitHub release created
- [ ] Release notes written
- [ ] Assets uploaded

### Post-Release
- [ ] Documentation updated
- [ ] Announcement posted
- [ ] Release monitored
- [ ] Issues triaged

---

## Additional Resources

- **Semantic Versioning**: https://semver.org/
- **Swift Package Manager**: https://swift.org/package-manager/
- **CocoaPods Guides**: https://guides.cocoapods.org/
- **Gradle Publishing**: https://docs.gradle.org/current/userguide/publishing_maven.html
- **GitHub Packages**: https://docs.github.com/en/packages
- **Maven Central**: https://central.sonatype.org/publish/

---

**Document Version:** 1.0.0
**Last Updated:** October 9, 2025
**Maintained By:** RunAnywhere SDK Team
