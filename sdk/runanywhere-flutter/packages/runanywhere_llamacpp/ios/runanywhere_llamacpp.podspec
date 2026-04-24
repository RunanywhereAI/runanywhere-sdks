#
# RunAnywhere LlamaCPP Backend - iOS
#
# Vendors the locally built RABackendLLAMACPP.xcframework (LLM text
# generation via llama.cpp) into Flutter iOS apps.
#
# The xcframework is staged into this plugin's ios/Frameworks/ directory by
# scripts/build-core-xcframework.sh → sync_flutter_frameworks().
#

Pod::Spec.new do |s|
  s.name             = 'runanywhere_llamacpp'
  s.version          = '0.16.0'
  s.summary          = 'RunAnywhere LlamaCPP: LLM text generation for Flutter'
  s.description      = <<-DESC
LlamaCPP backend for RunAnywhere Flutter SDK. Provides LLM text generation
capabilities using llama.cpp via RABackendLLAMACPP.xcframework.
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
  # Depend on the core pod for RACommons (registry, tensor layer, etc).
  s.dependency 'runanywhere'

  # =============================================================================
  # Vendored xcframework (built by scripts/build-core-xcframework.sh)
  # =============================================================================
  s.vendored_frameworks = 'Frameworks/RABackendLLAMACPP.xcframework'
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

  # See runanywhere.podspec for rationale on EXCLUDED_ARCHS + HEADER_SEARCH_PATHS.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '-lc++',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'ENABLE_BITCODE' => 'NO',
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/Frameworks/RABackendLLAMACPP.xcframework/ios-arm64/Headers"',
      '"${PODS_TARGET_SRCROOT}/Frameworks/RABackendLLAMACPP.xcframework/ios-arm64-simulator/Headers"',
    ].join(' '),
  }

  # -all_load ensures every object in RABackendLLAMACPP.xcframework is linked,
  # including `rac_backend_llamacpp_register` / `rac_llm_llamacpp_*` that are
  # only referenced via Flutter FFI's dlsym() at runtime.
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '-lc++ -all_load',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  s.static_framework = true
end
