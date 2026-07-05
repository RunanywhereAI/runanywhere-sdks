#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# TypeScript convenience-accessor post-processor for ts-proto output.
#
# Phase 4 / T3.3-ts-impl. Reads RunAnywhere's custom proto annotations from
# idl/rac_options.proto and emits ts-proto-compatible convenience helpers
# alongside the message bindings produced by generate_ts.sh.
#
# Annotations consumed (mirrors generate_swift_convenience.py):
#   EnumValueOptions:
#     rac_display_name  (50010, string) -> emits `<enumName>DisplayName`
#     rac_analytics_key (50011, string) -> emits `<enumName>AnalyticsKey`
#     rac_wire_string   (50012, string) -> emits `<enumName>WireString`
#                                          + `<enumName>FromWireString` (reverse)
#   FieldOptions:
#     rac_default       (50001, string) -> participates in `<msgName>Defaults`
#     rac_required      (50002, bool)   -> participates in `validate<Msg>`
#     rac_min           (50004, int32)  -> participates in `validate<Msg>` (int)
#     rac_max           (50005, int32)  -> participates in `validate<Msg>` (int)
#     rac_min_float     (50006, double) -> participates in `validate<Msg>` (float)
#     rac_max_float     (50007, double) -> participates in `validate<Msg>` (float)
#
# Output:
#   sdk/shared/proto-ts/src/convenience/<base>_convenience.ts (one file per
#   source proto that carries at least one rac_* annotation).
#
# Constraints honoured:
#   * ts-proto messages are TS `interface`s; helpers are namespaced free
#     functions, not static methods.
#   * `useOptionals=messages` (scripts/codegen/generate_ts.sh:73) makes nested
#     message-typed fields `?`-optional. Defaults factory therefore
#     initialises every required scalar / repeated / enum field to its
#     proto3 zero value (or rac_default when set) and may omit nested
#     message + proto3-optional fields unless explicitly defaulted.
#   * Validate throws ValidationError from `./_errors` (hand-written, see
#     sdk/shared/proto-ts/src/convenience/_errors.ts).
#
# Invoked by generate_all.sh AFTER generate_ts.sh so the message / enum
# names referenced by the convenience file are already on disk.

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from google.protobuf import descriptor_pb2

# --- RunAnywhere proto-annotation field numbers (mirror idl/rac_options.proto).
RAC_DEFAULT_FIELD_NUM       = 50001
RAC_REQUIRED_FIELD_NUM      = 50002
RAC_MIN_FIELD_NUM           = 50004
RAC_MAX_FIELD_NUM           = 50005
RAC_MIN_FLOAT_FIELD_NUM     = 50006
RAC_MAX_FLOAT_FIELD_NUM     = 50007
RAC_DISPLAY_NAME_FIELD_NUM  = 50010
RAC_ANALYTICS_KEY_FIELD_NUM = 50011
RAC_WIRE_STRING_FIELD_NUM   = 50012

# --- Proto wire type enums (mirror google/protobuf/descriptor.proto).
TYPE_DOUBLE   = 1
TYPE_FLOAT    = 2
TYPE_INT64    = 3
TYPE_UINT64   = 4
TYPE_INT32    = 5
TYPE_FIXED64  = 6
TYPE_FIXED32  = 7
TYPE_BOOL     = 8
TYPE_STRING   = 9
TYPE_MESSAGE  = 11
TYPE_BYTES    = 12
TYPE_UINT32   = 13
TYPE_ENUM     = 14
TYPE_SFIXED32 = 15
TYPE_SFIXED64 = 16
TYPE_SINT32   = 17
TYPE_SINT64   = 18

LABEL_OPTIONAL = 1
LABEL_REQUIRED = 2
LABEL_REPEATED = 3

_INTEGER_TYPES = frozenset((
    TYPE_INT32, TYPE_INT64, TYPE_UINT32, TYPE_UINT64,
    TYPE_FIXED32, TYPE_FIXED64, TYPE_SFIXED32, TYPE_SFIXED64,
    TYPE_SINT32, TYPE_SINT64,
))
_FLOAT_TYPES = frozenset((TYPE_DOUBLE, TYPE_FLOAT))


# --- Wire-format readers for unknown FieldOptions/EnumValueOptions extensions.
# ts-proto strips rac_* annotations from generated source; we therefore
# decode them straight off the descriptor's serialized bytes.

def _read_varint(buf: bytes, pos: int) -> tuple[int, int]:
    result = 0
    shift = 0
    while True:
        if pos >= len(buf):
            raise ValueError("truncated varint")
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if (b & 0x80) == 0:
            return result, pos
        shift += 7
        if shift >= 64:
            raise ValueError("varint too long")


def _scan_fields(buf: bytes) -> Iterable[tuple[int, int, bytes | int]]:
    pos = 0
    while pos < len(buf):
        tag, pos = _read_varint(buf, pos)
        wt = tag & 0x07
        fn = tag >> 3
        if wt == 0:
            val, pos = _read_varint(buf, pos)
            yield fn, wt, val
        elif wt == 2:
            length, pos = _read_varint(buf, pos)
            payload = buf[pos:pos + length]
            pos += length
            yield fn, wt, payload
        elif wt == 1:  # 64-bit
            pos += 8
        elif wt == 5:  # 32-bit
            pos += 4
        else:
            pass


def _decode_string_field(buf: bytes, field_num: int) -> str | None:
    for fn, wt, payload in _scan_fields(buf):
        if fn == field_num and wt == 2:
            return payload.decode("utf-8")
    return None


def _decode_bool_field(buf: bytes, field_num: int) -> bool | None:
    for fn, wt, payload in _scan_fields(buf):
        if fn == field_num and wt == 0:
            return bool(payload)
    return None


def _decode_int32_field(buf: bytes, field_num: int) -> int | None:
    for fn, wt, payload in _scan_fields(buf):
        if fn == field_num and wt == 0:
            v = int(payload) & 0xFFFFFFFF
            if v & 0x80000000:
                v -= 0x100000000
            return v
    return None


def _decode_double_field(buf: bytes, field_num: int) -> float | None:
    import struct
    pos = 0
    while pos < len(buf):
        tag, pos = _read_varint(buf, pos)
        wt = tag & 0x07
        fn = tag >> 3
        if wt == 1:
            if fn == field_num:
                return struct.unpack("<d", buf[pos:pos + 8])[0]
            pos += 8
        elif wt == 0:
            _, pos = _read_varint(buf, pos)
        elif wt == 2:
            length, pos = _read_varint(buf, pos)
            pos += length
        elif wt == 5:
            pos += 4
        else:
            pass
    return None


def _opt_string(opts, field_num: int) -> str | None:
    return _decode_string_field(opts.SerializeToString(), field_num)


def _opt_bool(opts, field_num: int) -> bool | None:
    return _decode_bool_field(opts.SerializeToString(), field_num)


def _opt_int32(opts, field_num: int) -> int | None:
    return _decode_int32_field(opts.SerializeToString(), field_num)


def _opt_double(opts, field_num: int) -> float | None:
    return _decode_double_field(opts.SerializeToString(), field_num)


# --- Naming utilities -----------------------------------------------------

def _ts_proto_function_prefix(symbol: str) -> str:
    """First character lowercased, rest preserved.

    ts-proto's deterministic rule for deriving the function-name prefix
    from a type symbol. Verified at sdk/shared/proto-ts/src/stt_options.ts:58
    (`sTTLanguageFromJSON` derived from `STTLanguage`) and model_types.ts:47
    (`audioFormatFromJSON` from `AudioFormat`).
    """
    if not symbol:
        return symbol
    return symbol[0].lower() + symbol[1:]


def _proto_field_to_ts_camel(name: str) -> str:
    """Convert proto snake_case field name to ts-proto's lowerCamelCase form.

    ts-proto uses the standard snake_case-to-camelCase rule and DOES NOT
    apply Swift's `Id`->`ID` upper-case shortcut (verified at
    sdk/shared/proto-ts/src/stt_options.ts:266 — `modelId`, not `modelID`).
    """
    parts = name.split("_")
    if not parts:
        return name
    head = parts[0]
    tail = [p[:1].upper() + p[1:] if p else "" for p in parts[1:]]
    return head + "".join(tail)


# --- Default-literal translation ------------------------------------------

def _ts_default_literal(
    field: descriptor_pb2.FieldDescriptorProto,
    default_str: str,
    enum_const_names: dict[str, set[str]],
    needed_imports: dict[str, set[str]],
    enum_owner_file: dict[str, str],
) -> str | None:
    """Translate the rac_default string into a ts-proto-compatible literal.

    Returns None when the value cannot be translated (skip emission).
    Mutates `needed_imports` to record any enum import the literal pulls in.
    """
    t = field.type
    label = field.label
    if label == LABEL_REPEATED:
        # Repeated fields don't carry single-value defaults in any of our
        # current annotations; skip rather than guess at semantics.
        return None
    if t == TYPE_STRING:
        safe = default_str.replace("\\", "\\\\").replace("'", "\\'")
        return f"'{safe}'"
    if t == TYPE_BOOL:
        s = default_str.strip().lower()
        if s in ("true", "1"):
            return "true"
        if s in ("false", "0"):
            return "false"
        return None
    if t in _INTEGER_TYPES:
        try:
            return str(int(default_str))
        except ValueError:
            return None
    if t in _FLOAT_TYPES:
        try:
            v = float(default_str)
        except ValueError:
            return None
        text = repr(v)
        if "." not in text and "e" not in text and "E" not in text:
            text += ".0"
        return text
    if t == TYPE_ENUM:
        # field.type_name is fully-qualified, e.g. ".runanywhere.v1.STTLanguage".
        enum_name = field.type_name.split(".")[-1]
        const_name = default_str.strip()
        if enum_name not in enum_const_names:
            return None
        if const_name not in enum_const_names[enum_name]:
            return None
        owner = enum_owner_file.get(enum_name)
        if owner is None:
            return None
        needed_imports.setdefault(owner, set()).add(enum_name)
        return f"{enum_name}.{const_name}"
    return None


def _ts_zero_literal(
    field: descriptor_pb2.FieldDescriptorProto,
) -> str:
    """Return the proto3 zero-value literal for a required ts-proto field.

    Matches ts-proto's own `createBase<Msg>` initialiser semantics (verified
    in sdk/shared/proto-ts/src/stt_options.ts:540, where enum-typed fields
    take the bare numeric `0` and string/number/bool fall back to `""`/`0`/`false`).
    """
    t = field.type
    if field.label == LABEL_REPEATED:
        return "[]"
    if t == TYPE_STRING:
        return "''"
    if t == TYPE_BOOL:
        return "false"
    if t in _INTEGER_TYPES or t in _FLOAT_TYPES:
        return "0"
    if t == TYPE_ENUM:
        # Bare numeric assignment matches ts-proto's createBase initialiser
        # and avoids forcing an extra enum import per field.
        return "0"
    if t == TYPE_BYTES:
        return "new Uint8Array(0)"
    # Unknown / message types should never reach here; the caller must
    # filter them out before requesting a zero literal.
    return "undefined"


# --- Descriptor walking ---------------------------------------------------

@dataclass
class GeneratedFile:
    base_name: str           # e.g. "stt_options"
    blocks: list[str]        # already-rendered code blocks
    imports_from_self: set[str]            # symbols imported from `../<base>`
    imports_from_other: dict[str, set[str]]  # owner_file -> {symbols}
    needs_validation_error: bool
    enum_helpers_emitted: int
    defaults_emitted: int
    validate_emitted: int


def _is_proto3_optional(field: descriptor_pb2.FieldDescriptorProto) -> bool:
    return bool(getattr(field, "proto3_optional", False))


def _is_singular_message(field: descriptor_pb2.FieldDescriptorProto) -> bool:
    return field.type == TYPE_MESSAGE and field.label != LABEL_REPEATED


def _emit_enum_accessor(
    proto_enum_name: str,
    enum_desc: descriptor_pb2.EnumDescriptorProto,
    function_name: str,
    field_num: int,
) -> str | None:
    """Emit `export const <function_name> = (e: <Enum>): string => { ... }`
    when at least one enum value carries the annotation; otherwise None."""
    cases: list[tuple[str, str]] = []
    for value in enum_desc.value:
        if not value.HasField("options"):
            continue
        annotated = _opt_string(value.options, field_num)
        if annotated is None:
            continue
        # Escape both backslash and backtick for safe inclusion in template literals.
        safe = annotated.replace("\\", "\\\\").replace("'", "\\'")
        cases.append((value.name, safe))
    if not cases:
        return None

    lines: list[str] = []
    lines.append(f"export const {function_name} = (e: {proto_enum_name}): string => {{")
    lines.append("  switch (e) {")
    for const_name, value in cases:
        lines.append(f"    case {proto_enum_name}.{const_name}:")
        lines.append(f"      return '{value}';")
    lines.append("    default:")
    lines.append("      return '';")
    lines.append("  }")
    lines.append("};")
    return "\n".join(lines)


def _emit_enum_reverse_factory(
    proto_enum_name: str,
    enum_desc: descriptor_pb2.EnumDescriptorProto,
    function_name: str,
    field_num: int,
) -> str | None:
    """Emit reverse-lookup helper: `s -> <Enum> | undefined`. Returns None
    when no values are annotated. Matches case-insensitively against the
    annotation value, mirroring the Swift `from(wireString:)` factory."""
    cases: list[tuple[str, str]] = []
    for value in enum_desc.value:
        if not value.HasField("options"):
            continue
        annotated = _opt_string(value.options, field_num)
        if annotated is None:
            continue
        safe = annotated.replace("\\", "\\\\").replace("'", "\\'").lower()
        cases.append((value.name, safe))
    if not cases:
        return None

    lines: list[str] = []
    lines.append(
        f"export const {function_name} = (s: string): {proto_enum_name} | undefined => {{"
    )
    lines.append("  switch (s.toLowerCase()) {")
    for const_name, value in cases:
        lines.append(f"    case '{value}':")
        lines.append(f"      return {proto_enum_name}.{const_name};")
    lines.append("    default:")
    lines.append("      return undefined;")
    lines.append("  }")
    lines.append("};")
    return "\n".join(lines)


def _emit_message_defaults(
    msg_desc: descriptor_pb2.DescriptorProto,
    enum_const_names: dict[str, set[str]],
    enum_owner_file: dict[str, str],
    needed_other_imports: dict[str, set[str]],
) -> str | None:
    """Emit `export const <msgName>Defaults = (): <Msg> => ({ ... });`.

    Initialises every required field (proto3 zero value) plus any field
    that carries `rac_default`. Skips proto3-optional and singular-message
    fields unless they also carry an explicit `rac_default`.
    """
    msg_name = msg_desc.name
    has_any_default = False
    field_lines: list[str] = []

    for field in msg_desc.field:
        ts_field = _proto_field_to_ts_camel(field.name)
        rac_default: str | None = None
        if field.HasField("options"):
            rac_default = _opt_string(field.options, RAC_DEFAULT_FIELD_NUM)
        if rac_default is not None:
            has_any_default = True

        is_optional_in_ts = (
            _is_proto3_optional(field)
            or _is_singular_message(field)
        )

        if rac_default is not None:
            literal = _ts_default_literal(
                field,
                rac_default,
                enum_const_names,
                needed_other_imports,
                enum_owner_file,
            )
            if literal is not None:
                field_lines.append(f"  {ts_field}: {literal},")
                continue
            # rac_default was set but couldn't be translated; fall through to
            # zero/skip handling so the literal still type-checks.

        if is_optional_in_ts:
            # No rac_default and the field is `?`-optional in the interface;
            # safely omit (TS treats absent as undefined).
            continue

        # Required field — must initialise to satisfy the interface.
        field_lines.append(f"  {ts_field}: {_ts_zero_literal(field)},")

    if not has_any_default:
        # Per the design: only emit defaults() when at least one rac_default
        # exists; otherwise the helper would be redundant with ts-proto's
        # built-in `<Msg>.create({})` factory.
        return None

    fn_name = f"{_ts_proto_function_prefix(msg_name)}Defaults"
    lines: list[str] = []
    lines.append(f"export const {fn_name} = (): {msg_name} => ({{")
    lines.extend(field_lines)
    lines.append("});")
    return "\n".join(lines)


def _emit_message_validate(
    msg_desc: descriptor_pb2.DescriptorProto,
) -> str | None:
    """Emit `export const validate<Msg> = (m: <Msg>): void => { ... };`
    when at least one field carries a validation annotation. Returns None
    when no relevant annotations are present."""
    msg_name = msg_desc.name
    checks: list[str] = []

    def _throw(field_name: str, message_literal: str) -> list[str]:
        """Emit a `throw new ValidationError({ ... })` block with the
        canonical `{ code, category, fieldPath, message }` shape. The
        `code` and `category` fields are filled in by the
        ValidationError constructor's defaults."""
        field_path = f"{msg_name}.{field_name}"
        return [
            "    throw new ValidationError({",
            f"      fieldPath: '{field_path}',",
            f"      message: {message_literal},",
            "    });",
        ]

    for field in msg_desc.field:
        if not field.HasField("options"):
            continue
        ts_field = _proto_field_to_ts_camel(field.name)
        is_required = _opt_bool(field.options, RAC_REQUIRED_FIELD_NUM) or False
        min_int = _opt_int32(field.options, RAC_MIN_FIELD_NUM)
        max_int = _opt_int32(field.options, RAC_MAX_FIELD_NUM)
        min_f = _opt_double(field.options, RAC_MIN_FLOAT_FIELD_NUM)
        max_f = _opt_double(field.options, RAC_MAX_FLOAT_FIELD_NUM)
        # proto3 explicit-optional fields are typed `T | undefined` on the
        # ts-proto wire type, so direct numeric/string comparisons need a
        # presence guard. When unset, validation is intentionally skipped:
        # commons applies canonical defaults via rac_*_with_defaults_proto.
        is_proto3_optional = bool(getattr(field, "proto3_optional", False))
        opt_guard = f"m.{ts_field} !== undefined && " if is_proto3_optional else ""

        if is_required and field.label != LABEL_REPEATED:
            t = field.type
            zero_check: str | None = None
            if t == TYPE_STRING:
                zero_check = f"{opt_guard}m.{ts_field} === ''"
            elif t in _INTEGER_TYPES or t in _FLOAT_TYPES:
                zero_check = f"{opt_guard}m.{ts_field} === 0"
            # pass3-syn-038: TYPE_BOOL deliberately skips the required-check
            # to match Swift / Kotlin / Dart cross-SDK behaviour. The other
            # three generators treat `bool + rac_required` as a no-op
            # (Dart documents the skip explicitly at
            # generate_dart_convenience.py:475-478; Swift / Kotlin fall
            # through because TYPE_BOOL is in neither INTEGER_TYPES nor
            # FLOAT_TYPES). Emitting `m.field === false` here would create
            # a silent business-logic skew for any future proto that adopts
            # the `bool + rac_required` pattern.
            if zero_check is not None:
                checks.append(f"  if ({zero_check}) {{")
                checks.extend(_throw(field.name, f"'{field.name} is required'"))
                checks.append("  }")

        if (min_int is not None or max_int is not None) and field.type in _INTEGER_TYPES:
            parts: list[str] = []
            if min_int is not None:
                parts.append(f"m.{ts_field} < {min_int}")
            if max_int is not None:
                parts.append(f"m.{ts_field} > {max_int}")
            cond = " || ".join(parts)
            if is_proto3_optional:
                cond = f"m.{ts_field} !== undefined && ({cond})"
            if min_int is not None and max_int is not None:
                range_desc = f"{min_int}...{max_int}"
            elif min_int is not None:
                range_desc = f">= {min_int}"
            else:
                range_desc = f"<= {max_int}"
            msg_literal = f"`{field.name} must be in {range_desc} (got ${{m.{ts_field}}})`"
            checks.append(f"  if ({cond}) {{")
            checks.extend(_throw(field.name, msg_literal))
            checks.append("  }")

        if (min_f is not None or max_f is not None) and field.type in _FLOAT_TYPES:
            parts = []
            if min_f is not None:
                parts.append(f"m.{ts_field} < {min_f}")
            if max_f is not None:
                parts.append(f"m.{ts_field} > {max_f}")
            cond = " || ".join(parts)
            if is_proto3_optional:
                cond = f"m.{ts_field} !== undefined && ({cond})"
            if min_f is not None and max_f is not None:
                range_desc = f"{min_f}...{max_f}"
            elif min_f is not None:
                range_desc = f">= {min_f}"
            else:
                range_desc = f"<= {max_f}"
            msg_literal = f"`{field.name} must be in {range_desc} (got ${{m.{ts_field}}})`"
            checks.append(f"  if ({cond}) {{")
            checks.extend(_throw(field.name, msg_literal))
            checks.append("  }")

    if not checks:
        return None

    fn_name = f"validate{msg_name}"
    lines: list[str] = []
    lines.append(f"export const {fn_name} = (m: {msg_name}): void => {{")
    lines.extend(checks)
    lines.append("};")
    return "\n".join(lines)


# --- Per-file aggregation -------------------------------------------------

def _file_basename(file_desc: descriptor_pb2.FileDescriptorProto) -> str:
    return Path(file_desc.name).stem


def _collect_message_symbols_per_file(
    fds: descriptor_pb2.FileDescriptorSet,
) -> tuple[dict[str, str], dict[str, str], dict[str, set[str]]]:
    """Walk all proto files in the descriptor set once.

    Returns:
      enum_owner_file:    {EnumName -> file_basename}
      message_owner_file: {MessageName -> file_basename}
      enum_const_names:   {EnumName -> {ConstantName, ...}}
    """
    enum_owner: dict[str, str] = {}
    msg_owner: dict[str, str] = {}
    enum_consts: dict[str, set[str]] = {}

    for file_desc in fds.file:
        if file_desc.package != "runanywhere.v1":
            continue
        base = _file_basename(file_desc)
        for enum_desc in file_desc.enum_type:
            enum_owner[enum_desc.name] = base
            enum_consts[enum_desc.name] = {v.name for v in enum_desc.value}
        for msg_desc in file_desc.message_type:
            msg_owner[msg_desc.name] = base
            # Nested enums: register so cross-file references can still
            # resolve, but their owner is the parent file.
            for nested_enum in msg_desc.enum_type:
                enum_owner.setdefault(nested_enum.name, base)
                enum_consts.setdefault(
                    nested_enum.name,
                    {v.name for v in nested_enum.value},
                )

    return enum_owner, msg_owner, enum_consts


def _process_file(
    file_desc: descriptor_pb2.FileDescriptorProto,
    enum_owner_file: dict[str, str],
    enum_const_names: dict[str, set[str]],
) -> GeneratedFile | None:
    base = _file_basename(file_desc)
    blocks: list[str] = []
    imports_from_self: set[str] = set()
    imports_from_other: dict[str, set[str]] = {}
    enum_helpers_emitted = 0
    defaults_emitted = 0
    validate_emitted = 0
    needs_validation_error = False

    # Top-level enums -> wireString / displayName / analyticsKey + reverse.
    for enum_desc in file_desc.enum_type:
        enum_name = enum_desc.name
        prefix = _ts_proto_function_prefix(enum_name)
        per_enum_blocks: list[str] = []

        wire_block = _emit_enum_accessor(
            enum_name, enum_desc, f"{prefix}WireString", RAC_WIRE_STRING_FIELD_NUM,
        )
        if wire_block is not None:
            per_enum_blocks.append(wire_block)
            reverse_block = _emit_enum_reverse_factory(
                enum_name, enum_desc, f"{prefix}FromWireString", RAC_WIRE_STRING_FIELD_NUM,
            )
            if reverse_block is not None:
                per_enum_blocks.append(reverse_block)

        for fn_suffix, field_num in (
            ("DisplayName", RAC_DISPLAY_NAME_FIELD_NUM),
            ("AnalyticsKey", RAC_ANALYTICS_KEY_FIELD_NUM),
        ):
            block = _emit_enum_accessor(
                enum_name, enum_desc, f"{prefix}{fn_suffix}", field_num,
            )
            if block is not None:
                per_enum_blocks.append(block)

        if per_enum_blocks:
            imports_from_self.add(enum_name)
            blocks.extend(per_enum_blocks)
            enum_helpers_emitted += len(per_enum_blocks)

    # Top-level messages -> defaults() / validate().
    for msg_desc in file_desc.message_type:
        defaults_block = _emit_message_defaults(
            msg_desc, enum_const_names, enum_owner_file, imports_from_other,
        )
        if defaults_block is not None:
            imports_from_self.add(msg_desc.name)
            blocks.append(defaults_block)
            defaults_emitted += 1

        validate_block = _emit_message_validate(msg_desc)
        if validate_block is not None:
            imports_from_self.add(msg_desc.name)
            blocks.append(validate_block)
            validate_emitted += 1
            needs_validation_error = True

    if not blocks:
        return None

    # Drop any cross-file enum import that turned out to live in our own
    # file (e.g. message and its enum are both top-level in the same proto).
    imports_from_other.pop(base, None)

    return GeneratedFile(
        base_name=base,
        blocks=blocks,
        imports_from_self=imports_from_self,
        imports_from_other=imports_from_other,
        needs_validation_error=needs_validation_error,
        enum_helpers_emitted=enum_helpers_emitted,
        defaults_emitted=defaults_emitted,
        validate_emitted=validate_emitted,
    )


def _render_file(generated: GeneratedFile) -> str:
    header = [
        "// GENERATED by idl/codegen/generate_ts_convenience.py — DO NOT EDIT.",
        "//",
        "// Source: idl/" + generated.base_name + ".proto",
        "//",
        "// Convenience helpers derived from RunAnywhere's `rac_*` proto",
        "// annotations (see idl/rac_options.proto):",
        "//   * `<enumName>WireString`         (rac_wire_string)",
        "//   * `<enumName>FromWireString`     (reverse of rac_wire_string)",
        "//   * `<enumName>DisplayName`        (rac_display_name)",
        "//   * `<enumName>AnalyticsKey`       (rac_analytics_key)",
        "//   * `<msgName>Defaults`            (rac_default)",
        "//   * `validate<MsgName>`            (rac_required / rac_min / rac_max /",
        "//                                     rac_min_float / rac_max_float)",
        "",
        "/* eslint-disable */",
    ]

    import_lines: list[str] = []
    if generated.imports_from_self:
        symbols = ", ".join(sorted(generated.imports_from_self))
        import_lines.append(
            f"import {{ {symbols} }} from '../{generated.base_name}';"
        )
    for owner in sorted(generated.imports_from_other):
        symbols = ", ".join(sorted(generated.imports_from_other[owner]))
        import_lines.append(f"import {{ {symbols} }} from '../{owner}';")
    if generated.needs_validation_error:
        import_lines.append("import { ValidationError } from './_errors';")

    sections: list[str] = []
    sections.append("\n".join(header))
    if import_lines:
        sections.append("\n".join(import_lines))
    sections.extend(generated.blocks)
    # Trailing newline keeps Prettier / EditorConfig happy.
    return "\n\n".join(sections) + "\n"


# --- Top-level driver -----------------------------------------------------

def _build_descriptor_set(proto_dir: Path, proto_files: list[Path]) -> Path:
    fd, set_path = tempfile.mkstemp(prefix="rac-fds-ts-", suffix=".pb")
    os.close(fd)
    cmd = [
        "protoc",
        f"--proto_path={proto_dir}",
        f"--descriptor_set_out={set_path}",
        "--include_imports",
        *[str(p) for p in proto_files],
    ]
    subprocess.run(cmd, check=True)
    return Path(set_path)


def _clean_stale_outputs(out_dir: Path, written: set[str]) -> None:
    """Drop generator-owned `*_convenience.ts` files that this run did not
    rewrite. The hand-written `_errors.ts` (and any other underscore-prefix
    file) is preserved — it is part of the source tree, not a generator
    artefact."""
    if not out_dir.is_dir():
        return
    for path in out_dir.glob("*_convenience.ts"):
        if path.name not in written:
            path.unlink()


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    proto_dir = repo_root / "idl"
    out_dir = repo_root / "sdk" / "shared" / "proto-ts" / "src" / "convenience"

    out_dir.mkdir(parents=True, exist_ok=True)

    proto_files = sorted(proto_dir.glob("*.proto"))
    if not proto_files:
        print(f"warning: no .proto files in {proto_dir}", file=sys.stderr)
        return 0

    set_path = _build_descriptor_set(proto_dir, proto_files)
    try:
        fds = descriptor_pb2.FileDescriptorSet()
        fds.ParseFromString(set_path.read_bytes())
    finally:
        try:
            set_path.unlink()
        except OSError:
            pass

    enum_owner_file, _msg_owner_file, enum_const_names = (
        _collect_message_symbols_per_file(fds)
    )

    written: set[str] = set()
    total_enum_helpers = 0
    total_defaults = 0
    total_validate = 0

    for file_desc in fds.file:
        if file_desc.package != "runanywhere.v1":
            continue
        generated = _process_file(file_desc, enum_owner_file, enum_const_names)
        if generated is None:
            continue
        out_path = out_dir / f"{generated.base_name}_convenience.ts"
        out_path.write_text(_render_file(generated), encoding="utf-8")
        written.add(out_path.name)
        total_enum_helpers += generated.enum_helpers_emitted
        total_defaults += generated.defaults_emitted
        total_validate += generated.validate_emitted

    _clean_stale_outputs(out_dir, written)

    print(f"✓ TypeScript convenience post-processor → {out_dir}")
    print(f"  files written: {len(written)}")
    print(f"  enum-accessor blocks emitted: {total_enum_helpers}")
    print(f"  message Defaults factories emitted: {total_defaults}")
    print(f"  validate<Msg> helpers emitted: {total_validate}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
