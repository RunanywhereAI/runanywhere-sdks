#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Dart ABI result-code emitter.
#
# The Flutter SDK marshals `rac_result_t` across dart:ffi, where the C ABI
# returns the canonical idl/errors.proto codes negated. It had transcribed 125 of
# those numbers by hand into `RacResultCode` in lib/native/types/basic_types.dart
# under a comment describing itself as "only the ABI sign-convention boundary" —
# which is what it should have been, and 125 hand-copied integers is not that.
#
# Why generate rather than derive at runtime:
#
#   - `Pointer.fromFunction(..., exceptionalReturn:)` demands a compile-time
#     constant, and a ProtobufEnum's `.value` is a field read, so
#     `static final int x = -ErrorCode.X.value` fails to compile there.
#   - `switch` cases need constants for the same reason.
#   - Enum *names* can be stripped at build time via
#     `--define=protobuf.omit_enum_names=true`, so deriving human-readable
#     messages from `.name` at runtime would silently yield empty strings.
#
# Generating sidesteps all three: the output is plain `const int` literals plus a
# switch over them, and the message strings are humanized here, at codegen time.
#
# Output:
#   bindings/flutter/packages/runanywhere/lib/generated/ra_result_codes.dart

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

OUT_RELPATH = Path(
    "bindings/flutter/packages/runanywhere/lib/generated/ra_result_codes.dart"
)
ENUM_NAME = "ErrorCode"

# Words that should not be title-cased into something odd when a constant name is
# turned into a message. Everything else follows "first word capitalized".
ACRONYMS = {
    "abi": "ABI",
    "api": "API",
    "cpu": "CPU",
    "gpu": "GPU",
    "http": "HTTP",
    "io": "I/O",
    "json": "JSON",
    "llm": "LLM",
    "npu": "NPU",
    "sdk": "SDK",
    "stt": "STT",
    "tts": "TTS",
    "url": "URL",
    "uuid": "UUID",
    "vad": "VAD",
    "vlm": "VLM",
    "wasm": "WASM",
}


def dart_member(enum_value_name: str) -> str:
    """ERROR_CODE_FILE_NOT_FOUND -> errorFileNotFound; ERROR_CODE_SUCCESS -> success."""
    prefix = enum_name_to_screaming_snake(ENUM_NAME) + "_"
    body = enum_value_name[len(prefix):] if enum_value_name.startswith(prefix) else enum_value_name
    parts = [p for p in body.lower().split("_") if p]
    if not parts:
        return "success"
    # rac_result_t 0 is success. The proto spells that slot UNSPECIFIED because
    # proto3 requires a zero enumerator; on the ABI it means the call succeeded,
    # so the Dart member keeps the name the call sites already use.
    if parts in (["success"], ["unspecified"]):
        return "success"
    camel = parts[0] + "".join(p.capitalize() for p in parts[1:])
    return "error" + camel[0].upper() + camel[1:]


def dart_message(enum_value_name: str) -> str:
    """ERROR_CODE_FILE_NOT_FOUND -> 'File not found'."""
    prefix = enum_name_to_screaming_snake(ENUM_NAME) + "_"
    body = enum_value_name[len(prefix):] if enum_value_name.startswith(prefix) else enum_value_name
    parts = [p for p in body.lower().split("_") if p]
    if not parts or parts in (["success"], ["unspecified"]):
        return "Success"
    words = [ACRONYMS.get(p, p) for p in parts]
    first = words[0]
    if first not in ACRONYMS.values():
        first = first.capitalize()
    return " ".join([first] + words[1:])


def collect(fds: descriptor_pb2.FileDescriptorSet) -> list[tuple[str, int, str, str]]:
    """Return [(dart_member, abi_value, message, proto_name)] in declaration order."""
    for file_desc in iter_runanywhere_files(fds):
        if file_desc.name != "errors.proto":
            continue
        for enum_name, enum_desc in iter_top_level_enums(file_desc):
            if enum_name != ENUM_NAME:
                continue
            out: list[tuple[str, int, str, str]] = []
            seen: set[str] = set()
            for value in enum_desc.value:
                member = dart_member(value.name)
                if member in seen:
                    print(
                        f"note: skipping duplicate Dart member {member} "
                        f"from {value.name}",
                        file=sys.stderr,
                    )
                    continue
                seen.add(member)
                # Success is 0; every failure is returned negated by the C ABI.
                abi = 0 if value.number == 0 else -value.number
                out.append((member, abi, dart_message(value.name), value.name))
            return out
    return []


def render(entries: list[tuple[str, int, str, str]]) -> str:
    lines: list[str] = []
    lines.append("// GENERATED FILE — DO NOT EDIT.")
    lines.append("// Regenerate with: idl/codegen/generate_dart_result_codes.py")
    lines.append("//")
    lines.append("// The C ABI returns idl/errors.proto codes negated as rac_result_t. These are")
    lines.append("// the negated values, emitted as `const` so they can be used as `switch` cases")
    lines.append("// and as `Pointer.fromFunction(exceptionalReturn:)` arguments, neither of which")
    lines.append("// accepts a value read from a ProtobufEnum at runtime.")
    lines.append("")
    lines.append("/// Result codes matching rac_error.h, generated from idl/errors.proto.")
    lines.append("abstract final class RacResultCodes {")
    width = max(len(m) for m, _, _, _ in entries)
    for member, abi, _, proto_name in entries:
        lines.append(f"  static const int {member.ljust(width)} = {abi};  // {proto_name}")
    lines.append("")
    lines.append("  /// Human-readable label for a rac_result_t.")
    lines.append("  ///")
    lines.append("  /// Strings are built at codegen time rather than from ProtobufEnum names,")
    lines.append("  /// which a build can strip with --define=protobuf.omit_enum_names=true.")
    lines.append("  static String message(int code) {")
    lines.append("    switch (code) {")
    for member, _, message, _ in entries:
        lines.append(f"      case {member}:")
        lines.append(f"        return '{message}';")
    lines.append("      default:")
    lines.append("        return 'Unknown error (code: $code)';")
    lines.append("    }")
    lines.append("  }")
    lines.append("}")
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

    entries = collect(fds)
    if not entries:
        print(f"error: {ENUM_NAME} not found in errors.proto", file=sys.stderr)
        return 1

    out_path = repo_root / OUT_RELPATH
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render(entries), encoding="utf-8")
    print(f"✓ Dart result codes → {out_path.relative_to(repo_root)} ({len(entries)} codes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
