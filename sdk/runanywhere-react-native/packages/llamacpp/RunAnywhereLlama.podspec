require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# =============================================================================
# Version Constants (MUST match Swift Package.swift)
# =============================================================================
LLAMACPP_VERSION = "0.1.4"

# =============================================================================
# Binary Source - RABackendLlamaCPP from runanywhere-binaries
# =============================================================================
LLAMACPP_GITHUB_ORG = "RunanywhereAI"
LLAMACPP_REPO = "runanywhere-binaries"

# =============================================================================
# testLocal Toggle
# Set RA_TEST_LOCAL=1 or create .testlocal file to use local binaries
# =============================================================================
LLAMACPP_TEST_LOCAL = ENV['RA_TEST_LOCAL'] == '1' || File.exist?(File.join(__dir__, 'ios', '.testlocal'))

Pod::Spec.new do |s|
  s.name         = "RunAnywhereLlama"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://runanywhere.com"
  s.license      = package["license"]
  s.authors      = "RunAnywhere AI"

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # =============================================================================
  # Llama Backend - RABackendLlamaCPP
  # Downloads from runanywhere-binaries (NOT runanywhere-sdks)
  # =============================================================================
  if LLAMACPP_TEST_LOCAL
    puts "[RunAnywhereLlama] Using LOCAL RABackendLlamaCPP from ios/Frameworks/"
    s.vendored_frameworks = "ios/Frameworks/RABackendLLAMACPP.xcframework"
  else
    s.prepare_command = <<-CMD
      set -e

      FRAMEWORK_DIR="ios/Frameworks"
      VERSION="#{LLAMACPP_VERSION}"
      VERSION_FILE="$FRAMEWORK_DIR/.llamacpp_version"

      # Check if already downloaded with correct version
      if [ -f "$VERSION_FILE" ] && [ -d "$FRAMEWORK_DIR/RABackendLLAMACPP.xcframework" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
        if [ "$CURRENT_VERSION" = "$VERSION" ]; then
          echo "✅ RABackendLLAMACPP.xcframework version $VERSION already downloaded"
          exit 0
        fi
      fi

      echo "📦 Downloading RABackendLlamaCPP.xcframework version $VERSION..."

      mkdir -p "$FRAMEWORK_DIR"
      rm -rf "$FRAMEWORK_DIR/RABackendLLAMACPP.xcframework"

      # Download from runanywhere-binaries
      DOWNLOAD_URL="https://github.com/#{LLAMACPP_GITHUB_ORG}/#{LLAMACPP_REPO}/releases/download/core-v$VERSION/RABackendLlamaCPP-ios-v$VERSION.zip"
      ZIP_FILE="/tmp/RABackendLlamaCPP.zip"

      echo "   URL: $DOWNLOAD_URL"

      curl -L -f -o "$ZIP_FILE" "$DOWNLOAD_URL" || {
        echo "❌ Failed to download RABackendLlamaCPP from $DOWNLOAD_URL"
        exit 1
      }

      echo "📂 Extracting RABackendLLAMACPP.xcframework..."
      unzip -q -o "$ZIP_FILE" -d "$FRAMEWORK_DIR/"
      rm -f "$ZIP_FILE"

      echo "$VERSION" > "$VERSION_FILE"

      if [ -d "$FRAMEWORK_DIR/RABackendLLAMACPP.xcframework" ]; then
        echo "✅ RABackendLLAMACPP.xcframework installed successfully"
      else
        echo "❌ RABackendLLAMACPP.xcframework extraction failed"
        exit 1
      fi
    CMD

    s.vendored_frameworks = "ios/Frameworks/RABackendLLAMACPP.xcframework"
  end

  # Source files - Llama C++ implementation
  s.source_files = [
    "cpp/HybridRunAnywhereLlama.cpp",
    "cpp/HybridRunAnywhereLlama.hpp",
    "cpp/bridges/**/*.{cpp,hpp}",
  ]

  # Build settings
  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/cpp/bridges",
      "$(PODS_TARGET_SRCROOT)/ios/Frameworks/RABackendLLAMACPP.xcframework/ios-arm64/RABackendLLAMACPP.framework/Headers",
      "$(PODS_TARGET_SRCROOT)/ios/Frameworks/RABackendLLAMACPP.xcframework/ios-arm64_x86_64-simulator/RABackendLLAMACPP.framework/Headers",
      "$(PODS_ROOT)/Headers/Public",
    ].join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) HAS_LLAMACPP=1",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
  }

  # Required system libraries
  s.libraries = "c++"
  s.frameworks = "Accelerate", "Foundation", "CoreML"

  # Dependencies
  s.dependency 'RunAnywhereCore'
  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  # Load Nitrogen-generated autolinking
  load 'nitrogen/generated/ios/RunAnywhereLlama+autolinking.rb'
  add_nitrogen_files(s)

  install_modules_dependencies(s)
end
