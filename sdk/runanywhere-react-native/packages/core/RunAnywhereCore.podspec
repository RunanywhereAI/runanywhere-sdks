require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# =============================================================================
# Version Constants (MUST match Swift Package.swift)
# =============================================================================
COMMONS_VERSION = "0.1.2"

# =============================================================================
# Binary Source - RACommons from runanywhere-sdks
# =============================================================================
GITHUB_ORG = "RunanywhereAI"
COMMONS_REPO = "runanywhere-sdks"

# =============================================================================
# testLocal Toggle
# Set RA_TEST_LOCAL=1 or create .testlocal file to use local binaries
# =============================================================================
TEST_LOCAL = ENV['RA_TEST_LOCAL'] == '1' || File.exist?(File.join(__dir__, '.testlocal'))

Pod::Spec.new do |s|
  s.name         = "RunAnywhereCore"
  s.module_name  = "RunAnywhereCore"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://runanywhere.com"
  s.license      = package["license"]
  s.authors      = "RunAnywhere AI"

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # =============================================================================
  # Core SDK - RACommons Only
  # No LLM/STT/TTS/VAD backends - those are in @runanywhere/llamacpp and @runanywhere/onnx
  # =============================================================================
  if TEST_LOCAL
    puts "[RunAnywhereCore] Using LOCAL RACommons from ios/Binaries/"
    s.vendored_frameworks = "ios/Binaries/RACommons.xcframework"
  else
    s.prepare_command = <<-CMD
      set -e

      FRAMEWORK_DIR="ios/Frameworks"
      VERSION="#{COMMONS_VERSION}"
      VERSION_FILE="$FRAMEWORK_DIR/.version"

      # Check if already downloaded with correct version
      if [ -f "$VERSION_FILE" ] && [ -d "$FRAMEWORK_DIR/RACommons.xcframework" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
        if [ "$CURRENT_VERSION" = "$VERSION" ]; then
          echo "✅ RACommons.xcframework version $VERSION already downloaded"
          exit 0
        fi
      fi

      echo "📦 Downloading RACommons.xcframework version $VERSION..."

      mkdir -p "$FRAMEWORK_DIR"
      rm -rf "$FRAMEWORK_DIR/RACommons.xcframework"

      # Download RACommons from runanywhere-sdks
      DOWNLOAD_URL="https://github.com/#{GITHUB_ORG}/#{COMMONS_REPO}/releases/download/commons-v$VERSION/RACommons-ios-v$VERSION.zip"
      ZIP_FILE="/tmp/RACommons.zip"

      echo "   URL: $DOWNLOAD_URL"

      curl -L -f -o "$ZIP_FILE" "$DOWNLOAD_URL" || {
        echo "❌ Failed to download RACommons from $DOWNLOAD_URL"
        exit 1
      }

      echo "📂 Extracting RACommons.xcframework..."
      unzip -q -o "$ZIP_FILE" -d "$FRAMEWORK_DIR/"
      rm -f "$ZIP_FILE"

      echo "$VERSION" > "$VERSION_FILE"

      if [ -d "$FRAMEWORK_DIR/RACommons.xcframework" ]; then
        echo "✅ RACommons.xcframework installed successfully"
      else
        echo "❌ RACommons.xcframework extraction failed"
        exit 1
      fi
    CMD

    s.vendored_frameworks = "ios/Frameworks/RACommons.xcframework"
  end

  # Source files - Core only (no LLM/STT/TTS/VAD bridges)
  s.source_files = [
    "ios/**/*.{swift}",
    "ios/**/*.{h,m,mm}",
    "cpp/HybridRunAnywhereCore.cpp",
    "cpp/HybridRunAnywhereCore.hpp",
    "cpp/bridges/**/*.{cpp,hpp}",
  ]

  # Build settings with header paths for RACommons.xcframework
  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/cpp/bridges",
      "$(PODS_TARGET_SRCROOT)/ios/Frameworks/RACommons.xcframework/ios-arm64/Headers",
      "$(PODS_TARGET_SRCROOT)/ios/Frameworks/RACommons.xcframework/ios-arm64_x86_64-simulator/Headers",
      "$(PODS_TARGET_SRCROOT)/ios/Binaries/RACommons.xcframework/ios-arm64/Headers",
      "$(PODS_TARGET_SRCROOT)/ios/Binaries/RACommons.xcframework/ios-arm64_x86_64-simulator/Headers",
      "$(PODS_ROOT)/Headers/Public",
    ].join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited)",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
  }

  # Required system libraries and frameworks
  s.libraries = "c++", "archive", "bz2"
  s.frameworks = "Accelerate", "Foundation", "CoreML", "AudioToolbox"

  # React Native dependencies
  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  # Load Nitrogen-generated autolinking
  load 'nitrogen/generated/ios/RunAnywhereCore+autolinking.rb'
  add_nitrogen_files(s)

  install_modules_dependencies(s)
end
