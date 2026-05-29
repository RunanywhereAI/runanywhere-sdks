require "json"
require "pathname"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RunAnywhereLlama"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://runanywhere.com"
  s.license      = package["license"]
  s.authors      = "RunAnywhere AI"

  s.platforms    = { :ios => "17.0" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # =============================================================================
  # LlamaCPP Backend - xcframework is bundled in npm package
  # No downloads needed - framework is included in ios/Binaries/
  # =============================================================================
  puts "[RunAnywhereLlama] Using bundled RABackendLLAMACPP.xcframework from npm package"
  s.vendored_frameworks = "ios/Binaries/RABackendLLAMACPP.xcframework"

  # Source files
  s.source_files = [
    "cpp/HybridRunAnywhereLlama.cpp",
    "cpp/HybridRunAnywhereLlama.hpp",
  ]

  rac_headers_root = File.expand_path("../core/ios/Binaries/RACommons.xcframework/ios-arm64/Headers", __dir__)
  rac_header_dirs = Dir.glob(File.join(rac_headers_root, "**", "*.h"))
                       .map { |f| File.dirname(f) }
                       .uniq
                       .map { |d| "$(PODS_TARGET_SRCROOT)/" + Pathname.new(d).relative_path_from(Pathname.new(__dir__)).to_s }

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "HEADER_SEARCH_PATHS" => ([
      "$(PODS_TARGET_SRCROOT)/cpp",
      # nlohmann/json (header-only) vendored by sibling @runanywhere/core package.
      "$(PODS_TARGET_SRCROOT)/../core/cpp/third_party",
      "$(PODS_ROOT)/Headers/Public",
    ] + rac_header_dirs).join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) HAS_LLAMACPP=1",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
  }

  s.libraries = "c++"
  s.frameworks = "Accelerate", "Foundation", "Metal", "MetalKit"

  s.dependency 'RunAnywhereCore', "~> #{s.version}"
  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  load 'nitrogen/generated/ios/RunAnywhereLlama+autolinking.rb'
  add_nitrogen_files(s)

  install_modules_dependencies(s)
end
