#
# RunAnywhere Core SDK - iOS
#
# This podspec integrates RACommons.xcframework and RABackendRAG.xcframework
# into Flutter iOS apps. RACommons provides the core infrastructure for
# on-device AI capabilities. RABackendRAG provides the RAG pipeline backend.
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
COMMONS_VERSION = "0.1.6"
RAG_VERSION = "0.1.6"

# =============================================================================
# Binary Source - RACommons and RABackendRAG from runanywhere-sdks
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
  s.version          = '0.16.0'
  s.summary          = 'RunAnywhere: Privacy-first, on-device AI SDK for Flutter'
  s.description      = <<-DESC
Privacy-first, on-device AI SDK for Flutter. This package provides the core
infrastructure (RACommons) for speech-to-text (STT), text-to-speech (TTS),
language models (LLM), voice activity detection (VAD), and embeddings.
RABackendRAG provides the RAG pipeline for document ingestion and querying.
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
  # RABackendRAG XCFramework - RAG pipeline backend
  # Both downloaded from runanywhere-sdks releases
  # =============================================================================
  if TEST_LOCAL
    puts "[runanywhere] Using LOCAL RACommons from Frameworks/"
    puts "[runanywhere] Using LOCAL RABackendRAG from Frameworks/"
    s.vendored_frameworks = [
      'Frameworks/RACommons.xcframework',
      'Frameworks/RABackendRAG.xcframework'
    ]
  else
    s.prepare_command = <<-CMD
      set -e

      FRAMEWORK_DIR="Frameworks"

      # ---------------------------------------------------------------------------
      # RACommons
      # ---------------------------------------------------------------------------
      COMMONS_VERSION="#{COMMONS_VERSION}"
      COMMONS_VERSION_FILE="$FRAMEWORK_DIR/.racommons_version"

      # Check if already downloaded with correct version
      if [ -f "$COMMONS_VERSION_FILE" ] && [ -d "$FRAMEWORK_DIR/RACommons.xcframework" ]; then
        CURRENT_VERSION=$(cat "$COMMONS_VERSION_FILE")
        if [ "$CURRENT_VERSION" = "$COMMONS_VERSION" ]; then
          echo "RACommons.xcframework version $COMMONS_VERSION already downloaded"
        else
          SKIP_COMMONS=false
        fi
      else
        SKIP_COMMONS=false
      fi

      if [ "${SKIP_COMMONS:-true}" != "true" ]; then
        echo "Downloading RACommons.xcframework version $COMMONS_VERSION..."

        mkdir -p "$FRAMEWORK_DIR"
        rm -rf "$FRAMEWORK_DIR/RACommons.xcframework"

        COMMONS_DOWNLOAD_URL="https://github.com/#{GITHUB_ORG}/#{COMMONS_REPO}/releases/download/commons-v$COMMONS_VERSION/RACommons-ios-v$COMMONS_VERSION.zip"
        COMMONS_ZIP_FILE="/tmp/RACommons.zip"

        echo "   URL: $COMMONS_DOWNLOAD_URL"

        curl -L -f -o "$COMMONS_ZIP_FILE" "$COMMONS_DOWNLOAD_URL" || {
          echo "Failed to download RACommons from $COMMONS_DOWNLOAD_URL"
          exit 1
        }

        echo "Extracting RACommons.xcframework..."
        unzip -q -o "$COMMONS_ZIP_FILE" -d "$FRAMEWORK_DIR/"
        rm -f "$COMMONS_ZIP_FILE"

        echo "$COMMONS_VERSION" > "$COMMONS_VERSION_FILE"

        if [ -d "$FRAMEWORK_DIR/RACommons.xcframework" ]; then
          echo "RACommons.xcframework installed successfully"
        else
          echo "RACommons.xcframework extraction failed"
          exit 1
        fi
      fi

      # ---------------------------------------------------------------------------
      # RABackendRAG
      # ---------------------------------------------------------------------------
      RAG_VERSION="#{RAG_VERSION}"
      RAG_VERSION_FILE="$FRAMEWORK_DIR/.rag_version"

      # Check if already downloaded with correct version
      if [ -f "$RAG_VERSION_FILE" ] && [ -d "$FRAMEWORK_DIR/RABackendRAG.xcframework" ]; then
        CURRENT_RAG_VERSION=$(cat "$RAG_VERSION_FILE")
        if [ "$CURRENT_RAG_VERSION" = "$RAG_VERSION" ]; then
          echo "RABackendRAG.xcframework version $RAG_VERSION already downloaded"
        else
          SKIP_RAG=false
        fi
      else
        SKIP_RAG=false
      fi

      if [ "${SKIP_RAG:-true}" != "true" ]; then
        echo "Downloading RABackendRAG.xcframework version $RAG_VERSION..."

        mkdir -p "$FRAMEWORK_DIR"
        rm -rf "$FRAMEWORK_DIR/RABackendRAG.xcframework"

        RAG_DOWNLOAD_URL="https://github.com/#{GITHUB_ORG}/#{COMMONS_REPO}/releases/download/commons-v$RAG_VERSION/RABackendRAG-ios-v$RAG_VERSION.zip"
        RAG_ZIP_FILE="/tmp/RABackendRAG.zip"

        echo "   URL: $RAG_DOWNLOAD_URL"

        curl -L -f -o "$RAG_ZIP_FILE" "$RAG_DOWNLOAD_URL" || {
          echo "Failed to download RABackendRAG from $RAG_DOWNLOAD_URL"
          exit 1
        }

        echo "Extracting RABackendRAG.xcframework..."
        unzip -q -o "$RAG_ZIP_FILE" -d "$FRAMEWORK_DIR/"
        rm -f "$RAG_ZIP_FILE"

        echo "$RAG_VERSION" > "$RAG_VERSION_FILE"

        if [ -d "$FRAMEWORK_DIR/RABackendRAG.xcframework" ]; then
          echo "RABackendRAG.xcframework installed successfully"
        else
          echo "RABackendRAG.xcframework extraction failed"
          exit 1
        fi
      fi
    CMD

    s.vendored_frameworks = [
      'Frameworks/RACommons.xcframework',
      'Frameworks/RABackendRAG.xcframework'
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
  # from vendored static frameworks are linked AND EXPORTED in the final binary.
  #
  # -ObjC ensures Objective-C categories are loaded.
  # -all_load forces ALL object files from static libraries to be linked.
  # DEAD_CODE_STRIPPING=NO prevents unused symbol removal.
  #
  # SYMBOL EXPORT FIX (iOS):
  # When using `use_frameworks! :linkage => :static`, symbols from static frameworks
  # become LOCAL in the final dylib, making them invisible to dlsym() at runtime.
  # Flutter FFI uses dlsym() to find symbols, so we MUST explicitly export them.
  #
  # -Wl,-export_dynamic exports ALL symbols from the dylib, making them accessible
  # via dlsym(). This is broader than -exported_symbols_list but ensures Flutter's
  # own symbols are not accidentally hidden.
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -ObjC -all_load -Wl,-export_dynamic',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  # Mark static framework for proper linking
  s.static_framework = true
end
