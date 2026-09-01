require "json"
require "pathname"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RunAnywhereLlama"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://runanywhere.ai"
  s.license      = { type: "RunAnywhere License", file: "LICENSE" }
  s.authors      = "RunAnywhere AI"

  s.platforms    = { :ios => "17.5" }
  s.swift_version = "6.2"
  # TEMP: the source tag is pinned to the last release that was actually
  # tagged, not to s.version. s.version tracks package.json and leads the
  # published release whenever a release republishes only some packages, and
  # a tag built from s.version then resolves to one that was never pushed, so
  # `pod install` fails outright. Mirrors asset_version in the Flutter
  # podspecs. Bump back in step with the SwiftPM pin once a matching release
  # exists; check_release_version_coherence.sh enforces that they agree.
  source_tag_version = '0.20.33'
  s.source       = { :git => "https://github.com/RunanywhereAI/runanywhere-sdks.git", :tag => "v#{source_tag_version}" }

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

  # Header search paths for the RACommons xcframework (sibling @runanywhere/core
  # package). Include the Headers root so qualified includes like
  # "rac/backends/rac_llm_llamacpp.h" (and the canonical header's own
  # "rac/core/..."/"rac/features/llm/..." includes) resolve, plus every
  # subdirectory for flat includes like "rac_logger.h".
  rac_headers_root = File.expand_path("../core/ios/Binaries/RACommons.xcframework/ios-arm64/Headers", __dir__)
  rac_headers_root_rel = "$(PODS_TARGET_SRCROOT)/" +
                         Pathname.new(rac_headers_root).relative_path_from(Pathname.new(__dir__)).to_s
  rac_header_dirs = [rac_headers_root_rel] +
                    Dir.glob(File.join(rac_headers_root, "**", "*.h"))
                       .map { |f| File.dirname(f) }
                       .uniq
                       .map { |d| "$(PODS_TARGET_SRCROOT)/" + Pathname.new(d).relative_path_from(Pathname.new(__dir__)).to_s }

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "HEADER_SEARCH_PATHS" => ([
      # Package-local hybrid headers (HybridRunAnywhereLlama.hpp) — needed by the
      # nitrogen-generated OnLoad + cpp-adapter (the forked rac_llm_llamacpp.h that
      # used to live here was deleted; canonical commons header comes via rac_header_dirs).
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
