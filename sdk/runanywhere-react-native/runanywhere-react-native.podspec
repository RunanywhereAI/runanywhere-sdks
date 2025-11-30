require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
folly_compiler_flags = '-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1 -Wno-comma -Wno-shorten-64-to-32'

# XCFramework configuration
# Update these values when new versions are released
ONNX_XCFRAMEWORK_VERSION = "0.0.1-dev.4767337"
ONNX_XCFRAMEWORK_CHECKSUM = "c054210880498119a7f61ffa2f922effa8e3c92513085f5c495011ea301f776a"

Pod::Spec.new do |s|
  s.name         = "runanywhere-react-native"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "14.0" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # Source files
  s.source_files = "ios/**/*.{h,m,mm}", "cpp/**/*.{h,hpp,cpp}"

  # Exclude include folder from compilation (headers only)
  s.exclude_files = "cpp/include/**/*.h"

  # Public headers
  s.public_header_files = "ios/**/*.h"

  # Header search paths
  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/cpp/include"
    ].join(" "),
    "OTHER_LDFLAGS" => "-ObjC -all_load",
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) RCT_NEW_ARCH_ENABLED=1"
  }

  # User target xcconfig
  s.user_target_xcconfig = {
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_ROOT)/runanywhere-react-native/cpp/include"
    ].join(" ")
  }

  # Required system libraries and frameworks
  s.libraries = "c++", "archive"
  s.frameworks = "Accelerate", "Foundation", "CoreML"

  # React Native dependencies
  install_modules_dependencies(s)

  # =============================================================================
  # XCFRAMEWORK DEPENDENCY
  # =============================================================================
  #
  # The RunAnywhereONNX.xcframework contains:
  # - ONNX Runtime
  # - Sherpa-ONNX (STT, TTS, VAD)
  # - RunAnywhere C API bridge
  #
  # For local development, you can download and place the XCFramework manually:
  #   1. Download from: https://github.com/RunanywhereAI/runanywhere-binaries/releases
  #   2. Extract to: ios/Frameworks/RunAnywhereONNX.xcframework
  #
  # For production, the framework is fetched via the vendored_frameworks setting below.
  # =============================================================================

  # Option 1: Local XCFramework (for development)
  # Uncomment this and comment out Option 2 if you have the framework locally
  # s.vendored_frameworks = "ios/Frameworks/RunAnywhereONNX.xcframework"

  # Option 2: Remote XCFramework via prepare_command
  # This downloads the XCFramework during pod install
  s.prepare_command = <<-CMD
    echo "Downloading RunAnywhereONNX.xcframework..."

    FRAMEWORK_DIR="#{__dir__}/ios/Frameworks"
    FRAMEWORK_PATH="$FRAMEWORK_DIR/RunAnywhereONNX.xcframework"

    # Skip if already exists
    if [ -d "$FRAMEWORK_PATH" ]; then
      echo "XCFramework already exists, skipping download."
      exit 0
    fi

    mkdir -p "$FRAMEWORK_DIR"

    DOWNLOAD_URL="https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v#{ONNX_XCFRAMEWORK_VERSION}/RunAnywhereONNX.xcframework.zip"
    ZIP_PATH="$FRAMEWORK_DIR/RunAnywhereONNX.xcframework.zip"

    echo "Downloading from: $DOWNLOAD_URL"
    curl -L -o "$ZIP_PATH" "$DOWNLOAD_URL"

    if [ $? -ne 0 ]; then
      echo "ERROR: Failed to download XCFramework"
      exit 1
    fi

    # Verify checksum
    ACTUAL_CHECKSUM=$(shasum -a 256 "$ZIP_PATH" | cut -d ' ' -f 1)
    EXPECTED_CHECKSUM="#{ONNX_XCFRAMEWORK_CHECKSUM}"

    if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
      echo "ERROR: Checksum mismatch!"
      echo "  Expected: $EXPECTED_CHECKSUM"
      echo "  Actual:   $ACTUAL_CHECKSUM"
      rm -f "$ZIP_PATH"
      exit 1
    fi

    echo "Checksum verified, extracting..."
    unzip -q -o "$ZIP_PATH" -d "$FRAMEWORK_DIR"
    rm -f "$ZIP_PATH"

    echo "XCFramework installed successfully!"
  CMD

  s.vendored_frameworks = "ios/Frameworks/RunAnywhereONNX.xcframework"

  # =============================================================================
  # OPTIONAL: LlamaCpp Subspec for LLM Support
  # =============================================================================
  # Uncomment this when RunAnywhereLlamaCpp.xcframework is available

  # s.default_subspecs = 'Core'
  #
  # s.subspec 'Core' do |core|
  #   core.source_files = "ios/**/*.{h,m,mm}", "cpp/**/*.{h,hpp,cpp}"
  #   core.vendored_frameworks = "ios/Frameworks/RunAnywhereONNX.xcframework"
  # end
  #
  # s.subspec 'LlamaCpp' do |llama|
  #   llama.dependency "runanywhere-react-native/Core"
  #   llama.vendored_frameworks = "ios/Frameworks/RunAnywhereLlamaCpp.xcframework"
  #   llama.pod_target_xcconfig = {
  #     'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) RA_ENABLE_LLAMACPP=1'
  #   }
  # end

end
