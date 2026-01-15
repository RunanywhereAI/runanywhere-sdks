require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RunAnywhereONNX"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://runanywhere.com"
  s.license      = package["license"]
  s.authors      = "RunAnywhere AI"

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # =============================================================================
  # ONNX Backend - xcframeworks are bundled in npm package
  # No downloads needed - frameworks are included in ios/Frameworks/
  # =============================================================================
  puts "[RunAnywhereONNX] Using bundled xcframeworks from npm package"
  s.vendored_frameworks = [
    "ios/Frameworks/RABackendONNX.xcframework",
    "ios/Frameworks/onnxruntime.xcframework"
  ]

  # Source files
  s.source_files = [
    "cpp/HybridRunAnywhereONNX.cpp",
    "cpp/HybridRunAnywhereONNX.hpp",
    "cpp/bridges/**/*.{cpp,hpp}",
  ]

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/cpp/bridges",
      "$(PODS_TARGET_SRCROOT)/ios/Frameworks/RABackendONNX.xcframework/ios-arm64/RABackendONNX.framework/Headers",
      "$(PODS_TARGET_SRCROOT)/ios/Frameworks/RABackendONNX.xcframework/ios-arm64_x86_64-simulator/RABackendONNX.framework/Headers",
      "$(PODS_TARGET_SRCROOT)/ios/Frameworks/onnxruntime.xcframework/ios-arm64/Headers",
      "$(PODS_TARGET_SRCROOT)/ios/Frameworks/onnxruntime.xcframework/ios-arm64_x86_64-simulator/Headers",
      "$(PODS_TARGET_SRCROOT)/../core/ios/Frameworks/RACommons.xcframework/ios-arm64/RACommons.framework/Headers",
      "$(PODS_TARGET_SRCROOT)/../core/ios/Frameworks/RACommons.xcframework/ios-arm64_x86_64-simulator/RACommons.framework/Headers",
      "$(PODS_ROOT)/Headers/Public",
    ].join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) HAS_ONNX=1",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
  }

  s.libraries = "c++"
  s.frameworks = "Accelerate", "Foundation", "CoreML", "AudioToolbox"

  s.dependency 'RunAnywhereCore'
  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  load 'nitrogen/generated/ios/RunAnywhereONNX+autolinking.rb'
  add_nitrogen_files(s)

  install_modules_dependencies(s)
end
