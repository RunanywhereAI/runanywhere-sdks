#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Shared building blocks for the per-language convenience post-processors:
#
#   - generate_swift_convenience.py
#   - generate_kotlin_convenience.py
#   - generate_dart_convenience.py   (forthcoming)
#   - generate_ts_convenience.py     (forthcoming)
#
# All four generators consume `idl/rac_options.proto` annotations off a
# `FileDescriptorSet` produced by `protoc --include_imports` and emit
# language-native `defaults() / validate() / wireString / fromWireString`
# helpers. The descriptor walk, wire-format readers, naming utilities, and
# default-literal translation are language-agnostic and live here; the
# per-language emitters compose them with their own output formatting.
#
# Verification stamps for every shared helper live in
# scripts/codegen/CONVENIENCE_CODEGEN_DESIGN.md (Section 6).

from __future__ import annotations

import os
import struct
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Optional

from google.protobuf import descriptor_pb2

# ---------------------------------------------------------------------------
# RunAnywhere proto-annotation field numbers (mirror idl/rac_options.proto).
# ---------------------------------------------------------------------------

RAC_DEFAULT_FIELD_NUM       = 50001
RAC_REQUIRED_FIELD_NUM      = 50002
RAC_MIN_FIELD_NUM           = 50004
RAC_MAX_FIELD_NUM           = 50005
RAC_MIN_FLOAT_FIELD_NUM     = 50006
RAC_MAX_FLOAT_FIELD_NUM     = 50007
RAC_DISPLAY_NAME_FIELD_NUM  = 50010
RAC_ANALYTICS_KEY_FIELD_NUM = 50011
RAC_WIRE_STRING_FIELD_NUM   = 50012

RUNANYWHERE_PACKAGE = "runanywhere.v1"

# ---------------------------------------------------------------------------
# Proto wire-format type enums (mirror google/protobuf/descriptor.proto).
# ---------------------------------------------------------------------------

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

INTEGER_TYPES = frozenset((
    TYPE_INT32, TYPE_INT64, TYPE_UINT32, TYPE_UINT64,
    TYPE_FIXED32, TYPE_FIXED64, TYPE_SFIXED32, TYPE_SFIXED64,
    TYPE_SINT32, TYPE_SINT64,
))
FLOAT_TYPES = frozenset((TYPE_DOUBLE, TYPE_FLOAT))
INT64_TYPES = frozenset((
    TYPE_INT64, TYPE_UINT64, TYPE_FIXED64, TYPE_SFIXED64, TYPE_SINT64,
))


def annotation_name(field_num: int) -> str:
    """Human-readable label for an `idl/rac_options.proto` extension field
    number. Used by emitters when documenting generated code."""
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


# ---------------------------------------------------------------------------
# Minimal proto wire-format reader. Only exercises the few fields we care
# about; unknown wire types are skipped while keeping the cursor in bounds.
# ---------------------------------------------------------------------------

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
    """Yield (field_number, wire_type, payload) tuples. Wire types we don't
    decode (1 / 5) advance the cursor without yielding so the scan stays
    aligned for later fields the caller might still want."""
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
            # SGROUP / EGROUP — not used in proto3, skip silently.
            pass


def _decode_string_field(buf: bytes, field_num: int) -> Optional[str]:
    for fn, wt, payload in _scan_fields(buf):
        if fn == field_num and wt == 2:
            return payload.decode("utf-8")
    return None


def _decode_bool_field(buf: bytes, field_num: int) -> Optional[bool]:
    for fn, wt, payload in _scan_fields(buf):
        if fn == field_num and wt == 0:
            return bool(payload)
    return None


def _decode_int32_field(buf: bytes, field_num: int) -> Optional[int]:
    for fn, wt, payload in _scan_fields(buf):
        if fn == field_num and wt == 0:
            v = int(payload) & 0xFFFFFFFF
            if v & 0x80000000:
                v -= 0x100000000
            return v
    return None


def _decode_double_field(buf: bytes, field_num: int) -> Optional[float]:
    """Read a proto3 double (wire type 1 = fixed64). The shared scanner
    skips 64-bit payloads, so this walks the buffer with a richer loop."""
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


# ---------------------------------------------------------------------------
# Annotation extraction. The protobuf python runtime can't always resolve
# our extensions through the typed accessors (no compiled extension
# registry on the codegen path), so we go through the raw serialized form.
# ---------------------------------------------------------------------------

def get_string_option(opts, field_num: int) -> Optional[str]:
    return _decode_string_field(opts.SerializeToString(), field_num)


def get_bool_option(opts, field_num: int) -> Optional[bool]:
    return _decode_bool_field(opts.SerializeToString(), field_num)


def get_int32_option(opts, field_num: int) -> Optional[int]:
    return _decode_int32_field(opts.SerializeToString(), field_num)


def get_double_option(opts, field_num: int) -> Optional[float]:
    return _decode_double_field(opts.SerializeToString(), field_num)


# ---------------------------------------------------------------------------
# Descriptor build & walk.
# ---------------------------------------------------------------------------

def build_descriptor_set(proto_dir: Path, proto_files: list[Path]) -> Path:
    """Invoke protoc to produce a FileDescriptorSet covering all idl/*.proto.
    Caller is responsible for unlinking the returned path."""
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


def load_file_descriptor_set(proto_dir: Path) -> Optional[descriptor_pb2.FileDescriptorSet]:
    """Build the descriptor set for every `*.proto` in `proto_dir` and return
    the parsed `FileDescriptorSet`, or `None` when the directory is empty."""
    proto_files = sorted(proto_dir.glob("*.proto"))
    if not proto_files:
        return None
    set_path = build_descriptor_set(proto_dir, proto_files)
    try:
        fds = descriptor_pb2.FileDescriptorSet()
        fds.ParseFromString(set_path.read_bytes())
        return fds
    finally:
        try:
            set_path.unlink()
        except OSError:
            pass


def iter_runanywhere_files(
    fds: descriptor_pb2.FileDescriptorSet,
) -> Iterator[descriptor_pb2.FileDescriptorProto]:
    """Yield only the schemas RunAnywhere owns; skips Google's transitive
    `descriptor.proto` and any other imported third-party schemas."""
    for f in fds.file:
        if f.package == RUNANYWHERE_PACKAGE:
            yield f


def iter_top_level_enums(
    file_desc: descriptor_pb2.FileDescriptorProto,
) -> list[tuple[str, descriptor_pb2.EnumDescriptorProto]]:
    """Top-level enums only — nested enums use a different language-side
    name path and are out of scope for the first cut. Mirrors the Swift
    generator's `_collect_top_level_enums`."""
    return [(e.name, e) for e in file_desc.enum_type]


def iter_top_level_messages(
    file_desc: descriptor_pb2.FileDescriptorProto,
) -> list[tuple[str, descriptor_pb2.DescriptorProto]]:
    return [(m.name, m) for m in file_desc.message_type]


# ---------------------------------------------------------------------------
# Naming utilities. The Swift rules below mirror apple/swift-protobuf's
# NamingUtils.toLowerCamelCase so the convenience emitter matches the
# message types swift-protobuf actually generates. The other languages
# either keep proto SCREAMING_SNAKE verbatim (Kotlin enum constants) or
# go through `proto_field_to_camel` (Dart / TS field accessors).
# ---------------------------------------------------------------------------

def camel_case_from_snake(s: str) -> str:
    """Convert UPPER_SNAKE / lower_snake to lowerCamelCase, mirroring
    apple/swift-protobuf's NamingUtils.toLowerCamelCase behaviour.

    Hand-tested against the swift-protobuf-generated case names in
    `model_types.pb.swift` for: ``m4A``, ``pcmS16Le``, ``llamaCpp``,
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
                j = i
                while j < n and s[j].isupper():
                    j += 1
                run = s[i:j]
                if j < n and s[j].islower():
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
                    if first:
                        out.append(run.lower())
                        first = False
                    else:
                        out.append(run[:1].upper() + run[1:].lower())
                    i = j
            else:
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


def enum_name_to_screaming_snake(name: str) -> str:
    """Convert PascalCase enum name to SCREAMING_SNAKE prefix form, the way
    swift-protobuf strips enum-name prefixes from its constant cases:
        ExecutionTarget    -> EXECUTION_TARGET
        STTLanguage        -> STT_LANGUAGE
        LLMGenerationState -> LLM_GENERATION_STATE
    """
    out_chars: list[str] = []
    for i, ch in enumerate(name):
        if i > 0 and ch.isupper():
            prev = name[i - 1]
            nxt = name[i + 1] if i + 1 < len(name) else ""
            if (not prev.isupper()) or (prev.isupper() and nxt.islower()):
                out_chars.append("_")
        out_chars.append(ch.upper())
    return "".join(out_chars)


def swift_enum_case(enum_name: str, value_name: str) -> str:
    """swift-protobuf's enum-value naming. Strips the enum-name prefix in
    SCREAMING_SNAKE form, then lowerCamelCases the remainder."""
    prefix = enum_name_to_screaming_snake(enum_name) + "_"
    remainder = value_name
    if value_name.startswith(prefix):
        remainder = value_name[len(prefix):]
    return camel_case_from_snake(remainder)


def proto_field_to_camel(field_name: str, *, id_uppercase: bool = False) -> str:
    """Proto snake_case field names map to lowerCamelCase via the same
    rules as enum values (with first-word lowercase). When `id_uppercase`
    is set the trailing ``Id`` token is uppercased to ``ID`` to match
    swift-protobuf's struct-field convention (`model_id` -> `modelID`).
    Other languages (Dart's protoc_plugin, ts-proto) leave it as ``Id``;
    pass `id_uppercase=False` for those.
    """
    base = camel_case_from_snake(field_name)
    if id_uppercase and base.endswith("Id") and not base.endswith("UUID") and not base.endswith("Uid"):
        return base[:-2] + "ID"
    return base


def ts_proto_function_prefix(symbol: str) -> str:
    """ts-proto's first-character-lowercased helper-naming rule:
        STTLanguage    -> sTTLanguage
        AudioFormat    -> audioFormat
        RAGConfig      -> rAGConfig
    Verified against `audioFormatFromJSON` (model_types.ts:47) and
    `sTTLanguageFromJSON` (stt_options.ts:58)."""
    if not symbol:
        return symbol
    return symbol[0].lower() + symbol[1:]


# ---------------------------------------------------------------------------
# Default-literal translation. Each language passes a `LangProfile` that
# captures its dialect-specific suffixes/wrappers. Enum cases are looked
# up via a per-language `enum_case_map` built by `build_enum_case_map`.
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class LangProfile:
    """Per-language dialect for `to_default_literal`.

    Attributes:
        int64_wrapper: Optional callable-style wrapper for int64 literals
            (e.g. ``"Int64"`` -> ``Int64(16000)``, ``"Long.fromNumber"`` ->
            ``Long.fromNumber(16000)``). When ``None`` the literal is
            emitted as a bare integer with `int64_suffix` appended.
        int64_suffix: Suffix appended to bare int64 literals (Kotlin uses
            ``"L"``; Swift / Dart / TS use ``""``).
        float_suffix: Suffix appended to TYPE_FLOAT literals only (Kotlin
            uses ``"f"``; Swift / Dart / TS use ``""``). TYPE_DOUBLE is
            always emitted bare.
    """
    int64_wrapper: Optional[str] = None
    int64_suffix: str = ""
    float_suffix: str = ""


SWIFT_PROFILE  = LangProfile(int64_wrapper=None,             int64_suffix="",  float_suffix="")
KOTLIN_PROFILE = LangProfile(int64_wrapper=None,             int64_suffix="L", float_suffix="f")
# Dart's protoc_plugin generates int64 fields as ``Int64`` from the
# ``fixnum`` package — callers must wrap literal integer values rather
# than emit a bare ``L``/``int64`` suffix. TYPE_DOUBLE and TYPE_FLOAT are
# both Dart ``double`` (no float suffix).
DART_PROFILE   = LangProfile(int64_wrapper="Int64",          int64_suffix="",  float_suffix="")
# ts-proto emits int64 as JS ``number`` by default (the project does not
# enable the ``Long`` runtime), so bare integer literals are correct.
# TypeScript has no float suffix — TYPE_FLOAT and TYPE_DOUBLE are both
# ``number``.
TS_PROFILE     = LangProfile(int64_wrapper=None,             int64_suffix="",  float_suffix="")


def build_enum_case_map(
    fds: descriptor_pb2.FileDescriptorSet,
    profile_kind: str,
) -> dict[str, str]:
    """Return a dict mapping ``"EnumName.PROTO_CONSTANT_NAME"`` to the
    language-native case literal for a `rac_default = "PROTO_CONSTANT"`
    annotation on an enum-typed field.

    `profile_kind`:
      - ``"swift"``: ``.case`` (type-relative, swift-protobuf naming).
      - ``"kotlin"`` / ``"dart"`` / ``"ts"``: ``EnumName.PROTO_CONSTANT``.

    Walks every top-level enum in every `runanywhere.v1` file plus
    every nested-in-message enum.
    """
    out: dict[str, str] = {}

    def emit(enum_name: str, value_name: str) -> str:
        if profile_kind == "swift":
            return "." + swift_enum_case(enum_name, value_name)
        return f"{enum_name}.{value_name}"

    for file_desc in iter_runanywhere_files(fds):
        for e in file_desc.enum_type:
            for v in e.value:
                out[f"{e.name}.{v.name}"] = emit(e.name, v.name)
        for msg in file_desc.message_type:
            for e in msg.enum_type:
                for v in e.value:
                    out[f"{e.name}.{v.name}"] = emit(e.name, v.name)
    return out


def zero_literal_for_required(
    field: descriptor_pb2.FieldDescriptorProto,
    profile: LangProfile,
) -> Optional[str]:
    """Return the language-typed proto3 zero literal for a numeric scalar field,
    or ``None`` when the field's type is not a scalar number (caller should
    skip the required-check or handle it specially).

    Used by per-language ``validate()`` emitters when they need to compare an
    INT64 / INT32 / FLOAT / DOUBLE field against its proto3 zero. Kotlin in
    particular MUST emit ``0L`` for Long fields (``Long == Int`` is
    structurally false) and ``0.0f`` for Float fields, so a generic ``== 0``
    silently neuters required-checks on those types. Swift / Dart / TS use a
    bare ``0`` here because their scalar arithmetic is structurally unified.
    """
    t = field.type
    if t in INTEGER_TYPES:
        if t in INT64_TYPES:
            if profile.int64_wrapper:
                return f"{profile.int64_wrapper}(0)"
            return f"0{profile.int64_suffix}"
        return "0"
    if t in FLOAT_TYPES:
        if t == TYPE_FLOAT:
            return f"0.0{profile.float_suffix}"
        return "0.0"
    return None


def to_default_literal(
    field: descriptor_pb2.FieldDescriptorProto,
    default_str: str,
    enum_case_map: dict[str, str],
    profile: LangProfile,
) -> Optional[str]:
    """Translate the string form of `rac_default` into a language-native
    literal for the given field. Returns `None` when the type isn't
    supported (caller should skip emission for that field)."""
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
    if t in INTEGER_TYPES:
        try:
            n = int(default_str)
        except ValueError:
            return None
        if t in INT64_TYPES:
            if profile.int64_wrapper:
                return f"{profile.int64_wrapper}({n})"
            return f"{n}{profile.int64_suffix}"
        return str(n)
    if t in FLOAT_TYPES:
        try:
            v = float(default_str)
        except ValueError:
            return None
        text = repr(v)
        if "." not in text and "e" not in text and "E" not in text:
            text += ".0"
        if t == TYPE_FLOAT:
            text += profile.float_suffix
        return text
    if t == TYPE_ENUM:
        # rac_default for an enum field MUST be the proto constant name.
        enum_type = field.type_name.split(".")[-1]
        return enum_case_map.get(f"{enum_type}.{default_str.strip()}")
    return None
