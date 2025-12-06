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
  TEST_LOCAL = true

  # Remote binary configuration (used when TEST_LOCAL = false)
  REMOTE_VERSION = "v0.0.1-dev.aade097"
  REMOTE_BASE_URL = "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download"

  # iOS XCFramework
  IOS_XCFRAMEWORK_URL = "#{REMOTE_BASE_URL}/#{REMOTE_VERSION}/RunAnywhereCore.xcframework.zip"
  IOS_XCFRAMEWORK_CHECKSUM = "b678cbfea242a2a9004c8d52cdf3637483b4a3f4376cd51ae939c3671f33dc5c"

  # Android native libraries
  ANDROID_LIBS_URL = "#{REMOTE_BASE_URL}/#{REMOTE_VERSION}/android-native-libs.zip"
  ANDROID_LIBS_CHECKSUM = "TBD" # Will be updated when we publish Android binaries

  def self.test_local?
    TEST_LOCAL
  end

  def self.should_download?
    !TEST_LOCAL
  end
end
