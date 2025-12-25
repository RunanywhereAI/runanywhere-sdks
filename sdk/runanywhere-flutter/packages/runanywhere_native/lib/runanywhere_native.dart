/// RunAnywhere Native Binaries Package
///
/// This package bundles the native libraries (.so files for Android,
/// XCFramework for iOS) required by the RunAnywhere Flutter SDK.
///
/// ## Purpose
///
/// This package exists solely to bundle and distribute native binaries.
/// It is a dependency of the main `runanywhere` package and should not
/// be used directly by applications.
///
/// ## Binary Configuration
///
/// Binaries can be configured in two modes:
///
/// ### Remote Mode (Default - Production)
/// Binaries are downloaded from GitHub releases during build.
/// Configure in:
/// - Android: `android/binary_config.gradle`
/// - iOS: `ios/binary_config.rb`
///
/// ### Local Mode (Development)
/// Use locally built binaries for testing:
/// - Android: Copy .so files to `android/src/main/jniLibs/`
/// - iOS: Copy XCFramework to `ios/Frameworks/`
///
/// Set `testLocal = true` in the config files to enable local mode.
library runanywhere_native;

/// The version of native binaries bundled with this package.
const String nativeBinaryVersion = 'v0.0.1-dev.27bdcd0';

/// The commit hash of the native binaries.
const String nativeBinaryCommit = '27bdcd0';
