#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Swift modality-ABI codegen.
#
# Phase 4 / P4-T11 of the Swift simplification plan: read the manifest at
# idl/codegen/swift-modality-abi.yaml (P4-T10) and emit a Swift file containing
# the 24 codegen-eligible methods (invoke + stream kinds). The 18 methods tagged
# `kind: custom` cannot be expressed by the helper variants below and stay
# hand-written in CppBridge+ModalityProtoABI.swift.
#
# Output:
#   sdk/runanywhere-swift/Sources/RunAnywhere/Generated/ModalityProtoABI+Generated.swift
#
# The generated file lives under Generated/ (clearly marked auto-generated) and
# coexists with the hand-written CppBridge+ModalityProtoABI.swift during P4-T11
# / P4-T12 validation. To avoid method-name collisions while both files coexist,
# all generated methods are emitted into a parallel namespace:
#
#     enum CppBridge_Generated { enum LLM { static func generate(...) ... } }
#
# P4-T13 will:
#   * Delete the hand-written CppBridge+ModalityProtoABI.swift's invoke/stream
#     methods.
#   * Strip the `CppBridge_Generated` namespace wrapper and emit straight into
#     `extension CppBridge.LLM { ... }` etc. so the public API surface is
#     unchanged.
#
# This file's generated methods accept handles as explicit parameters (since
# they live outside the actor and can't call `getHandle()`). After P4-T13's
# swap, the regenerated file will reside on the actor extensions and call
# `getHandle()` directly. For P4-T11 we only need a SHAPE check.
#
# Special cases:
#   * `resolveRAGConfigurationDefaults` is optional-when-unsupported: returns
#     `nil` instead of throwing when the symbol is missing.
#   * Each `kind: stream` entry has its own terminal-event factory keyed by
#     c_symbol (see STREAM_ON_ERROR_FACTORIES).
#
# Invoked by generate_swift.sh AFTER swift-protobuf has produced the *.pb.swift
# files, so the RA*-prefixed type names are already known to exist.

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

try:
    import yaml  # PyYAML
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "error: PyYAML not installed. Run "
        "`python3 -m pip install pyyaml` or use the toolchain installed by "
        "scripts/setup-toolchain.sh.\n"
    )
    sys.exit(127)

# ----------------------------------------------------------------------------
# Paths

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
MANIFEST_PATH = SCRIPT_DIR / "swift-modality-abi.yaml"
OUTPUT_PATH = (
    REPO_ROOT
    / "sdk"
    / "runanywhere-swift"
    / "Sources"
    / "RunAnywhere"
    / "Generated"
    / "ModalityProtoABI+Generated.swift"
)

# ----------------------------------------------------------------------------
# Per-stream terminal-event factories (mirrors the hand-written `onError:`
# closures in CppBridge+ModalityProtoABI.swift). Keyed by c_symbol.

STREAM_ON_ERROR_FACTORIES: dict[str, str] = {
    "rac_llm_generate_stream_proto": """{ rc in
                let mapped = RASDKError.from(rcResult: rc)
                var event = RALLMStreamEvent()
                event.isFinal = true
                event.finishReason = "error"
                event.errorCode = rc
                event.errorMessage = mapped?.message ?? "LLM stream failed: \\(rc)"
                return event
            }""",
    "rac_structured_output_generate_stream_proto": """{ rc in
                var event = RAStructuredOutputStreamEvent()
                event.kind = .error
                event.errorMessage = "Structured output stream failed: \\(rc)"
                return event
            }""",
    "rac_stt_transcribe_stream_lifecycle_proto": """{ rc in
                var final = RASTTPartialResult()
                final.isFinal = true
                final.text = "STT stream failed: \\(rc)"
                return final
            }""",
    "rac_tts_synthesize_stream_lifecycle_proto": """{ _ in
                var output = RATTSOutput()
                output.timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
                return output
            }""",
}

# Symbols that map a Swift facade method to a request-helper-build wrapper. The
# hand-written facade builds the request proto out of audio/text + options
# arguments before calling the C symbol. For codegen we keep the standard
# `(_ request:)` shape -- callers compose the proto themselves -- so these
# bullet notes from the manifest are informational only.

# ----------------------------------------------------------------------------
# Manifest helpers


def is_codegen_eligible(method: dict[str, Any]) -> bool:
    """Only invoke + stream kinds are emitted by this generator. The 18
    `custom` methods stay hand-written."""
    return method.get("kind") in {"invoke", "stream"}


def to_typealias_name(swift_name: str) -> str:
    """Generate a unique typealias name within a generated-enum scope.

    Result is `<PascalSwiftName>Fn`. Eg. `generate` -> `GenerateFn`."""
    head = swift_name[:1].upper() + swift_name[1:]
    return f"{head}Fn"


# ----------------------------------------------------------------------------
# Header banner


def render_header(modality_count: int, method_count: int) -> str:
    return f"""// DO NOT EDIT.
// swift-format-ignore-file
// swiftlint:disable all
//
// Generated by idl/codegen/generate_swift_modality_abi.py from the manifest at
// idl/codegen/swift-modality-abi.yaml.
//
// Covers {method_count} codegen-eligible invoke/stream methods across
// {modality_count} modality entries. The 18 entries tagged `kind: custom` in
// the manifest stay hand-written in CppBridge+ModalityProtoABI.swift.
//
// P4-T11: emit this file alongside the hand-written companion for shape
// inspection. All methods are routed through a parallel `CppBridge_Generated`
// namespace so the file COMPILES alongside the existing
// `extension CppBridge.LLM` / `extension CppBridge.STT` / etc. without
// duplicate-declaration errors.
//
// P4-T13: drop the `CppBridge_Generated` namespace wrapper, swap the file
// into `extension CppBridge.<Modality>` and delete the hand-written copy.

import CRACommons
import Foundation
import SwiftProtobuf

// MARK: - Top-level namespace for generated methods

/// Parallel namespace that mirrors `CppBridge.<Modality>` so generated methods
/// can coexist with the hand-written ones during P4-T11 validation. After
/// P4-T13 the contents move into the corresponding `extension CppBridge.<Modality>`
/// and this enum disappears.
enum CppBridge_Generated {{
    enum LLM {{}}
    enum StructuredOutput {{}}
    enum STT {{}}
    enum TTS {{}}
    enum VAD {{}}
    enum VoiceAgent {{}}
    enum VLM {{}}
    enum EmbeddingsProto {{}}
    enum RAG {{}}
    enum LoraRegistry {{}}
}}

// MARK: - Shared scaffolding (generated copy)
//
// Local copies of the proto-stream callback shape and the
// `ProtoStreamContext.runRequestStream` helper so this file compiles standalone
// alongside the hand-written file (whose copies are `private`). P4-T13 drops
// these and reuses the hand-written companions.

private typealias ProtoStreamCallbackGenerated = @convention(c) (
    UnsafePointer<UInt8>?,
    Int,
    UnsafeMutableRawPointer?
) -> Void

private protocol ProtoStreamYielderGenerated: AnyObject {{
    func yield(bytes: UnsafePointer<UInt8>?, size: Int)
}}

private let protoStreamTrampolineGenerated: @convention(c) (
    UnsafePointer<UInt8>?,
    Int,
    UnsafeMutableRawPointer?
) -> Void = {{ bytes, size, userData in
    guard let userData else {{ return }}
    let yielder = Unmanaged<AnyObject>.fromOpaque(userData).takeUnretainedValue()
    (yielder as? ProtoStreamYielderGenerated)?.yield(bytes: bytes, size: size)
}}

private final class ProtoStreamContextGenerated<Event: Message>: @unchecked Sendable, ProtoStreamYielderGenerated {{
    let continuation: AsyncStream<Event>.Continuation
    let logger: SDKLogger

    init(continuation: AsyncStream<Event>.Continuation, category: String) {{
        self.continuation = continuation
        self.logger = SDKLogger(category: category)
    }}

    func yield(bytes: UnsafePointer<UInt8>?, size: Int) {{
        guard let bytes, size > 0 else {{ return }}
        do {{
            let event = try Event(serializedBytes: Data(bytes: bytes, count: size))
            continuation.yield(event)
        }} catch {{
            logger.warning("Failed to decode proto stream event: \\(error.localizedDescription)")
        }}
    }}

    static func runRequestStream<Request: Message>(
        request: Request,
        category: String,
        onError: (@Sendable (rac_result_t) -> Event?)? = nil,
        body: @escaping @Sendable (
            UnsafePointer<UInt8>?,
            Int,
            @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?) -> Void,
            UnsafeMutableRawPointer
        ) -> rac_result_t
    ) throws -> AsyncStream<Event> {{
        let requestData = try request.serializedData()
        return AsyncStream {{ continuation in
            let context = ProtoStreamContextGenerated<Event>(
                continuation: continuation,
                category: category
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            Task.detached {{
                let rc = requestData.withUnsafeBytes {{ rawBuffer in
                    body(
                        rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                        rawBuffer.count,
                        protoStreamTrampolineGenerated,
                        contextPtr
                    )
                }}
                Unmanaged<ProtoStreamContextGenerated<Event>>
                    .fromOpaque(contextPtr)
                    .release()
                if rc != RAC_SUCCESS, let terminal = onError?(rc) {{
                    continuation.yield(terminal)
                }}
                continuation.finish()
            }}
        }}
    }}
}}

// MARK: - Generated C symbol tables

"""


# ----------------------------------------------------------------------------
# Per-modality dlsym table


def render_generated_enum(modality: dict[str, Any]) -> str:
    """Emit a private dlsym table for one modality's invoke + stream entries.

    Stream entries get a stream-shaped function-pointer typealias; invoke
    entries reuse the shared `NativeProtoABI.ProtoRequest` typealias for
    context-less calls or a fresh function-pointer typealias for
    context-threaded ones.
    """
    name = modality["name"]
    methods = [m for m in modality.get("methods", []) if is_codegen_eligible(m)]
    if not methods:
        return ""

    suffix = "GeneratedProtoABIv2"
    enum_name = f"{name}{suffix}"

    lines: list[str] = []
    lines.append(f"private enum {enum_name} {{")

    type_lines: list[str] = []
    name_lines: list[str] = []
    load_lines: list[str] = []

    for method in methods:
        swift = method["swift_name"]
        c_symbol = method["c_symbol"]
        kind = method["kind"]
        context = method.get("context")
        type_alias = to_typealias_name(swift)

        if kind == "stream":
            type_lines.append(
                f"    typealias {type_alias} = @convention(c) (\n"
                f"        UnsafePointer<UInt8>?,\n"
                f"        Int,\n"
                f"        ProtoStreamCallbackGenerated?,\n"
                f"        UnsafeMutableRawPointer?\n"
                f"    ) -> rac_result_t"
            )
        elif kind == "invoke":
            if context:
                type_lines.append(
                    f"    typealias {type_alias} = @convention(c) (\n"
                    f"        {context}?,\n"
                    f"        UnsafePointer<UInt8>?,\n"
                    f"        Int,\n"
                    f"        UnsafeMutablePointer<rac_proto_buffer_t>?\n"
                    f"    ) -> rac_result_t"
                )
            else:
                type_lines.append(
                    f"    typealias {type_alias} = NativeProtoABI.ProtoRequest"
                )

        name_lines.append(f'    static let {swift}Name = "{c_symbol}"')
        load_lines.append(
            f"    static let {swift} = NativeProtoABI.load({swift}Name, as: {type_alias}.self)"
        )

    lines.extend(type_lines)
    lines.append("")
    lines.extend(name_lines)
    lines.append("")
    lines.extend(load_lines)
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


# ----------------------------------------------------------------------------
# Per-method body templates


def render_invoke_method(modality: dict[str, Any], method: dict[str, Any]) -> str:
    name = modality["name"]
    enum_ref = f"{name}GeneratedProtoABIv2"
    swift = method["swift_name"]
    c_symbol = method["c_symbol"]
    request_proto = method.get("request")
    response_proto = method.get("response")
    context = method.get("context")
    is_static = bool(method.get("static"))
    async_handle = bool(method.get("async_handle"))

    # Special case: optional-when-unsupported (RAGFreeFunctions only).
    if c_symbol == "rac_rag_request_with_defaults_proto":
        return _render_optional_freefunc(enum_ref, swift, request_proto, response_proto)

    # Function head. Generated methods accept the handle (if any) as an
    # explicit first parameter so they're callable from outside the actor
    # extensions. P4-T13 will replace this with `try getHandle()` inside the
    # actor.
    keyword = "static func" if is_static else "static func"
    throws = "async throws" if async_handle else "throws"

    if context:
        head = (
            f"    {keyword} {swift}(handle: {context}, request: {request_proto}) "
            f"{throws} -> {response_proto} {{"
        )
    else:
        head = (
            f"    {keyword} {swift}(request: {request_proto}) "
            f"{throws} -> {response_proto} {{"
        )

    body_lines: list[str] = []
    if context:
        body_lines.append("        return try NativeProtoABI.invoke(")
        body_lines.append("            request,")
        body_lines.append("            on: handle,")
        body_lines.append(f"            symbol: {enum_ref}.{swift},")
        body_lines.append(f"            symbolName: {enum_ref}.{swift}Name,")
        body_lines.append(f"            responseType: {response_proto}.self")
        body_lines.append("        )")
    else:
        body_lines.append("        return try NativeProtoABI.invoke(")
        body_lines.append("            request,")
        body_lines.append(f"            symbol: {enum_ref}.{swift},")
        body_lines.append(f"            symbolName: {enum_ref}.{swift}Name,")
        body_lines.append(f"            responseType: {response_proto}.self")
        body_lines.append("        )")

    body_lines.append("    }")
    return head + "\n" + "\n".join(body_lines)


def _render_optional_freefunc(
    enum_ref: str, swift: str, request_proto: str, response_proto: str
) -> str:
    """Optional-when-unsupported free function: returns nil instead of throwing.

    Mirrors the hand-written `resolveRAGConfigurationDefaults`. Suffixed with
    `_generated` to avoid collision with the hand-written top-level function
    of the same name.
    """
    return (
        f"func {swift}_generated(_ request: {request_proto}) -> {response_proto}? {{\n"
        f"    guard let symbol = {enum_ref}.{swift} else {{\n"
        f"        return nil\n"
        f"    }}\n"
        f"    return try? NativeProtoABI.invoke(\n"
        f"        request,\n"
        f"        symbol: symbol,\n"
        f"        symbolName: {enum_ref}.{swift}Name,\n"
        f"        responseType: {response_proto}.self\n"
        f"    )\n"
        f"}}"
    )


def render_stream_method(modality: dict[str, Any], method: dict[str, Any]) -> str:
    name = modality["name"]
    enum_ref = f"{name}GeneratedProtoABIv2"
    swift = method["swift_name"]
    c_symbol = method["c_symbol"]
    request_proto = method.get("request")
    response_proto = method.get("response")

    factory = STREAM_ON_ERROR_FACTORIES.get(c_symbol)
    if factory is None:
        on_error_clause = ""
    else:
        on_error_clause = f"\n            onError: {factory},"

    keyword = "static func"
    category = f"CppBridge.{name}.ProtoStreamGenerated"

    head = (
        f"    {keyword} {swift}(request: {request_proto}) throws "
        f"-> AsyncStream<{response_proto}> {{"
    )

    body = f"""
        let stream = try NativeProtoABI.require(
            {enum_ref}.{swift},
            named: {enum_ref}.{swift}Name
        )
        return try ProtoStreamContextGenerated<{response_proto}>.runRequestStream(
            request: request,
            category: "{category}",{on_error_clause}
            body: {{ bytes, size, trampoline, userData in
                stream(bytes, size, trampoline, userData)
            }}
        )
    }}"""

    return head + body


# ----------------------------------------------------------------------------
# Top-level rendering per modality


def render_modality_methods(modality: dict[str, Any]) -> str:
    name = modality["name"]
    extension = modality.get("extension", "")
    methods = [m for m in modality.get("methods", []) if is_codegen_eligible(m)]
    if not methods:
        return ""

    # Decide which Generated sub-namespace to use. The YAML's `extension`
    # field encodes the hand-written extension target (eg. `CppBridge.LLM`,
    # `CppBridge.EmbeddingsProto`, or "" for top-level free functions).
    # For the LoRA modality it's `CppBridge.LLM` -- so LoRA methods also
    # live on `CppBridge_Generated.LLM`. For the empty string we emit
    # file-level free functions.

    if extension == "":
        # File-level free functions (RAGFreeFunctions).
        free_funcs: list[str] = []
        for method in methods:
            if method["kind"] == "invoke":
                rendered = render_invoke_method(modality, method)
                if rendered.startswith("    "):
                    rendered = "\n".join(
                        line[4:] if line.startswith("    ") else line
                        for line in rendered.splitlines()
                    )
                free_funcs.append(rendered)
            elif method["kind"] == "stream":  # pragma: no cover - none today
                rendered = render_stream_method(modality, method)
                rendered = "\n".join(
                    line[4:] if line.startswith("    ") else line
                    for line in rendered.splitlines()
                )
                free_funcs.append(rendered)

        out_lines: list[str] = []
        out_lines.append(f"// MARK: - {name}")
        out_lines.append("")
        out_lines.append("\n\n".join(free_funcs))
        out_lines.append("")
        return "\n".join(out_lines)

    # Map `CppBridge.LLM` -> `CppBridge_Generated.LLM`, etc.
    if not extension.startswith("CppBridge."):
        # Shouldn't happen with the current YAML, but be defensive.
        sub_namespace = extension
    else:
        sub_namespace = "CppBridge_Generated." + extension[len("CppBridge."):]

    rendered_methods: list[str] = []
    for method in methods:
        if method["kind"] == "invoke":
            rendered_methods.append(render_invoke_method(modality, method))
        elif method["kind"] == "stream":
            rendered_methods.append(render_stream_method(modality, method))

    out_lines = [
        f"// MARK: - {name}",
        "",
        f"extension {sub_namespace} {{",
        "\n\n".join(rendered_methods),
        "}",
        "",
    ]
    return "\n".join(out_lines)


# ----------------------------------------------------------------------------
# Driver


def main() -> int:
    if not MANIFEST_PATH.exists():
        sys.stderr.write(f"error: manifest not found at {MANIFEST_PATH}\n")
        return 1

    with MANIFEST_PATH.open("r", encoding="utf-8") as fh:
        manifest = yaml.safe_load(fh)

    modalities = manifest.get("modalities") or []
    method_count = 0
    enum_blocks: list[str] = []
    method_blocks: list[str] = []
    for modality in modalities:
        eligible = [m for m in modality.get("methods", []) if is_codegen_eligible(m)]
        if not eligible:
            continue
        method_count += len(eligible)
        enum_blocks.append(render_generated_enum(modality))
        method_blocks.append(render_modality_methods(modality))

    output_parts: list[str] = []
    output_parts.append(
        render_header(modality_count=len(modalities), method_count=method_count)
    )
    output_parts.extend(enum_blocks)
    output_parts.extend(method_blocks)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text("\n".join(output_parts), encoding="utf-8")

    rel = OUTPUT_PATH.relative_to(REPO_ROOT)
    print(f"GENERATED {rel} ({method_count} methods across {len(modalities)} modalities)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
