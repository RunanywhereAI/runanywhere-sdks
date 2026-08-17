#!/usr/bin/env bash
#
# rcli is compiled by two build systems from two hand-maintained source lists:
# rcli/CMakeLists.txt (RCLI_SOURCES) builds the Linux/Windows/dev binary, and
# Package.swift (the RCLIHost target) builds the Swift-hosted macOS binary that
# actually ships. Nothing links them, so adding a .cpp to one and not the other
# compiles fine and then fails at link, in whichever build you happen not to run.
#
# That is not hypothetical: src/repl/transcript.cpp was added to CMake only, and
# the Swift build died with "undefined symbol rcli::repl::Transcript::Transcript"
# after six minutes of compiling. This gate compares the two lists directly.
#
# linenoise is excluded: CMake drops it on Windows (POSIX-only) while SwiftPM,
# which only ever builds Apple targets, always includes it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CMAKE_FILE="${REPO_ROOT}/rcli/CMakeLists.txt"
PACKAGE_FILE="${REPO_ROOT}/Package.swift"

for f in "${CMAKE_FILE}" "${PACKAGE_FILE}"; do
    [ -f "$f" ] || { echo "ERROR: missing ${f}" >&2; exit 1; }
done

# RCLI_SOURCES( ... ) up to the closing paren.
cmake_sources="$(awk '/^set\(RCLI_SOURCES/{flag=1; next} /^\)/{flag=0} flag' "${CMAKE_FILE}" \
    | tr -d ' \t' | grep -E '^src/.*\.(cpp|c)$' | sort -u)"

# The RCLIHost target's sources: [ ... ] block.
swift_sources="$(awk '/name: "RCLIHost"/{flag=1} flag && /sources: \[/{collect=1; next} collect && /\],/{collect=0; flag=0} collect' "${PACKAGE_FILE}" \
    | tr -d ' \t"' | sed 's/,$//' | grep -E '^src/.*\.(cpp|c)$' | sort -u)"

if [ -z "${cmake_sources}" ] || [ -z "${swift_sources}" ]; then
    echo "ERROR: parsed an empty source list (CMake: $(echo "${cmake_sources}" | grep -c . || true), SwiftPM: $(echo "${swift_sources}" | grep -c . || true))." >&2
    echo "       The gate cannot pass vacuously; fix the parser before trusting it." >&2
    exit 1
fi

only_cmake="$(comm -23 <(echo "${cmake_sources}") <(echo "${swift_sources}"))"
only_swift="$(comm -13 <(echo "${cmake_sources}") <(echo "${swift_sources}"))"

status=0
if [ -n "${only_cmake}" ]; then
    echo "In rcli/CMakeLists.txt but NOT in Package.swift RCLIHost:" >&2
    echo "${only_cmake}" | sed 's/^/  /' >&2
    echo "  -> the macOS binary will fail to link these symbols." >&2
    status=1
fi
if [ -n "${only_swift}" ]; then
    echo "In Package.swift RCLIHost but NOT in rcli/CMakeLists.txt:" >&2
    echo "${only_swift}" | sed 's/^/  /' >&2
    echo "  -> the CMake binary will fail to link these symbols." >&2
    status=1
fi

if [ "${status}" -eq 0 ]; then
    echo "rcli source lists agree ($(echo "${cmake_sources}" | grep -c .) files)"
fi
exit "${status}"
