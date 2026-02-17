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
  # =============================================================================
  puts "[RunAnywhereCore] Using bundled RACommons.xcframework from npm package"
  s.vendored_frameworks = "ios/Binaries/RACommons.xcframework"

  # Source files
  s.source_files = [
    "ios/**/*.{swift}",
    "ios/**/*.{h,m,mm}",
    "cpp/HybridRunAnywhereCore.cpp",
    "cpp/HybridRunAnywhereCore.hpp",
    "cpp/bridges/**/*.{cpp,hpp}",
  ]

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/cpp/bridges",
      "$(PODS_TARGET_SRCROOT)/cpp/third_party",
      "$(PODS_TARGET_SRCROOT)/ios/Binaries/RACommons.xcframework/ios-arm64/RACommons.framework/Headers",
      "$(PODS_TARGET_SRCROOT)/ios/Binaries/RACommons.xcframework/ios-arm64_x86_64-simulator/RACommons.framework/Headers",
      "$(PODS_ROOT)/Headers/Public",
    ].join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) HAS_RACOMMONS=1",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
  }

  s.libraries = "c++", "archive", "bz2"
  s.frameworks = "Accelerate", "Foundation", "CoreML", "AudioToolbox"

  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  load 'nitrogen/generated/ios/RunAnywhereCore+autolinking.rb'
  add_nitrogen_files(s)

  install_modules_dependencies(s)
end
