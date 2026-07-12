#
# RunAnywhere LlamaCPP Backend - iOS
#
# Uses a locally staged RABackendLLAMACPP.xcframework during monorepo
# development. A clean pub.dev package downloads the checksum-pinned release
# archive before CocoaPods resolves the vendored framework.
#

package_manifest = File.read(File.join(__dir__, 'runanywhere_llamacpp', 'Package.swift'))
checksum_for = lambda do |name|
  match = package_manifest.match(
    /runAnywhereBinaryTarget\(\s*name:\s*"#{Regexp.escape(name)}",\s*checksum:\s*"([0-9a-f]{64})"\s*\)/m
  )
  unless match
    raise Pod::Informative, "Missing immutable checksum for #{name} in runanywhere_llamacpp/Package.swift"
  end

  match[1]
end

Pod::Spec.new do |s|
  s.name             = 'runanywhere_llamacpp'
  s.version          = '0.19.15'
  s.summary          = 'RunAnywhere LlamaCPP: LLM text generation for Flutter'
  s.description      = <<-DESC
LlamaCPP backend for RunAnywhere Flutter SDK. Provides LLM text generation
capabilities using llama.cpp via RABackendLLAMACPP.xcframework.
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'MIT' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  # The base URL override is for release-contract fixtures only; the archive
  # checksum is read from the package manifest and cannot be overridden.
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
  RABackendLLAMACPP \
  "#{checksum_for.call('RABackendLLAMACPP')}" \
  runanywhere_llamacpp/Frameworks
  CMD

  s.ios.deployment_target = '17.5'
  s.swift_version = '6.2'

  # Source files (plugin entry point only — native logic lives in xcframework).
  s.source_files = 'runanywhere_llamacpp/Sources/**/*.swift'

  s.dependency 'Flutter'
  # Depend on the core pod for RACommons (registry, tensor layer, etc).
  s.dependency 'runanywhere'

  # =============================================================================
  # Vendored xcframework (local build or checksum-pinned release archive)
  # =============================================================================
  s.vendored_frameworks = 'runanywhere_llamacpp/Frameworks/RABackendLLAMACPP.xcframework'
  s.preserve_paths = 'runanywhere_llamacpp/Frameworks/**/*'

  # Required frameworks
  s.frameworks = [
    'Foundation',
    'CoreML',
    'Accelerate'
  ]

  # Weak frameworks (optional hardware acceleration)
  s.weak_frameworks = [
    'Metal',
    'MetalKit',
    'MetalPerformanceShaders'
  ]

  # See runanywhere.podspec for rationale on EXCLUDED_ARCHS + HEADER_SEARCH_PATHS.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '-lc++',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/runanywhere_llamacpp/Frameworks/RABackendLLAMACPP.xcframework/ios-arm64/Headers"',
      '"${PODS_TARGET_SRCROOT}/runanywhere_llamacpp/Frameworks/RABackendLLAMACPP.xcframework/ios-arm64-simulator/Headers"',
    ].join(' '),
  }

  # -all_load ensures every object in RABackendLLAMACPP.xcframework is linked,
  # including `rac_backend_llamacpp_register` / `rac_llm_llamacpp_*` that are
  # only referenced via Flutter FFI's dlsym() at runtime.
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '-lc++ -all_load',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  s.static_framework = true
end
