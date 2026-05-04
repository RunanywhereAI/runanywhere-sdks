#
# RunAnywhere ONNX Backend - iOS
#
# Vendors the locally built RABackendONNX.xcframework (STT/TTS/VAD/embeddings
# via ONNX Runtime + Sherpa-ONNX) into Flutter iOS apps.
#
# The xcframework is staged into this plugin's ios/Frameworks/ directory by
# scripts/build-core-xcframework.sh → sync_flutter_frameworks().
#
# Note: as of v0.19.0 the ONNX Runtime C library is statically linked
# directly into RABackendONNX.a — no separate onnxruntime.xcframework is
# required (matches the Swift SPM + React Native setup).
#

Pod::Spec.new do |s|
  s.name             = 'runanywhere_onnx'
  s.version          = '0.16.0'
  s.summary          = 'RunAnywhere ONNX: STT, TTS, VAD for Flutter'
  s.description      = <<-DESC
ONNX Runtime backend for RunAnywhere Flutter SDK. Provides speech-to-text (STT),
text-to-speech (TTS), voice activity detection (VAD), and embeddings via
ONNX Runtime and Sherpa-ONNX — all statically linked into
RABackendONNX.xcframework.
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'MIT' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  s.ios.deployment_target = '15.1'
  s.swift_version = '5.0'

  # Source files (plugin entry point only — native logic lives in xcframework).
  s.source_files = 'Classes/**/*'

  s.dependency 'Flutter'
  s.dependency 'runanywhere'

  # =============================================================================
  # Vendored xcframework (built by scripts/build-core-xcframework.sh)
  # =============================================================================
  s.vendored_frameworks = 'Frameworks/RABackendONNX.xcframework'
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

  # See runanywhere.podspec for rationale on EXCLUDED_ARCHS.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -lz',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'ENABLE_BITCODE' => 'NO',
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/Frameworks/RABackendONNX.xcframework/ios-arm64/Headers"',
      '"${PODS_TARGET_SRCROOT}/Frameworks/RABackendONNX.xcframework/ios-arm64-simulator/Headers"',
    ].join(' '),
  }

  # -all_load ensures every object in RABackendONNX.xcframework is linked;
  # Flutter FFI resolves symbols via dlsym() at runtime.
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -lz -all_load',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  s.static_framework = true
end
