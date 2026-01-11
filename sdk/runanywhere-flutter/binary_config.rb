# =============================================================================
# BINARY CONFIGURATION FOR RUNANYWHERE FLUTTER SDK
# =============================================================================
# This file controls whether to use local or remote native binaries.
# Similar to Swift Package.swift's testLocal flag.
#
# Set to `true` to use local binaries from ios/Frameworks/ and android/src/main/jniLibs/
# Set to `false` to download binaries from GitHub releases (production mode)
# =============================================================================

module RunAnywhereBinaryConfig
  # Set this to true for local development/testing
  # Set to false for production builds (downloads from GitHub releases)
  TEST_LOCAL = false

  # Remote binary configuration (used when TEST_LOCAL = false)
  REMOTE_VERSION = "v0.0.1-dev.27bdcd0"
  REMOTE_COMMIT = "27bdcd0"  # Short commit hash for Android artifact naming
  REMOTE_BASE_URL = "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download"

  # iOS XCFramework
  IOS_XCFRAMEWORK_URL = "#{REMOTE_BASE_URL}/#{REMOTE_VERSION}/RunAnywhereCore.xcframework.zip"
  IOS_XCFRAMEWORK_CHECKSUM = "81f6d24230807dff93b6cb0d590f3dd82f69349ad47167c7cb6074903bc2af18"

  # Android native libraries (unified package with ONNX + LlamaCPP)
  ANDROID_LIBS_URL = "#{REMOTE_BASE_URL}/#{REMOTE_VERSION}/RunAnywhereUnified-android-#{REMOTE_COMMIT}.zip"
  ANDROID_LIBS_CHECKSUM = "7e09fe00bad585cc245fd98f89c34b58bc84904e26e118163210e564f4bf2c18"

  def self.test_local?
    TEST_LOCAL
  end

  def self.should_download?
    !TEST_LOCAL
  end
end
