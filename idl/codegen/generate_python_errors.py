#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Python error-enum emitter.
#
# The Python SDK talks to the flat C ABI for everything except RAG, so it has
# no full proto binding layer and no convenience post-processor. What it did
# have was a 139-member ErrorCode IntEnum and a 9-member ErrorCategory
# transcribed by hand from idl/errors.proto, under a docstring asking the
# reader to "keep in sync" — the kind of instruction nothing enforces.
#
# This generates both enums instead. errors.py keeps its SDKException, its
# category_for_code range table, and everything else that is real logic; only
# the transcription moves here.
#
# Output:
#   sdk/runanywhere-python/runanywhere/_generated_errors.py
#
# Naming: the proto strips the enum-name prefix, so ERROR_CODE_MODEL_NOT_FOUND
# becomes MODEL_NOT_FOUND and ERROR_CATEGORY_NETWORK becomes NETWORK. That
# matches what errors.py already exposed, so nothing downstream changes.

from __future__ import annotations

import sys
from pathlib import Path

from google.protobuf import descriptor_pb2

from _convenience_common import (
    enum_name_to_screaming_snake,
    iter_runanywhere_files,
    iter_top_level_enums,
    load_file_descriptor_set,
)

OUT_RELPATH = Path("sdk/runanywhere-python/runanywhere/_generated_errors.py")

# Only what errors.py re-exports. ErrorSeverity exists in the IDL but nothing in
# the Python SDK consumes it, and the package's AGENTS.md is explicit about not
# shipping surface that implies a capability nobody uses.
WANTED = ("ErrorCode", "ErrorCategory")


def strip_prefix(enum_name: str, value_name: str) -> str:
    prefix = enum_name_to_screaming_snake(enum_name) + "_"
    if value_name.startswith(prefix):
        return value_name[len(prefix):]
    return value_name


def collect(
    fds: descriptor_pb2.FileDescriptorSet,
) -> dict[str, list[tuple[str, int, str]]]:
    """Return {enum_name: [(python_name, number, trailing_comment)]}."""
    found: dict[str, list[tuple[str, int, str]]] = {}
    for file_desc in iter_runanywhere_files(fds):
        if file_desc.name != "errors.proto":
            continue
        for enum_name, enum_desc in iter_top_level_enums(file_desc):
            if enum_name not in WANTED:
                continue
            entries: list[tuple[str, int, str]] = []
            seen: dict[int, str] = {}
            for value in enum_desc.value:
                py_name = strip_prefix(enum_name, value.name)
                # Python IntEnum turns a duplicate number into an alias of the
                # first member rather than a second member. That is silent, so
                # report it: two proto constants sharing a number is either
                # deliberate aliasing or a numbering bug worth seeing.
                if value.number in seen:
                    print(
                        f"note: {enum_name}.{py_name} = {value.number} aliases "
                        f"{seen[value.number]}; emitting as a comment",
                        file=sys.stderr,
                    )
                    entries.append((py_name, value.number, f"alias of {seen[value.number]}"))
                    continue
                seen[value.number] = py_name
                entries.append((py_name, value.number, ""))
            found[enum_name] = entries
    return found


def render(enums: dict[str, list[tuple[str, int, str]]]) -> str:
    lines: list[str] = []
    # One-line docstring then the future import, per the Python SDK's module
    # convention; everything else is a comment below them.
    lines.append('"""Error enums generated from idl/errors.proto."""')
    lines.append("")
    lines.append("from __future__ import annotations")
    lines.append("")
    lines.append("# GENERATED FILE - DO NOT EDIT.")
    lines.append("# Regenerate with: idl/codegen/generate_python_errors.py")
    lines.append("#")
    lines.append("# Values are the positive canonical numbers from the IDL. The C ABI returns")
    lines.append("# them negated as rac_result_t; negate once at the boundary rather than")
    lines.append("# maintaining a second table.")
    lines.append("")
    lines.append("from enum import IntEnum")
    lines.append("")

    for enum_name in WANTED:
        entries = enums.get(enum_name)
        if not entries:
            continue
        lines.append("")
        lines.append(f"class {enum_name}(IntEnum):")
        lines.append(f'    """Generated from the {enum_name} enum in idl/errors.proto."""')
        lines.append("")
        for py_name, number, comment in entries:
            if comment:
                lines.append(f"    # {py_name} = {number}  # {comment}")
            else:
                lines.append(f"    {py_name} = {number}")
        lines.append("")

    # Sorted so RUF022 stays quiet on every regeneration.
    names = ", ".join(f'"{n}"' for n in sorted(n for n in WANTED if enums.get(n)))
    lines.append("")
    lines.append(f"__all__ = [{names}]")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    idl_dir = script_dir.parent
    repo_root = idl_dir.parent

    fds = load_file_descriptor_set(idl_dir)
    if fds is None:
        print("error: no .proto files found in idl/", file=sys.stderr)
        return 1

    enums = collect(fds)
    missing = [n for n in WANTED if not enums.get(n)]
    if missing:
        print(f"error: errors.proto is missing expected enums: {missing}", file=sys.stderr)
        return 1

    out_path = repo_root / OUT_RELPATH
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render(enums), encoding="utf-8")

    counts = ", ".join(f"{n}={len(enums[n])}" for n in WANTED if enums.get(n))
    print(f"✓ Python error enums → {out_path} ({counts})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
