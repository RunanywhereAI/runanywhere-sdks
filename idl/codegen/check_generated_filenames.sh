#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# check_generated_filenames.sh — assert that the filenames codegen just wrote
# are the filenames git has committed, compared case-exactly.
#
# Why this exists as a separate gate from `git status`:
#
# On a case-insensitive filesystem (macOS APFS by default, Windows NTFS) git
# resolves an index entry through the OS, so `LoRAState.kt` in the index and
# `LoraState.kt` on disk are the same file as far as `git status` is concerned
# — it reports a clean tree. On Linux they are two different files, and the
# same codegen run reports one deletion plus one untracked file. The IDL drift
# job runs on macOS, so a generator-side rename that differs only in letter
# case is invisible to it and detonates for everyone on Linux instead.
#
# That is not hypothetical: wire-compiler emits `Lora*.kt` for the six
# lora_options.proto messages, while `LoRA*.kt` stayed committed from an older
# Wire naming. Byte-identical contents, different names, green on macOS, red on
# Linux. This script compares `git ls-files` (always case-exact, it reads the
# index) against what the OS actually reports, which catches it everywhere.
#
# Usage:
#   ./idl/codegen/check_generated_filenames.sh     # run after generate_all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

# Every tree idl/codegen/generate_all.sh writes into. Keep in step with the
# output paths documented at the top of each generate_*.sh / generate_*.py.
# (bindings/proto-ts/dist is deliberately absent: tsc produces it, not protoc.)
CODEGEN_PATHS=(
    core/src/generated/proto
    core/include/rac/rac_defaults_generated.h
    bindings/kotlin/src/main/kotlin/com/runanywhere/sdk/generated
    bindings/proto-ts/src
    bindings/swift/Sources/RunAnywhere/Generated
    bindings/flutter/packages/runanywhere/lib/generated
    bindings/flutter/packages/runanywhere/android/src/main/kotlin/com/runanywhere/sdk/generated/RADefaultsPool.kt
    bindings/react-native/packages/core/android/src/main/java/com/runanywhere/sdk/generated/RADefaultsPool.kt
    bindings/python/runanywhere/_proto
    bindings/python/runanywhere/_generated_errors.py
    bindings/python/runanywhere/_generated_defaults.py
)

TRACKED="$(git ls-files -- "${CODEGEN_PATHS[@]}" | LC_ALL=C sort)"
ON_DISK="$(find "${CODEGEN_PATHS[@]}" -type f | LC_ALL=C sort)"

if [ "${TRACKED}" = "${ON_DISK}" ]; then
    echo "✓ generated filenames match the committed names (case-exact)."
    exit 0
fi

echo "::error::Generated filenames do not match the committed names." >&2
echo "" >&2
echo "  '<' = committed but not produced by codegen" >&2
echo "  '>' = produced by codegen but not committed under that exact name" >&2
echo "" >&2
diff <(printf '%s\n' "${TRACKED}") <(printf '%s\n' "${ON_DISK}") >&2 || true
echo "" >&2
echo "If the pairs differ only in letter case, git on macOS/Windows cannot see" >&2
echo "it but Linux CI can. Rename the committed files to what the generator" >&2
echo "emits: git mv -f <OldName> <NewName>" >&2
exit 1
