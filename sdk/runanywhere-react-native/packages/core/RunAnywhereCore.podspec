require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RunAnywhereCore"
  s.module_name  = "RunAnywhereCore"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://runanywhere.com"
  s.license      = package["license"]
  s.authors      = "RunAnywhere AI"

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # =============================================================================
  # Core SDK - RACommons xcframework is bundled in npm package
  # No downloads needed - framework is included in ios/Binaries/
  # RAG pipeline is compiled directly into RACommons.
  # =============================================================================
  puts "[RunAnywhereCore] Using bundled xcframeworks from npm package"
  s.vendored_frameworks = [
    "ios/Binaries/RACommons.xcframework",
  ]

  # Source files
  s.source_files = [
    "ios/**/*.{swift}",
    "ios/**/*.{h,m,mm}",
    "cpp/HybridLLM.cpp",
    "cpp/HybridLLM.hpp",
    "cpp/HybridRunAnywhereCore.cpp",
    "cpp/HybridRunAnywhereCore+*.cpp",
    "cpp/HybridRunAnywhereCore+Common.hpp",
    "cpp/HybridRunAnywhereCore.hpp",
    "cpp/HybridVoiceAgent.cpp",
    "cpp/HybridVoiceAgent.hpp",
    "cpp/bridges/**/*.{cpp,hpp}",
  ]

  # Build header search paths: include the Headers root (for qualified includes
  # like "rac/core/rac_types.h") plus every subdirectory (for flat includes
  # like "rac_types.h").  Computed dynamically so new xcframework subdirectories
  # are picked up automatically.
  rac_headers_root = "ios/Binaries/RACommons.xcframework/ios-arm64/Headers"
  rac_header_dirs = Dir.glob(File.join(__dir__, rac_headers_root, "**", "*.h"))
                       .map { |f| File.dirname(f) }
                       .uniq
                       .map { |d| "$(PODS_TARGET_SRCROOT)/" + d.sub(__dir__ + "/", "") }

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "HEADER_SEARCH_PATHS" => ([
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/cpp/bridges",
      "$(PODS_TARGET_SRCROOT)/cpp/third_party",
      "$(PODS_ROOT)/Headers/Public",
    ] + rac_header_dirs).join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) HAS_RACOMMONS=1 RAC_HAS_HTTP_TRANSPORT=1",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
  }

  s.libraries = "c++", "archive", "bz2", "z"
  s.frameworks = "Accelerate", "Foundation", "CoreML", "AudioToolbox", "CFNetwork", "Security", "SystemConfiguration"

  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  load 'nitrogen/generated/ios/RunAnywhereCore+autolinking.rb'
  add_nitrogen_files(s)

  install_modules_dependencies(s)
end
