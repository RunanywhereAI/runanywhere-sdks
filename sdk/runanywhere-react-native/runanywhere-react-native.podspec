require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
folly_compiler_flags = '-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1 -Wno-comma -Wno-shorten-64-to-32'

Pod::Spec.new do |s|
  s.name         = "runanywhere-react-native"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/RunanywhereAI/sdks.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"

  # React Native dependencies
  install_modules_dependencies(s)

  # RunAnywhere Swift SDK dependency
  # When the Swift SDK is published to CocoaPods, uncomment this:
  # s.dependency "RunAnywhere", "~> 1.0"

  # For local development, you can use:
  # s.dependency "RunAnywhere", :path => "../runanywhere-swift"

  s.swift_version = "5.9"
end
