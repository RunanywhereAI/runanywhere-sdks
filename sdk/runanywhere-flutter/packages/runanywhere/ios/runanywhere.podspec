#
# RunAnywhere Core SDK - iOS
#
# Uses a locally staged RACommons.xcframework during monorepo development. A
# clean pub.dev package downloads the checksum-pinned release archive before
# CocoaPods resolves the vendored framework.
#

package_manifest = File.read(File.join(__dir__, 'runanywhere', 'Package.swift'))
checksum_for = lambda do |name|
  match = package_manifest.match(
    /runAnywhereBinaryTarget\(\s*name:\s*"#{Regexp.escape(name)}",\s*checksum:\s*"([0-9a-f]{64})"\s*\)/m
  )
  unless match
    raise Pod::Informative, "Missing immutable checksum for #{name} in runanywhere/Package.swift"
  end

  match[1]
end

Pod::Spec.new do |s|
  s.name             = 'runanywhere'
  s.version          = '0.19.15'
  s.summary          = 'RunAnywhere: Privacy-first, on-device AI SDK for Flutter'
  s.description      = <<-DESC
Privacy-first, on-device AI SDK for Flutter. This package provides the core
infrastructure (RACommons) for speech-to-text (STT), text-to-speech (TTS),
language models (LLM), voice activity detection (VAD), embeddings, and RAG.
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'MIT' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  # Published Flutter packages intentionally omit large XCFrameworks. CocoaPods
  # runs prepare_command for both registry and `:path` pods, so fetch the exact
  # release archive when the local development framework is absent. The base URL
  # override is scoped to release-contract tests; checksums remain immutable.
  s.prepare_command = <<-CMD
set -euo pipefail

fail() {
  echo "RunAnywhere iOS preparation failed: $*" >&2
  exit 1
}

release_base_url="${RUNANYWHERE_FLUTTER_IOS_RELEASE_BASE_URL:-https://github.com/RunanywhereAI/runanywhere-sdks/releases/download}"
while [ "${release_base_url%/}" != "$release_base_url" ]; do
  release_base_url="${release_base_url%/}"
done

work_root="$(mktemp -d "${TMPDIR:-/tmp}/runanywhere-flutter-ios.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT HUP INT TERM

download_xcframework() {
  name="$1"
  expected_checksum="$2"
  framework_root="$3"
  destination="$framework_root/$name.xcframework"

  if [ -d "$destination" ]; then
    [ -f "$destination/Info.plist" ] || fail "$destination is incomplete"
    return
  fi
  [ ! -e "$destination" ] || fail "$destination exists but is not an XCFramework directory"

  archive_url="$release_base_url/v#{s.version}/$name-ios-v#{s.version}.zip"
  case "$archive_url" in
    https://*|file://*) ;;
    *) fail "unsupported release URL: $archive_url" ;;
  esac

  archive="$work_root/$name.zip"
  curl --fail --location --silent --show-error \
    --proto '=https,file' --proto-redir '=https' --tlsv1.2 --retry 3 \
    --output "$archive" "$archive_url"

  actual_checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [ "$actual_checksum" = "$expected_checksum" ] || \
    fail "checksum mismatch for $name (expected $expected_checksum, got $actual_checksum)"

  mkdir -p "$framework_root"
  staging="$(mktemp -d "$framework_root/.$name.XXXXXX")"
  ditto -x -k "$archive" "$staging"
  [ -f "$staging/$name.xcframework/Info.plist" ] || \
    fail "archive does not contain $name.xcframework"
  mv "$staging/$name.xcframework" "$destination"
  rmdir "$staging"
}

download_xcframework \
  RACommons \
  "#{checksum_for.call('RACommons')}" \
  runanywhere/Frameworks
  CMD

  s.ios.deployment_target = '17.5'
  s.swift_version = '6.2'

  # Source files: Swift plugin entry point + URLSession HTTP transport. The
  # implementation include is mirrored into this package so clean pub.dev
  # consumers never depend on the monorepo layout. It is included by the .mm
  # wrapper and excluded as a standalone compilation unit.
  s.source_files = 'runanywhere/Sources/**/*.{h,m,mm,swift}'
  s.exclude_files = 'runanywhere/Sources/runanywhere_native/URLSessionHttpTransportImpl.inc.mm'
  s.resource_bundles = {
    'runanywhere_privacy' => [
      'runanywhere/Sources/runanywhere/PrivacyInfo.xcprivacy',
    ],
  }

  s.dependency 'Flutter'

  # =============================================================================
  # Vendored xcframework (local build or checksum-pinned release archive)
  # =============================================================================
  s.vendored_frameworks = 'runanywhere/Frameworks/RACommons.xcframework'

  # Keep the framework and package-local implementation include available to
  # downstream toolchains.
  s.preserve_paths = [
    'runanywhere/Frameworks/**/*',
    'runanywhere/Sources/runanywhere_native/URLSessionHttpTransportImpl.inc.mm',
  ]

  # Required frameworks
  s.frameworks = [
    'Foundation',
    'CoreML',
    'Accelerate',
    'AVFoundation',
    'AudioToolbox'
  ]

  # Weak frameworks (optional hardware acceleration)
  s.weak_frameworks = [
    'Metal',
    'MetalKit',
    'MetalPerformanceShaders'
  ]

  # ---------------------------------------------------------------------------
  # pod_target_xcconfig
  #
  # EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64
  #   The locally built xcframework only ships `ios-arm64` + `ios-arm64-simulator`
  #   slices (no `ios-arm64_x86_64-simulator`). Xcode's default simulator archs
  #   include x86_64 on Intel hosts; exclude it so the linker doesn't try to
  #   pull a slice that isn't there.
  #
  # HEADER_SEARCH_PATHS
  #   - RACommons.xcframework/*/Headers: rac/** C API headers consumed by Dart
  #     FFI (surfaced by -headers on `xcodebuild -create-xcframework`).
  # ---------------------------------------------------------------------------
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    # -lz matches the Swift SDK (Package.swift linkerSettings) — libarchive
    # baked into RACommons transitively needs zlib.
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -lz',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/runanywhere/Frameworks/RACommons.xcframework/ios-arm64/Headers"',
      '"${PODS_TARGET_SRCROOT}/runanywhere/Frameworks/RACommons.xcframework/ios-arm64-simulator/Headers"',
      '"${PODS_TARGET_SRCROOT}/runanywhere/Sources/runanywhere_native/include"',
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited)',
  }

  # ---------------------------------------------------------------------------
  # user_target_xcconfig
  #
  # Flags that must propagate to the hosting app target so FFI symbols from
  # vendored static frameworks actually reach the final binary:
  #   -ObjC                  load Obj-C categories from static archives
  #   -all_load              link every object in every static archive
  #   -Wl,-export_dynamic    export local symbols so dlsym() can find them
  #                          (Flutter FFI relies on DynamicLibrary.executable())
  #   DEAD_CODE_STRIPPING=NO don't let the linker drop unreferenced symbols
  # ---------------------------------------------------------------------------
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -lz -ObjC -all_load -Wl,-export_dynamic',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  s.static_framework = true
end
