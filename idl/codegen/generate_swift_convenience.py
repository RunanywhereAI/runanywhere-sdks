#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Swift convenience-accessor post-processor.
#
# Phase 4 / P4-T2 of the Swift simplification plan: read RunAnywhere's
# custom proto annotations from idl/rac_options.proto (defined in P4-T1) and
# emit Swift extension methods on the RA*-prefixed types so SDKs can drop the
# hand-written displayName / analyticsKey / wireString / defaults() / validate()
# scaffolding that currently lives in per-modality *Configuration+Helpers.swift
# files.
#
# Annotations consumed (see idl/rac_options.proto for full reference):
#   EnumValueOptions:
#     rac_display_name  (50010, string) -> emits  var displayName: String
#     rac_analytics_key (50011, string) -> emits  var analyticsKey: String
#     rac_wire_string   (50012, string) -> emits  var wireString: String
#                                                 + static func from(wireString:)
#   FieldOptions:
#     rac_default       (50001, string) -> participates in defaults()
#     rac_required      (50002, bool)   -> participates in validate()
#     rac_min           (50004, int32)  -> participates in validate()
#     rac_max           (50005, int32)  -> participates in validate()
#     rac_min_float     (50006, double) -> participates in validate()
#     rac_max_float     (50007, double) -> participates in validate()
#
# Output:
#   sdk/runanywhere-swift/Sources/RunAnywhere/Generated/RAConvenience.swift
#
# Descriptor parsing, wire-format readers, naming utilities, and the
# default-literal translator are factored into `_convenience_common.py`
# (T3.3) so this generator is a pure Swift output formatter — every
# Kotlin / Dart / TypeScript convenience generator consumes the same
# helpers.
#
# Invoked by generate_swift.sh AFTER swift-protobuf has produced the *.pb.swift
# files, so the RA* type names are already known to exist in the same module.

from __future__ import annotations

import sys
from pathlib import Path

from google.protobuf import descriptor_pb2

from _convenience_common import (
    INTEGER_TYPES,
    FLOAT_TYPES,
    RAC_ANALYTICS_KEY_FIELD_NUM,
    RAC_DEFAULT_FIELD_NUM,
    RAC_DISPLAY_NAME_FIELD_NUM,
    RAC_MAX_FIELD_NUM,
    RAC_MAX_FLOAT_FIELD_NUM,
    RAC_MIN_FIELD_NUM,
    RAC_MIN_FLOAT_FIELD_NUM,
    RAC_REQUIRED_FIELD_NUM,
    RAC_WIRE_STRING_FIELD_NUM,
    SWIFT_PROFILE,
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
    proto_field_to_camel,
    swift_enum_case,
    to_default_literal,
)

SWIFT_PREFIX = "RA"


# --- Enum-level emitters. --------------------------------------------------

def _emit_enum_accessor(
    proto_enum_name: str,
    enum_desc: descriptor_pb2.EnumDescriptorProto,
    accessor_name: str,
    field_num: int,
) -> str | None:
    """Emit a Swift `var <accessor_name>: String` on RA<EnumName> if at
    least one enum value carries the given annotation. Returns None when
    no values are annotated (so the caller can skip the whole extension)."""
    cases: list[tuple[str, str]] = []
    for value in enum_desc.value:
        if not value.HasField("options"):
            continue
        opt_str = get_string_option(value.options, field_num)
        if opt_str is None:
            continue
        case_name = swift_enum_case(proto_enum_name, value.name)
        safe = opt_str.replace("\\", "\\\\").replace("\"", "\\\"")
        cases.append((case_name, safe))
    if not cases:
        return None

    swift_type = f"{SWIFT_PREFIX}{proto_enum_name}"
    lines: list[str] = []
    lines.append(f"extension {swift_type} {{")
    lines.append(f"    /// Generated from `(runanywhere.v1.{annotation_name(field_num)})` annotations in idl/.")
    lines.append(f"    public var {accessor_name}: String {{")
    lines.append("        switch self {")
    for case_name, value in cases:
        lines.append(f"        case .{case_name}: return \"{value}\"")
    lines.append("        default: return \"\"")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    return "\n".join(lines)


def _emit_enum_reverse_factory(
    proto_enum_name: str,
    enum_desc: descriptor_pb2.EnumDescriptorProto,
    factory_name: str,
    parameter_label: str,
    field_num: int,
) -> str | None:
    """Emit `static func <factory_name>(<parameter_label>:)` on RA<EnumName>
    that reverses the wire-string annotation lookup. Static factory rather
    than `init?` to avoid colliding with swift-protobuf's auto-generated
    `init?(rawValue:)` / `init?(name:)` initializers. Match is
    case-insensitive against the annotation value to preserve the
    pre-IDL hand-written behavior. Returns None when no values are
    annotated."""
    cases: list[tuple[str, str]] = []
    for value in enum_desc.value:
        if not value.HasField("options"):
            continue
        opt_str = get_string_option(value.options, field_num)
        if opt_str is None:
            continue
        case_name = swift_enum_case(proto_enum_name, value.name)
        safe = opt_str.replace("\\", "\\\\").replace("\"", "\\\"").lower()
        cases.append((case_name, safe))
    if not cases:
        return None

    swift_type = f"{SWIFT_PREFIX}{proto_enum_name}"
    lines: list[str] = []
    lines.append(f"extension {swift_type} {{")
    lines.append(f"    /// Generated reverse of the `{annotation_name(field_num)}` accessor.")
    lines.append(f"    /// Matches case-insensitively against the annotation value.")
    lines.append(f"    public static func {factory_name}({parameter_label}: String) -> {swift_type}? {{")
    lines.append(f"        switch {parameter_label}.lowercased() {{")
    for case_name, value in cases:
        lines.append(f"        case \"{value}\": return .{case_name}")
    lines.append("        default: return nil")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    return "\n".join(lines)


# --- Message-level emitters. -----------------------------------------------

def _emit_message_defaults_factory(
    proto_msg_name: str,
    msg_desc: descriptor_pb2.DescriptorProto,
    enum_case_map: dict[str, str],
) -> str | None:
    """Emit `public static func defaults() -> RA<MessageName>` when at
    least one field carries `rac_default`. Returns None when the message
    has no relevant annotations."""
    assignments: list[tuple[str, str]] = []
    for field in msg_desc.field:
        if not field.HasField("options"):
            continue
        default_str = get_string_option(field.options, RAC_DEFAULT_FIELD_NUM)
        if default_str is None:
            continue
        literal = to_default_literal(field, default_str, enum_case_map, SWIFT_PROFILE)
        if literal is None:
            continue
        # swift-protobuf upper-cases trailing "Id" -> "ID" (e.g. modelID).
        swift_field = proto_field_to_camel(field.name, id_uppercase=True)
        assignments.append((swift_field, literal))

    if not assignments:
        return None

    swift_type = f"{SWIFT_PREFIX}{proto_msg_name}"
    lines: list[str] = []
    lines.append(f"extension {swift_type} {{")
    lines.append(f"    /// Generated from `(runanywhere.v1.rac_default)` annotations in idl/.")
    lines.append(f"    public static func defaults() -> {swift_type} {{")
    lines.append(f"        var r = {swift_type}()")
    for swift_field, literal in assignments:
        lines.append(f"        r.{swift_field} = {literal}")
    lines.append("        return r")
    lines.append("    }")
    lines.append("}")
    return "\n".join(lines)


def _emit_message_validate(
    proto_msg_name: str,
    msg_desc: descriptor_pb2.DescriptorProto,
) -> str | None:
    """Emit `public func validate() throws` when at least one field carries
    `rac_required`, `rac_min`, `rac_max`, `rac_min_float`, or
    `rac_max_float`. Returns None when no relevant annotations are
    present."""
    checks: list[str] = []
    for field in msg_desc.field:
        if not field.HasField("options"):
            continue
        swift_field = proto_field_to_camel(field.name, id_uppercase=True)

        def _throw(message_literal: str, indent: str = "            ") -> list[str]:
            """Canonical `{ code, category, fieldPath, message }` shape.
            Uses the `SDKException.validationFailed(fieldPath:message:)`
            factory which threads field_path through
            `proto.context.metadata["field_path"]`.

            `indent` is the leading whitespace for the `throw` keyword
            itself. Default is 12 spaces because every caller in this
            generator emits the helper INSIDE an `if`-block already
            opened at 8 spaces, so the throw body must be one
            indentation level deeper to render idiomatically."""
            field_path = f"{proto_msg_name}.{field.name}"
            return [
                f"{indent}throw SDKException.validationFailed(",
                f'{indent}    fieldPath: "{field_path}",',
                f"{indent}    message: {message_literal}",
                f"{indent})",
            ]

        is_required = get_bool_option(field.options, RAC_REQUIRED_FIELD_NUM)
        if is_required:
            t = field.type
            if t == TYPE_STRING:
                checks.append(f"        if {swift_field}.isEmpty {{")
                checks.extend(_throw(f'"{field.name} is required"'))
                checks.append(f"        }}")
            elif t in INTEGER_TYPES or t in FLOAT_TYPES:
                checks.append(f"        if {swift_field} == 0 {{")
                checks.extend(_throw(f'"{field.name} is required"'))
                checks.append(f"        }}")

        min_int = get_int32_option(field.options, RAC_MIN_FIELD_NUM)
        max_int = get_int32_option(field.options, RAC_MAX_FIELD_NUM)
        if (min_int is not None or max_int is not None) and field.type in INTEGER_TYPES:
            parts: list[str] = []
            if min_int is not None:
                parts.append(f"{swift_field} < {min_int}")
            if max_int is not None:
                parts.append(f"{swift_field} > {max_int}")
            cond = " || ".join(parts)
            if min_int is not None and max_int is not None:
                range_desc = f"{min_int}...{max_int}"
            elif min_int is not None:
                range_desc = f">= {min_int}"
            else:
                range_desc = f"<= {max_int}"
            checks.append(f"        if {cond} {{")
            checks.extend(_throw(
                f'"{field.name} must be in {range_desc} (got \\({swift_field}))"'
            ))
            checks.append(f"        }}")

        min_f = get_double_option(field.options, RAC_MIN_FLOAT_FIELD_NUM)
        max_f = get_double_option(field.options, RAC_MAX_FLOAT_FIELD_NUM)
        if (min_f is not None or max_f is not None) and field.type in FLOAT_TYPES:
            parts = []
            if min_f is not None:
                parts.append(f"{swift_field} < {min_f}")
            if max_f is not None:
                parts.append(f"{swift_field} > {max_f}")
            cond = " || ".join(parts)
            if min_f is not None and max_f is not None:
                range_desc = f"{min_f}...{max_f}"
            elif min_f is not None:
                range_desc = f">= {min_f}"
            else:
                range_desc = f"<= {max_f}"
            checks.append(f"        if {cond} {{")
            checks.extend(_throw(
                f'"{field.name} must be in {range_desc} (got \\({swift_field}))"'
            ))
            checks.append(f"        }}")

    if not checks:
        return None

    swift_type = f"{SWIFT_PREFIX}{proto_msg_name}"
    lines: list[str] = []
    lines.append(f"extension {swift_type} {{")
    lines.append(f"    /// Generated from `(runanywhere.v1.rac_required / rac_min / rac_max / rac_min_float / rac_max_float)` annotations in idl/.")
    lines.append(f"    public func validate() throws {{")
    lines.extend(checks)
    lines.append("    }")
    lines.append("}")
    return "\n".join(lines)


# --- Top-level driver. -----------------------------------------------------

def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root  = script_dir.parent.parent
    proto_dir  = repo_root / "idl"
    out_dir    = repo_root / "sdk" / "runanywhere-swift" / "Sources" / "RunAnywhere" / "Generated"
    out_path   = out_dir / "RAConvenience.swift"

    out_dir.mkdir(parents=True, exist_ok=True)

    fds = load_file_descriptor_set(proto_dir)
    if fds is None:
        print(f"warning: no .proto files in {proto_dir}", file=sys.stderr)
        return 0

    blocks: list[str] = []
    annotated_enum_count = 0
    annotated_message_defaults_count = 0
    annotated_message_validate_count = 0

    enum_case_map = build_enum_case_map(fds, "swift")

    for file_desc in iter_runanywhere_files(fds):
        for proto_enum_name, enum_desc in iter_top_level_enums(file_desc):
            for accessor_name, field_num in (
                ("displayName",   RAC_DISPLAY_NAME_FIELD_NUM),
                ("analyticsKey",  RAC_ANALYTICS_KEY_FIELD_NUM),
                ("wireString",    RAC_WIRE_STRING_FIELD_NUM),
            ):
                block = _emit_enum_accessor(proto_enum_name, enum_desc, accessor_name, field_num)
                if block is not None:
                    blocks.append(block)
                    annotated_enum_count += 1

            # Reverse factory for wireString (mirrors the hand-written
            # `fromWireString` switches that lived across SDKEnvironment.swift,
            # RAAudioFormat+Extensions.swift, ModelTypes.swift, ...).
            reverse_block = _emit_enum_reverse_factory(
                proto_enum_name,
                enum_desc,
                factory_name="from",
                parameter_label="wireString",
                field_num=RAC_WIRE_STRING_FIELD_NUM,
            )
            if reverse_block is not None:
                blocks.append(reverse_block)

        for proto_msg_name, msg_desc in iter_top_level_messages(file_desc):
            defaults_block = _emit_message_defaults_factory(
                proto_msg_name, msg_desc, enum_case_map,
            )
            if defaults_block is not None:
                blocks.append(defaults_block)
                annotated_message_defaults_count += 1

            validate_block = _emit_message_validate(proto_msg_name, msg_desc)
            if validate_block is not None:
                blocks.append(validate_block)
                annotated_message_validate_count += 1

    header = [
        "// DO NOT EDIT.",
        "// swift-format-ignore-file",
        "// swiftlint:disable all",
        "//",
        "// Generated by idl/codegen/generate_swift_convenience.py.",
        "//",
        "// This file exposes hand-friendly convenience accessors derived from",
        "// RunAnywhere's custom proto annotations (see idl/rac_options.proto):",
        "//   - .displayName              (rac_display_name)",
        "//   - .analyticsKey             (rac_analytics_key)",
        "//   - .wireString               (rac_wire_string)",
        "//   - .from(wireString:)        (reverse of rac_wire_string)",
        "//   - .defaults()               (rac_default)",
        "//   - .validate()               (rac_required / rac_min / rac_max /",
        "//                                rac_min_float / rac_max_float)",
        "",
        "import Foundation",
        "",
        "",
    ]

    if blocks:
        body_text = "\n\n".join(blocks)
    else:
        body_text = (
            "// (Currently empty: no proto in idl/ has adopted rac_display_name /\n"
            "// rac_analytics_key / rac_wire_string annotations yet.)"
        )

    content = "\n".join(header) + body_text + "\n"
    out_path.write_text(content, encoding="utf-8")

    print(f"✓ Swift convenience post-processor → {out_path}")
    print(f"  annotated enum-accessor blocks emitted: {annotated_enum_count}")
    print(f"  message defaults() factories emitted: {annotated_message_defaults_count}")
    print(f"  message validate() helpers emitted: {annotated_message_validate_count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
