#
# RunAnywhere ONNX Backend - iOS
#
# This podspec integrates RABackendONNX.xcframework into Flutter iOS apps.
# RABackendONNX provides STT, TTS, VAD capabilities using ONNX Runtime and Sherpa-ONNX.
#
# Binary Configuration:
#   - Set RA_TEST_LOCAL=1 or create .testlocal file to use local binaries
#   - Otherwise, binaries are downloaded from GitHub releases (production mode)
#
# Version: Must match Swift SDK's Package.swift and Kotlin SDK's build.gradle.kts
#
# Architecture Note:
#   This follows the same pattern as React Native and Swift SDKs - bundling
#   onnxruntime.xcframework directly rather than using a CocoaPods dependency.
#   This ensures version consistency across all SDKs.
#

# =============================================================================
# Version Constants (MUST match Swift Package.swift)
# =============================================================================
ONNX_VERSION = "0.1.4"
ONNXRUNTIME_VERSION = "1.17.1"

# =============================================================================
# Binary Source - RABackendONNX from runanywhere-binaries
# =============================================================================
GITHUB_ORG = "RunanywhereAI"
BINARIES_REPO = "runanywhere-binaries"

# =============================================================================
# testLocal Toggle
# Set RA_TEST_LOCAL=1 or create .testlocal file to use local binaries
# =============================================================================
TEST_LOCAL = ENV['RA_TEST_LOCAL'] == '1' || File.exist?(File.join(__dir__, '.testlocal'))

Pod::Spec.new do |s|
  s.name             = 'runanywhere_onnx'
  s.version          = '0.15.10'
  s.summary          = 'RunAnywhere ONNX: STT, TTS, VAD for Flutter'
  s.description      = <<-DESC
ONNX Runtime backend for RunAnywhere Flutter SDK. Provides speech-to-text (STT),
text-to-speech (TTS), and voice activity detection (VAD) capabilities using
ONNX Runtime and Sherpa-ONNX. Pre-built binaries are downloaded from:
https://github.com/RunanywhereAI/runanywhere-binaries
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'MIT' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.0'

  # Source files (minimal - main logic is in the xcframework)
  s.source_files = 'Classes/**/*'

  # Flutter dependency
  s.dependency 'Flutter'

  # Core SDK dependency (provides RACommons)
  s.dependency 'runanywhere'

  # =============================================================================
  # RABackendONNX + ONNX Runtime XCFrameworks
  #
  # Unlike using `s.dependency 'onnxruntime-c'`, we bundle onnxruntime.xcframework
  # directly to match the architecture of other SDKs:
  #   - Swift SDK: Downloads via SPM binaryTarget from download.onnxruntime.ai
  #   - React Native: Downloads in prepare_command alongside RABackendONNX
  #   - Kotlin: Bundles libonnxruntime.so in jniLibs
  #
  # This ensures version consistency (1.17.1) across all platforms.
  # =============================================================================
  if TEST_LOCAL
    puts "[runanywhere_onnx] Using LOCAL frameworks from Frameworks/"
    s.vendored_frameworks = [
      'Frameworks/RABackendONNX.xcframework',
      'Frameworks/onnxruntime.xcframework'
    ]
  else
    s.prepare_command = <<-CMD
      set -e

      FRAMEWORK_DIR="Frameworks"
      VERSION="#{ONNX_VERSION}"
      ONNX_VERSION="#{ONNXRUNTIME_VERSION}"
      VERSION_FILE="$FRAMEWORK_DIR/.onnx_version"

      # Check if already downloaded with correct version
      if [ -f "$VERSION_FILE" ] && [ -d "$FRAMEWORK_DIR/RABackendONNX.xcframework" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
        if [ "$CURRENT_VERSION" = "$VERSION" ]; then
          echo "✅ RABackendONNX.xcframework version $VERSION already downloaded"
          # Still need to check onnxruntime
          if [ -d "$FRAMEWORK_DIR/onnxruntime.xcframework" ]; then
            exit 0
          fi
        fi
      fi

      echo "📦 Downloading RABackendONNX.xcframework version $VERSION..."

      mkdir -p "$FRAMEWORK_DIR"
      rm -rf "$FRAMEWORK_DIR/RABackendONNX.xcframework"

      # Download from runanywhere-binaries
      DOWNLOAD_URL="https://github.com/#{GITHUB_ORG}/#{BINARIES_REPO}/releases/download/core-v$VERSION/RABackendONNX-ios-v$VERSION.zip"
      ZIP_FILE="/tmp/RABackendONNX.zip"

      echo "   URL: $DOWNLOAD_URL"

      curl -L -f -o "$ZIP_FILE" "$DOWNLOAD_URL" || {
        echo "❌ Failed to download RABackendONNX from $DOWNLOAD_URL"
        exit 1
      }

      echo "📂 Extracting RABackendONNX.xcframework..."
      unzip -q -o "$ZIP_FILE" -d "$FRAMEWORK_DIR/"
      rm -f "$ZIP_FILE"

      # Download ONNX Runtime if not present (matches Swift/React Native SDKs)
      if [ ! -d "$FRAMEWORK_DIR/onnxruntime.xcframework" ]; then
        echo "📦 Downloading ONNX Runtime version $ONNX_VERSION..."
        ONNX_URL="https://download.onnxruntime.ai/pod-archive-onnxruntime-c-$ONNX_VERSION.zip"
        ONNX_ZIP="/tmp/onnxruntime.zip"

        curl -L -f -o "$ONNX_ZIP" "$ONNX_URL" || {
          echo "❌ Failed to download ONNX Runtime from $ONNX_URL"
          exit 1
        }

        echo "📂 Extracting onnxruntime.xcframework..."
        unzip -q -o "$ONNX_ZIP" -d "$FRAMEWORK_DIR/"
        rm -f "$ONNX_ZIP"
      fi

      echo "$VERSION" > "$VERSION_FILE"

      if [ -d "$FRAMEWORK_DIR/RABackendONNX.xcframework" ] && [ -d "$FRAMEWORK_DIR/onnxruntime.xcframework" ]; then
        echo "✅ ONNX frameworks installed successfully"
      else
        echo "❌ ONNX framework extraction failed"
        exit 1
      fi
    CMD

    s.vendored_frameworks = [
      'Frameworks/RABackendONNX.xcframework',
      'Frameworks/onnxruntime.xcframework'
    ]
  end

  s.preserve_paths = 'Frameworks/**/*'

  # Required frameworks
  s.frameworks = [
    'Foundation',
    'CoreML',
    'Accelerate',
    'AVFoundation',
    'AudioToolbox'
  ]

  # Weak frameworks (optional hardware acceleration)
  s.weak_frameworks = [
    'Metal',
    'MetalKit',
    'MetalPerformanceShaders'
  ]

  # Build settings
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'ENABLE_BITCODE' => 'NO',
    # Header search paths for onnxruntime.xcframework (needed for compilation)
    'HEADER_SEARCH_PATHS' => [
      '$(PODS_TARGET_SRCROOT)/Frameworks/onnxruntime.xcframework/ios-arm64/Headers',
      '$(PODS_TARGET_SRCROOT)/Frameworks/onnxruntime.xcframework/ios-arm64_x86_64-simulator/Headers',
    ].join(' '),
  }

  # CRITICAL: -all_load ensures ALL object files from RABackendONNX.xcframework are linked.
  # This is required for Flutter FFI to find symbols at runtime via dlsym().
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -all_load',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  # Mark static framework for proper linking
  s.static_framework = true
end
