#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# C header emitter for `rac_default` annotations.
#
# The other four convenience post-processors give Swift, Kotlin, Dart, and
# TypeScript a `defaults()` factory per annotated message. C++ commons had no
# equivalent, so its default structs (RAC_LLM_OPTIONS_DEFAULT,
# RAC_VLM_OPTIONS_DEFAULT, RAC_STT_DEFAULT_SAMPLE_RATE, ...) were hand-written
# and free to drift from the proto the SDKs generate against. This closes that
# gap: the annotations become C macros, and commons composes its structs from
# them.
#
# That matters more than it sounds. commons is the layer that actually runs
# inference, so a proto default the C layer disagrees with is a default that
# does not take effect.
#
# Output:
#   sdk/runanywhere-commons/include/rac/rac_defaults_generated.h
#
# Macro naming is mechanical: RAC_DEFAULT_<MESSAGE>_<FIELD>, both in
# SCREAMING_SNAKE, with a trailing _DEFAULTS stripped from the message so the
# pool messages read RAC_DEFAULT_NETWORK_REQUEST_TIMEOUT_MS rather than
# RAC_DEFAULT_NETWORK_DEFAULTS_REQUEST_TIMEOUT_MS.
#
# Enum-typed fields are skipped: `rac_default` names a proto constant, and
# mapping that to the corresponding C enumerator needs a name table this
# generator has no way to derive. No annotated field is an enum today; if one
# appears, the skip is reported on stderr rather than passed over in silence.

from __future__ import annotations

import sys
from pathlib import Path

from google.protobuf import descriptor_pb2

from _convenience_common import (
    RAC_DEFAULT_FIELD_NUM,
    TYPE_BOOL,
    TYPE_ENUM,
    LangProfile,
    enum_name_to_screaming_snake,
    get_string_option,
    iter_runanywhere_files,
    iter_top_level_messages,
    load_file_descriptor_set,
    to_default_literal,
)

# C literals: float constants take an `f` suffix, int64 takes `LL`.
C_PROFILE = LangProfile(int64_wrapper=None, int64_suffix="LL", float_suffix="f")

HEADER_GUARD = "RAC_DEFAULTS_GENERATED_H"
OUT_RELPATH = Path("sdk/runanywhere-commons/include/rac/rac_defaults_generated.h")


def macro_name(message_name: str, field_name: str) -> str:
    msg = enum_name_to_screaming_snake(message_name)
    if msg.endswith("_DEFAULTS"):
        msg = msg[: -len("_DEFAULTS")]
    return f"RAC_DEFAULT_{msg}_{field_name.upper()}"


def collect(fds: descriptor_pb2.FileDescriptorSet) -> list[tuple[str, str, list[tuple[str, str, str]]]]:
    """Return [(file_name, message_name, [(macro, literal, comment)])] for every
    message carrying at least one usable rac_default."""
    out: list[tuple[str, str, list[tuple[str, str, str]]]] = []
    # include_declaration_only: the pool in sdk_defaults.proto has no generated
    # message type in any language, but commons still needs its values.
    for file_desc in iter_runanywhere_files(fds, include_declaration_only=True):
        for msg_name, msg_desc in iter_top_level_messages(file_desc):
            entries: list[tuple[str, str, str]] = []
            for field in msg_desc.field:
                if not field.HasField("options"):
                    continue
                default_str = get_string_option(field.options, RAC_DEFAULT_FIELD_NUM)
                if default_str is None:
                    continue
                if field.type == TYPE_ENUM:
                    print(
                        f"note: skipping enum field {msg_name}.{field.name} "
                        f"(rac_default={default_str!r}); C enumerator mapping is not derivable",
                        file=sys.stderr,
                    )
                    continue
                literal = to_default_literal(field, default_str, {}, C_PROFILE)
                if field.type == TYPE_BOOL and literal is not None:
                    # `true` / `false` are C++ keywords; in C they need
                    # <stdbool.h>, and this header is included from C
                    # translation units through rac_llm_types.h and friends.
                    # RAC_TRUE / RAC_FALSE are the repo's rac_bool_t constants
                    # and carry the right type as well as the right value.
                    literal = "RAC_TRUE" if literal == "true" else "RAC_FALSE"
                if literal is None:
                    print(
                        f"note: skipping {msg_name}.{field.name}: "
                        f"unsupported type {field.type} for rac_default={default_str!r}",
                        file=sys.stderr,
                    )
                    continue
                entries.append((macro_name(msg_name, field.name), literal, field.name))
            if entries:
                out.append((file_desc.name, msg_name, entries))
    return out


def render(groups: list[tuple[str, str, list[tuple[str, str, str]]]]) -> str:
    lines: list[str] = []
    lines.append("// SPDX-License-Identifier: Apache-2.0")
    lines.append("//")
    lines.append("// GENERATED FILE — DO NOT EDIT.")
    lines.append("// Regenerate with: idl/codegen/generate_cpp_defaults.py")
    lines.append("//")
    lines.append("// Every macro here comes from a `(runanywhere.v1.rac_default)` annotation in")
    lines.append("// idl/. Change the value in the .proto, not here: the SDKs generate their own")
    lines.append("// defaults from the same annotations, so editing this file only desynchronizes")
    lines.append("// C++ from the five platform SDKs.")
    lines.append("")
    lines.append(f"#ifndef {HEADER_GUARD}")
    lines.append(f"#define {HEADER_GUARD}")
    lines.append("")
    lines.append('#include "rac/core/rac_types.h"  // RAC_TRUE / RAC_FALSE')
    lines.append("")

    total = 0
    for file_name, msg_name, entries in groups:
        width = max(len(m) for m, _, _ in entries)
        lines.append(f"// {msg_name} ({file_name})")
        for macro, literal, field_name in entries:
            lines.append(f"#define {macro.ljust(width)} {literal}")
            total += 1
        lines.append("")

    lines.append(f"// {total} defaults across {len(groups)} messages.")
    lines.append(f"#endif  // {HEADER_GUARD}")
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

    groups = collect(fds)
    if not groups:
        print("error: no rac_default annotations found; refusing to write an empty header", file=sys.stderr)
        return 1

    out_path = repo_root / OUT_RELPATH
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render(groups), encoding="utf-8")

    count = sum(len(e) for _, _, e in groups)
    print(f"✓ C defaults header → {out_path} ({count} macros, {len(groups)} messages)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
