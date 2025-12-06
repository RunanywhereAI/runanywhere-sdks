#
# RunAnywhere Flutter SDK - iOS Plugin
#
# This podspec integrates the RunAnywhere native library (RunAnywhereCore.xcframework)
# into Flutter iOS apps.
#
# Configuration:
#   Edit ../binary_config.rb to toggle between local and remote binaries:
#   - TEST_LOCAL = true:  Use local xcframework from ios/Frameworks/ (for development)
#   - TEST_LOCAL = false: Download from GitHub releases (for production)
#
# Local mode setup:
#   1. Build locally: cd ../../runanywhere-core/scripts/ios && ./build.sh --all
#   2. Copy: cp -R ../dist/RunAnywhereCore.xcframework path/to/flutter-sdk/ios/Frameworks/
#
# Remote mode: Binaries are automatically downloaded from runanywhere-binaries releases
#

# Load binary configuration
require_relative '../binary_config.rb'

Pod::Spec.new do |s|
  s.name             = 'runanywhere'
  s.version          = '0.15.8'
  s.summary          = 'RunAnywhere: On-device AI SDK for Flutter'
  s.description      = <<-DESC
Privacy-first, on-device AI SDK for Flutter. Provides native capabilities for
speech-to-text (STT), text-to-speech (TTS), language models (LLM), voice activity
detection (VAD), and embeddings.

Pre-built binaries are downloaded from:
https://github.com/RunanywhereAI/runanywhere-binaries
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.0'

  # Source files (minimal - main logic is in the xcframework)
  s.source_files = 'Classes/**/*'

  # Flutter dependency
  s.dependency 'Flutter'

  # Link to RunAnywhereCore XCFramework
  # Mode is controlled by binary_config.rb (testLocal flag)
  if RunAnywhereBinaryConfig.test_local?
    # Local mode: Use xcframework from Frameworks/ directory
    s.vendored_frameworks = 'Frameworks/RunAnywhereCore.xcframework'
    s.preserve_paths = 'Frameworks/**/*'
  else
    # Remote mode: Download from GitHub releases
    # Note: CocoaPods doesn't support remote binary downloads in podspecs directly
    # So we download in prepare_command and then use it locally
    s.vendored_frameworks = 'Frameworks/RunAnywhereCore.xcframework'
    s.preserve_paths = 'Frameworks/**/*'
  end

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
  }

  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }

  # Prepare command to download xcframework if in remote mode
  s.prepare_command = <<-CMD
    # Load configuration to check mode
    TEST_LOCAL=#{RunAnywhereBinaryConfig.test_local?}

    if [ "$TEST_LOCAL" = "false" ]; then
      echo "📦 Remote mode: Downloading RunAnywhereCore.xcframework..."

      if [ ! -d "Frameworks/RunAnywhereCore.xcframework" ]; then
        mkdir -p Frameworks
        cd Frameworks

        # Download from GitHub releases
        DOWNLOAD_URL="#{RunAnywhereBinaryConfig::IOS_XCFRAMEWORK_URL}"
        echo "Downloading from: $DOWNLOAD_URL"

        curl -L "$DOWNLOAD_URL" -o RunAnywhereCore.xcframework.zip
        unzip -q RunAnywhereCore.xcframework.zip
        rm RunAnywhereCore.xcframework.zip

        echo "✅ XCFramework downloaded successfully"
      else
        echo "✅ XCFramework already exists"
      fi
    else
      echo "🔧 Local mode: Using xcframework from Frameworks/ directory"

      if [ ! -d "Frameworks/RunAnywhereCore.xcframework" ]; then
        echo "⚠️  RunAnywhereCore.xcframework not found!"
        echo ""
        echo "For local mode, please build and copy the xcframework:"
        echo "  1. cd ../../runanywhere-core/scripts/ios && ./build.sh --all"
        echo "  2. cp -R ../dist/RunAnywhereCore.xcframework path/to/flutter-sdk/ios/Frameworks/"
        echo ""
        echo "Or switch to remote mode by editing binary_config.rb:"
        echo "  TEST_LOCAL = false"
        echo ""
        exit 1
      else
        echo "✅ Using local xcframework"
      fi
    fi
  CMD
end
