#
# RunAnywhere ONNX Backend - iOS
#
# Uses locally staged RABackendONNX and RABackendSherpa XCFrameworks during
# monorepo development. A clean pub.dev package downloads checksum-pinned
# release archives before CocoaPods resolves the vendored frameworks.
#
# Note: as of v0.19.0 the ONNX Runtime C library is statically linked
# directly into RABackendONNX.a — no separate onnxruntime.xcframework is
# required (matches the Swift SPM + React Native setup).
#

package_manifest = File.read(File.join(__dir__, 'runanywhere_onnx', 'Package.swift'))
checksum_for = lambda do |name|
  match = package_manifest.match(
    /runAnywhereBinaryTarget\(\s*name:\s*"#{Regexp.escape(name)}",\s*checksum:\s*"([0-9a-f]{64})"\s*\)/m
  )
  unless match
    raise Pod::Informative, "Missing immutable checksum for #{name} in runanywhere_onnx/Package.swift"
  end

  match[1]
end

Pod::Spec.new do |s|
  s.name             = 'runanywhere_onnx'
  s.version          = '0.20.10'
  s.summary          = 'RunAnywhere ONNX: STT, TTS, VAD for Flutter'
  s.description      = <<-DESC
ONNX Runtime backend for RunAnywhere Flutter SDK. Provides speech-to-text (STT),
text-to-speech (TTS), voice activity detection (VAD), and embeddings via
ONNX Runtime and Sherpa-ONNX — all statically linked into
RABackendONNX.xcframework.
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'RunAnywhere License', :file => '../LICENSE' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  # The base URL override is for release-contract fixtures only; archive
  # checksums are read from the package manifest and cannot be overridden.
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
  RABackendONNX \
  "#{checksum_for.call('RABackendONNX')}" \
  runanywhere_onnx/Frameworks
download_xcframework \
  RABackendSherpa \
  "#{checksum_for.call('RABackendSherpa')}" \
  runanywhere_onnx/Frameworks
download_xcframework \
  RABackendCoreML \
  "#{checksum_for.call('RABackendCoreML')}" \
  runanywhere_onnx/Frameworks
  CMD

  s.ios.deployment_target = '17.5'
  s.swift_version = '6.2'

  # Source files (plugin entry point only — native logic lives in xcframework).
  s.source_files = 'runanywhere_onnx/Sources/**/*.swift'

  s.dependency 'Flutter'
  s.dependency 'runanywhere'

  # =============================================================================
  # Vendored xcframeworks (local builds or checksum-pinned release archives)
  # =============================================================================
  # RABackendONNX provides the ONNX Runtime engine.
  # RABackendSherpa provides STT/TTS/VAD via sherpa-onnx — its plugin entry
  # symbol (_rac_plugin_entry_sherpa) is referenced from RACommons, so without
  # vendoring this xcframework the linker fails with an Undefined symbol error.
  # RABackendCoreML provides the Apple CoreML Stable-Diffusion engine — RACommons
  # references _rac_plugin_entry_coreml (0.20.10 enabled the CoreML backend in
  # commons), so it must be vendored here for the same reason, and it makes
  # image generation (diffusion.generateImage) routable on Apple devices.
  s.vendored_frameworks = [
    'runanywhere_onnx/Frameworks/RABackendONNX.xcframework',
    'runanywhere_onnx/Frameworks/RABackendSherpa.xcframework',
    'runanywhere_onnx/Frameworks/RABackendCoreML.xcframework'
  ]
  s.preserve_paths = 'runanywhere_onnx/Frameworks/**/*'

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

  # See runanywhere.podspec for rationale on EXCLUDED_ARCHS.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -lz',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/runanywhere_onnx/Frameworks/RABackendONNX.xcframework/ios-arm64/Headers"',
      '"${PODS_TARGET_SRCROOT}/runanywhere_onnx/Frameworks/RABackendONNX.xcframework/ios-arm64-simulator/Headers"',
    ].join(' '),
  }

  # -all_load ensures every object in RABackendONNX.xcframework is linked;
  # Flutter FFI resolves symbols via dlsym() at runtime.
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '-lc++ -larchive -lbz2 -lz -all_load',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  s.static_framework = true
end
