#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/core/VERSION")"
FAILURES=0

if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo "[FAIL] invalid canonical release version: ${VERSION}" >&2
  exit 1
fi

validate_pr_release_bump() {
  local base_sha="${PR_BASE_SHA}"
  local labels_json="${PR_RELEASE_LABELS_JSON:-[]}"
  local base_version
  local label
  local bump=""
  local release_label_count=0

  if ! command -v jq >/dev/null 2>&1; then
    echo "[FAIL] jq is required for the PR release-label contract" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if ! jq -e 'type == "array" and all(.[]; type == "string")' \
    >/dev/null 2>&1 <<< "${labels_json}"; then
    echo "[FAIL] PR release labels are not a JSON string array" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  # VERSION lived at sdk/runanywhere-commons/VERSION until the core/ rename, so a
  # PR whose base predates that commit only has the old path. Probing just one
  # spelling makes the gate report the base as "unavailable" when it is merely
  # older, which is indistinguishable from a genuinely missing fetch.
  base_version_path=""
  for candidate in core/VERSION sdk/runanywhere-commons/VERSION; do
    if git -C "${REPO_ROOT}" cat-file -e "${base_sha}:${candidate}" 2>/dev/null; then
      base_version_path="${candidate}"
      break
    fi
  done
  if [ -z "${base_version_path}" ]; then
    echo "[FAIL] PR base ${base_sha} is unavailable; fetch it before running this gate" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  base_version="$(git -C "${REPO_ROOT}" show "${base_sha}:${base_version_path}" | tr -d '[:space:]')"
  if ! [[ "${base_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
    echo "[FAIL] invalid PR-base release version: ${base_version}" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  while IFS= read -r label; do
    case "${label}" in
      release:patch) bump="patch"; release_label_count=$((release_label_count + 1)) ;;
      release:minor) bump="minor"; release_label_count=$((release_label_count + 1)) ;;
      release:major) bump="major"; release_label_count=$((release_label_count + 1)) ;;
    esac
  done < <(jq -r '.[]' <<< "${labels_json}")

  if [ "${release_label_count}" -gt 1 ]; then
    echo "[FAIL] PR has multiple release:* labels; exactly one is allowed" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if [ "${release_label_count}" -eq 0 ]; then
    if [ "${VERSION}" != "${base_version}" ]; then
      echo "[FAIL] PR changes version ${base_version} -> ${VERSION} without a release:* label" >&2
      FAILURES=$((FAILURES + 1))
    else
      echo "[OK] PR release contract: no version change and no release label"
    fi
    return
  fi

  local base_core="${base_version%%-*}"
  local major minor patch
  IFS='.' read -r major minor patch <<< "${base_core}"
  case "${bump}" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
  esac
  local expected="${major}.${minor}.${patch}"
  if [ "${VERSION}" != "${expected}" ]; then
    # The base+1 rule assumes one PR carries one release. A long-lived release
    # branch can cut several before it merges, and then VERSION is legitimately
    # more than one step ahead of base. What makes that safe is not the label
    # arithmetic but the tag: v${VERSION} already exists, so the version was
    # reviewed and published rather than slipped in here. Accept only that case,
    # and only for a real tag object -- anything else still fails.
    # actions/checkout fetches no tags by default, so a local-only probe finds
    # nothing on CI even when the tag exists. Fall back to asking the remote.
    if git -C "${REPO_ROOT}" rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null 2>&1; then
      echo "[OK] PR release contract: ${base_version} -> ${VERSION}, already tagged v${VERSION}"
      return
    fi
    if git -C "${REPO_ROOT}" ls-remote --exit-code --tags origin "refs/tags/v${VERSION}" >/dev/null 2>&1; then
      echo "[OK] PR release contract: ${base_version} -> ${VERSION}, already tagged v${VERSION} on origin"
      return
    fi
    echo "[FAIL] release:${bump} requires ${base_version} -> ${expected}; reviewed version is ${VERSION}" >&2
    echo "       (no refs/tags/v${VERSION} either, so this is not a published catch-up)" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "[OK] PR release contract: release:${bump} selects ${base_version} -> ${VERSION}"
}

if [ -n "${PR_BASE_SHA:-}" ]; then
  validate_pr_release_bump
fi

expect_literal() {
  local file="$1"
  local literal="$2"
  if ! grep -Fq -- "${literal}" "${REPO_ROOT}/${file}"; then
    echo "[FAIL] ${file}: expected '${literal}'" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

reject_literal() {
  local file="$1"
  local literal="$2"
  if grep -Fq -- "${literal}" "${REPO_ROOT}/${file}"; then
    echo "[FAIL] ${file}: retired literal remains '${literal}'" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

expect_exact_file() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(tr -d '[:space:]' < "${REPO_ROOT}/${file}")"
  if [ "${actual}" != "${expected}" ]; then
    echo "[FAIL] ${file}: expected '${expected}', found '${actual}'" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

expect_count() {
  local file="$1"
  local literal="$2"
  local expected_count="$3"
  local actual_count
  actual_count="$(grep -Fc -- "${literal}" "${REPO_ROOT}/${file}" || true)"
  if [ "${actual_count}" -ne "${expected_count}" ]; then
    echo "[FAIL] ${file}: expected ${expected_count} occurrences of '${literal}', found ${actual_count}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

expect_exact_file "core/VERSION" "${VERSION}"
expect_literal "core/VERSIONS" "PROJECT_VERSION=${VERSION}"
expect_literal "AGENTS.md" \
  "**Current version**: \`${VERSION}\` (canonical source: \`core/VERSION\`)"

# SwiftPM consumers resolve prebuilt XCFrameworks from a GitHub release. During
# release preparation, the canonical SDK train can temporarily be ahead of the
# latest published Apple archives. Package.swift records that state explicitly
# so external consumers stay on an available release instead of resolving a
# non-existent v${VERSION} asset. All SwiftPM manifests must use the same pin.
SPM_VERSION="$(awk -F'"' '/^let sdkVersion = "/ { print $2; exit }' "${REPO_ROOT}/Package.swift")"
SPM_TEMP_PIN=0
if [ -z "${SPM_VERSION}" ]; then
  echo "[FAIL] Package.swift: missing sdkVersion pin" >&2
  FAILURES=$((FAILURES + 1))
elif [ "${SPM_VERSION}" = "${VERSION}" ]; then
  echo "[OK] SwiftPM manifests use canonical release version ${VERSION}"
else
  SPM_TEMP_MARKER="TEMP: pin to ${SPM_VERSION} until the v${VERSION} GitHub release assets are published."
  if grep -Fq -- "${SPM_TEMP_MARKER}" "${REPO_ROOT}/Package.swift"; then
    SPM_TEMP_PIN=1
    echo "[OK] SwiftPM manifests temporarily pin ${SPM_VERSION} until v${VERSION} assets are published"
  else
    echo "[FAIL] Package.swift: sdkVersion ${SPM_VERSION} differs from canonical ${VERSION} without an explicit unpublished-assets pin" >&2
    FAILURES=$((FAILURES + 1))
  fi
fi

expect_spm_version() {
  local file="$1"
  if grep -Fq -- "let sdkVersion = \"${VERSION}\"" "${REPO_ROOT}/${file}"; then
    return
  fi
  if [ "${SPM_TEMP_PIN}" -eq 1 ] && grep -Fq -- "let sdkVersion = \"${SPM_VERSION}\"" "${REPO_ROOT}/${file}"; then
    return
  fi
  echo "[FAIL] ${file}: expected SwiftPM sdkVersion ${VERSION}" >&2
  FAILURES=$((FAILURES + 1))
}

# The external-consumer example in Package.swift points at the Swift
# DISTRIBUTION repo, never this monorepo: this repo's tags do not compile as a
# Swift package (the generated Sources/ are no longer committed). Assert that
# exact literal so the documented URL cannot silently drift back.
if [ "${SPM_TEMP_PIN}" -eq 1 ]; then
  expect_literal "Package.swift" ".package(url: \"https://github.com/RunanywhereAI/runanywhere-swift.git\", from: \"${SPM_VERSION}\")"
else
  expect_literal "Package.swift" ".package(url: \"https://github.com/RunanywhereAI/runanywhere-swift.git\", from: \"${VERSION}\")"
fi
expect_exact_file "bindings/swift/VERSION" "${VERSION}"
expect_literal "bindings/swift/Sources/RunAnywhere/Generated/Versions.swift" \
  "public static let sdkVersion = \"${VERSION}\""

expect_literal "bindings/kotlin/gradle.properties" "runanywhere.nativeLibVersion=${VERSION}"
expect_literal "bindings/kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/constants/SDKConstants.kt" \
  "const val VERSION = \"${VERSION}\""
for kotlin_publication in \
  bindings/kotlin/build.gradle.kts \
  bindings/kotlin/modules/runanywhere-core-llamacpp/build.gradle.kts \
  bindings/kotlin/modules/runanywhere-core-onnx/build.gradle.kts; do
  expect_literal "${kotlin_publication}" 'name.set("RunAnywhere License")'
  expect_literal "${kotlin_publication}" \
    'url.set("https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE")'
done

read_version_pin() {
  local key="$1"
  awk -F= -v key="${key}" '$1 == key { print substr($0, index($0, "=") + 1); exit }' \
    "${REPO_ROOT}/core/VERSIONS"
}

ONNX_VERSION_IOS_PIN="$(read_version_pin ONNX_VERSION_IOS)"
ONNX_VERSION_ANDROID_PIN="$(read_version_pin ONNX_VERSION_ANDROID)"
if [ -z "${ONNX_VERSION_IOS_PIN}" ] || [ -z "${ONNX_VERSION_ANDROID_PIN}" ]; then
  echo "[FAIL] VERSIONS: missing platform ONNX Runtime pin" >&2
  FAILURES=$((FAILURES + 1))
elif [ "${ONNX_VERSION_IOS_PIN}" != "${ONNX_VERSION_ANDROID_PIN}" ]; then
  echo "[FAIL] VERSIONS: shared SDK ONNX metadata requires matching iOS/Android pins; found iOS=${ONNX_VERSION_IOS_PIN}, Android=${ONNX_VERSION_ANDROID_PIN}" >&2
  FAILURES=$((FAILURES + 1))
else
  expect_literal "bindings/swift/Sources/RunAnywhere/Generated/Versions.swift" \
    "public static let onnxRuntimeIOS = \"${ONNX_VERSION_IOS_PIN}\""
  expect_literal "bindings/swift/Sources/ONNXRuntime/ONNX.swift" \
    "public static let onnxRuntimeVersion = RAVersions.onnxRuntimeIOS"
  expect_literal "bindings/kotlin/modules/runanywhere-core-onnx/src/main/kotlin/com/runanywhere/sdk/core/onnx/ONNX.kt" \
    "const val onnxRuntimeVersion = \"${ONNX_VERSION_ANDROID_PIN}\""
  expect_literal "bindings/flutter/packages/runanywhere_onnx/lib/onnx.dart" \
    "static const String onnxRuntimeVersion = '${ONNX_VERSION_IOS_PIN}'"
  expect_literal "bindings/react-native/packages/onnx/src/ONNXProvider.ts" \
    "static readonly version = '${ONNX_VERSION_IOS_PIN}'"
fi

expect_literal "bindings/proto-ts/package.json" "\"version\": \"${VERSION}\""
expect_literal "bindings/proto-ts/package.json" '"license": "SEE LICENSE IN LICENSE"'
expect_literal "bindings/proto-ts/package.json" '"LICENSE"'
expect_literal "bindings/proto-ts/LICENSE" 'RunAnywhere License Notice'
expect_count "bindings/proto-ts/package-lock.json" "\"version\": \"${VERSION}\"" 2
expect_literal "dependencies/versions.json" "\"@runanywhere/proto-ts\": \"^${VERSION}\""

for package_json in \
  bindings/web/package.json \
  bindings/web/packages/core/package.json \
  bindings/web/packages/llamacpp/package.json \
  bindings/web/packages/onnx/package.json; do
  expect_literal "${package_json}" "\"version\": \"${VERSION}\""
done
expect_literal "bindings/web/packages/core/src/Foundation/Version.ts" \
  "export const SDK_VERSION = '${VERSION}'"
for package_json in \
  bindings/web/packages/llamacpp/package.json \
  bindings/web/packages/onnx/package.json; do
  expect_literal "${package_json}" "\"@runanywhere/web\": \">=${VERSION} <1\""
done
# core + llamacpp + onnx each declare the published peer/dep range.
expect_count "bindings/web/package-lock.json" \
  "\"@runanywhere/proto-ts\": \"^${VERSION}\"" 3
expect_count "bindings/web/package-lock.json" \
  "\"@runanywhere/web\": \">=${VERSION} <1\"" 2

for package_json in \
  bindings/react-native/package.json \
  bindings/react-native/packages/core/package.json \
  bindings/react-native/packages/llamacpp/package.json \
  bindings/react-native/packages/mlx/package.json \
  bindings/react-native/packages/onnx/package.json \
  bindings/react-native/packages/qhexrt/package.json; do
  expect_literal "${package_json}" "\"version\": \"${VERSION}\""
done
expect_literal "bindings/react-native/lerna.json" "\"version\": \"${VERSION}\""
for package_json in \
  bindings/react-native/packages/llamacpp/package.json \
  bindings/react-native/packages/mlx/package.json \
  bindings/react-native/packages/onnx/package.json \
  bindings/react-native/packages/qhexrt/package.json; do
  expect_literal "${package_json}" "\"@runanywhere/core\": \">=${VERSION}\""
done
expect_literal "bindings/react-native/packages/core/src/Foundation/Constants/SDKConstants.ts" \
  "version: '${VERSION}'"
expect_literal "bindings/react-native/packages/qhexrt/src/QHexRTProvider.ts" \
  "static readonly version = '${VERSION}'"
for gradle_file in \
  bindings/react-native/packages/llamacpp/android/build.gradle \
  bindings/react-native/packages/onnx/android/build.gradle; do
  expect_literal "${gradle_file}" \
    "def coreVersion = coreVersionFile.exists() ? coreVersionFile.text.trim() : \"${VERSION}\""
done
expect_count "bindings/react-native/yarn.lock" \
  "\"@runanywhere/core\": \">=${VERSION}\"" 4
expect_count "yarn.lock" "\"@runanywhere/core\": \">=${VERSION}\"" 4

for pubspec in \
  bindings/flutter/packages/runanywhere/pubspec.yaml \
  bindings/flutter/packages/runanywhere_llamacpp/pubspec.yaml \
  bindings/flutter/packages/runanywhere_mlx/pubspec.yaml \
  bindings/flutter/packages/runanywhere_onnx/pubspec.yaml \
  bindings/flutter/packages/runanywhere_qhexrt/pubspec.yaml; do
  expect_literal "${pubspec}" "version: ${VERSION}"
done
for pubspec in \
  bindings/flutter/packages/runanywhere_llamacpp/pubspec.yaml \
  bindings/flutter/packages/runanywhere_mlx/pubspec.yaml \
  bindings/flutter/packages/runanywhere_onnx/pubspec.yaml \
  bindings/flutter/packages/runanywhere_qhexrt/pubspec.yaml; do
  expect_literal "${pubspec}" "runanywhere: ^${VERSION}"
done
expect_literal "bindings/flutter/packages/runanywhere/lib/foundation/constants/sdk_constants.dart" \
  "static final String version = _nativeVersion"
expect_literal "bindings/flutter/packages/runanywhere/lib/foundation/constants/sdk_constants.dart" \
  "RacNative.bindings.rac_sdk_get_version()"
reject_literal "bindings/flutter/packages/runanywhere/lib/foundation/constants/sdk_constants.dart" \
  "_fallbackVersion"
expect_literal "bindings/flutter/packages/runanywhere_qhexrt/lib/qhexrt.dart" \
  "static const String version = '${VERSION}'"
for changelog in \
  bindings/flutter/packages/runanywhere/CHANGELOG.md \
  bindings/flutter/packages/runanywhere_llamacpp/CHANGELOG.md \
  bindings/flutter/packages/runanywhere_mlx/CHANGELOG.md \
  bindings/flutter/packages/runanywhere_onnx/CHANGELOG.md \
  bindings/flutter/packages/runanywhere_qhexrt/CHANGELOG.md; do
  expect_literal "${changelog}" "## [${VERSION}] -"
done

for gradle_file in \
  bindings/flutter/packages/runanywhere/android/build.gradle \
  bindings/flutter/packages/runanywhere_llamacpp/android/build.gradle \
  bindings/flutter/packages/runanywhere_onnx/android/build.gradle \
  bindings/flutter/packages/runanywhere_qhexrt/android/build.gradle; do
  expect_literal "${gradle_file}" "version = '${VERSION}'"
done
for binary_config in \
  bindings/flutter/packages/runanywhere/android/binary_config.gradle \
  bindings/flutter/packages/runanywhere_llamacpp/android/binary_config.gradle \
  bindings/flutter/packages/runanywhere_onnx/android/binary_config.gradle; do
  expect_literal "${binary_config}" "fallbackCoreVersion = \"${VERSION}\""
  # Gradle expands these placeholders when selecting an ABI/version archive.
  # shellcheck disable=SC2016
  expect_literal "${binary_config}" 'RACommons-android-${abi}-v${coreVersion}.zip'
done
expect_literal "bindings/flutter/packages/runanywhere/android/src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt" \
  "private const val SDK_VERSION = \"${VERSION}\""
expect_literal "bindings/flutter/packages/runanywhere/android/src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt" \
  "private const val COMMONS_VERSION = \"${VERSION}\""
expect_count "bindings/flutter/packages/runanywhere/ios/runanywhere/Sources/runanywhere/RunAnywherePlugin.swift" \
  "result(\"${VERSION}\")" 2
expect_literal "bindings/flutter/packages/runanywhere_qhexrt/android/src/main/kotlin/ai/runanywhere/sdk/qhexrt/QhexrtPlugin.kt" \
  "private const val BACKEND_VERSION = \"${VERSION}\""

# The podspecs carry TWO versions, and conflating them ships a dangling download.
# `s.version` is the CocoaPods version and tracks the canonical release, but the
# iOS archives are fetched from a GitHub release URL built from `asset_version`.
# When the repo version leads the published assets — as it does whenever a release
# republishes only some packages — an `s.version`-derived URL 404s, and the
# checksums in the podspec still describe the OLDER archives anyway, because
# sync-versions.sh deliberately never rewrites checksums. So asset_version must
# track the SwiftPM pin (both name the last release that actually has assets).
for podspec in \
  bindings/flutter/packages/runanywhere/ios/runanywhere.podspec \
  bindings/flutter/packages/runanywhere_llamacpp/ios/runanywhere_llamacpp.podspec \
  bindings/flutter/packages/runanywhere_mlx/ios/runanywhere_mlx.podspec \
  bindings/flutter/packages/runanywhere_onnx/ios/runanywhere_onnx.podspec; do
  expect_literal "${podspec}" "s.version          = '${VERSION}'"
  expect_literal "${podspec}" "asset_version      = '${SPM_VERSION}'"
  if grep -qF 'ios-v#{s.version}' "${REPO_ROOT}/${podspec}" 2>/dev/null; then
    echo "[FAIL] ${podspec}: archive URL interpolates s.version; it must use asset_version so it points at a release that exists" >&2
    FAILURES=$((FAILURES + 1))
  fi
done

for package_manifest in \
  bindings/flutter/packages/runanywhere/ios/runanywhere/Package.swift \
  bindings/flutter/packages/runanywhere_llamacpp/ios/runanywhere_llamacpp/Package.swift \
  bindings/flutter/packages/runanywhere_onnx/ios/runanywhere_onnx/Package.swift; do
  expect_spm_version "${package_manifest}"
done

for release_doc in \
  bindings/react-native/AGENTS.md \
  bindings/react-native/packages/mlx/README.md \
  bindings/flutter/AGENTS.md \
  bindings/flutter/README.md \
  bindings/flutter/packages/runanywhere/README.md \
  bindings/flutter/packages/runanywhere_llamacpp/README.md \
  bindings/flutter/packages/runanywhere_mlx/README.md \
  bindings/flutter/packages/runanywhere_onnx/README.md \
  bindings/flutter/docs/ARCHITECTURE.md \
  bindings/flutter/docs/Documentation.md \
  bindings/swift/ARCHITECTURE.md \
  bindings/swift/README.md \
  bindings/swift/Sources/LlamaCPPRuntime/README.md \
  bindings/swift/Sources/ONNXRuntime/README.md \
  bindings/kotlin/README.md; do
  expect_literal "${release_doc}" "${VERSION}"
done

if [ "${FAILURES}" -ne 0 ]; then
  echo "[FAIL] release version coherence: ${FAILURES} mismatch(es)" >&2
  echo "Run: scripts/release/sync-versions.sh ${VERSION}" >&2
  exit 1
fi

echo "[OK] release version coherence: ${VERSION}"
