#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Per-language constants for the central default pool (idl/sdk_defaults.proto).
#
# Why this is one generator and not four:
#
# CONVENIENCE_CODEGEN_DESIGN.md §0.3 argues for separate per-language
# post-processors because `defaults()`, `validate()`, and the enum accessors
# each need genuinely different idiom — extensions on a companion object in
# Kotlin, top-level functions in Dart, namespaced exports in TypeScript. That
# reasoning holds for those emitters. It does not hold here. The pool is a flat
# table of scalar constants, and the only per-language variation is the literal
# suffix and how you spell "constant". Splitting that four ways would
# quadruplicate a descriptor walk to gain nothing.
#
# Why the pool has no generated message types:
#
# Nothing sends a NetworkDefaults over a wire; the messages exist to carry
# `rac_default` annotations. Generating six message classes in five languages to
# transport 24 integers would be bloat, and it would make every call site read
# `RANetworkDefaults.defaults().requestTimeoutMs` where a constant is clearer.
# So sdk_defaults.proto is listed in DECLARATION_ONLY_FILES and excluded from
# the message generators; this emits plain constants instead.
#
# Outputs:
#   sdk/runanywhere-swift/Sources/RunAnywhere/Generated/RADefaultsPool.swift
#   sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/RADefaultsPool.kt
#   sdk/runanywhere-flutter/packages/runanywhere/lib/generated/ra_defaults_pool.dart
#   sdk/shared/proto-ts/src/defaults/pool.ts
#
# The C header comes from generate_cpp_defaults.py, which covers every
# rac_default in idl/ rather than just the pool.

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

from google.protobuf import descriptor_pb2

from _convenience_common import (
    DECLARATION_ONLY_FILES,
    RAC_DEFAULT_FIELD_NUM,
    TYPE_BOOL,
    TYPE_ENUM,
    TYPE_FLOAT,
    TYPE_STRING,
    FLOAT_TYPES,
    INT64_TYPES,
    LangProfile,
    get_string_option,
    iter_runanywhere_files,
    iter_top_level_messages,
    load_file_descriptor_set,
    proto_field_to_camel,
    to_default_literal,
)

POOL_FILE = "sdk_defaults.proto"


@dataclass(frozen=True)
class Target:
    """One emitted file: where it goes and how the language spells things."""

    rel_path: str
    profile: LangProfile
    comment: str = "//"


SWIFT = Target(
    rel_path="sdk/runanywhere-swift/Sources/RunAnywhere/Generated/RADefaultsPool.swift",
    profile=LangProfile(int64_wrapper=None, int64_suffix="", float_suffix=""),
)
KOTLIN_PROFILE = LangProfile(int64_wrapper=None, int64_suffix="L", float_suffix="f")

KOTLIN = Target(
    rel_path="sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/RADefaultsPool.kt",
    profile=KOTLIN_PROFILE,
)

# The Flutter and React Native Android plugins each carry their own fork of
# OkHttpHttpTransport.kt and depend on neither the Kotlin SDK nor each other, so
# `com.runanywhere.sdk.generated.RADefaults` is not on their classpath. Emitting a
# copy into each module's own source set keeps all three transports reading the
# same proto declaration without adding a Gradle dependency between them.
# De-forking the transports themselves is separate work; until then this is what
# stops the three copies drifting (they had already reached 256 KB vs 32 KB
# stream chunks and 60s vs 120s read timeouts).
KOTLIN_ANDROID_FORKS = (
    Target(
        rel_path=(
            "sdk/runanywhere-flutter/packages/runanywhere/android/src/main/kotlin/"
            "com/runanywhere/sdk/generated/RADefaultsPool.kt"
        ),
        profile=KOTLIN_PROFILE,
    ),
    Target(
        rel_path=(
            "sdk/runanywhere-react-native/packages/core/android/src/main/java/"
            "com/runanywhere/sdk/generated/RADefaultsPool.kt"
        ),
        profile=KOTLIN_PROFILE,
    ),
)
DART = Target(
    rel_path="sdk/runanywhere-flutter/packages/runanywhere/lib/generated/ra_defaults_pool.dart",
    profile=LangProfile(int64_wrapper=None, int64_suffix="", float_suffix=""),
)
TS = Target(
    rel_path="sdk/shared/proto-ts/src/defaults/pool.ts",
    profile=LangProfile(int64_wrapper=None, int64_suffix="", float_suffix=""),
)
# Python consumes the flat C ABI for everything but RAG and has no convenience
# post-processor, but it still has pooled values of its own (the STT capture rate
# in the HTTP server, for one), so it gets the constants like everyone else.
PYTHON = Target(
    rel_path="sdk/runanywhere-python/runanywhere/_generated_defaults.py",
    profile=LangProfile(int64_wrapper=None, int64_suffix="", float_suffix=""),
)


def strip_defaults_suffix(message_name: str) -> str:
    return message_name[: -len("Defaults")] if message_name.endswith("Defaults") else message_name


def collect(fds: descriptor_pb2.FileDescriptorSet) -> list[tuple[str, list[tuple[str, descriptor_pb2.FieldDescriptorProto, str]]]]:
    """Return [(group_name, [(field_name, field_desc, default_string)])]."""
    groups: list[tuple[str, list[tuple[str, descriptor_pb2.FieldDescriptorProto, str]]]] = []
    for file_desc in iter_runanywhere_files(fds, include_declaration_only=True):
        if file_desc.name != POOL_FILE:
            continue
        for msg_name, msg_desc in iter_top_level_messages(file_desc):
            fields: list[tuple[str, descriptor_pb2.FieldDescriptorProto, str]] = []
            for field in msg_desc.field:
                if not field.HasField("options"):
                    continue
                default_str = get_string_option(field.options, RAC_DEFAULT_FIELD_NUM)
                if default_str is None:
                    print(
                        f"note: {msg_name}.{field.name} has no rac_default; "
                        f"a pool field without a default is almost certainly a mistake",
                        file=sys.stderr,
                    )
                    continue
                if field.type == TYPE_ENUM:
                    print(
                        f"note: skipping enum field {msg_name}.{field.name}; "
                        f"the pool emitter handles scalars and strings only",
                        file=sys.stderr,
                    )
                    continue
                fields.append((field.name, field, default_str))
            if fields:
                groups.append((strip_defaults_suffix(msg_name), fields))
    return groups


def _banner(lines: list[str], regen: str) -> None:
    lines.append("// GENERATED FILE — DO NOT EDIT.")
    lines.append(f"// Regenerate with: {regen}")
    lines.append("//")
    lines.append("// Values come from `(runanywhere.v1.rac_default)` annotations in")
    lines.append(f"// idl/{POOL_FILE}. That file is the single declaration of every default")
    lines.append("// here; the C header and the other three SDK languages are generated from")
    lines.append("// the same annotations, so editing this copy only desynchronizes one SDK.")
    lines.append("")


REGEN = "idl/codegen/generate_defaults_pool.py"


def render_swift(groups) -> str:
    lines: list[str] = ["// SPDX-License-Identifier: Apache-2.0", "//"]
    _banner(lines, REGEN)
    lines.append("/// Central default pool. Read these instead of retyping a literal.")
    lines.append("public enum RADefaults {")
    for i, (group, fields) in enumerate(groups):
        if i:
            lines.append("")
        lines.append(f"    public enum {group} {{")
        for field_name, field, default_str in fields:
            literal = to_default_literal(field, default_str, {}, SWIFT.profile)
            name = proto_field_to_camel(field_name, id_uppercase=True)
            # Annotate the type rather than letting Swift infer it: a bare 2.0
            # infers Double, and the sampling fields it feeds are Float on the
            # C ABI. Inference would push a conversion onto every call site.
            lines.append(f"        public static let {name}: {swift_type(field)} = {literal}")
        lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def render_kotlin(groups) -> str:
    lines: list[str] = ["// SPDX-License-Identifier: Apache-2.0", "//"]
    _banner(lines, REGEN)
    lines.append("package com.runanywhere.sdk.generated")
    lines.append("")
    lines.append("/** Central default pool. Read these instead of retyping a literal. */")
    lines.append("public object RADefaults {")
    for i, (group, fields) in enumerate(groups):
        if i:
            lines.append("")
        lines.append(f"    public object {group} {{")
        for field_name, field, default_str in fields:
            literal = to_default_literal(field, default_str, {}, KOTLIN.profile)
            lines.append(f"        public const val {field_name.upper()}: {kotlin_type(field)} = {literal}")
        lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def ts_type(field: descriptor_pb2.FieldDescriptorProto) -> str:
    if field.type == TYPE_STRING:
        return "string"
    if field.type == TYPE_BOOL:
        return "boolean"
    return "number"


def swift_type(field: descriptor_pb2.FieldDescriptorProto) -> str:
    if field.type == TYPE_STRING:
        return "String"
    if field.type == TYPE_BOOL:
        return "Bool"
    if field.type in FLOAT_TYPES:
        return "Float" if field.type == TYPE_FLOAT else "Double"
    if field.type in INT64_TYPES:
        return "Int64"
    return "Int"


def kotlin_type(field: descriptor_pb2.FieldDescriptorProto) -> str:
    if field.type == TYPE_STRING:
        return "String"
    if field.type == TYPE_BOOL:
        return "Boolean"
    if field.type in FLOAT_TYPES:
        return "Float" if field.type == TYPE_FLOAT else "Double"
    if field.type in INT64_TYPES:
        return "Long"
    return "Int"


def render_dart(groups) -> str:
    lines: list[str] = ["// SPDX-License-Identifier: Apache-2.0", "//"]
    _banner(lines, REGEN)
    lines.append("/// Central default pool. Read these instead of retyping a literal.")
    lines.append("library;")
    lines.append("")
    for i, (group, fields) in enumerate(groups):
        if i:
            lines.append("")
        lines.append(f"abstract final class RADefaults{group} {{")
        for field_name, field, default_str in fields:
            literal = to_default_literal(field, default_str, {}, DART.profile)
            name = proto_field_to_camel(field_name)
            lines.append(f"  static const {dart_type(field)} {name} = {literal};")
        lines.append("}")
    lines.append("")
    return "\n".join(lines)


def dart_type(field: descriptor_pb2.FieldDescriptorProto) -> str:
    if field.type == TYPE_STRING:
        return "String"
    if field.type == TYPE_BOOL:
        return "bool"
    if field.type in FLOAT_TYPES:
        return "double"
    return "int"


def render_ts(groups) -> str:
    lines: list[str] = ["// SPDX-License-Identifier: Apache-2.0", "//"]
    _banner(lines, REGEN)
    lines.append("/** Central default pool. Read these instead of retyping a literal. */")
    for i, (group, fields) in enumerate(groups):
        lines.append("")
        first = group[0].lower() + group[1:]
        # Object.freeze rather than `as const`: freeze gives runtime immutability
        # while leaving the property types widened to number/string/boolean. With
        # `as const` every value takes a literal type, so `const x =
        # pool.speechRmsThreshold` infers `0.015` and any later assignment to `x`
        # fails to typecheck. Matches the existing LLM_GENERATION_DEFAULTS shape
        # in the Web SDK.
        lines.append(f"export const {first}Defaults = Object.freeze({{")
        for field_name, field, default_str in fields:
            literal = to_default_literal(field, default_str, {}, TS.profile)
            name = proto_field_to_camel(field_name)
            lines.append(f"  {name}: {literal} as {ts_type(field)},")
        lines.append("});")
    lines.append("")
    return "\n".join(lines)


def render_python(groups) -> str:
    lines: list[str] = []
    # One-line docstring then `from __future__ import annotations`, per the
    # Python SDK's module convention; the detail goes in comments below it.
    lines.append('"""Central default pool generated from idl/sdk_defaults.proto."""')
    lines.append("")
    lines.append("from __future__ import annotations")
    lines.append("")
    lines.append("# GENERATED FILE - DO NOT EDIT.")
    lines.append(f"# Regenerate with: {REGEN}")
    lines.append("#")
    lines.append("# Values come from `(runanywhere.v1.rac_default)` annotations. Change the")
    lines.append(f"# value in idl/{POOL_FILE}, not here.")
    lines.append("")
    lines.append("from typing import Final")
    for group, fields in groups:
        lines.append("")
        lines.append("")
        lines.append(f"class {group}Defaults:")
        lines.append(f'    """Generated from {group}Defaults in idl/{POOL_FILE}."""')
        lines.append("")
        for field_name, field, default_str in fields:
            literal = to_default_literal(field, default_str, {}, PYTHON.profile)
            if field.type == TYPE_BOOL:
                literal = "True" if literal == "true" else "False"
            lines.append(f"    {field_name.upper()}: Final[{python_type(field)}] = {literal}")
    names = ", ".join(f'"{g}Defaults"' for g, _ in groups)
    lines.append("")
    lines.append("")
    lines.append(f"__all__ = [{names}]")
    lines.append("")
    return "\n".join(lines)


def python_type(field: descriptor_pb2.FieldDescriptorProto) -> str:
    if field.type == TYPE_STRING:
        return "str"
    if field.type == TYPE_BOOL:
        return "bool"
    if field.type in FLOAT_TYPES:
        return "float"
    return "int"


RENDERERS = (
    (SWIFT, render_swift),
    (KOTLIN, render_kotlin),
    *((t, render_kotlin) for t in KOTLIN_ANDROID_FORKS),
    (DART, render_dart),
    (TS, render_ts),
    (PYTHON, render_python),
)


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    idl_dir = script_dir.parent
    repo_root = idl_dir.parent

    if POOL_FILE not in DECLARATION_ONLY_FILES:
        print(
            f"error: {POOL_FILE} is not in DECLARATION_ONLY_FILES, so the message "
            f"generators will emit types for it and these constants would duplicate them",
            file=sys.stderr,
        )
        return 1

    fds = load_file_descriptor_set(idl_dir)
    if fds is None:
        print("error: no .proto files found in idl/", file=sys.stderr)
        return 1

    groups = collect(fds)
    if not groups:
        print(f"error: no annotated messages found in {POOL_FILE}", file=sys.stderr)
        return 1

    for target, render in RENDERERS:
        out_path = repo_root / target.rel_path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(render(groups), encoding="utf-8")
        print(f"✓ {out_path.relative_to(repo_root)}")

    total = sum(len(f) for _, f in groups)
    print(f"✓ default pool → {total} constants in {len(groups)} groups, {len(RENDERERS)} targets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
