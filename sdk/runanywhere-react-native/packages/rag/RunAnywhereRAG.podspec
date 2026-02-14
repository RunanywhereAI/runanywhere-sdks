require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RunAnywhereRAG"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://runanywhere.com"
  s.license      = package["license"]
  s.authors      = "RunAnywhere AI"

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  # =============================================================================
  # RAG Backend - XCFrameworks bundled in npm package
  # Using XCFramework format to support arm64 on both device and simulator
  # =============================================================================
  puts "[RunAnywhereRAG] Using bundled XCFrameworks from npm package"
  s.vendored_frameworks = [
    "ios/Libraries/rac_backend_rag.xcframework",
    "ios/Libraries/rac_backend_onnx.xcframework"
  ]

  # Source files
  s.source_files = [
    "cpp/HybridRunAnywhereRAG.cpp",
    "cpp/HybridRunAnywhereRAG.hpp",
  ]

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/ios/Headers",
      "$(PODS_TARGET_SRCROOT)/../core/ios/Headers",
      "$(PODS_TARGET_SRCROOT)/../llamacpp/ios/Headers",
      "$(PODS_TARGET_SRCROOT)/../onnx/ios/Headers",
      "$(PODS_ROOT)/Headers/Public",
    ].join(" "),
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) HAS_RAG=1 HAS_LLAMACPP=1 HAS_ONNX=1",
    "DEFINES_MODULE" => "YES",
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
    "OTHER_LDFLAGS" => "-lc++",
  }

  s.libraries = "c++"
  s.frameworks = "Accelerate", "Foundation", "CoreML"

  # Dependencies
  s.dependency 'RunAnywhereCore'
  s.dependency 'RunAnywhereLlama'
  s.dependency 'RunAnywhereONNX'
  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  load 'nitrogen/generated/ios/RunAnywhereRAG+autolinking.rb'
  add_nitrogen_files(s)

  install_modules_dependencies(s)
end
