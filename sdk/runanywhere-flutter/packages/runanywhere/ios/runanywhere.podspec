#
# RunAnywhere Core SDK - iOS
#
# Vendors the locally built RACommons.xcframework (plus the C++ RAG bridge
# source that consumes RACommons' C API) into Flutter iOS apps.
#
# The xcframework is staged into this plugin's ios/Frameworks/ directory by
# scripts/build-core-xcframework.sh → sync_flutter_frameworks(). Run that
# script once after checkout, and re-run it whenever the native layer changes.
#

Pod::Spec.new do |s|
  s.name             = 'runanywhere'
  s.version          = '0.16.0'
  s.summary          = 'RunAnywhere: Privacy-first, on-device AI SDK for Flutter'
  s.description      = <<-DESC
Privacy-first, on-device AI SDK for Flutter. This package provides the core
infrastructure (RACommons) for speech-to-text (STT), text-to-speech (TTS),
language models (LLM), voice activity detection (VAD), embeddings, and RAG.
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'MIT' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  s.ios.deployment_target = '15.1'
  s.swift_version = '5.0'

  # Source files: Swift plugin entry point + C++ RAG bridge. The bridge
  # includes `third_party/nlohmann/json.hpp` from the package root (src/)
  # via Classes/ symlinks — see HEADER_SEARCH_PATHS below.
  s.source_files = 'Classes/**/*'

  s.dependency 'Flutter'

  # =============================================================================
  # Vendored xcframework (built by scripts/build-core-xcframework.sh)
  # =============================================================================
  s.vendored_frameworks = 'Frameworks/RACommons.xcframework'

  # Keep the source tree that the RAG bridge includes and the xcframework
  # next to the installed pod so downstream toolchains can resolve headers.
  s.preserve_paths = ['Frameworks/**/*', '../src/**/*', 'Classes/third_party/**/*']

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

  # ---------------------------------------------------------------------------
  # pod_target_xcconfig
  #
  # EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64
  #   The locally built xcframework only ships `ios-arm64` + `ios-arm64-simulator`
  #   slices (no `ios-arm64_x86_64-simulator`). Xcode's default simulator archs
  #   include x86_64 on Intel hosts; exclude it so the linker doesn't try to
  #   pull a slice that isn't there.
  #
  # HEADER_SEARCH_PATHS
  #   - Classes / ../src: nlohmann/json.hpp (vendored under third_party/)
  #   - RACommons.xcframework/*/Headers: rac/** C API headers consumed by the
  #     RAG bridge (surfaced by -headers on `xcodebuild -create-xcframework`).
  # ---------------------------------------------------------------------------
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    # -lz matches the Swift SDK (Package.swift linkerSettings) — libarchive
    # + libcurl baked into RACommons both transitively need zlib.
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -lz',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'ENABLE_BITCODE' => 'NO',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/Classes"',
      '"${PODS_TARGET_SRCROOT}/Classes/third_party"',
      '"${PODS_TARGET_SRCROOT}/../src"',
      '"${PODS_TARGET_SRCROOT}/../src/third_party"',
      '"${PODS_TARGET_SRCROOT}/Frameworks/RACommons.xcframework/ios-arm64/Headers"',
      '"${PODS_TARGET_SRCROOT}/Frameworks/RACommons.xcframework/ios-arm64-simulator/Headers"',
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited)',
  }

  # ---------------------------------------------------------------------------
  # user_target_xcconfig
  #
  # Flags that must propagate to the hosting app target so FFI symbols from
  # vendored static frameworks actually reach the final binary:
  #   -ObjC                  load Obj-C categories from static archives
  #   -all_load              link every object in every static archive
  #   -Wl,-export_dynamic    export local symbols so dlsym() can find them
  #                          (Flutter FFI relies on DynamicLibrary.executable())
  #   DEAD_CODE_STRIPPING=NO don't let the linker drop unreferenced symbols
  # ---------------------------------------------------------------------------
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -lz -ObjC -all_load -Wl,-export_dynamic',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  s.static_framework = true
end
