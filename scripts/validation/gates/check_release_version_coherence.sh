#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/sdk/runanywhere-commons/VERSION")"
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
  if ! git -C "${REPO_ROOT}" cat-file -e "${base_sha}:sdk/runanywhere-commons/VERSION" 2>/dev/null; then
    echo "[FAIL] PR base ${base_sha} is unavailable; fetch it before running this gate" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  base_version="$(git -C "${REPO_ROOT}" show "${base_sha}:sdk/runanywhere-commons/VERSION" | tr -d '[:space:]')"
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
    echo "[FAIL] release:${bump} requires ${base_version} -> ${expected}; reviewed version is ${VERSION}" >&2
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

expect_exact_file "sdk/runanywhere-commons/VERSION" "${VERSION}"
expect_literal "sdk/runanywhere-commons/VERSIONS" "PROJECT_VERSION=${VERSION}"
expect_literal "AGENTS.md" \
  "**Current version**: \`${VERSION}\` (canonical source: \`sdk/runanywhere-commons/VERSION\`)"

expect_literal "Package.swift" "let sdkVersion = \"${VERSION}\""
expect_literal "Package.swift" ".package(url: \"https://github.com/RunanywhereAI/runanywhere-sdks\", from: \"${VERSION}\")"
expect_exact_file "sdk/runanywhere-swift/VERSION" "${VERSION}"
expect_literal "sdk/runanywhere-swift/Sources/RunAnywhere/Generated/Versions.swift" \
  "public static let sdkVersion = \"${VERSION}\""

expect_literal "sdk/runanywhere-kotlin/gradle.properties" "runanywhere.nativeLibVersion=${VERSION}"
expect_literal "sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/constants/SDKConstants.kt" \
  "const val VERSION = \"${VERSION}\""
for kotlin_publication in \
  sdk/runanywhere-kotlin/build.gradle.kts \
  sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp/build.gradle.kts \
  sdk/runanywhere-kotlin/modules/runanywhere-core-onnx/build.gradle.kts; do
  expect_literal "${kotlin_publication}" 'name.set("RunAnywhere License")'
  expect_literal "${kotlin_publication}" \
    'url.set("https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE")'
done

read_version_pin() {
  local key="$1"
  awk -F= -v key="${key}" '$1 == key { print substr($0, index($0, "=") + 1); exit }' \
    "${REPO_ROOT}/sdk/runanywhere-commons/VERSIONS"
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
  expect_literal "sdk/runanywhere-swift/Sources/RunAnywhere/Generated/Versions.swift" \
    "public static let onnxRuntimeIOS = \"${ONNX_VERSION_IOS_PIN}\""
  expect_literal "sdk/runanywhere-swift/Sources/ONNXRuntime/ONNX.swift" \
    "public static let onnxRuntimeVersion = RAVersions.onnxRuntimeIOS"
  expect_literal "sdk/runanywhere-kotlin/modules/runanywhere-core-onnx/src/main/kotlin/com/runanywhere/sdk/core/onnx/ONNX.kt" \
    "const val onnxRuntimeVersion = \"${ONNX_VERSION_ANDROID_PIN}\""
  expect_literal "sdk/runanywhere-flutter/packages/runanywhere_onnx/lib/onnx.dart" \
    "static const String onnxRuntimeVersion = '${ONNX_VERSION_IOS_PIN}'"
  expect_literal "sdk/runanywhere-react-native/packages/onnx/src/ONNXProvider.ts" \
    "static readonly version = '${ONNX_VERSION_IOS_PIN}'"
fi

expect_literal "sdk/shared/proto-ts/package.json" "\"version\": \"${VERSION}\""
expect_literal "sdk/shared/proto-ts/package.json" '"license": "SEE LICENSE IN LICENSE"'
expect_literal "sdk/shared/proto-ts/package.json" '"LICENSE"'
expect_literal "sdk/shared/proto-ts/LICENSE" 'RunAnywhere License Notice'
expect_count "sdk/shared/proto-ts/package-lock.json" "\"version\": \"${VERSION}\"" 2
expect_literal "dependencies/versions.json" "\"@runanywhere/proto-ts\": \"^${VERSION}\""

for package_json in \
  sdk/runanywhere-web/package.json \
  sdk/runanywhere-web/packages/core/package.json \
  sdk/runanywhere-web/packages/diffusion/package.json \
  sdk/runanywhere-web/packages/llamacpp/package.json \
  sdk/runanywhere-web/packages/onnx/package.json; do
  expect_literal "${package_json}" "\"version\": \"${VERSION}\""
done
expect_literal "sdk/runanywhere-web/packages/core/src/Foundation/Version.ts" \
  "export const SDK_VERSION = '${VERSION}'"
for package_json in \
  sdk/runanywhere-web/packages/diffusion/package.json \
  sdk/runanywhere-web/packages/llamacpp/package.json \
  sdk/runanywhere-web/packages/onnx/package.json; do
  expect_literal "${package_json}" "\"@runanywhere/web\": \">=${VERSION} <1\""
done
expect_count "sdk/runanywhere-web/package-lock.json" \
  "\"@runanywhere/proto-ts\": \"^${VERSION}\"" 2
expect_count "sdk/runanywhere-web/package-lock.json" \
  "\"@runanywhere/web\": \">=${VERSION} <1\"" 3

for package_json in \
  sdk/runanywhere-react-native/package.json \
  sdk/runanywhere-react-native/packages/core/package.json \
  sdk/runanywhere-react-native/packages/llamacpp/package.json \
  sdk/runanywhere-react-native/packages/mlx/package.json \
  sdk/runanywhere-react-native/packages/onnx/package.json \
  sdk/runanywhere-react-native/packages/qhexrt/package.json; do
  expect_literal "${package_json}" "\"version\": \"${VERSION}\""
done
expect_literal "sdk/runanywhere-react-native/lerna.json" "\"version\": \"${VERSION}\""
for package_json in \
  sdk/runanywhere-react-native/packages/llamacpp/package.json \
  sdk/runanywhere-react-native/packages/mlx/package.json \
  sdk/runanywhere-react-native/packages/onnx/package.json \
  sdk/runanywhere-react-native/packages/qhexrt/package.json; do
  expect_literal "${package_json}" "\"@runanywhere/core\": \">=${VERSION}\""
done
expect_literal "sdk/runanywhere-react-native/packages/core/src/Foundation/Constants/SDKConstants.ts" \
  "version: '${VERSION}'"
expect_literal "sdk/runanywhere-react-native/packages/qhexrt/src/QHexRTProvider.ts" \
  "static readonly version = '${VERSION}'"
for gradle_file in \
  sdk/runanywhere-react-native/packages/llamacpp/android/build.gradle \
  sdk/runanywhere-react-native/packages/onnx/android/build.gradle; do
  expect_literal "${gradle_file}" \
    "def coreVersion = coreVersionFile.exists() ? coreVersionFile.text.trim() : \"${VERSION}\""
done
expect_count "sdk/runanywhere-react-native/yarn.lock" \
  "\"@runanywhere/core\": \">=${VERSION}\"" 4
expect_count "yarn.lock" "\"@runanywhere/core\": \">=${VERSION}\"" 4

for pubspec in \
  sdk/runanywhere-flutter/packages/runanywhere/pubspec.yaml \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/pubspec.yaml \
  sdk/runanywhere-flutter/packages/runanywhere_mlx/pubspec.yaml \
  sdk/runanywhere-flutter/packages/runanywhere_onnx/pubspec.yaml \
  sdk/runanywhere-flutter/packages/runanywhere_qhexrt/pubspec.yaml; do
  expect_literal "${pubspec}" "version: ${VERSION}"
done
for pubspec in \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/pubspec.yaml \
  sdk/runanywhere-flutter/packages/runanywhere_mlx/pubspec.yaml \
  sdk/runanywhere-flutter/packages/runanywhere_onnx/pubspec.yaml \
  sdk/runanywhere-flutter/packages/runanywhere_qhexrt/pubspec.yaml; do
  expect_literal "${pubspec}" "runanywhere: ^${VERSION}"
done
expect_literal "sdk/runanywhere-flutter/packages/runanywhere/lib/foundation/constants/sdk_constants.dart" \
  "static final String version = _nativeVersion"
expect_literal "sdk/runanywhere-flutter/packages/runanywhere/lib/foundation/constants/sdk_constants.dart" \
  "RacNative.bindings.rac_sdk_get_version()"
reject_literal "sdk/runanywhere-flutter/packages/runanywhere/lib/foundation/constants/sdk_constants.dart" \
  "_fallbackVersion"
expect_literal "sdk/runanywhere-flutter/packages/runanywhere_qhexrt/lib/qhexrt.dart" \
  "static const String version = '${VERSION}'"
for changelog in \
  sdk/runanywhere-flutter/packages/runanywhere/CHANGELOG.md \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/CHANGELOG.md \
  sdk/runanywhere-flutter/packages/runanywhere_mlx/CHANGELOG.md \
  sdk/runanywhere-flutter/packages/runanywhere_onnx/CHANGELOG.md \
  sdk/runanywhere-flutter/packages/runanywhere_qhexrt/CHANGELOG.md; do
  expect_literal "${changelog}" "## [${VERSION}] -"
done

for gradle_file in \
  sdk/runanywhere-flutter/packages/runanywhere/android/build.gradle \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/android/build.gradle \
  sdk/runanywhere-flutter/packages/runanywhere_onnx/android/build.gradle \
  sdk/runanywhere-flutter/packages/runanywhere_qhexrt/android/build.gradle; do
  expect_literal "${gradle_file}" "version = '${VERSION}'"
done
for binary_config in \
  sdk/runanywhere-flutter/packages/runanywhere/android/binary_config.gradle \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/android/binary_config.gradle \
  sdk/runanywhere-flutter/packages/runanywhere_onnx/android/binary_config.gradle; do
  expect_literal "${binary_config}" "fallbackCoreVersion = \"${VERSION}\""
  # Gradle expands these placeholders when selecting an ABI/version archive.
  # shellcheck disable=SC2016
  expect_literal "${binary_config}" 'RACommons-android-${abi}-v${coreVersion}.zip'
done
expect_literal "sdk/runanywhere-flutter/packages/runanywhere/android/src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt" \
  "private const val SDK_VERSION = \"${VERSION}\""
expect_literal "sdk/runanywhere-flutter/packages/runanywhere/android/src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt" \
  "private const val COMMONS_VERSION = \"${VERSION}\""
expect_count "sdk/runanywhere-flutter/packages/runanywhere/ios/runanywhere/Sources/runanywhere/RunAnywherePlugin.swift" \
  "result(\"${VERSION}\")" 2
expect_literal "sdk/runanywhere-flutter/packages/runanywhere_qhexrt/android/src/main/kotlin/ai/runanywhere/sdk/qhexrt/QhexrtPlugin.kt" \
  "private const val BACKEND_VERSION = \"${VERSION}\""

for podspec in \
  sdk/runanywhere-flutter/packages/runanywhere/ios/runanywhere.podspec \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/ios/runanywhere_llamacpp.podspec \
  sdk/runanywhere-flutter/packages/runanywhere_mlx/ios/runanywhere_mlx.podspec \
  sdk/runanywhere-flutter/packages/runanywhere_onnx/ios/runanywhere_onnx.podspec; do
  expect_literal "${podspec}" "s.version          = '${VERSION}'"
done

for package_manifest in \
  sdk/runanywhere-flutter/packages/runanywhere/ios/runanywhere/Package.swift \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/ios/runanywhere_llamacpp/Package.swift \
  sdk/runanywhere-flutter/packages/runanywhere_onnx/ios/runanywhere_onnx/Package.swift; do
  expect_literal "${package_manifest}" "let sdkVersion = \"${VERSION}\""
done

for release_doc in \
  sdk/runanywhere-react-native/AGENTS.md \
  sdk/runanywhere-react-native/packages/mlx/README.md \
  sdk/runanywhere-flutter/AGENTS.md \
  sdk/runanywhere-flutter/README.md \
  sdk/runanywhere-flutter/packages/runanywhere/README.md \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/README.md \
  sdk/runanywhere-flutter/packages/runanywhere_mlx/README.md \
  sdk/runanywhere-flutter/packages/runanywhere_onnx/README.md \
  sdk/runanywhere-flutter/docs/ARCHITECTURE.md \
  sdk/runanywhere-flutter/docs/Documentation.md \
  sdk/runanywhere-swift/ARCHITECTURE.md \
  sdk/runanywhere-swift/Sources/LlamaCPPRuntime/README.md \
  sdk/runanywhere-swift/Sources/ONNXRuntime/README.md \
  sdk/runanywhere-kotlin/README.md; do
  expect_literal "${release_doc}" "${VERSION}"
done

if [ "${FAILURES}" -ne 0 ]; then
  echo "[FAIL] release version coherence: ${FAILURES} mismatch(es)" >&2
  echo "Run: scripts/release/sync-versions.sh ${VERSION}" >&2
  exit 1
fi

echo "[OK] release version coherence: ${VERSION}"
