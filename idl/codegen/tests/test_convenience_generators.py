#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Smoke test for the four convenience generators
# (generate_{swift,kotlin,dart,ts}_convenience.py).
#
# pass2-syn-056: the production IDL only exercises rac_required against a
# single string field and rac_min/max against int32 sample_rate fields,
# leaving the int64, float, double, bool, and enum-default code paths in
# the generators dormant. This test:
#
#   1. Builds a FileDescriptorSet covering idl/codegen/tests/fixtures/
#      test_options.proto (which applies every rac_* option to every
#      relevant scalar type) plus the canonical idl/rac_options.proto.
#
#   2. Runs each generator against that fixture FDS, writing the output
#      to a temp directory.
#
#   3. Diffs the per-language output against the committed goldens at
#      idl/codegen/tests/golden/{swift,kotlin,dart,ts}.expected.
#
# Approach: each generator's `main()` reads `proto_dir = repo_root / "idl"`
# and writes to a fixed SDK output path, with `repo_root` computed from
# `__file__`. To run them against the fixture in isolation, we copy the
# entire idl/codegen/ tree into a tempdir sandbox and populate
# `sandbox/idl/` with only `rac_options.proto` + the fixture. The
# generators then compute their own paths via `Path(__file__).resolve()`
# and operate purely on the sandbox — they never see or touch the real
# repo's idl/ or SDK source trees.
#
# Usage
# -----
#
#   # Bootstrap the goldens (first run, after fixture changes):
#   python3 idl/codegen/tests/test_convenience_generators.py --update-golden
#
#   # Verify (CI / pre-commit):
#   python3 idl/codegen/tests/test_convenience_generators.py
#
# Exit code: 0 on success, 1 if any generator output diverges from its
# golden, 2 if the toolchain (protoc, python protobuf) is missing.
#
# CI integration: not currently wired into pr-build.yml. Running this in
# CI requires protoc on PATH and the Python protobuf runtime installed —
# both are already prerequisites for the existing idl-drift-check.yml
# workflow, so the additional cost is two subprocess invocations per
# language. A follow-up patch may add a `convenience-smoke` job that
# invokes this script after idl-drift-check; see pass2-syn-056 for the
# rationale and the dormant-bug surface this smoke test catches.

from __future__ import annotations

import argparse
import difflib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
TESTS_DIR  = SCRIPT_DIR
REPO_ROOT  = SCRIPT_DIR.parent.parent.parent
CODEGEN_DIR = REPO_ROOT / "idl" / "codegen"
FIXTURE_DIR = TESTS_DIR / "fixtures"
GOLDEN_DIR  = TESTS_DIR / "golden"

FIXTURE_PROTO     = FIXTURE_DIR / "test_options.proto"
RAC_OPTIONS_PROTO = REPO_ROOT / "idl" / "rac_options.proto"


# Each tuple = (language label, generator filename, relative output path
# under the sandbox repo). The relative output path mirrors each
# generator's hard-coded SDK output location; we read the resulting file
# from inside the sandbox after running the generator.
GENERATORS: list[tuple[str, str, Path]] = [
    (
        "swift",
        "generate_swift_convenience.py",
        Path("sdk") / "runanywhere-swift" / "Sources" / "RunAnywhere"
        / "Generated" / "RAConvenience.swift",
    ),
    (
        "kotlin",
        "generate_kotlin_convenience.py",
        Path("sdk") / "runanywhere-kotlin" / "src" / "main" / "kotlin"
        / "com" / "runanywhere" / "sdk" / "generated" / "convenience"
        / "RAConvenience.kt",
    ),
    (
        "dart",
        "generate_dart_convenience.py",
        Path("sdk") / "runanywhere-flutter" / "packages" / "runanywhere"
        / "lib" / "generated" / "convenience" / "ra_convenience.dart",
    ),
    (
        "ts",
        "generate_ts_convenience.py",
        # The TS generator emits one file per .proto under the convenience/
        # directory. For this fixture (single proto: test_options.proto) the
        # output is test_options_convenience.ts.
        Path("sdk") / "shared" / "proto-ts" / "src" / "convenience"
        / "test_options_convenience.ts",
    ),
]


# ---------------------------------------------------------------------------
# Toolchain checks.
# ---------------------------------------------------------------------------

def check_toolchain() -> int:
    """Return 0 if protoc + python protobuf runtime are available, 2 otherwise."""
    if shutil.which("protoc") is None:
        print("error: protoc not found on PATH — required to build the FileDescriptorSet.",
              file=sys.stderr)
        return 2
    try:
        import google.protobuf  # noqa: F401
    except ImportError:
        print("error: python protobuf runtime not installed; "
              "run `pip install protobuf`.", file=sys.stderr)
        return 2
    return 0


# ---------------------------------------------------------------------------
# Sandbox repo setup.
# ---------------------------------------------------------------------------

def build_sandbox(sandbox: Path) -> None:
    """Create a minimal repo layout under `sandbox` that the generators can
    operate on unchanged. The generators compute `repo_root` from
    `Path(__file__).resolve().parent.parent.parent` — `.resolve()` follows
    symlinks, so we cannot symlink the codegen dir; we must copy it so the
    generator scripts physically live inside the sandbox.

    Layout produced:
      sandbox/
        idl/
          rac_options.proto          (copy of the real one)
          test_options.proto         (copy of fixtures/test_options.proto)
          codegen/                   (copy of the real codegen/ dir)
            generate_swift_convenience.py
            generate_kotlin_convenience.py
            generate_dart_convenience.py
            generate_ts_convenience.py
            _convenience_common.py
            templates/...
    """
    (sandbox / "idl").mkdir(parents=True)
    shutil.copy(RAC_OPTIONS_PROTO, sandbox / "idl" / "rac_options.proto")
    shutil.copy(FIXTURE_PROTO,     sandbox / "idl" / "test_options.proto")
    # Copy the entire codegen/ tree so the generator scripts compute
    # `repo_root` as the sandbox (their `.resolve()` chain stays inside
    # `sandbox/`). The copy is shallow enough (<200 KB) that the cost is
    # negligible per test run.
    shutil.copytree(
        CODEGEN_DIR,
        sandbox / "idl" / "codegen",
        ignore=shutil.ignore_patterns("__pycache__", "tests"),
    )


def run_generator(generator_script: str, sandbox: Path) -> tuple[int, str, str]:
    """Run a single generator's main() against the sandbox idl/ dir."""
    script_path = sandbox / "idl" / "codegen" / generator_script
    proc = subprocess.run(
        [sys.executable, str(script_path)],
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


# ---------------------------------------------------------------------------
# Compare / update goldens.
# ---------------------------------------------------------------------------

def diff_against_golden(language: str, generated: str) -> tuple[bool, str]:
    """Return (matches, diff_text). When the golden is missing or differs,
    `matches` is False and `diff_text` is the unified diff."""
    golden_path = GOLDEN_DIR / f"{language}.expected"
    if not golden_path.is_file():
        return False, (
            f"golden missing: {golden_path}\n"
            f"  bootstrap with: python3 {Path(__file__).name} --update-golden"
        )
    golden = golden_path.read_text(encoding="utf-8")
    if golden == generated:
        return True, ""
    diff = "\n".join(difflib.unified_diff(
        golden.splitlines(),
        generated.splitlines(),
        fromfile=str(golden_path),
        tofile=f"<generated:{language}>",
        lineterm="",
    ))
    return False, diff


def write_golden(language: str, generated: str) -> Path:
    GOLDEN_DIR.mkdir(parents=True, exist_ok=True)
    golden_path = GOLDEN_DIR / f"{language}.expected"
    golden_path.write_text(generated, encoding="utf-8")
    return golden_path


# ---------------------------------------------------------------------------
# Cross-language structural parity (pass3-syn-124).
# ---------------------------------------------------------------------------
#
# The per-language goldens above catch regressions where a single generator
# drifts from its own committed output. They do NOT catch the case where two
# generators produce structurally divergent output for the same fixture —
# notably hotspot-conv-003 (bool + rac_required), where TS historically
# emitted a validate-block for `enable_feature_bool` while Swift/Kotlin/Dart
# did not.
#
# `assert_cross_language_parity()` extracts, from each language's emitted
# output, the structural signature of the convenience surface:
#
#   - The SET of fields the generator emits a validate-block for
#     (matched via the language-agnostic `fieldPath` strings
#     `'RacTestConfig.<field_name>'` that all four generators thread through
#     to the SDKException / ValidationError constructor).
#   - The SET of fields the generator emits a default literal for
#     (matched against the proto field names in the fixture).
#   - The error-shape: whether the validate-block raises a typed exception
#     (all four current generators do).
#
# We then assert pairwise that all four generators agree on:
#   * the set of validated fields (structural parity), and
#   * the error-shape category (semantic parity).
#
# Syntactic differences (e.g. `nameString.isEmpty` vs `m.nameString === ''`
# vs `name_string.isEmpty()`) are intentionally ignored — only the LOGICAL
# field set + error category matter.

# Proto field names from idl/codegen/tests/fixtures/test_options.proto.
# The fixture-protocol contract: any rac_required/rac_min/rac_max annotated
# field is expected to surface as a fieldPath of `RacTestConfig.<name>` in
# whatever exception/error the generator emits.
_FIXTURE_VALIDATABLE_FIELDS: frozenset[str] = frozenset({
    "name_string",
    "retries_int32",
    "limit_int64",
    "threshold_float",
    "precision_double",
    "enable_feature_bool",
    "mono_channel_count",
})

# Regex captures the field-name suffix of every `'RacTestConfig.<name>'`
# literal in a golden. The four generators all thread the proto field name
# through the fieldPath argument, so a hit here means "this generator emits
# a validate-or-default block referencing that field". To narrow strictly to
# validate-blocks we restrict to fieldPath literals that co-occur with the
# exception/error constructor on the same logical block.
_FIELDPATH_RE = re.compile(r"RacTestConfig\.([a-z_][a-z0-9_]*)")


def _validate_block_text(generated: str, language: str) -> str:
    """Extract just the validate() function/block body from a generated
    file. Falls back to the whole text if the marker isn't found, which
    keeps the parity check conservative (over-counting fields rather than
    silently dropping them)."""
    markers = {
        "swift":  ("public func validate() throws", "extension RARacTestConfig"),
        "kotlin": ("public fun RacTestConfig.validate()", None),
        "dart":   ("void validate() {", None),
        "ts":     ("validateRacTestConfig", None),
    }
    start_marker, _ = markers.get(language, (None, None))
    if start_marker is None or start_marker not in generated:
        return generated
    return generated[generated.index(start_marker):]


def _extract_validated_fields(generated: str, language: str) -> frozenset[str]:
    """Return the set of proto field names referenced inside the validate
    block of `generated`. Uses the language-agnostic `RacTestConfig.<name>`
    fieldPath literal that all four generators emit."""
    block = _validate_block_text(generated, language)
    found = set()
    for m in _FIELDPATH_RE.finditer(block):
        name = m.group(1)
        if name in _FIXTURE_VALIDATABLE_FIELDS:
            found.add(name)
    return frozenset(found)


# Substrings that, if present in a validate-block, identify the error-shape
# the generator emits. All four currently throw a typed exception (Swift /
# Kotlin / Dart use SDKException.validationFailed; TS uses ValidationError).
# A future generator that populated a result struct instead of throwing
# would fail this check, surfacing the divergence.
_ERROR_SHAPE_SIGNATURES: dict[str, tuple[str, ...]] = {
    "swift":  ("throw SDKException.validationFailed",),
    "kotlin": ("throw SDKException.validationFailed",),
    "dart":   ("throw SDKException.validationFailed",),
    "ts":     ("throw new ValidationError",),
}


def _classify_error_shape(generated: str, language: str) -> str:
    """Classify the error-shape of `language`'s validate block. Returns
    'throws_exception' if any of the language's signature substrings appear,
    else 'no_validate_block' / 'unknown_shape'."""
    block = _validate_block_text(generated, language)
    sigs = _ERROR_SHAPE_SIGNATURES.get(language, ())
    if any(sig in block for sig in sigs):
        return "throws_exception"
    # No marker AND no fieldPath references → generator emitted no
    # validate block at all (legitimate if no fields were annotated).
    if not _FIELDPATH_RE.search(block):
        return "no_validate_block"
    return "unknown_shape"


def assert_cross_language_parity(
    outputs: dict[str, str],
) -> list[str]:
    """Compare the four languages' outputs structurally. Returns a list of
    parity violations (empty == aligned).

    `outputs` maps language label -> generated source text.
    """
    violations: list[str] = []

    # 1. Validated-field-set parity.
    fields_by_lang: dict[str, frozenset[str]] = {
        lang: _extract_validated_fields(src, lang) for lang, src in outputs.items()
    }
    union = frozenset().union(*fields_by_lang.values())
    for lang, fs in fields_by_lang.items():
        missing = union - fs
        if missing:
            other_langs = sorted(
                other for other, other_fs in fields_by_lang.items()
                if other != lang and missing & other_fs
            )
            violations.append(
                f"[parity] {lang} does NOT emit validate-block for field(s) "
                f"{sorted(missing)} that {other_langs} DO validate. "
                f"This is the hotspot-conv-003 class of divergence — fix by "
                f"either adding the missing validate check to {lang} or "
                f"removing it from {other_langs}."
            )

    # 2. Error-shape parity. All four generators must agree on whether
    # validate() throws a typed exception or returns a structured result.
    shape_by_lang: dict[str, str] = {
        lang: _classify_error_shape(src, lang) for lang, src in outputs.items()
    }
    distinct_shapes = set(shape_by_lang.values())
    if len(distinct_shapes) > 1:
        violations.append(
            f"[parity] error-shape diverges across languages: "
            f"{sorted(shape_by_lang.items())}. All four generators must "
            f"agree on whether validate() throws a typed exception or "
            f"populates a result struct."
        )

    return violations


# The fixture's optional threshold_float mirrors DiarizationOptions.threshold.
# A plain `< min || > max` guard accepts NaN in every target language, so keep
# explicit structural cases for all three invalid classes at the generator
# boundary. These tokens live in the same emitted condition in each golden.
_FLOAT_RANGE_CASE_SIGNATURES: dict[str, dict[str, str]] = {
    "swift": {
        "negative": "effectiveThresholdFloat < 0.0",
        "above_max": "effectiveThresholdFloat > 1.0",
        "nan_or_non_finite": "!effectiveThresholdFloat.isFinite",
    },
    "kotlin": {
        "negative": "threshold_float < 0.0",
        "above_max": "threshold_float > 1.0",
        "nan_or_non_finite": "!threshold_float.isFinite()",
    },
    "dart": {
        "negative": "effectiveThresholdFloat < 0.0",
        "above_max": "effectiveThresholdFloat > 1.0",
        "nan_or_non_finite": "!effectiveThresholdFloat.isFinite",
    },
    "ts": {
        "negative": "m.thresholdFloat < 0.0",
        "above_max": "m.thresholdFloat > 1.0",
        "nan_or_non_finite": "!Number.isFinite(m.thresholdFloat)",
    },
}


def assert_float_range_cases(outputs: dict[str, str]) -> list[str]:
    """Require negative, above-max, and NaN/non-finite threshold guards."""
    violations: list[str] = []
    for language, signatures in _FLOAT_RANGE_CASE_SIGNATURES.items():
        generated = outputs.get(language, "")
        for case_name, signature in signatures.items():
            if signature not in generated:
                violations.append(
                    f"[float-range] {language} is missing the {case_name} "
                    f"threshold guard: {signature}"
                )
    return violations


# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Smoke test for idl/codegen convenience generators "
                    "(pass2-syn-056).",
    )
    parser.add_argument(
        "--update-golden",
        action="store_true",
        help="Re-bootstrap the golden files from the current generator output. "
             "Run after changing the fixture or the generator implementation.",
    )
    parser.add_argument(
        "--keep-sandbox",
        action="store_true",
        help="Print the sandbox path and skip cleanup. Useful for "
             "debugging generator failures interactively.",
    )
    args = parser.parse_args()

    rc = check_toolchain()
    if rc != 0:
        return rc

    failures: list[str] = []
    updated_paths: list[Path] = []
    generated_outputs: dict[str, str] = {}

    with tempfile.TemporaryDirectory(prefix="rac-convenience-test-") as tmp:
        sandbox = Path(tmp) / "repo"
        build_sandbox(sandbox)

        for language, generator_script, out_rel_path in GENERATORS:
            print(f"-- running {generator_script} (language={language}) ...")
            code, stdout, stderr = run_generator(generator_script, sandbox)
            if code != 0:
                failures.append(
                    f"[{language}] {generator_script} exited {code}\n"
                    f"  stdout: {stdout}\n"
                    f"  stderr: {stderr}"
                )
                continue

            out_path = sandbox / out_rel_path
            if not out_path.is_file():
                failures.append(
                    f"[{language}] generator did not produce expected output at "
                    f"{out_rel_path}\n  stdout: {stdout}\n  stderr: {stderr}"
                )
                continue

            generated = out_path.read_text(encoding="utf-8")
            generated_outputs[language] = generated

            if args.update_golden:
                p = write_golden(language, generated)
                updated_paths.append(p)
                print(f"   wrote golden -> {p}")
                continue

            ok, diff = diff_against_golden(language, generated)
            if not ok:
                failures.append(f"[{language}] golden mismatch:\n{diff}")
            else:
                print(f"   {language} ok ({len(generated)} bytes)")

        # Cross-language structural parity check (pass3-syn-124). Runs in
        # both verification and --update-golden modes so that bootstrapping
        # the goldens still surfaces structural divergences. Skipped if any
        # generator failed (incomplete inputs would yield spurious
        # violations).
        if len(generated_outputs) == len(GENERATORS):
            print("-- asserting cross-language structural parity ...")
            parity_violations = assert_cross_language_parity(generated_outputs)
            if parity_violations:
                for v in parity_violations:
                    failures.append(v)
            else:
                print("   parity ok (validated-field set + error-shape "
                      "aligned across swift/kotlin/dart/ts)")

            print("-- asserting float-range invalid-value cases ...")
            float_range_violations = assert_float_range_cases(generated_outputs)
            if float_range_violations:
                failures.extend(float_range_violations)
            else:
                print("   float-range ok (negative, above-max, and NaN/non-finite)")

        if args.keep_sandbox:
            # Re-root the sandbox so the TemporaryDirectory cleanup does
            # not delete it. (shutil.copytree → /tmp/.../keep)
            keep = Path(tempfile.mkdtemp(prefix="rac-convenience-keep-"))
            shutil.copytree(sandbox, keep / "repo", symlinks=True)
            print(f"-- sandbox copy retained at: {keep / 'repo'}")

    if failures:
        print(file=sys.stderr)
        print("=" * 70, file=sys.stderr)
        print("FAIL: convenience generator smoke test", file=sys.stderr)
        print("=" * 70, file=sys.stderr)
        for f in failures:
            print(f, file=sys.stderr)
            print(file=sys.stderr)
        return 1

    if updated_paths:
        print()
        print(f"Updated {len(updated_paths)} golden file(s). Commit these.")

    print()
    print("OK: convenience generator smoke test passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
