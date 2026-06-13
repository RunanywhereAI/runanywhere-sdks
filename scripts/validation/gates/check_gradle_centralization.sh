#!/usr/bin/env bash
#
# check_gradle_centralization.sh
#
# T4.2 (PR #494) Kotlin Gradle centralization gate. Fails if any
# `*.gradle.kts` file declares a Maven dependency with a hardcoded
# `group:artifact:version` coordinate instead of resolving it through the
# canonical version catalog at `gradle/libs.versions.toml`.
#
# What this rejects:
#   implementation("io.ktor:ktor-client-core:3.0.3")
#   api("com.squareup.okhttp3:okhttp:4.12.0")
#   testImplementation("io.mockk:mockk:1.13.14")
#   kapt("androidx.room:room-compiler:2.6.1")
#   runtimeOnly("org.junit.vintage:junit-vintage-engine:5.10.2")
#   compileOnly("org.jetbrains:annotations:24.0.1")
#   debugImplementation("androidx.compose.ui:ui-tooling:1.5.0")
#   classpath("com.android.tools.build:gradle:8.11.2")
#
# What this allows:
#   - libs.<alias> references (catalog-resolved)
#   - 2-part coordinates with no version (e.g. inside `constraints { ... }`
#     where the version is pinned via `strictly(libs.versions.kotlin.get())`)
#   - Comments (`//` line comments and `/* ... */` block comments)
#   - The catalog file itself (`gradle/libs.versions.toml`)
#
# Scope:
#   Walks every tracked `*.gradle.kts` file under the repo root, excluding
#   build outputs (`build/`, `.gradle/`), vendored third-party trees, and
#   node_modules.
#
# Exit codes:
#   0 - no hardcoded coordinates found
#   1 - one or more violations detected (printed with file:line:source)
#   2 - usage / environment error
#
# Usage:
#   scripts/validation/gates/check_gradle_centralization.sh
#
# CI wiring: invoke this from the Kotlin / lint job; it is a fast pure-bash
# gate with no Gradle/JDK dependency.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

cd "${REPO_ROOT}"

# Maven-coord configurations we audit. `classpath` is included because it is
# the legacy buildscript form that also carries hardcoded coordinates.
CONFIGS_REGEX='(implementation|api|testImplementation|androidTestImplementation|kapt|ksp|runtimeOnly|compileOnly|debugImplementation|releaseImplementation|classpath)'

# Hardcoded coord: `config("group:artifact:version")` — three colon-separated
# segments inside the literal. Version segment starts with a digit to avoid
# matching `project("...")` paths or stringly-typed task names.
HARDCODED_REGEX="^[[:space:]]*${CONFIGS_REGEX}[[:space:]]*\\([[:space:]]*\"[A-Za-z0-9._-]+:[A-Za-z0-9._-]+:[0-9][A-Za-z0-9._+-]*\"[[:space:]]*[),]"

# Paths to exclude — vendored projects and generated outputs. Applied as an
# ERE filter over the tracked-file list. Playground/ is a collection of
# standalone demo projects that are not part of any unified build system (see
# AGENTS.md); it is intentionally excluded from the centralization gate so its
# experimental version pins can drift independently.
EXCLUDE_PATHS_REGEX='(^|/)(build|\.gradle|node_modules|third_party)/|(^|/)build[-_][^/]*/|^Playground/'

# Tracked *.gradle.kts files only — matches the stated scope and needs no
# external tooling beyond git + grep.
files=()
while IFS= read -r f; do
    files+=("${f}")
done < <(git ls-files -- '*.gradle.kts' | grep -Ev "${EXCLUDE_PATHS_REGEX}" || true)

if [[ ${#files[@]} -eq 0 ]]; then
    echo "[OK] check_gradle_centralization: no tracked *.gradle.kts files in scope."
    exit 0
fi

# Collect every line matching the hardcoded coord shape. The regex's
# `^[[:space:]]*` anchor excludes `//` line comments and the comment-form
# `// Usage: implementation(...)` pattern that documents Maven Central usage
# in publishing blocks.
#
# `grep` returns exit code 1 when no matches are found, so we tolerate that
# specific code without failing the script.
set +e
matches="$(grep -EHn "${HARDCODED_REGEX}" "${files[@]}")"
grep_status=$?
set -e

if [[ ${grep_status} -ne 0 && ${grep_status} -ne 1 ]]; then
    echo "error: grep failed with exit code ${grep_status}" >&2
    exit 2
fi

if [[ -z "${matches}" ]]; then
    echo "[OK] check_gradle_centralization: no hardcoded Maven coordinates found in *.gradle.kts."
    exit 0
fi

echo "[FAIL] check_gradle_centralization: hardcoded Maven coordinates detected." >&2
echo "" >&2
echo "Every Gradle dependency MUST resolve through gradle/libs.versions.toml." >&2
echo "Fix by:" >&2
echo "  1. Adding a [versions] + [libraries] entry to gradle/libs.versions.toml" >&2
echo "  2. Replacing the hardcoded coord with libs.<alias>" >&2
echo "" >&2
echo "Violations:" >&2
echo "${matches}" >&2
exit 1
