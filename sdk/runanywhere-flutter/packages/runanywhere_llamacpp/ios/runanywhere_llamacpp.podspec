#
# RunAnywhere LlamaCPP Backend - iOS
#
# This podspec integrates RABackendLLAMACPP.xcframework into Flutter iOS apps.
# RABackendLLAMACPP provides LLM text generation capabilities using llama.cpp.
#
# Binary Configuration:
#   - Set RA_TEST_LOCAL=1 or create .testlocal file to use local binaries
#   - Otherwise, binaries are downloaded from GitHub releases (production mode)
#
# Version: Must match Swift SDK's Package.swift and Kotlin SDK's build.gradle.kts
#

# =============================================================================
# Version Constants (MUST match Swift Package.swift)
# =============================================================================
LLAMACPP_VERSION = "0.1.4"

# =============================================================================
# Binary Source - RABackendLlamaCPP from runanywhere-binaries
# =============================================================================
GITHUB_ORG = "RunanywhereAI"
BINARIES_REPO = "runanywhere-binaries"

# =============================================================================
# testLocal Toggle
# Set RA_TEST_LOCAL=1 or create .testlocal file to use local binaries
# =============================================================================
TEST_LOCAL = ENV['RA_TEST_LOCAL'] == '1' || File.exist?(File.join(__dir__, '.testlocal'))

Pod::Spec.new do |s|
  s.name             = 'runanywhere_llamacpp'
  s.version          = '0.15.8'
  s.summary          = 'RunAnywhere LlamaCPP: LLM text generation for Flutter'
  s.description      = <<-DESC
LlamaCPP backend for RunAnywhere Flutter SDK. Provides LLM text generation
capabilities using llama.cpp. Pre-built binaries are downloaded from:
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
  # RABackendLLAMACPP XCFramework - LLM text generation
  # Downloaded from runanywhere-binaries releases
  # =============================================================================
  if TEST_LOCAL
    puts "[runanywhere_llamacpp] Using LOCAL RABackendLLAMACPP from Frameworks/"
    s.vendored_frameworks = 'Frameworks/RABackendLLAMACPP.xcframework'
  else
    s.prepare_command = <<-CMD
      set -e

      FRAMEWORK_DIR="Frameworks"
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

      echo "📦 Downloading RABackendLLAMACPP.xcframework version $VERSION..."

      mkdir -p "$FRAMEWORK_DIR"
      rm -rf "$FRAMEWORK_DIR/RABackendLLAMACPP.xcframework"

      # Download from runanywhere-binaries
      DOWNLOAD_URL="https://github.com/#{GITHUB_ORG}/#{BINARIES_REPO}/releases/download/core-v$VERSION/RABackendLlamaCPP-ios-v$VERSION.zip"
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

    s.vendored_frameworks = 'Frameworks/RABackendLLAMACPP.xcframework'
  end

  s.preserve_paths = 'Frameworks/**/*'

  # Required frameworks
  s.frameworks = [
    'Foundation',
    'CoreML',
    'Accelerate'
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
    'OTHER_LDFLAGS' => '-lc++',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'ENABLE_BITCODE' => 'NO',
  }

  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
