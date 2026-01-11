#
# RunAnywhere Core SDK - iOS
#
# This podspec integrates RACommons.xcframework into Flutter iOS apps.
# RACommons provides the core infrastructure for on-device AI capabilities.
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
COMMONS_VERSION = "0.1.4"

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
  s.name             = 'runanywhere'
  s.version          = '0.15.8'
  s.summary          = 'RunAnywhere: Privacy-first, on-device AI SDK for Flutter'
  s.description      = <<-DESC
Privacy-first, on-device AI SDK for Flutter. This package provides the core
infrastructure (RACommons) for speech-to-text (STT), text-to-speech (TTS),
language models (LLM), voice activity detection (VAD), and embeddings.
Pre-built binaries are downloaded from:
https://github.com/RunanywhereAI/runanywhere-sdks
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

  # =============================================================================
  # RACommons XCFramework - Core infrastructure
  # Downloaded from runanywhere-sdks releases (NOT runanywhere-binaries)
  # =============================================================================
  if TEST_LOCAL
    puts "[runanywhere] Using LOCAL RACommons from Frameworks/"
    s.vendored_frameworks = 'Frameworks/RACommons.xcframework'
  else
    s.prepare_command = <<-CMD
      set -e

      FRAMEWORK_DIR="Frameworks"
      VERSION="#{COMMONS_VERSION}"
      VERSION_FILE="$FRAMEWORK_DIR/.racommons_version"

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

      # Download from runanywhere-sdks
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

    s.vendored_frameworks = 'Frameworks/RACommons.xcframework'
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
  # Note: -all_load forces all symbols from static libraries to be loaded
  # With static linkage (use_frameworks! :linkage => :static in Podfile),
  # all symbols from RACommons.xcframework will be available in the final app
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'ENABLE_BITCODE' => 'NO',
  }

  # CRITICAL: These flags propagate to the main app target to ensure all symbols
  # from vendored static frameworks are linked into the final binary.
  #
  # -ObjC ensures Objective-C categories are loaded.
  # DEAD_CODE_STRIPPING=NO prevents unused symbol removal.
  #
  # Symbol retention is ensured by RunAnywherePlugin.swift which references
  # key C symbols, forcing the linker to include them even when only called via FFI.
  # CRITICAL: -all_load ensures ALL object files from static libraries are linked.
  # This is required because:
  # 1. RACommons.xcframework is a static library
  # 2. The linker normally strips "unused" symbols not directly referenced by native code
  # 3. Flutter FFI calls these symbols at runtime via dlsym() which the linker can't see
  # Without -all_load, symbols like rac_llm_component_create won't be in the final binary
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -ObjC -all_load',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  # Mark static framework for proper linking
  s.static_framework = true
end
