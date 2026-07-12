#
# RunAnywhere MLX Backend - iOS
#
# The MLX distribution is four independently checksum-pinned release assets:
# three XCFramework archives plus one Hub/Crypto/notices resource archive.
# A complete local staging tree is accepted for monorepo development; a clean
# pub.dev install downloads and validates all four immutable assets.
#

mlx_checksums = {
  'RABackendMLX' => 'b7532f4321d6f8726cd0e5b3cc2bd1c9fe031337217baf846e7e76fb98e6ba80',
  'RunAnywhereMLXRuntime' => '569e8cfecf1e7b328328698d53ce78ad8fb3ea262832e38ef7b8a059f1c15b3e',
  'RunAnywhereMLXMetal' => '17a2f8c4ce09ef691cde5e7d04171ce749fca89315205f90eb2eed5a76b682b1',
  'RunAnywhereMLXResources' => '70de4c70143b4544204b2c0e8af296546bc31ccf3ffda2f7b813fffb5b720ae9'
}.freeze

checksum_for = lambda do |name|
  checksum = mlx_checksums[name]
  unless checksum&.match?(/\A[0-9a-f]{64}\z/)
    raise Pod::Informative, "Missing immutable checksum for #{name} in runanywhere_mlx.podspec"
  end

  checksum
end

Pod::Spec.new do |s|
  s.name             = 'runanywhere_mlx'
  s.version          = '0.20.0'
  s.summary          = 'RunAnywhere MLX backend for physical iOS devices'
  s.description      = <<-DESC
Apple MLX backend for the RunAnywhere Flutter SDK. Provides on-device LLM,
VLM, embeddings, speech recognition, and speech synthesis on physical iOS
devices. The arm64 simulator slice supports package, link, and startup
validation only; MLX runtime availability remains false there.
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'RunAnywhere License', :file => '../LICENSE' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  s.prepare_command = <<-CMD
set -euo pipefail

fail() {
  echo "RunAnywhere MLX iOS preparation failed: $*" >&2
  exit 1
}

framework_root="runanywhere_mlx/Frameworks"
resource_root="runanywhere_mlx/Resources"
notices_root="runanywhere_mlx/ThirdPartyNotices"
release_base_url="${RUNANYWHERE_FLUTTER_IOS_RELEASE_BASE_URL:-https://github.com/RunanywhereAI/runanywhere-sdks/releases/download}"
while [ "${release_base_url%/}" != "$release_base_url" ]; do
  release_base_url="${release_base_url%/}"
done

work_root="$(mktemp -d "${TMPDIR:-/tmp}/runanywhere-flutter-mlx-ios.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT HUP INT TERM

validate_framework() {
  name="$1"
  root="$2/$name.xcframework"
  [ -f "$root/Info.plist" ] || fail "$name.xcframework is missing Info.plist"
  plutil -lint "$root/Info.plist" >/dev/null || fail "$name.xcframework has an invalid Info.plist"
  for slice in ios-arm64 ios-arm64-simulator; do
    [ -d "$root/$slice" ] || fail "$name.xcframework is missing $slice"
    if [ "$name" = "RunAnywhereMLXMetal" ]; then
      [ -s "$root/$slice/RunAnywhereMLXMetal.framework/default.metallib" ] || \
        fail "RunAnywhereMLXMetal.xcframework is missing $slice/default.metallib"
    fi
  done
}

validate_resources() {
  root="$1"
  resource_count="$(find "$root" -mindepth 1 -maxdepth 1 -type d -name '*.bundle' | wc -l | tr -d ' ')"
  [ "$resource_count" = "2" ] || fail "MLX resources must contain exactly the Hub and Crypto bundles"
  for required in \
    "swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy" \
    "swift-transformers_Hub.bundle/gpt2_tokenizer_config.json" \
    "swift-transformers_Hub.bundle/t5_tokenizer_config.json"; do
    [ -s "$root/$required" ] || fail "MLX resources are missing or empty: $required"
  done
  for obsolete in RunAnywhereMLXMetalDevice RunAnywhereMLXMetalSimulator; do
    [ ! -e "$root/${obsolete}.bundle" ] || \
      fail "obsolete MLX Metal sidecar is not supported: ${obsolete}.bundle"
  done
}

validate_notices() {
  root="$1"
  [ -d "$root" ] || fail "MLX third-party notices are missing"
  [ -n "$(find "$root" -type f -print -quit)" ] || fail "MLX third-party notices are empty"
}

validate_archive_paths() {
  archive="$1"
  if zipinfo -1 "$archive" | grep -Eq '(^/|(^|/)\\.\\.(/|$)|\\\\)'; then
    fail "archive contains an unsafe path: $archive"
  fi
}

extract_single_root() {
  archive="$1"
  expected_root="$2"
  destination="$3"
  validate_archive_paths "$archive"
  mkdir -p "$destination"
  ditto -x -k "$archive" "$destination"
  [ ! -L "$destination/$expected_root" ] || fail "$expected_root must not be a symbolic link"
  [ -e "$destination/$expected_root" ] || fail "archive does not contain $expected_root"
  top_level_count="$(find "$destination" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')"
  [ "$top_level_count" = "1" ] || fail "archive must contain only $expected_root"
  [ -z "$(find "$destination/$expected_root" -type l -print -quit)" ] || \
    fail "$expected_root contains a symbolic link"
}

download_archive() {
  asset_name="$1"
  expected_checksum="$2"
  archive="$work_root/$asset_name.zip"
  archive_url="$release_base_url/v#{s.version}/$asset_name-ios-v#{s.version}.zip"
  case "$archive_url" in
    https://*|file://*) ;;
    *) fail "unsupported release URL: $archive_url" ;;
  esac
  curl --fail --location --silent --show-error \
    --proto '=https,file' --proto-redir '=https' --tlsv1.2 --retry 3 \
    --output "$archive" "$archive_url"
  actual_checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [ "$actual_checksum" = "$expected_checksum" ] || \
    fail "checksum mismatch for $asset_name (expected $expected_checksum, got $actual_checksum)"
  printf '%s\n' "$archive"
}

framework_count=0
for path in \
  "$framework_root/RABackendMLX.xcframework" \
  "$framework_root/RunAnywhereMLXRuntime.xcframework" \
  "$framework_root/RunAnywhereMLXMetal.xcframework"; do
  if [ -e "$path" ]; then
    framework_count=$((framework_count + 1))
  fi
done
resource_payload_count=0
for path in \
  "$resource_root/swift-crypto_Crypto.bundle" \
  "$resource_root/swift-transformers_Hub.bundle" \
  "$notices_root"; do
  if [ -e "$path" ]; then
    resource_payload_count=$((resource_payload_count + 1))
  fi
done

if [ "$resource_payload_count" = "3" ]; then
  validate_resources "$resource_root"
  validate_notices "$notices_root"
fi

if [ "$framework_count" = "3" ] && [ "$resource_payload_count" = "3" ]; then
  validate_framework RABackendMLX "$framework_root"
  validate_framework RunAnywhereMLXRuntime "$framework_root"
  validate_framework RunAnywhereMLXMetal "$framework_root"
elif [ "$framework_count" != "0" ] || [ "$resource_payload_count" != "0" ]; then
  fail "local MLX payload is partial ($framework_count of 3 frameworks, $resource_payload_count of 3 resource entries)"
else
  download_root="$work_root/downloaded"
  mkdir -p "$download_root/frameworks" "$download_root/resources"

  backend_archive="$(download_archive RABackendMLX "#{checksum_for.call('RABackendMLX')}")"
  runtime_archive="$(download_archive RunAnywhereMLXRuntime "#{checksum_for.call('RunAnywhereMLXRuntime')}")"
  metal_archive="$(download_archive RunAnywhereMLXMetal "#{checksum_for.call('RunAnywhereMLXMetal')}")"
  resources_archive="$(download_archive RunAnywhereMLXResources "#{checksum_for.call('RunAnywhereMLXResources')}")"

  extract_single_root "$backend_archive" RABackendMLX.xcframework "$download_root/frameworks/backend"
  extract_single_root "$runtime_archive" RunAnywhereMLXRuntime.xcframework "$download_root/frameworks/runtime"
  extract_single_root "$metal_archive" RunAnywhereMLXMetal.xcframework "$download_root/frameworks/metal"
  extract_single_root "$resources_archive" RunAnywhereMLXRuntimeResources "$download_root/resources/archive"

  archive_resources="$download_root/resources/archive/RunAnywhereMLXRuntimeResources"
  validate_resources "$archive_resources"
  validate_notices "$archive_resources/ThirdPartyNotices"

  staged_frameworks="$download_root/final-frameworks"
  staged_resources="$download_root/final-resources"
  staged_notices="$download_root/final-notices"
  mkdir -p "$staged_frameworks" "$staged_resources"
  mv "$download_root/frameworks/backend/RABackendMLX.xcframework" "$staged_frameworks/"
  mv "$download_root/frameworks/runtime/RunAnywhereMLXRuntime.xcframework" "$staged_frameworks/"
  mv "$download_root/frameworks/metal/RunAnywhereMLXMetal.xcframework" "$staged_frameworks/"
  cp -R \
    "$download_root/resources/archive/RunAnywhereMLXRuntimeResources/swift-crypto_Crypto.bundle" \
    "$download_root/resources/archive/RunAnywhereMLXRuntimeResources/swift-transformers_Hub.bundle" \
    "$staged_resources/"
  cp -R \
    "$download_root/resources/archive/RunAnywhereMLXRuntimeResources/ThirdPartyNotices" \
    "$staged_notices"

  validate_framework RABackendMLX "$staged_frameworks"
  validate_framework RunAnywhereMLXRuntime "$staged_frameworks"
  validate_framework RunAnywhereMLXMetal "$staged_frameworks"
  validate_resources "$staged_resources"
  validate_notices "$staged_notices"

  mkdir -p "$framework_root" "$resource_root"
  rm -rf \
    "$resource_root/swift-crypto_Crypto.bundle" \
    "$resource_root/swift-transformers_Hub.bundle" \
    "$notices_root"
  mv "$staged_frameworks/RABackendMLX.xcframework" "$framework_root/"
  mv "$staged_frameworks/RunAnywhereMLXRuntime.xcframework" "$framework_root/"
  mv "$staged_frameworks/RunAnywhereMLXMetal.xcframework" "$framework_root/"
  mv "$staged_resources/swift-crypto_Crypto.bundle" "$resource_root/"
  mv "$staged_resources/swift-transformers_Hub.bundle" "$resource_root/"
  mv "$staged_notices" "$notices_root"
fi
  CMD

  s.ios.deployment_target = '17.5'
  s.swift_version = '6.2'
  s.source_files = 'runanywhere_mlx/Sources/**/*.swift'

  s.dependency 'Flutter'
  # Flutter links the core `runanywhere` plugin through SwiftPM. Declaring it
  # again as a pod would create a second package-manager owner for RACommons.
  # The final app link resolves this pod's MLX symbols against that one core.

  s.vendored_frameworks = [
    'runanywhere_mlx/Frameworks/RABackendMLX.xcframework',
    'runanywhere_mlx/Frameworks/RunAnywhereMLXRuntime.xcframework',
    'runanywhere_mlx/Frameworks/RunAnywhereMLXMetal.xcframework'
  ]
  s.resources = [
    'runanywhere_mlx/Resources/swift-crypto_Crypto.bundle',
    'runanywhere_mlx/Resources/swift-transformers_Hub.bundle'
  ]
  s.preserve_paths = [
    'runanywhere_mlx/Frameworks/**/*',
    'runanywhere_mlx/Resources/**/*',
    'runanywhere_mlx/ThirdPartyNotices/**/*'
  ]

  s.frameworks = [
    'Accelerate',
    'AVFoundation',
    'CoreGraphics',
    'CoreImage',
    'CoreML',
    'Foundation',
    'Metal',
    'MetalKit',
    'NaturalLanguage',
    'UIKit'
  ]
  s.libraries = 'c++'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'SWIFT_VERSION' => '6.2'
  }
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_ra_mlx_runtime_is_available'
  }

  s.static_framework = true
end
