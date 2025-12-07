require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# XCFramework configuration
XCFRAMEWORK_VERSION = "0.0.1-dev.e0bac69"
XCFRAMEWORK_NAME = "RunAnywhereCore"

Pod::Spec.new do |s|
  # Pod name must match the Nitrogen module name for Swift interop
  s.name         = "RunAnywhere"
  s.module_name  = "RunAnywhere"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # Source files - C++ HybridObject + Swift implementations
  s.source_files = [
    "ios/**/*.{swift}",
    "ios/**/*.{h,m,mm}",
    "cpp/HybridRunAnywhere.cpp",
    "cpp/HybridRunAnywhere.hpp",
    "cpp/include/**/*.{h,hpp}",
  ]

  # XCFramework with runanywhere-core (ONNX Runtime + LlamaCpp + Sherpa-ONNX)
  s.vendored_frameworks = "ios/Frameworks/#{XCFRAMEWORK_NAME}.xcframework"

  # Build settings
  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/cpp/include",
      "$(PODS_ROOT)/Headers/Public",
    ].join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited)",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
  }

  # Required system libraries and frameworks
  s.libraries = "c++", "archive", "bz2"
  s.frameworks = "Accelerate", "Foundation", "CoreML", "AudioToolbox"

  # React Native dependencies
  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  # Load Nitrogen-generated autolinking
  load 'nitrogen/generated/ios/RunAnywhere+autolinking.rb'
  add_nitrogen_files(s)

  # Install React Native module dependencies
  install_modules_dependencies(s)
end
