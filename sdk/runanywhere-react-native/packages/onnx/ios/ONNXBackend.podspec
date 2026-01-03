Pod::Spec.new do |s|
  s.name         = "ONNXBackend"
  s.version      = "0.1.0"
  s.summary      = "ONNX backend for RunAnywhere SDK (STT/TTS/VAD)"
  s.description  = <<-DESC
    ONNX backend module for RunAnywhere SDK (React Native).
    Provides STT (Speech-to-Text), TTS (Text-to-Speech), and VAD (Voice Activity Detection)
    capabilities using ONNX Runtime.
    This is an optional module - only include if you need STT/TTS/VAD features.
  DESC
  s.homepage     = "https://github.com/RunanywhereAI/runanywhere-sdks"
  s.license      = { :type => "MIT", :file => "../../../LICENSE" }
  s.author       = { "RunAnywhere" => "info@runanywhere.ai" }
  s.source       = { :git => "https://github.com/RunanywhereAI/runanywhere-sdks.git", :tag => "commons-v#{s.version}" }
  s.platform     = :ios, "15.1"

  # =============================================================================
  # Version Constants (MUST match Swift Package.swift)
  # =============================================================================
  COMMONS_VERSION = "0.1.0"
  CORE_VERSION = "0.1.1-dev.03aacf9"
  GITHUB_ORG = "RunanywhereAI"
  COMMONS_REPO = "runanywhere-sdks"
  CORE_REPO = "runanywhere-binaries"

  # =============================================================================
  # testLocal Toggle
  # =============================================================================
  TEST_LOCAL = ENV['RA_TEST_LOCAL'] == '1' || File.exist?(File.join(__dir__, '../../native/.testlocal'))

  # =============================================================================
  # Dependencies - Requires core RunAnywhereNative
  # =============================================================================
  s.dependency "RunAnywhereNative"

  # =============================================================================
  # Binary Frameworks - RABackendONNX + onnxruntime
  # =============================================================================
  if TEST_LOCAL
    puts "[ONNXBackend] Using LOCAL binaries from Frameworks/"
    s.vendored_frameworks = [
      "Frameworks/RABackendONNX.xcframework",
      "Frameworks/onnxruntime.xcframework"
    ]
  else
    s.prepare_command = <<-CMD
      set -e

      FRAMEWORK_DIR="Frameworks"
      VERSION="#{COMMONS_VERSION}"
      CORE_VER="#{CORE_VERSION}"
      VERSION_FILE="$FRAMEWORK_DIR/.version-onnx"

      if [ -f "$VERSION_FILE" ] && [ -d "$FRAMEWORK_DIR/RABackendONNX.xcframework" ] && [ -d "$FRAMEWORK_DIR/onnxruntime.xcframework" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
        if [ "$CURRENT_VERSION" = "$VERSION-$CORE_VER" ]; then
          echo "✅ ONNX frameworks already downloaded"
          exit 0
        fi
      fi

      echo "📦 Downloading ONNX backend frameworks..."

      mkdir -p "$FRAMEWORK_DIR"

      # Download RABackendONNX from runanywhere-sdks
      echo "📦 Downloading RABackendONNX.xcframework..."
      ONNX_BACKEND_URL="https://github.com/#{GITHUB_ORG}/#{COMMONS_REPO}/releases/download/commons-v$VERSION/RABackendONNX-$VERSION.zip"
      curl -L -f -o /tmp/RABackendONNX.zip "$ONNX_BACKEND_URL" || {
        echo "❌ Failed to download RABackendONNX"
        exit 1
      }
      rm -rf "$FRAMEWORK_DIR/RABackendONNX.xcframework"
      unzip -q -o /tmp/RABackendONNX.zip -d "$FRAMEWORK_DIR/"
      rm -f /tmp/RABackendONNX.zip
      echo "✅ RABackendONNX.xcframework installed"

      # Download onnxruntime from runanywhere-binaries
      echo "📦 Downloading onnxruntime.xcframework..."
      ONNXRUNTIME_URL="https://github.com/#{GITHUB_ORG}/#{CORE_REPO}/releases/download/core-v$CORE_VER/onnxruntime-ios-v$CORE_VER.zip"
      curl -L -f -o /tmp/onnxruntime.zip "$ONNXRUNTIME_URL" || {
        echo "❌ Failed to download onnxruntime"
        exit 1
      }
      rm -rf "$FRAMEWORK_DIR/onnxruntime.xcframework"
      unzip -q -o /tmp/onnxruntime.zip -d "$FRAMEWORK_DIR/"
      rm -f /tmp/onnxruntime.zip
      echo "✅ onnxruntime.xcframework installed"

      echo "$VERSION-$CORE_VER" > "$VERSION_FILE"

      echo "✅ All ONNX frameworks installed successfully"
    CMD

    s.vendored_frameworks = [
      "Frameworks/RABackendONNX.xcframework",
      "Frameworks/onnxruntime.xcframework"
    ]
  end

  # Build settings
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17"
  }

  # Required frameworks for ONNX
  s.frameworks = "Accelerate", "CoreML"
  s.libraries = "c++", "archive", "bz2"
end
