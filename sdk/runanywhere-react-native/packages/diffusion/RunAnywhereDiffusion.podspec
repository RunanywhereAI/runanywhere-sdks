require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RunAnywhereDiffusion"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://runanywhere.com"
  s.license      = package["license"]
  s.authors      = "RunAnywhere AI"

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # No vendored framework - diffusion uses RACommons from RunAnywhereCore
  # Source: C++ bridge + Nitrogen-generated iOS files
  s.source_files = [
    "cpp/HybridRunAnywhereDiffusion.cpp",
    "cpp/HybridRunAnywhereDiffusion.hpp",
    "cpp/bridges/**/*.{cpp,hpp}",
  ]

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/cpp/bridges",
      "$(PODS_TARGET_SRCROOT)/nitrogen/generated/shared/c++",
      "$(PODS_TARGET_SRCROOT)/../core/ios/Binaries/RACommons.xcframework/ios-arm64/RACommons.framework/Headers",
      "$(PODS_TARGET_SRCROOT)/../core/ios/Binaries/RACommons.xcframework/ios-arm64_x86_64-simulator/RACommons.framework/Headers",
      "$(PODS_TARGET_SRCROOT)/../core/cpp/third_party",
      "$(PODS_ROOT)/Headers/Public",
    ].join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) HAS_DIFFUSION=1",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
  }

  s.libraries = "c++"
  s.frameworks = "Accelerate", "Foundation", "CoreML"

  s.dependency "RunAnywhereCore"
  s.dependency "React-jsi"
  s.dependency "React-callinvoker"

  load "nitrogen/generated/ios/RunAnywhereDiffusion+autolinking.rb"
  add_nitrogen_files(s)

  install_modules_dependencies(s)
end
