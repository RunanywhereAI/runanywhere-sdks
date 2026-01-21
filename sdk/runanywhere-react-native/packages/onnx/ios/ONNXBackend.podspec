require "json"

package = JSON.parse(File.read(File.join(__dir__, "..", "package.json")))

# =============================================================================
# Version Constants (MUST match Swift Package.swift)
# =============================================================================
CORE_VERSION = "0.1.4"
ONNXRUNTIME_VERSION = "1.17.1"

# =============================================================================
# Binary Source - RABackendONNX from runanywhere-sdks
# =============================================================================
GITHUB_ORG = "RunanywhereAI"
CORE_REPO = "runanywhere-sdks"

# =============================================================================
# testLocal Toggle
# Set RA_TEST_LOCAL=1 or create .testlocal file to use local binaries
# =============================================================================
TEST_LOCAL = ENV['RA_TEST_LOCAL'] == '1' || File.exist?(File.join(__dir__, '.testlocal'))

Pod::Spec.new do |s|
  s.name         = "ONNXBackend"
  s.module_name  = "RunAnywhereONNX"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://runanywhere.com"
  s.license      = package["license"]
  s.authors      = "RunAnywhere AI"

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # =============================================================================
  # ONNX Backend - RABackendONNX + ONNX Runtime
  # Downloads from runanywhere-sdks (NOT runanywhere-sdks)
  # =============================================================================
  if TEST_LOCAL
    puts "[ONNXBackend] Using LOCAL RABackendONNX from Frameworks/"
    s.vendored_frameworks = [
      "Frameworks/RABackendONNX.xcframework",
      "Frameworks/onnxruntime.xcframework"
    ]
  else
    s.prepare_command = <<-CMD
      set -e

      FRAMEWORK_DIR="Frameworks"
      VERSION="#{CORE_VERSION}"
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

      # Download RABackendONNX from runanywhere-sdks
      DOWNLOAD_URL="https://github.com/#{GITHUB_ORG}/#{CORE_REPO}/releases/download/core-v$VERSION/RABackendONNX-ios-v$VERSION.zip"
      ZIP_FILE="/tmp/RABackendONNX.zip"

      echo "   URL: $DOWNLOAD_URL"

      curl -L -f -o "$ZIP_FILE" "$DOWNLOAD_URL" || {
        echo "❌ Failed to download RABackendONNX from $DOWNLOAD_URL"
        exit 1
      }

      echo "📂 Extracting RABackendONNX.xcframework..."
      unzip -q -o "$ZIP_FILE" -d "$FRAMEWORK_DIR/"
      rm -f "$ZIP_FILE"

      # Download ONNX Runtime if not present
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
      "Frameworks/RABackendONNX.xcframework",
      "Frameworks/onnxruntime.xcframework"
    ]
  end

  # Source files - ONNX C++ implementation
  s.source_files = [
    "../cpp/HybridRunAnywhereONNX.cpp",
    "../cpp/HybridRunAnywhereONNX.hpp",
    "../cpp/bridges/**/*.{cpp,hpp}",
  ]

  # Build settings
  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/../cpp",
      "$(PODS_TARGET_SRCROOT)/../cpp/bridges",
      "$(PODS_TARGET_SRCROOT)/Frameworks/RABackendONNX.xcframework/ios-arm64/RABackendONNX.framework/Headers",
      "$(PODS_TARGET_SRCROOT)/Frameworks/RABackendONNX.xcframework/ios-arm64_x86_64-simulator/RABackendONNX.framework/Headers",
      "$(PODS_TARGET_SRCROOT)/Frameworks/onnxruntime.xcframework/ios-arm64/onnxruntime.framework/Headers",
      "$(PODS_TARGET_SRCROOT)/Frameworks/onnxruntime.xcframework/ios-arm64_x86_64-simulator/onnxruntime.framework/Headers",
      "$(PODS_ROOT)/Headers/Public",
    ].join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) HAS_ONNX=1",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
  }

  # Required system libraries
  s.libraries = "c++"
  s.frameworks = "Accelerate", "Foundation", "CoreML", "AudioToolbox"

  # Dependencies
  s.dependency 'RunAnywhereCore'
  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  # Load Nitrogen-generated autolinking
  load '../nitrogen/generated/ios/RunAnywhereONNX+autolinking.rb'
  add_nitrogen_files(s)

  install_modules_dependencies(s)
end
