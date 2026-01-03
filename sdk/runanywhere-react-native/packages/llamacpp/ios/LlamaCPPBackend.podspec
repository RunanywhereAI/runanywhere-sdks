Pod::Spec.new do |s|
  s.name         = "LlamaCPPBackend"
  s.version      = "0.1.0"
  s.summary      = "LlamaCPP backend for RunAnywhere SDK"
  s.description  = <<-DESC
    LlamaCPP backend module for RunAnywhere SDK (React Native).
    Provides LLM text generation capabilities using llama.cpp.
    This is an optional module - only include if you need LLM features.
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
  GITHUB_ORG = "RunanywhereAI"
  COMMONS_REPO = "runanywhere-sdks"

  # =============================================================================
  # testLocal Toggle
  # =============================================================================
  TEST_LOCAL = ENV['RA_TEST_LOCAL'] == '1' || File.exist?(File.join(__dir__, '../../native/.testlocal'))

  # =============================================================================
  # Dependencies - Requires core RunAnywhereNative
  # =============================================================================
  s.dependency "RunAnywhereNative"

  # =============================================================================
  # Binary Framework - RABackendLlamaCPP
  # =============================================================================
  if TEST_LOCAL
    puts "[LlamaCPPBackend] Using LOCAL binaries from Frameworks/"
    s.vendored_frameworks = "Frameworks/RABackendLlamaCPP.xcframework"
  else
    s.prepare_command = <<-CMD
      set -e

      FRAMEWORK_DIR="Frameworks"
      VERSION="#{COMMONS_VERSION}"
      VERSION_FILE="$FRAMEWORK_DIR/.version-llamacpp"

      if [ -f "$VERSION_FILE" ] && [ -d "$FRAMEWORK_DIR/RABackendLlamaCPP.xcframework" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
        if [ "$CURRENT_VERSION" = "$VERSION" ]; then
          echo "✅ RABackendLlamaCPP.xcframework version $VERSION already downloaded"
          exit 0
        fi
      fi

      echo "📦 Downloading RABackendLlamaCPP.xcframework version $VERSION..."

      mkdir -p "$FRAMEWORK_DIR"

      # Download from runanywhere-sdks releases
      DOWNLOAD_URL="https://github.com/#{GITHUB_ORG}/#{COMMONS_REPO}/releases/download/commons-v$VERSION/RABackendLlamaCPP-$VERSION.zip"
      ZIP_FILE="/tmp/RABackendLlamaCPP.zip"

      echo "   URL: $DOWNLOAD_URL"

      curl -L -f -o "$ZIP_FILE" "$DOWNLOAD_URL" || {
        echo "❌ Failed to download RABackendLlamaCPP"
        exit 1
      }

      rm -rf "$FRAMEWORK_DIR/RABackendLlamaCPP.xcframework"

      echo "📂 Extracting RABackendLlamaCPP.xcframework..."
      unzip -q -o "$ZIP_FILE" -d "$FRAMEWORK_DIR/"

      rm -f "$ZIP_FILE"
      echo "$VERSION" > "$VERSION_FILE"

      echo "✅ RABackendLlamaCPP.xcframework installed successfully"
    CMD

    s.vendored_frameworks = "Frameworks/RABackendLlamaCPP.xcframework"
  end

  # Build settings
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17"
  }

  # Required frameworks for LlamaCPP (Metal for GPU acceleration)
  s.frameworks = "Accelerate", "Metal", "MetalKit"
  s.libraries = "c++"
end
