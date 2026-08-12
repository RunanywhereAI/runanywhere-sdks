require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name          = "RunAnywhereMLX"
  s.version       = package["version"]
  s.summary       = package["description"]
  s.homepage      = "https://runanywhere.ai"
  s.license       = { type: "RunAnywhere License", file: "LICENSE" }
  s.authors       = "RunAnywhere AI"

  s.platforms     = { :ios => "17.5" }
  s.swift_version = "6.2"
  s.source        = { :git => "https://github.com/RunanywhereAI/runanywhere-sdks.git", :tag => "v#{s.version}" }

  # All three binaries are required. RABackendMLX owns the commons backend
  # plugin, RunAnywhereMLXRuntime owns the static Swift runtime, and the tiny
  # dynamic Metal framework lets Xcode embed exactly the active platform slice
  # and its default.metallib. Missing staging must fail pod installation instead
  # of silently producing a facade-only package.
  s.vendored_frameworks = [
    "ios/Binaries/RABackendMLX.xcframework",
    "ios/Binaries/RunAnywhereMLXRuntime.xcframework",
    "ios/Binaries/RunAnywhereMLXMetal.xcframework"
  ]
  s.resources = [
    "ios/Resources/swift-crypto_Crypto.bundle",
    "ios/Resources/swift-transformers_Hub.bundle"
  ]

  # Core discovers MLX through dlsym, so give the final app linker one precise
  # undefined root. This retains the static runtime archive; its strong Metal
  # resource anchor then retains the dynamic resource framework as well.
  s.user_target_xcconfig = {
    "OTHER_LDFLAGS" => "$(inherited) -Wl,-u,_ra_mlx_runtime_is_available",
  }

  s.frameworks = \
    "Accelerate", "AVFoundation", "CoreGraphics", "CoreImage", "CoreML", \
    "Foundation", "Metal", "MetalKit", "NaturalLanguage", "UIKit"
  s.libraries = "c++"
  s.dependency "RunAnywhereCore", "~> #{s.version}"
end
