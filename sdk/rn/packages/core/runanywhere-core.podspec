require 'json'
pkg = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name             = "RunAnywhereCore"
  s.version          = pkg['version']
  s.summary          = pkg['description']
  s.homepage         = pkg['repository']
  s.license          = "Apache-2.0"
  s.authors          = "RunAnywhere AI, Inc."
  s.platforms        = { :ios => "17.0" }
  s.source           = { :git => "https://github.com/RunanywhereAI/runanywhere-sdks.git", :tag => "v#{s.version}" }
  s.source_files     = "cpp/**/*.{h,hpp,cpp,mm}", "ios/**/*.{h,m,mm}"
  s.public_header_files = "cpp/**/*.h"
  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "HEADER_SEARCH_PATHS" => [
      "$(PODS_TARGET_SRCROOT)/cpp",
      "$(PODS_TARGET_SRCROOT)/../../../swift/Binaries/RACommonsCore.xcframework/ios-arm64/Headers",
    ].join(" "),
  }
  s.vendored_frameworks = "../../../swift/Binaries/RACommonsCore.xcframework"
  s.dependency "React-Core"
  s.dependency "react-native-nitro-modules"
end
