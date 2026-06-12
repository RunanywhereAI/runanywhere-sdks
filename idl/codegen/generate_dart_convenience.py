#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Dart convenience-accessor post-processor (T3.3 / PR #494).
#
# Reads RunAnywhere's custom proto annotations from idl/rac_options.proto and
# emits Dart helpers on top of the dart-protobuf-generated .pb.dart / .pbenum.dart
# files. See idl/codegen/CONVENIENCE_CODEGEN_DESIGN.md (Section 2) for the
# full spec.
#
# Annotations consumed:
#   EnumValueOptions:
#     rac_wire_string   -> extension <Enum>WireString on <Enum> { String get wireString }
#                          + top-level <enumName>FromWireString(String) -> <Enum>?
#     rac_display_name  -> extension <Enum>DisplayName on <Enum> { String get displayName }
#     rac_analytics_key -> extension <Enum>AnalyticsKey on <Enum> { String get analyticsKey }
#   FieldOptions (per message field):
#     rac_default       -> extension <Msg>Convenience on <Msg> { static <Msg> defaults() }
#     rac_required / rac_min / rac_max / rac_min_float / rac_max_float ->
#                       extension <Msg>Validate on <Msg> { void validate() }
#
# Output (single file):
#   sdk/runanywhere-flutter/packages/runanywhere/lib/generated/convenience/ra_convenience.dart
#
# Invoked by generate_dart.sh / generate_all.sh AFTER protoc-gen-dart has
# produced the .pb.dart files so the message / enum type names referenced
# by the convenience file are already on disk.

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable

from google.protobuf import descriptor_pb2

# --- rac_options.proto field numbers (mirror idl/rac_options.proto:97-135).
RAC_DEFAULT_FIELD_NUM       = 50001
RAC_REQUIRED_FIELD_NUM      = 50002
RAC_MIN_FIELD_NUM           = 50004
RAC_MAX_FIELD_NUM           = 50005
RAC_MIN_FLOAT_FIELD_NUM     = 50006
RAC_MAX_FLOAT_FIELD_NUM     = 50007
RAC_DISPLAY_NAME_FIELD_NUM  = 50010
RAC_ANALYTICS_KEY_FIELD_NUM = 50011
RAC_WIRE_STRING_FIELD_NUM   = 50012

# --- Proto wire-format type enums (mirror google/protobuf/descriptor.proto).
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

_INT32_TYPES = frozenset((
    TYPE_INT32, TYPE_UINT32, TYPE_FIXED32, TYPE_SFIXED32, TYPE_SINT32,
))
_INT64_TYPES = frozenset((
    TYPE_INT64, TYPE_UINT64, TYPE_FIXED64, TYPE_SFIXED64, TYPE_SINT64,
))
_INTEGER_TYPES = _INT32_TYPES | _INT64_TYPES
_FLOAT_TYPES = frozenset((TYPE_DOUBLE, TYPE_FLOAT))

LABEL_REPEATED = 3

# --- Output target ---------------------------------------------------------
DART_PACKAGE_NAME = "runanywhere"
PROTO_PACKAGE     = "runanywhere.v1"
GENERATED_SUBDIR  = "generated"  # relative to lib/
CONVENIENCE_SUBDIR = "convenience"
OUTPUT_FILE_NAME  = "ra_convenience.dart"


# --- Minimal wire-format reader -------------------------------------------
# The Python proto runtime can't decode our rac_* extensions unless the
# extension definitions are themselves compiled into the runtime; rather than
# bootstrap that, we walk the serialized options bytes directly using the
# proto wire format (varint + length-delimited only — that covers every
# rac_* field type we care about).

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
    """Yield (field_number, wire_type, payload) for length-delim / varint
    fields. 64-bit / 32-bit fields are consumed separately by callers needing
    them (see ``_decode_double_field``)."""
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
        elif wt == 1:
            pos += 8
        elif wt == 5:
            pos += 4
        else:
            # SGROUP / EGROUP — not used in proto3.
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
    """Read a proto3 double (wire type 1 = fixed64) at ``field_num``."""
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
    return None


def _get_string_opt(opts, field_num: int) -> str | None:
    return _decode_string_field(opts.SerializeToString(), field_num)


def _get_bool_opt(opts, field_num: int) -> bool | None:
    return _decode_bool_field(opts.SerializeToString(), field_num)


def _get_int32_opt(opts, field_num: int) -> int | None:
    return _decode_int32_field(opts.SerializeToString(), field_num)


def _get_double_opt(opts, field_num: int) -> float | None:
    return _decode_double_field(opts.SerializeToString(), field_num)


# --- Naming utilities ------------------------------------------------------

def _snake_to_lower_camel(name: str) -> str:
    """Convert ``snake_case`` to ``lowerCamelCase``.

    Matches the protoc-gen-dart field-name rule: each ``_<word>`` segment
    becomes ``<Word>`` with the first character capitalised; the leading
    segment stays lowercase. Verified against the .pb.dart output for
    ``model_id`` -> ``modelId``, ``enable_word_timestamps`` -> ``enableWordTimestamps``,
    ``embedding_dimension`` -> ``embeddingDimension``. Notably the Dart plugin
    does NOT apply Swift's ``Id`` -> ``ID`` special case (``modelId`` stays
    lowercase).
    """
    parts = name.split("_")
    if not parts:
        return name
    head = parts[0]
    tail = "".join(p[:1].upper() + p[1:] for p in parts[1:])
    return head + tail


def _dart_lower_first(name: str) -> str:
    """Lower the leading capital run of a PascalCase identifier.

    Dart style guide: when initialisms appear at the start of an identifier,
    lowercase the entire acronym (``IOError`` -> ``ioError``,
    ``STTLanguage`` -> ``sttLanguage``, ``SDKEnvironment`` -> ``sdkEnvironment``).
    When a single capital starts a name, just lowercase it (``AudioFormat``
    -> ``audioFormat``).
    """
    if not name:
        return name
    n = len(name)
    i = 0
    while i < n and name[i].isupper():
        i += 1
    if i == 0:
        return name
    if i == 1:
        return name[0].lower() + name[1:]
    if i == n:
        return name.lower()
    # Multiple leading uppers + lowercase: the last upper starts the next
    # word, so lowercase everything before it and keep the rest as-is.
    return name[: i - 1].lower() + name[i - 1:]


def _simple_type_name(type_name: str) -> str:
    """Strip the leading ``.runanywhere.v1.`` qualifier off a type_name."""
    if not type_name:
        return type_name
    return type_name.rsplit(".", 1)[-1]


def _escape_dart_string(s: str) -> str:
    """Escape a Python string for safe embedding in a single-quoted Dart literal."""
    return (
        s.replace("\\", "\\\\")
         .replace("'", "\\'")
         .replace("$", "\\$")
    )


def _proto_basename(file_desc) -> str:
    """Return the base name (no .proto suffix) for a FileDescriptorProto."""
    return Path(file_desc.name).stem


# --- Descriptor build ------------------------------------------------------

def _build_descriptor_set(proto_dir: Path, proto_files: list[Path]) -> Path:
    fd, set_path = tempfile.mkstemp(prefix="rac-fds-dart-", suffix=".pb")
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


# --- Enum-name -> source-file lookup --------------------------------------

def _build_enum_file_map(fds: descriptor_pb2.FileDescriptorSet) -> dict[str, str]:
    """Map ``EnumName`` -> proto file basename for every top-level enum in
    package ``runanywhere.v1``. Used to resolve which ``.pbenum.dart`` to
    import for a cross-file enum reference in a ``defaults()`` literal."""
    out: dict[str, str] = {}
    for f in fds.file:
        if f.package != PROTO_PACKAGE:
            continue
        base = _proto_basename(f)
        for e in f.enum_type:
            out[e.name] = base
    return out


# --- Default-literal translation ------------------------------------------

def _dart_default_literal(field, default_str: str, want_int64_wrapper: list[bool]) -> str | None:
    """Translate ``rac_default`` (string form) into a Dart literal for the
    field's declared type. Returns ``None`` when the field's type is not
    supported by the convenience defaults emitter (the field is skipped)."""
    t = field.type
    if t == TYPE_STRING:
        return "'" + _escape_dart_string(default_str) + "'"
    if t == TYPE_BOOL:
        s = default_str.strip().lower()
        if s in ("true", "1"):
            return "true"
        if s in ("false", "0"):
            return "false"
        return None
    if t in _INT32_TYPES:
        try:
            return str(int(default_str))
        except ValueError:
            return None
    if t in _INT64_TYPES:
        try:
            v = int(default_str)
        except ValueError:
            return None
        want_int64_wrapper[0] = True
        return f"Int64({v})"
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
        enum_type = _simple_type_name(field.type_name)
        return f"{enum_type}.{default_str.strip()}"
    return None


# --- Emitter: enum extensions / reverse factory ---------------------------

def _emit_enum_extension(
    enum_name: str,
    enum_desc: descriptor_pb2.EnumDescriptorProto,
    extension_suffix: str,
    getter_name: str,
    field_num: int,
) -> str | None:
    """Emit ``extension <Enum><Suffix> on <Enum> { String get <getter> }`` when
    at least one enum value carries the given annotation.

    The switch enumerates EVERY enum value (annotated values return their
    annotation string; unannotated values return ``''``) so the analyzer's
    ``exhaustive_cases`` lint is satisfied without a fallback default clause.
    """
    annotated: dict[str, str] = {}
    has_any = False
    for value in enum_desc.value:
        if value.HasField("options"):
            s = _get_string_opt(value.options, field_num)
            if s is not None:
                annotated[value.name] = _escape_dart_string(s)
                has_any = True
    if not has_any:
        return None
    lines: list[str] = []
    lines.append(f"extension {enum_name}{extension_suffix} on {enum_name} {{")
    lines.append(f"  String get {getter_name} {{")
    lines.append("    switch (this) {")
    for value in enum_desc.value:
        lines.append(f"      case {enum_name}.{value.name}:")
        if value.name in annotated:
            lines.append(f"        return '{annotated[value.name]}';")
        else:
            lines.append("        return '';")
    lines.append("    }")
    # Dart's flow analyzer doesn't treat ProtobufEnum switches as exhaustive
    # even when every known instance is listed (the class could be extended at
    # runtime). The trailing ``return ''`` keeps the method type-sound.
    lines.append("    return '';")
    lines.append("  }")
    lines.append("}")
    return "\n".join(lines)


def _emit_enum_reverse_factory(
    enum_name: str,
    enum_desc: descriptor_pb2.EnumDescriptorProto,
    field_num: int,
) -> str | None:
    """Emit ``<enumName>FromWireString(String value) -> <Enum>?`` top-level
    function when at least one enum value carries ``rac_wire_string``."""
    cases: list[tuple[str, str]] = []
    for value in enum_desc.value:
        if not value.HasField("options"):
            continue
        s = _get_string_opt(value.options, field_num)
        if s is None:
            continue
        cases.append((value.name, _escape_dart_string(s.lower())))
    if not cases:
        return None
    fn_name = _dart_lower_first(enum_name) + "FromWireString"
    lines: list[str] = []
    lines.append(f"{enum_name}? {fn_name}(String value) {{")
    lines.append("  switch (value.toLowerCase()) {")
    for value_name, value_str in cases:
        lines.append(f"    case '{value_str}':")
        lines.append(f"      return {enum_name}.{value_name};")
    lines.append("  }")
    lines.append("  return null;")
    lines.append("}")
    return "\n".join(lines)


# --- Emitter: message defaults() / validate() -----------------------------

def _emit_message_defaults(
    msg_name: str,
    msg_desc: descriptor_pb2.DescriptorProto,
    enum_file_map: dict[str, str],
    int64_used: list[bool],
    enum_imports: set[str],
) -> str | None:
    """Emit ``extension <Msg>Convenience on <Msg> { static <Msg> defaults() }``
    when at least one field carries ``rac_default``. Repeated fields are
    skipped (Dart returns the empty list, never null)."""
    assignments: list[tuple[str, str]] = []
    for field in msg_desc.field:
        if field.label == LABEL_REPEATED:
            continue
        if not field.HasField("options"):
            continue
        default_str = _get_string_opt(field.options, RAC_DEFAULT_FIELD_NUM)
        if default_str is None:
            continue
        wants64 = [False]
        literal = _dart_default_literal(field, default_str, wants64)
        if literal is None:
            continue
        if wants64[0]:
            int64_used[0] = True
        if field.type == TYPE_ENUM:
            enum_name = _simple_type_name(field.type_name)
            src = enum_file_map.get(enum_name)
            if src is not None:
                enum_imports.add(src)
        dart_name = _snake_to_lower_camel(field.name)
        assignments.append((dart_name, literal))

    if not assignments:
        return None

    lines: list[str] = []
    lines.append(f"extension {msg_name}Convenience on {msg_name} {{")
    lines.append(f"  static {msg_name} defaults() {{")
    lines.append(f"    final r = {msg_name}();")
    for name, literal in assignments:
        lines.append(f"    r.{name} = {literal};")
    lines.append("    return r;")
    lines.append("  }")
    lines.append("}")
    return "\n".join(lines)


def _required_zero_check_expr(field, dart_name: str, int64_used: list[bool]) -> str | None:
    """Return the Dart expression that detects the proto3-zero value for a
    required field, or ``None`` for unsupported types (skip the check)."""
    t = field.type
    if t == TYPE_STRING:
        return f"{dart_name}.isEmpty"
    if t == TYPE_BOOL:
        # A required bool field is ill-defined in proto3 (default 0 == false
        # is the only sentinel and "false" may be a meaningful value); skip.
        return None
    if t in _INT32_TYPES:
        return f"{dart_name} == 0"
    if t in _INT64_TYPES:
        int64_used[0] = True
        return f"{dart_name} == Int64(0)"
    if t in _FLOAT_TYPES:
        return f"{dart_name} == 0"
    if t == TYPE_ENUM:
        enum_type = _simple_type_name(field.type_name)
        # The proto3 zero value for an enum is the constant numbered 0,
        # conventionally the "<ENUM>_UNSPECIFIED" member. The Dart plugin
        # exposes ``ProtobufEnum.value`` as int.
        return f"{dart_name}.value == 0"
    return None


def _emit_message_validate(
    msg_name: str,
    msg_desc: descriptor_pb2.DescriptorProto,
    int64_used: list[bool],
) -> str | None:
    """Emit ``extension <Msg>Validate on <Msg> { void validate() }`` when at
    least one field carries a validation annotation."""
    checks: list[str] = []
    for field in msg_desc.field:
        if field.label == LABEL_REPEATED:
            continue
        if not field.HasField("options"):
            continue
        dart_name = _snake_to_lower_camel(field.name)

        field_path = f"{msg_name}.{field.name}"
        field_path_escaped = _escape_dart_string(field_path)

        is_required = _get_bool_opt(field.options, RAC_REQUIRED_FIELD_NUM)
        if is_required:
            expr = _required_zero_check_expr(field, dart_name, int64_used)
            if expr is not None:
                msg = _escape_dart_string(f"{field.name} is required")
                checks.append(f"    if ({expr}) {{")
                checks.append("      throw SDKException.validationFailed(")
                checks.append(f"        '{msg}',")
                checks.append(f"        fieldPath: '{field_path_escaped}',")
                checks.append("      );")
                checks.append("    }")

        min_int = _get_int32_opt(field.options, RAC_MIN_FIELD_NUM)
        max_int = _get_int32_opt(field.options, RAC_MAX_FIELD_NUM)
        if (min_int is not None or max_int is not None) and field.type in _INTEGER_TYPES:
            is64 = field.type in _INT64_TYPES
            if is64:
                int64_used[0] = True
            def lit(v: int) -> str:
                return f"Int64({v})" if is64 else str(v)
            parts: list[str] = []
            if min_int is not None:
                parts.append(f"{dart_name} < {lit(min_int)}")
            if max_int is not None:
                parts.append(f"{dart_name} > {lit(max_int)}")
            cond = " || ".join(parts)
            if min_int is not None and max_int is not None:
                range_desc = f"{min_int}...{max_int}"
            elif min_int is not None:
                range_desc = f">= {min_int}"
            else:
                range_desc = f"<= {max_int}"
            msg_prefix = _escape_dart_string(f"{field.name} must be in {range_desc} (got ")
            checks.append(f"    if ({cond}) {{")
            checks.append("      throw SDKException.validationFailed(")
            checks.append(f"        '{msg_prefix}${dart_name})',")
            checks.append(f"        fieldPath: '{field_path_escaped}',")
            checks.append("      );")
            checks.append("    }")

        min_f = _get_double_opt(field.options, RAC_MIN_FLOAT_FIELD_NUM)
        max_f = _get_double_opt(field.options, RAC_MAX_FLOAT_FIELD_NUM)
        if (min_f is not None or max_f is not None) and field.type in _FLOAT_TYPES:
            parts = []
            if min_f is not None:
                parts.append(f"{dart_name} < {min_f}")
            if max_f is not None:
                parts.append(f"{dart_name} > {max_f}")
            cond = " || ".join(parts)
            if min_f is not None and max_f is not None:
                range_desc = f"{min_f}...{max_f}"
            elif min_f is not None:
                range_desc = f">= {min_f}"
            else:
                range_desc = f"<= {max_f}"
            msg_prefix = _escape_dart_string(f"{field.name} must be in {range_desc} (got ")
            checks.append(f"    if ({cond}) {{")
            checks.append("      throw SDKException.validationFailed(")
            checks.append(f"        '{msg_prefix}${dart_name})',")
            checks.append(f"        fieldPath: '{field_path_escaped}',")
            checks.append("      );")
            checks.append("    }")

    if not checks:
        return None

    lines: list[str] = []
    lines.append(f"extension {msg_name}Validate on {msg_name} {{")
    lines.append("  void validate() {")
    lines.extend(checks)
    lines.append("  }")
    lines.append("}")
    return "\n".join(lines)


# --- Top-level driver ------------------------------------------------------

def _format_import_block(
    enum_imports: set[str],
    message_imports: set[str],
    extra_imports: list[str],
) -> list[str]:
    """Return a single alphabetically-sorted block of Dart imports.

    The Dart ``directives_ordering`` lint expects ``package:`` directives to
    be sorted alphabetically by URI, regardless of whether each one targets a
    ``.pb.dart`` or ``.pbenum.dart`` file. We therefore merge every URI into
    a single list and sort, rather than emitting two separate blocks."""
    uris: list[str] = list(extra_imports)
    for base in message_imports:
        uris.append(
            f"package:{DART_PACKAGE_NAME}/{GENERATED_SUBDIR}/{base}.pb.dart"
        )
    for base in enum_imports:
        uris.append(
            f"package:{DART_PACKAGE_NAME}/{GENERATED_SUBDIR}/{base}.pbenum.dart"
        )
    return [f"import '{uri}';" for uri in sorted(set(uris))]


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root  = script_dir.parent.parent
    proto_dir  = repo_root / "idl"
    out_dir    = (
        repo_root
        / "sdk" / "runanywhere-flutter" / "packages" / "runanywhere"
        / "lib" / GENERATED_SUBDIR / CONVENIENCE_SUBDIR
    )
    out_path   = out_dir / OUTPUT_FILE_NAME

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

    enum_file_map = _build_enum_file_map(fds)

    blocks: list[str] = []
    enum_imports: set[str] = set()
    message_imports: set[str] = set()
    int64_used: list[bool] = [False]
    validate_emitted = False
    enum_block_count = 0
    defaults_count = 0
    validate_count = 0

    for file_desc in fds.file:
        if file_desc.package != PROTO_PACKAGE:
            continue

        base = _proto_basename(file_desc)
        file_added_enum_import = False
        file_added_message_import = False

        for enum_desc in file_desc.enum_type:
            enum_name = enum_desc.name
            local_blocks: list[str] = []
            for suffix, getter, fn in (
                ("WireString",   "wireString",   RAC_WIRE_STRING_FIELD_NUM),
                ("DisplayName",  "displayName",  RAC_DISPLAY_NAME_FIELD_NUM),
                ("AnalyticsKey", "analyticsKey", RAC_ANALYTICS_KEY_FIELD_NUM),
            ):
                b = _emit_enum_extension(enum_name, enum_desc, suffix, getter, fn)
                if b is not None:
                    local_blocks.append(b)
                    enum_block_count += 1

            reverse = _emit_enum_reverse_factory(
                enum_name, enum_desc, RAC_WIRE_STRING_FIELD_NUM,
            )
            if reverse is not None:
                local_blocks.append(reverse)

            if local_blocks:
                blocks.extend(local_blocks)
                if not file_added_enum_import:
                    enum_imports.add(base)
                    file_added_enum_import = True

        for msg_desc in file_desc.message_type:
            msg_name = msg_desc.name
            defaults_block = _emit_message_defaults(
                msg_name, msg_desc, enum_file_map,
                int64_used, enum_imports,
            )
            if defaults_block is not None:
                blocks.append(defaults_block)
                defaults_count += 1
                if not file_added_message_import:
                    message_imports.add(base)
                    file_added_message_import = True

            validate_block = _emit_message_validate(msg_name, msg_desc, int64_used)
            if validate_block is not None:
                blocks.append(validate_block)
                validate_count += 1
                validate_emitted = True
                if not file_added_message_import:
                    message_imports.add(base)
                    file_added_message_import = True

    # When a message-import covers the same base as an enum-import, drop the
    # redundant enum import: the .pb.dart file re-exports its .pbenum.dart.
    enum_imports_final = {b for b in enum_imports if b not in message_imports}

    header_lines: list[str] = [
        "// GENERATED by idl/codegen/generate_dart_convenience.py — DO NOT EDIT.",
        "//",
        "// Convenience accessors derived from RunAnywhere's custom proto",
        "// annotations (see idl/rac_options.proto):",
        "//   - wireString getter / <enumName>FromWireString reverse factory",
        "//                              (rac_wire_string)",
        "//   - displayName getter       (rac_display_name)",
        "//   - analyticsKey getter      (rac_analytics_key)",
        "//   - defaults() factory       (rac_default)",
        "//   - validate()               (rac_required / rac_min / rac_max /",
        "//                              rac_min_float / rac_max_float)",
        "",
        "// ignore_for_file: prefer_const_constructors, unnecessary_this",
        "// ignore_for_file: constant_identifier_names, non_constant_identifier_names",
        "",
    ]

    extra_uris: list[str] = []
    if int64_used[0]:
        extra_uris.append("package:fixnum/fixnum.dart")
    if validate_emitted:
        extra_uris.append(
            f"package:{DART_PACKAGE_NAME}/foundation/errors/sdk_exception.dart"
        )

    pkg_imports = _format_import_block(enum_imports_final, message_imports, extra_uris)

    if pkg_imports:
        header_lines.extend(pkg_imports)
        header_lines.append("")
        header_lines.append("")

    if blocks:
        body_text = "\n\n".join(blocks)
    else:
        body_text = (
            "// (Currently empty: no proto in idl/ has adopted rac_* annotations\n"
            "// yet — file kept as a placeholder so the import path stays stable.)"
        )

    content = "\n".join(header_lines) + body_text + "\n"
    out_path.write_text(content, encoding="utf-8")

    print(f"✓ Dart convenience post-processor → {out_path}")
    print(f"  enum accessor blocks:    {enum_block_count}")
    print(f"  message defaults blocks: {defaults_count}")
    print(f"  message validate blocks: {validate_count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
