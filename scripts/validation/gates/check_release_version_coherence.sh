#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/sdk/runanywhere-commons/VERSION")"
FAILURES=0

if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo "[FAIL] invalid canonical release version: ${VERSION}" >&2
  exit 1
fi

expect_literal() {
  local file="$1"
  local literal="$2"
  if ! grep -Fq -- "${literal}" "${REPO_ROOT}/${file}"; then
    echo "[FAIL] ${file}: expected '${literal}'" >&2
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

expect_literal "sdk/shared/proto-ts/package.json" "\"version\": \"${VERSION}\""
expect_literal "dependencies/versions.json" "\"@runanywhere/proto-ts\": \"^${VERSION}\""

for package_json in \
  sdk/runanywhere-web/package.json \
  sdk/runanywhere-web/packages/core/package.json \
  sdk/runanywhere-web/packages/llamacpp/package.json \
  sdk/runanywhere-web/packages/onnx/package.json; do
  expect_literal "${package_json}" "\"version\": \"${VERSION}\""
done
expect_literal "sdk/runanywhere-web/packages/core/src/Foundation/Version.ts" \
  "export const SDK_VERSION = '${VERSION}'"
for package_json in \
  sdk/runanywhere-web/packages/llamacpp/package.json \
  sdk/runanywhere-web/packages/onnx/package.json; do
  expect_literal "${package_json}" "\"@runanywhere/web\": \">=${VERSION} <1\""
done
expect_literal "sdk/runanywhere-web/yarn.lock" \
  "\"@runanywhere/proto-ts@^${VERSION}\", \"@runanywhere/proto-ts@file:../shared/proto-ts\":"
expect_literal "sdk/runanywhere-web/yarn.lock" \
  "\"@runanywhere/web@>=${VERSION} <1\", \"@runanywhere/web@file:packages/core\":"

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
expect_literal "sdk/runanywhere-react-native/packages/core/android/build.gradle" \
  "def commonsVersion = \"${VERSION}\""
expect_literal "sdk/runanywhere-react-native/packages/llamacpp/android/build.gradle" ": \"${VERSION}\""
expect_literal "sdk/runanywhere-react-native/packages/onnx/android/build.gradle" \
  "def coreVersion = \"${VERSION}\""
expect_count "sdk/runanywhere-react-native/packages/core/android/build.gradle" \
  'releases/download/v${commonsVersion}/RACommons-android-v${commonsVersion}.zip' 2
expect_count "sdk/runanywhere-react-native/packages/llamacpp/android/build.gradle" \
  'releases/download/v${coreVersion}/RABackendLlamaCPP-android-v${coreVersion}.zip' 2
expect_count "sdk/runanywhere-react-native/packages/onnx/android/build.gradle" \
  'releases/download/v${coreVersion}/RABackendONNX-android-v${coreVersion}.zip' 2
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
  "static const String _fallbackVersion = '${VERSION}'"
expect_literal "sdk/runanywhere-flutter/packages/runanywhere_qhexrt/lib/qhexrt.dart" \
  "static const String version = '${VERSION}'"

for gradle_file in \
  sdk/runanywhere-flutter/packages/runanywhere/android/build.gradle \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/android/build.gradle \
  sdk/runanywhere-flutter/packages/runanywhere_onnx/android/build.gradle \
  sdk/runanywhere-flutter/packages/runanywhere_qhexrt/android/build.gradle; do
  expect_literal "${gradle_file}" "version '${VERSION}'"
done
expect_literal "sdk/runanywhere-flutter/packages/runanywhere/android/binary_config.gradle" \
  "commonsVersion = \"${VERSION}\""
expect_literal "sdk/runanywhere-flutter/packages/runanywhere/android/binary_config.gradle" \
  "coreVersion = \"${VERSION}\""
expect_literal "sdk/runanywhere-flutter/packages/runanywhere_llamacpp/android/binary_config.gradle" \
  "coreVersion = \"${VERSION}\""
expect_literal "sdk/runanywhere-flutter/packages/runanywhere_onnx/android/binary_config.gradle" \
  "coreVersion = \"${VERSION}\""
expect_literal "sdk/runanywhere-flutter/packages/runanywhere/android/binary_config.gradle" \
  'commonsAndroidUrl = "${commonsBaseUrl}/v${commonsVersion}/RACommons-android-v${commonsVersion}.zip"'
expect_literal "sdk/runanywhere-flutter/packages/runanywhere_llamacpp/android/binary_config.gradle" \
  'llamacppAndroidUrl = "${binariesBaseUrl}/v${coreVersion}/RABackendLlamaCPP-android-v${coreVersion}.zip"'
expect_literal "sdk/runanywhere-flutter/packages/runanywhere_onnx/android/binary_config.gradle" \
  'onnxAndroidUrl = "${binariesBaseUrl}/v${coreVersion}/RABackendONNX-android-v${coreVersion}.zip"'
expect_literal "sdk/runanywhere-flutter/packages/runanywhere/android/src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt" \
  "private const val SDK_VERSION = \"${VERSION}\""
expect_literal "sdk/runanywhere-flutter/packages/runanywhere/android/src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt" \
  "private const val COMMONS_VERSION = \"${VERSION}\""
expect_count "sdk/runanywhere-flutter/packages/runanywhere/ios/Classes/RunAnywherePlugin.swift" \
  "result(\"${VERSION}\")" 2
expect_literal "sdk/runanywhere-flutter/packages/runanywhere_qhexrt/android/src/main/kotlin/ai/runanywhere/sdk/qhexrt/QhexrtPlugin.kt" \
  "private const val BACKEND_VERSION = \"${VERSION}\""

for podspec in \
  sdk/runanywhere-flutter/packages/runanywhere/ios/runanywhere.podspec \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/ios/runanywhere_llamacpp.podspec \
  sdk/runanywhere-flutter/packages/runanywhere_onnx/ios/runanywhere_onnx.podspec \
  sdk/runanywhere-flutter/packages/runanywhere_qhexrt/ios/runanywhere_qhexrt.podspec; do
  expect_literal "${podspec}" "s.version          = '${VERSION}'"
done

for release_doc in \
  sdk/runanywhere-react-native/AGENTS.md \
  sdk/runanywhere-flutter/AGENTS.md \
  sdk/runanywhere-flutter/README.md \
  sdk/runanywhere-flutter/packages/runanywhere/README.md \
  sdk/runanywhere-flutter/packages/runanywhere_llamacpp/README.md \
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
