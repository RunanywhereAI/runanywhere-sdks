#
# RunAnywhere Flutter SDK - iOS Plugin
#
# This podspec integrates the RunAnywhere native library (RunAnywhereCore.xcframework)
# into Flutter iOS apps.
#
# Setup:
#   1. Download binaries: cd ../scripts && ./setup_native.sh --platform ios
#   2. Or use remote: The xcframework will be downloaded from runanywhere-binaries
#

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
  # Downloaded via: ./scripts/setup_native.sh --platform ios
  # Or from: https://github.com/RunanywhereAI/runanywhere-binaries/releases
  s.vendored_frameworks = 'Frameworks/RunAnywhereCore.xcframework'

  # Preserve framework paths
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

  # Prepare command to check for xcframework
  s.prepare_command = <<-CMD
    if [ ! -d "Frameworks/RunAnywhereCore.xcframework" ]; then
      echo "⚠️  RunAnywhereCore.xcframework not found!"
      echo ""
      echo "Please download binaries using one of these methods:"
      echo ""
      echo "  Option 1 - Using setup script:"
      echo "    cd .. && ./scripts/setup_native.sh --platform ios"
      echo ""
      echo "  Option 2 - Manual download:"
      echo "    curl -L https://github.com/RunanywhereAI/runanywhere-binaries/releases/latest/download/RunAnywhereCore.xcframework.zip -o Frameworks/xcframework.zip"
      echo "    unzip Frameworks/xcframework.zip -d Frameworks/"
      echo ""
    fi
  CMD
end
