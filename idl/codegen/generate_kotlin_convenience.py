#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Kotlin convenience-accessor post-processor.
#
# T3.3-kotlin-impl: read RunAnywhere's custom proto annotations from
# idl/rac_options.proto and emit Kotlin extension declarations on the
# Wire-generated `ai.runanywhere.proto.v1` types so the SDK can drop the
# hand-written `wireString` / `fromWireString` / `defaults()` /
# `validate()` scaffolding currently scattered across `RAAudioFormatExtensions.kt`,
# `SDKEnvironment.kt`, etc.
#
# Output:
#   sdk/runanywhere-kotlin/src/main/kotlin/
#     com/runanywhere/sdk/generated/convenience/RAConvenience.kt
#
# Single-file output mirrors the Swift `RAConvenience.swift` shape so the
# `idl-drift-check` gate can diff exactly one Kotlin file per regen, and so
# the file lives outside the Wire-owned `ai/runanywhere/proto/v1/` subtree
# (which `generate_kotlin.sh` strips on every regen).
#
# Annotations consumed:
#   EnumValueOptions:
#     rac_display_name  (50010, string) -> val <Enum>.displayName: String
#     rac_analytics_key (50011, string) -> val <Enum>.analyticsKey: String
#     rac_wire_string   (50012, string) -> val <Enum>.wireString: String
#                                          + fun <Enum>.Companion.fromWireString(...)
#   FieldOptions:
#     rac_default       (50001, string) -> fun <Msg>.Companion.defaults(): <Msg>
#     rac_required      (50002, bool)   -> fun <Msg>.validate()
#     rac_min           (50004, int32)  -> fun <Msg>.validate()
#     rac_max           (50005, int32)  -> fun <Msg>.validate()
#     rac_min_float     (50006, double) -> fun <Msg>.validate()
#     rac_max_float     (50007, double) -> fun <Msg>.validate()
#
# Naming choices follow CONVENIENCE_CODEGEN_DESIGN.md §1.4. Field names
# in `defaults()` and `validate()` use the proto snake_case verbatim — Wire
# uses snake_case for both constructor parameters and `val` properties, the
# inverse of swift-protobuf's camelCase rule. The descriptor walk therefore
# bypasses `proto_field_to_camel` for Kotlin emission.
#
# Tolerant: exits 0 (warning to stderr) when `protoc` is missing or no
# .proto files are found, matching `generate_swift_convenience.py`.

from __future__ import annotations

import sys
from pathlib import Path

from google.protobuf import descriptor_pb2

from _convenience_common import (
    INTEGER_TYPES,
    FLOAT_TYPES,
    KOTLIN_PROFILE,
    RAC_ANALYTICS_KEY_FIELD_NUM,
    RAC_DEFAULT_FIELD_NUM,
    RAC_DISPLAY_NAME_FIELD_NUM,
    RAC_MAX_FIELD_NUM,
    RAC_MAX_FLOAT_FIELD_NUM,
    RAC_MIN_FIELD_NUM,
    RAC_MIN_FLOAT_FIELD_NUM,
    RAC_REQUIRED_FIELD_NUM,
    RAC_WIRE_STRING_FIELD_NUM,
    TYPE_STRING,
    annotation_name,
    build_enum_case_map,
    get_bool_option,
    get_double_option,
    get_int32_option,
    get_string_option,
    iter_runanywhere_files,
    iter_top_level_enums,
    iter_top_level_messages,
    load_file_descriptor_set,
    to_default_literal,
    zero_literal_for_required,
)

# ---------------------------------------------------------------------------
# Output target & static configuration.
# ---------------------------------------------------------------------------

KOTLIN_OUT_PACKAGE = "com.runanywhere.sdk.generated.convenience"
WIRE_PROTO_PACKAGE = "ai.runanywhere.proto.v1"
SDKEXCEPTION_FQN   = "com.runanywhere.sdk.foundation.errors.SDKException"


# ---------------------------------------------------------------------------
# Kotlin string-literal escaping. Kotlin string templates interpret `$`
# followed by an identifier or `{` as interpolation, so any literal `$`
# in an annotation value MUST be escaped. We also escape `\` and `"`.
# ---------------------------------------------------------------------------

def _escape_kotlin_string(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
         .replace("\"", "\\\"")
         .replace("$", "\\$")
    )


# ---------------------------------------------------------------------------
# Per-emitter helpers. Each returns either a string block to append to the
# output, or `None` when the input has no relevant annotations and the
# block should be skipped entirely.
# ---------------------------------------------------------------------------

def _emit_enum_accessor(
    proto_enum_name: str,
    enum_desc: descriptor_pb2.EnumDescriptorProto,
    accessor_name: str,
    field_num: int,
) -> str | None:
    """Emit `val <Enum>.<accessor>: String` as a switch over the proto
    SCREAMING_SNAKE constants. Always emits an `else -> ""` fall-through to
    mirror Swift's `default: return ""` safety net — Wire enums include an
    `UNRECOGNIZED` member that is structurally distinct from the declared
    cases, so `when` without an `else` would fail to compile as an
    expression even when every declared value carries the annotation.
    (pass3-syn-038)"""
    cases: list[tuple[str, str]] = []
    for value in enum_desc.value:
        if not value.HasField("options"):
            continue
        opt_str = get_string_option(value.options, field_num)
        if opt_str is None:
            continue
        cases.append((value.name, _escape_kotlin_string(opt_str)))
    if not cases:
        return None

    lines: list[str] = []
    lines.append(f"/** Generated from `(runanywhere.v1.{annotation_name(field_num)})` annotations in idl/. */")
    lines.append(f"public val {proto_enum_name}.{accessor_name}: String")
    lines.append("    get() = when (this) {")
    for case_name, value in cases:
        lines.append(f"        {proto_enum_name}.{case_name} -> \"{value}\"")
    lines.append("        else -> \"\"")
    lines.append("    }")
    return "\n".join(lines)


def _emit_enum_reverse_factory(
    proto_enum_name: str,
    enum_desc: descriptor_pb2.EnumDescriptorProto,
    field_num: int,
) -> str | None:
    """Emit `fun <Enum>.Companion.fromWireString(value: String): <Enum>?`.
    Wire generates a `companion object` on every enum (verified at
    `AudioFormat.kt:58`), so the extension binds without consumer-side
    boilerplate. Match is case-insensitive against the annotation value
    to preserve the pre-IDL hand-written `fromWireString` behaviour."""
    cases: list[tuple[str, str]] = []
    for value in enum_desc.value:
        if not value.HasField("options"):
            continue
        opt_str = get_string_option(value.options, field_num)
        if opt_str is None:
            continue
        safe = _escape_kotlin_string(opt_str.lower())
        cases.append((value.name, safe))
    if not cases:
        return None

    lines: list[str] = []
    lines.append(f"/** Generated reverse of the `{annotation_name(field_num)}` accessor. Case-insensitive. */")
    lines.append(
        f"public fun {proto_enum_name}.Companion.fromWireString(value: String): {proto_enum_name}? ="
    )
    lines.append("    when (value.lowercase()) {")
    for case_name, value in cases:
        lines.append(f"        \"{value}\" -> {proto_enum_name}.{case_name}")
    lines.append("        else -> null")
    lines.append("    }")
    return "\n".join(lines)


def _emit_message_defaults_factory(
    proto_msg_name: str,
    msg_desc: descriptor_pb2.DescriptorProto,
    enum_case_map: dict[str, str],
) -> str | None:
    """Emit `fun <Msg>.Companion.defaults(): <Msg>` invoking the Wire-
    generated primary constructor with named snake_case arguments for
    every annotated field. Unannotated fields keep their proto3-default
    values. Returns None when no fields carry `rac_default`."""
    assignments: list[tuple[str, str]] = []
    for field in msg_desc.field:
        if not field.HasField("options"):
            continue
        default_str = get_string_option(field.options, RAC_DEFAULT_FIELD_NUM)
        if default_str is None:
            continue
        literal = to_default_literal(field, default_str, enum_case_map, KOTLIN_PROFILE)
        if literal is None:
            continue
        # Wire uses proto snake_case verbatim for the constructor arg name.
        assignments.append((field.name, literal))

    if not assignments:
        return None

    lines: list[str] = []
    lines.append(f"/** Generated from `(runanywhere.v1.rac_default)` annotations in idl/. */")
    lines.append(f"public fun {proto_msg_name}.Companion.defaults(): {proto_msg_name} =")
    lines.append(f"    {proto_msg_name}(")
    for field_name, literal in assignments:
        lines.append(f"        {field_name} = {literal},")
    lines.append("    )")
    return "\n".join(lines)


def _emit_message_validate(
    proto_msg_name: str,
    msg_desc: descriptor_pb2.DescriptorProto,
) -> str | None:
    """Emit `fun <Msg>.validate()` issuing range / required-field checks
    and throwing `SDKException.validationFailed(...)` on first failure.
    Returns None when no relevant annotations are present."""
    checks: list[str] = []
    for field in msg_desc.field:
        if not field.HasField("options"):
            continue
        # Wire constructor args use snake_case verbatim — same name on the
        # extension receiver, so we reference the field by `field.name`.
        kt_field = field.name
        # Wire emits proto3 `optional` scalars as nullable Kotlin types, so a
        # bare relational comparison (`field < min`) is prohibited on the
        # nullable receiver. Range checks on such fields are guarded with a
        # non-null precondition: an unset optional field carries no value to
        # range-check (the canonical default applies elsewhere).
        is_optional = field.proto3_optional

        def _throw(message_literal: str) -> list[str]:
            """Canonical `{ code, category, fieldPath, message }` shape via
            the `SDKException.validationFailed(fieldPath, message)`
            factory. Threads `field_path` into `error.context.metadata`."""
            field_path = f"{proto_msg_name}.{field.name}"
            return [
                "        throw SDKException.validationFailed(",
                f"            fieldPath = \"{field_path}\",",
                f"            message = {message_literal},",
                "        )",
            ]

        is_required = get_bool_option(field.options, RAC_REQUIRED_FIELD_NUM)
        if is_required:
            t = field.type
            if t == TYPE_STRING:
                # A nullable (optional) required string is missing when null OR
                # empty; `?.isEmpty() != false` captures both without an
                # operator call on a null receiver.
                empty_check = (
                    f"{kt_field}?.isEmpty() != false" if is_optional
                    else f"{kt_field}.isEmpty()"
                )
                checks.append(f"    if ({empty_check}) {{")
                checks.extend(_throw(f"\"{field.name} is required\""))
                checks.append("    }")
            elif t in INTEGER_TYPES or t in FLOAT_TYPES:
                # pass3-syn-038: Kotlin's `Long == Int` / `Float == Int` are
                # structurally false (different concrete types) — comparing a
                # Long field against the bare `0` literal silently neuters
                # the required-check for proto3 zero. Emit the type-correct
                # literal via _convenience_common.zero_literal_for_required:
                # INT64 -> `0L`, INT32 -> `0`, FLOAT -> `0.0f`,
                # DOUBLE -> `0.0`.
                zero = zero_literal_for_required(field, KOTLIN_PROFILE) or "0"
                checks.append(f"    if ({kt_field} == {zero}) {{")
                checks.extend(_throw(f"\"{field.name} is required\""))
                checks.append("    }")

        min_int = get_int32_option(field.options, RAC_MIN_FIELD_NUM)
        max_int = get_int32_option(field.options, RAC_MAX_FIELD_NUM)
        if (min_int is not None or max_int is not None) and field.type in INTEGER_TYPES:
            parts: list[str] = []
            if min_int is not None:
                parts.append(f"{kt_field} < {min_int}")
            if max_int is not None:
                parts.append(f"{kt_field} > {max_int}")
            cond = " || ".join(parts)
            if is_optional:
                cond = f"{kt_field} != null && ({cond})"
            if min_int is not None and max_int is not None:
                range_desc = f"{min_int}...{max_int}"
            elif min_int is not None:
                range_desc = f">= {min_int}"
            else:
                range_desc = f"<= {max_int}"
            checks.append(f"    if ({cond}) {{")
            checks.extend(_throw(
                f"\"{field.name} must be in {range_desc} (got ${{{kt_field}}})\""
            ))
            checks.append("    }")

        min_f = get_double_option(field.options, RAC_MIN_FLOAT_FIELD_NUM)
        max_f = get_double_option(field.options, RAC_MAX_FLOAT_FIELD_NUM)
        if (min_f is not None or max_f is not None) and field.type in FLOAT_TYPES:
            parts = []
            if min_f is not None:
                parts.append(f"{kt_field} < {min_f}")
            if max_f is not None:
                parts.append(f"{kt_field} > {max_f}")
            cond = " || ".join(parts)
            if is_optional:
                cond = f"{kt_field} != null && ({cond})"
            if min_f is not None and max_f is not None:
                range_desc = f"{min_f}...{max_f}"
            elif min_f is not None:
                range_desc = f">= {min_f}"
            else:
                range_desc = f"<= {max_f}"
            checks.append(f"    if ({cond}) {{")
            checks.extend(_throw(
                f"\"{field.name} must be in {range_desc} (got ${{{kt_field}}})\""
            ))
            checks.append("    }")

    if not checks:
        return None

    lines: list[str] = []
    lines.append(
        "/** Generated from `(runanywhere.v1.rac_required / rac_min / rac_max / rac_min_float / rac_max_float)` annotations in idl/. */"
    )
    lines.append(f"public fun {proto_msg_name}.validate() {{")
    lines.extend(checks)
    lines.append("}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Top-level driver.
# ---------------------------------------------------------------------------

def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root  = script_dir.parent.parent
    proto_dir  = repo_root / "idl"
    out_dir = (
        repo_root
        / "sdk" / "runanywhere-kotlin" / "src" / "main" / "kotlin"
        / "com" / "runanywhere" / "sdk" / "generated" / "convenience"
    )
    out_path = out_dir / "RAConvenience.kt"

    out_dir.mkdir(parents=True, exist_ok=True)

    fds = load_file_descriptor_set(proto_dir)
    if fds is None:
        print(f"warning: no .proto files in {proto_dir}", file=sys.stderr)
        return 0

    enum_case_map = build_enum_case_map(fds, "kotlin")

    blocks: list[str] = []
    referenced_types: set[str] = set()
    annotated_enum_count = 0
    annotated_message_defaults_count = 0
    annotated_message_validate_count = 0

    for file_desc in iter_runanywhere_files(fds):
        for proto_enum_name, enum_desc in iter_top_level_enums(file_desc):
            enum_emitted = False
            for accessor_name, field_num in (
                ("displayName",   RAC_DISPLAY_NAME_FIELD_NUM),
                ("analyticsKey",  RAC_ANALYTICS_KEY_FIELD_NUM),
                ("wireString",    RAC_WIRE_STRING_FIELD_NUM),
            ):
                block = _emit_enum_accessor(proto_enum_name, enum_desc, accessor_name, field_num)
                if block is not None:
                    blocks.append(block)
                    enum_emitted = True
                    annotated_enum_count += 1

            reverse_block = _emit_enum_reverse_factory(
                proto_enum_name, enum_desc, RAC_WIRE_STRING_FIELD_NUM,
            )
            if reverse_block is not None:
                blocks.append(reverse_block)
                enum_emitted = True

            if enum_emitted:
                referenced_types.add(proto_enum_name)

        for proto_msg_name, msg_desc in iter_top_level_messages(file_desc):
            msg_emitted = False

            defaults_block = _emit_message_defaults_factory(
                proto_msg_name, msg_desc, enum_case_map,
            )
            if defaults_block is not None:
                blocks.append(defaults_block)
                annotated_message_defaults_count += 1
                msg_emitted = True

                # Track enum types referenced as `rac_default` literals so
                # we can import them alongside the message type itself.
                for field in msg_desc.field:
                    if not field.HasField("options"):
                        continue
                    if get_string_option(field.options, RAC_DEFAULT_FIELD_NUM) is None:
                        continue
                    if field.type_name and field.type == 14:  # TYPE_ENUM
                        referenced_types.add(field.type_name.split(".")[-1])

            validate_block = _emit_message_validate(proto_msg_name, msg_desc)
            if validate_block is not None:
                blocks.append(validate_block)
                annotated_message_validate_count += 1
                msg_emitted = True

            if msg_emitted:
                referenced_types.add(proto_msg_name)

    # Build the import list. Always include SDKException when at least one
    # validate() block was emitted; otherwise it would be an unused import
    # which Kotlin's compiler warnings flag.
    import_lines: list[str] = []
    for type_name in sorted(referenced_types):
        import_lines.append(f"import {WIRE_PROTO_PACKAGE}.{type_name}")
    if annotated_message_validate_count > 0:
        import_lines.append(f"import {SDKEXCEPTION_FQN}")

    header = [
        "// DO NOT EDIT.",
        "//",
        "// Generated by idl/codegen/generate_kotlin_convenience.py.",
        "//",
        "// This file exposes hand-friendly convenience accessors derived from",
        "// RunAnywhere's custom proto annotations (see idl/rac_options.proto):",
        "//   - .displayName              (rac_display_name)",
        "//   - .analyticsKey             (rac_analytics_key)",
        "//   - .wireString               (rac_wire_string)",
        "//   - .Companion.fromWireString (reverse of rac_wire_string)",
        "//   - .Companion.defaults()     (rac_default)",
        "//   - .validate()               (rac_required / rac_min / rac_max /",
        "//                                rac_min_float / rac_max_float)",
        "",
        "@file:Suppress(\"FunctionName\", \"VariableNaming\", \"MaximumLineLength\", \"MagicNumber\")",
        "",
        f"package {KOTLIN_OUT_PACKAGE}",
        "",
    ]

    if import_lines:
        header.extend(import_lines)
        header.append("")
        header.append("")

    if blocks:
        body_text = "\n\n".join(blocks)
    else:
        body_text = (
            "// (Currently empty: no proto in idl/ has adopted rac_display_name /\n"
            "// rac_analytics_key / rac_wire_string / rac_default / rac_required /\n"
            "// rac_min / rac_max / rac_min_float / rac_max_float annotations yet.)"
        )

    content = "\n".join(header) + body_text + "\n"
    out_path.write_text(content, encoding="utf-8")

    print(f"✓ Kotlin convenience post-processor → {out_path}")
    print(f"  annotated enum-accessor blocks emitted: {annotated_enum_count}")
    print(f"  message defaults() factories emitted: {annotated_message_defaults_count}")
    print(f"  message validate() helpers emitted: {annotated_message_validate_count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
