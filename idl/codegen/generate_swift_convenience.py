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
#   FieldOptions (for future use; emits if/when protos start adopting them):
#     rac_default       (50001, string) -> participates in defaults()
#     rac_required      (50002, bool)   -> participates in validate()
#     rac_min           (50004, int32)  -> participates in validate()
#     rac_max           (50005, int32)  -> participates in validate()
#
# Output:
#   sdk/runanywhere-swift/Sources/RunAnywhere/Generated/RAConvenience.swift
#
# The generator is intentionally tolerant: if NO proto in idl/ uses any of
# these annotations yet (which is the case immediately after P4-T1 lands),
# the output file contains only the header banner and a single comment
# noting the file is empty by design. The build still compiles.
#
# Invoked by generate_swift.sh AFTER swift-protobuf has produced the *.pb.swift
# files, so the RA* type names are already known to exist in the same module.

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
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

SWIFT_PREFIX = "RA"

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

_INTEGER_TYPES = frozenset((
    TYPE_INT32, TYPE_INT64, TYPE_UINT32, TYPE_UINT64,
    TYPE_FIXED32, TYPE_FIXED64, TYPE_SFIXED32, TYPE_SFIXED64,
    TYPE_SINT32, TYPE_SINT64,
))
_FLOAT_TYPES = frozenset((TYPE_DOUBLE, TYPE_FLOAT))


def _camel_case_from_snake(s: str) -> str:
    """Convert UPPER_SNAKE / lower_snake to lowerCamelCase, mirroring
    apple/swift-protobuf's NamingUtils.toLowerCamelCase behaviour.

    Key rules duplicated from swift-protobuf:
      - underscores are word separators
      - runs of uppercase letters are treated as acronyms; when followed by a
        lowercase letter, the trailing uppercase char terminates the acronym
        and starts the next word (e.g. ``S16LE`` followed by lowercase would
        split, but with no follower the entire run lowercases except the
        first char if not in the first word — ``S16LE`` -> ``s16Le`` standalone)
      - digit runs are passed through verbatim and end their current word
        run, so the next alphabetic chunk begins a new word
      - the very first emitted character is always lowercase (per the
        ``lowerCamelCase`` contract)

    Hand-tested against the swift-protobuf-generated case names in
    ``model_types.pb.swift`` for: ``m4A``, ``pcmS16Le``, ``llamaCpp``,
    ``speechRecognition``, ``voiceActivityDetection``, ``singleFileNested``,
    ``builtIn`` and the simple letter cases (``auto``, ``en``, ...).
    """
    out: list[str] = []
    i = 0
    n = len(s)
    first = True
    while i < n:
        ch = s[i]
        if ch == "_":
            i += 1
            continue
        if ch.isalpha():
            if ch.isupper():
                # Uppercase run — consume up to first non-upper char.
                j = i
                while j < n and s[j].isupper():
                    j += 1
                run = s[i:j]
                if j < n and s[j].islower():
                    # Acronym terminator: last char of run starts the new word.
                    head = run[:-1]
                    tail_start = run[-1]
                    k = j
                    while k < n and (s[k].islower() or s[k].isdigit()):
                        k += 1
                    rest = s[j:k]
                    if first:
                        out.append(head.lower())
                        first = False
                    else:
                        out.append(head[:1].upper() + head[1:].lower())
                    out.append(tail_start + rest)
                    i = k
                else:
                    # All-upper run at end of chunk or before digit / underscore.
                    if first:
                        out.append(run.lower())
                        first = False
                    else:
                        out.append(run[:1].upper() + run[1:].lower())
                    i = j
            else:
                # Lowercase run (rare in proto enum constants, but supported).
                j = i
                while j < n and (s[j].islower() or s[j].isdigit()):
                    j += 1
                run = s[i:j]
                if first:
                    out.append(run)
                    first = False
                else:
                    out.append(run[:1].upper() + run[1:])
                i = j
        elif ch.isdigit():
            # Digit run — passed through verbatim, treated as part of the
            # current word (no capitalization toggle).
            j = i
            while j < n and s[j].isdigit():
                j += 1
            out.append(s[i:j])
            if first:
                first = False
            i = j
        else:
            i += 1
    return "".join(out)


def _enum_name_to_screaming_snake(name: str) -> str:
    """Convert PascalCase enum name to SCREAMING_SNAKE prefix form.

    Mirrors swift-protobuf's rule: insert an underscore at a word boundary,
    where a boundary is either (a) a lowercase->uppercase transition, or
    (b) an uppercase->uppercase transition where the following character is
    lowercase (acronym terminator). Examples:
      ExecutionTarget   -> EXECUTION_TARGET
      STTLanguage       -> STT_LANGUAGE
      LLMGenerationState-> LLM_GENERATION_STATE
    """
    out_chars: list[str] = []
    for i, ch in enumerate(name):
        if i > 0 and ch.isupper():
            prev = name[i - 1]
            nxt = name[i + 1] if i + 1 < len(name) else ""
            # Boundary type (a): lowercase -> uppercase.
            # Boundary type (b): acronym terminator (current is upper, previous
            # is upper, next is lowercase — i.e. starting a new word).
            if (not prev.isupper()) or (prev.isupper() and nxt.islower()):
                out_chars.append("_")
        out_chars.append(ch.upper())
    return "".join(out_chars)


def _swift_case_name(enum_name: str, value_name: str) -> str:
    """Mirror swift-protobuf's enum value naming.

    Given proto enum constant `EXECUTION_TARGET_ON_DEVICE` in enum
    `ExecutionTarget`, swift-protobuf strips the enum-name prefix in
    SCREAMING_SNAKE form and emits the remainder as lowerCamelCase
    (`onDevice`). This helper duplicates that exact rule.
    """
    prefix = _enum_name_to_screaming_snake(enum_name) + "_"
    remainder = value_name
    if value_name.startswith(prefix):
        remainder = value_name[len(prefix):]
    return _camel_case_from_snake(remainder)


def _get_uninterpreted_string(opts, field_num: int) -> str | None:
    """Extract a string value from a FieldOptions/EnumValueOptions message
    even when the runtime has no compiled extension registered for the
    given field number.

    We rely on the protobuf python runtime preserving unknown extensions
    in the message's `_unknown_fields` (or in `unknown_fields` for newer
    runtimes). Failing that, we parse the message bytes directly.
    """
    raw = opts.SerializeToString()
    return _decode_string_field(raw, field_num)


def _get_uninterpreted_bool(opts, field_num: int) -> bool | None:
    raw = opts.SerializeToString()
    return _decode_bool_field(raw, field_num)


def _get_uninterpreted_int32(opts, field_num: int) -> int | None:
    raw = opts.SerializeToString()
    return _decode_int32_field(raw, field_num)


# --- Minimal wire-format reader for the few field types we care about. -----

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
    """Yield (field_number, wire_type, payload) for every field in `buf`.

    For wire-types we care about:
      0 (varint)        -> payload is int
      2 (length-delim)  -> payload is bytes
    Other wire types are skipped but consumed to keep position correct.
    """
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
            # SGROUP / EGROUP -- not used in proto3, skip silently.
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
            # Negative int32 values are encoded as 10-byte varint; mask to 32 bits and sign-extend.
            v = int(payload) & 0xFFFFFFFF
            if v & 0x80000000:
                v -= 0x100000000
            return v
    return None


def _decode_double_field(buf: bytes, field_num: int) -> float | None:
    """Read a proto3 double (wire type 1 = fixed64) at `field_num`."""
    import struct
    # Rebuild a richer scanner since the shared one drops 64-bit payloads.
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


def _get_uninterpreted_double(opts, field_num: int) -> float | None:
    raw = opts.SerializeToString()
    return _decode_double_field(raw, field_num)


# --- Descriptor-walking. ---------------------------------------------------

def _collect_top_level_enums(file_desc: descriptor_pb2.FileDescriptorProto):
    """Top-level enums only -- nested enums use a different Swift name path
    (RA<Parent>.<Nested>) and are out of scope for this minimal first cut.

    Walks file.enum_type. Returns list of (proto_enum_name, EnumDescriptorProto).
    """
    return [(e.name, e) for e in file_desc.enum_type]


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
        opt_str = _get_uninterpreted_string(value.options, field_num)
        if opt_str is None:
            continue
        swift_case = _swift_case_name(proto_enum_name, value.name)
        # Escape any embedded double-quote or backslash for safe inclusion in a Swift string literal.
        safe = opt_str.replace("\\", "\\\\").replace("\"", "\\\"")
        cases.append((swift_case, safe))
    if not cases:
        return None

    swift_type = f"{SWIFT_PREFIX}{proto_enum_name}"
    lines: list[str] = []
    lines.append(f"extension {swift_type} {{")
    lines.append(f"    /// Generated from `(runanywhere.v1.{_annotation_name(field_num)})` annotations in idl/.")
    lines.append(f"    public var {accessor_name}: String {{")
    lines.append("        switch self {")
    for swift_case, value in cases:
        lines.append(f"        case .{swift_case}: return \"{value}\"")
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
    """Emit a Swift `static func <factory_name>(<parameter_label>:)` factory on
    RA<EnumName> that reverses the wire-string annotation lookup. Returns None
    when no values are annotated.

    We expose this as a static factory rather than `init?(...)` to avoid
    collisions with swift-protobuf's auto-generated `init?(rawValue:)` and
    `init?(name:)` initializers. Matching is case-insensitive against the
    annotation value (preserves the lowercased pre-IDL behavior of every
    hand-written `fromWireString` switch in the SDK)."""
    cases: list[tuple[str, str]] = []
    for value in enum_desc.value:
        if not value.HasField("options"):
            continue
        opt_str = _get_uninterpreted_string(value.options, field_num)
        if opt_str is None:
            continue
        swift_case = _swift_case_name(proto_enum_name, value.name)
        safe = opt_str.replace("\\", "\\\\").replace("\"", "\\\"").lower()
        cases.append((swift_case, safe))
    if not cases:
        return None

    swift_type = f"{SWIFT_PREFIX}{proto_enum_name}"
    lines: list[str] = []
    lines.append(f"extension {swift_type} {{")
    lines.append(f"    /// Generated reverse of the `{_annotation_name(field_num)}` accessor.")
    lines.append(f"    /// Matches case-insensitively against the annotation value.")
    lines.append(f"    public static func {factory_name}({parameter_label}: String) -> {swift_type}? {{")
    lines.append(f"        switch {parameter_label}.lowercased() {{")
    for swift_case, value in cases:
        lines.append(f"        case \"{value}\": return .{swift_case}")
    lines.append("        default: return nil")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    return "\n".join(lines)


def _annotation_name(field_num: int) -> str:
    return {
        RAC_DEFAULT_FIELD_NUM:       "rac_default",
        RAC_REQUIRED_FIELD_NUM:      "rac_required",
        RAC_MIN_FIELD_NUM:           "rac_min",
        RAC_MAX_FIELD_NUM:           "rac_max",
        RAC_MIN_FLOAT_FIELD_NUM:     "rac_min_float",
        RAC_MAX_FLOAT_FIELD_NUM:     "rac_max_float",
        RAC_DISPLAY_NAME_FIELD_NUM:  "rac_display_name",
        RAC_ANALYTICS_KEY_FIELD_NUM: "rac_analytics_key",
        RAC_WIRE_STRING_FIELD_NUM:   "rac_wire_string",
    }.get(field_num, f"unknown_{field_num}")


# --- Message-level defaults() / validate() emitters. -----------------------

def _proto_field_to_swift_name(field_name: str) -> str:
    """Mirror swift-protobuf's struct-field name rule for proto fields.

    Proto snake_case names map to lowerCamelCase via the same rules as enum
    values (with first-word lowercase). Examples:
      sample_rate                  -> sampleRate
      enable_word_timestamps       -> enableWordTimestamps
      embedding_dimension          -> embeddingDimension
      max_sequence_length          -> maxSequenceLength
      max_tokens                   -> maxTokens
      model_id                     -> modelID    (swift-protobuf capitalizes ID)
    swift-protobuf's special-case "id" -> "ID" suffix is handled by detecting
    when the trailing word is exactly "id" and uppercasing it after camel
    conversion. Other common acronyms used by RA protos (json, url, uri, …)
    do NOT get this treatment by swift-protobuf and stay lowercase, so we
    only special-case `id` here.
    """
    base = _camel_case_from_snake(field_name)
    # swift-protobuf upper-cases trailing "Id" -> "ID".
    if base.endswith("Id") and not base.endswith("UUID") and not base.endswith("Uid"):
        return base[:-2] + "ID"
    return base


def _swift_default_literal(field, default_str: str, enum_swift_case: dict[str, str]) -> str | None:
    """Translate the string form of rac_default into a Swift literal for the
    given field. Returns None when the type isn't supported (skip emission)."""
    t = field.type
    if t == TYPE_STRING:
        safe = default_str.replace("\\", "\\\\").replace("\"", "\\\"")
        return f'"{safe}"'
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
        # Emit with explicit decimal so Swift sees a Float/Double literal.
        text = repr(v)
        if "." not in text and "e" not in text and "E" not in text:
            text += ".0"
        return text
    if t == TYPE_ENUM:
        # Resolve enum constant proto name -> swift case name.
        # The annotation string MUST be the proto constant (e.g. "STT_LANGUAGE_EN").
        enum_type = field.type_name.split(".")[-1]
        full_key = f"{enum_type}.{default_str.strip()}"
        return enum_swift_case.get(full_key)
    return None


def _collect_top_level_messages(file_desc: descriptor_pb2.FileDescriptorProto):
    return [(m.name, m) for m in file_desc.message_type]


def _build_enum_swift_case_map(fds: descriptor_pb2.FileDescriptorSet) -> dict[str, str]:
    """Return a dict mapping "EnumName.ENUM_CONSTANT_NAME" -> ".swiftCase".

    Walks every enum (top-level + nested) in every file with package
    runanywhere.v1 so the message-default emitter can translate
    `rac_default = "STT_LANGUAGE_EN"` into `.en` for an enum-typed field."""
    out: dict[str, str] = {}
    for file_desc in fds.file:
        if file_desc.package != "runanywhere.v1":
            continue
        def _walk(enums, _prefix=""):
            for e in enums:
                for v in e.value:
                    out[f"{e.name}.{v.name}"] = "." + _swift_case_name(e.name, v.name)
        _walk(file_desc.enum_type)
        for msg in file_desc.message_type:
            _walk(msg.enum_type)
    return out


def _emit_message_defaults_factory(
    proto_msg_name: str,
    msg_desc: descriptor_pb2.DescriptorProto,
    enum_swift_case: dict[str, str],
) -> str | None:
    """Emit `public static func defaults() -> RA<MessageName>` when at least
    one field carries `rac_default`. Returns None when the message has no
    relevant annotations."""
    assignments: list[tuple[str, str]] = []
    for field in msg_desc.field:
        if not field.HasField("options"):
            continue
        default_str = _get_uninterpreted_string(field.options, RAC_DEFAULT_FIELD_NUM)
        if default_str is None:
            continue
        literal = _swift_default_literal(field, default_str, enum_swift_case)
        if literal is None:
            continue
        swift_field = _proto_field_to_swift_name(field.name)
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
    `rac_required`, `rac_min`, `rac_max`, `rac_min_float`, or `rac_max_float`.
    Returns None when no relevant annotations are present."""
    checks: list[str] = []
    for field in msg_desc.field:
        if not field.HasField("options"):
            continue
        swift_field = _proto_field_to_swift_name(field.name)

        is_required = _get_uninterpreted_bool(field.options, RAC_REQUIRED_FIELD_NUM)
        if is_required:
            t = field.type
            if t == TYPE_STRING:
                checks.append(f"        if {swift_field}.isEmpty {{")
                checks.append(f"            throw SDKException(")
                checks.append(f"                code: .invalidArgument,")
                checks.append(f'                message: "{field.name} is required",')
                checks.append(f"                category: .validation")
                checks.append(f"            )")
                checks.append(f"        }}")
            elif t in _INTEGER_TYPES:
                checks.append(f"        if {swift_field} == 0 {{")
                checks.append(f"            throw SDKException(")
                checks.append(f"                code: .invalidArgument,")
                checks.append(f'                message: "{field.name} is required",')
                checks.append(f"                category: .validation")
                checks.append(f"            )")
                checks.append(f"        }}")
            elif t in _FLOAT_TYPES:
                checks.append(f"        if {swift_field} == 0 {{")
                checks.append(f"            throw SDKException(")
                checks.append(f"                code: .invalidArgument,")
                checks.append(f'                message: "{field.name} is required",')
                checks.append(f"                category: .validation")
                checks.append(f"            )")
                checks.append(f"        }}")

        min_int = _get_uninterpreted_int32(field.options, RAC_MIN_FIELD_NUM)
        max_int = _get_uninterpreted_int32(field.options, RAC_MAX_FIELD_NUM)
        if (min_int is not None or max_int is not None) and field.type in _INTEGER_TYPES:
            parts: list[str] = []
            if min_int is not None:
                parts.append(f"{swift_field} < {min_int}")
            if max_int is not None:
                parts.append(f"{swift_field} > {max_int}")
            cond = " || ".join(parts)
            range_desc = ""
            if min_int is not None and max_int is not None:
                range_desc = f"{min_int}...{max_int}"
            elif min_int is not None:
                range_desc = f">= {min_int}"
            else:
                range_desc = f"<= {max_int}"
            checks.append(f"        if {cond} {{")
            checks.append(f"            throw SDKException(")
            checks.append(f"                code: .invalidArgument,")
            checks.append(f'                message: "{field.name} must be in {range_desc} (got \\({swift_field}))",')
            checks.append(f"                category: .validation")
            checks.append(f"            )")
            checks.append(f"        }}")

        min_f = _get_uninterpreted_double(field.options, RAC_MIN_FLOAT_FIELD_NUM)
        max_f = _get_uninterpreted_double(field.options, RAC_MAX_FLOAT_FIELD_NUM)
        if (min_f is not None or max_f is not None) and field.type in _FLOAT_TYPES:
            parts = []
            if min_f is not None:
                parts.append(f"{swift_field} < {min_f}")
            if max_f is not None:
                parts.append(f"{swift_field} > {max_f}")
            cond = " || ".join(parts)
            range_desc = ""
            if min_f is not None and max_f is not None:
                range_desc = f"{min_f}...{max_f}"
            elif min_f is not None:
                range_desc = f">= {min_f}"
            else:
                range_desc = f"<= {max_f}"
            checks.append(f"        if {cond} {{")
            checks.append(f"            throw SDKException(")
            checks.append(f"                code: .invalidArgument,")
            checks.append(f'                message: "{field.name} must be in {range_desc} (got \\({swift_field}))",')
            checks.append(f"                category: .validation")
            checks.append(f"            )")
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

def _build_descriptor_set(proto_dir: Path, proto_files: list[Path]) -> Path:
    """Invoke protoc to produce a FileDescriptorSet covering all idl/*.proto."""
    fd, set_path = tempfile.mkstemp(prefix="rac-fds-", suffix=".pb")
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


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root  = script_dir.parent.parent
    proto_dir  = repo_root / "idl"
    out_dir    = repo_root / "sdk" / "runanywhere-swift" / "Sources" / "RunAnywhere" / "Generated"
    out_path   = out_dir / "RAConvenience.swift"

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

    blocks: list[str] = []
    annotated_enum_count = 0
    annotated_message_defaults_count = 0
    annotated_message_validate_count = 0

    enum_swift_case = _build_enum_swift_case_map(fds)

    for file_desc in fds.file:
        # Skip protos we don't own (google/protobuf/descriptor.proto, etc.)
        # by checking the package -- only our schemas declare package runanywhere.v1.
        if file_desc.package != "runanywhere.v1":
            continue

        for proto_enum_name, enum_desc in _collect_top_level_enums(file_desc):
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

        # Phase E: per-message defaults() / validate() emitters from
        # rac_default / rac_required / rac_min / rac_max / rac_min_float /
        # rac_max_float field annotations.
        for proto_msg_name, msg_desc in _collect_top_level_messages(file_desc):
            defaults_block = _emit_message_defaults_factory(
                proto_msg_name, msg_desc, enum_swift_case,
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
