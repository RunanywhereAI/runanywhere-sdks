#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Swift modality-ABI codegen.
#
# Phase 4 / P4-T11 of the Swift simplification plan: read the manifest at
# scripts/codegen/swift-modality-abi.yaml (P4-T10) and emit a Swift file containing
# the codegen-eligible methods (invoke + stream kinds where the hand-written
# Swift body is a 1:1 wrapper around the C ABI). The 18 methods tagged
# `kind: custom` and the 17 facade methods tagged `keep_handwritten: true` stay
# hand-written in CppBridge+ModalityProtoABI.swift.
#
# Output:
#   sdk/runanywhere-swift/Sources/RunAnywhere/Generated/ModalityProtoABI+Generated.swift
#
# Phase B simplification (B2 + B3): the generated file is now emitted directly
# onto `extension CppBridge.<Modality>` (no parallel `CppBridge_Generated`
# wrapper). Dlsym tables drop the `v2` suffix and own the C symbols outright;
# the hand-written `+ModalityProtoABI.swift` deletes its corresponding tables
# and method bodies for the 7 fully-equivalent methods. The shared `ProtoStream*`
# scaffolding (trampoline / yielder / context / runRequestStream) is canonical
# in the hand-written file — the generated file references those types
# instead of re-declaring its own private copies.
#
# Special cases:
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
        "scripts/setup/setup-toolchain.sh.\n"
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

# ----------------------------------------------------------------------------
# Per-stream cancel closures (mirrors the hand-written `onCancel:` in
# CppBridge+ModalityProtoABI.swift). Keyed by c_symbol. When set, the
# generated stream method passes the closure to `runRequestStream(onCancel:)`
# so consumer cancellation (`AsyncStream` termination = .cancelled) tears down
# the native producer.
#
# LLM + StructuredOutput both route through the lifecycle-LLM cancel symbol
# `rac_llm_cancel_proto` (parameter-less, proto-out — the result is discarded
# here because the consumer has already cancelled). STT/TTS streams are
# session-id-owned; the session handle isn't visible at this layer, so we
# emit an empty closure that satisfies the parameter contract while leaving
# the session to be torn down by `runRequestStream`'s native unwind.
STREAM_ON_CANCEL_FACTORIES: dict[str, str] = {
    "rac_llm_generate_stream_proto": """{
                var outBuffer = rac_proto_buffer_t()
                defer { NativeProtoABI.free(&outBuffer) }
                _ = rac_llm_cancel_proto(&outBuffer)
            }""",
    "rac_structured_output_generate_stream_proto": """{
                var outBuffer = rac_proto_buffer_t()
                defer { NativeProtoABI.free(&outBuffer) }
                _ = rac_llm_cancel_proto(&outBuffer)
            }""",
    "rac_stt_transcribe_stream_lifecycle_proto": """{
                // STT stream cancellation is session-id-owned (see
                // rac_stt_stream_cancel_proto). The session handle is not
                // visible from this scope; the native producer unwinds when
                // the C call returns after `isCancelled` flips.
            }""",
    "rac_tts_synthesize_stream_lifecycle_proto": """{
                // TTS stream cancellation is session-id-owned (see
                // rac_tts_stream_cancel_proto). The session handle is not
                // visible from this scope; the native producer unwinds when
                // the C call returns after `isCancelled` flips.
            }""",
}

# ----------------------------------------------------------------------------
# Manifest helpers


def is_codegen_eligible(method: dict[str, Any]) -> bool:
    """Codegen handles every kind except `custom`. Phase C adds 4 new kinds
    (getWithContext, voidCall, createHandle, invokeOutOnly) to the original
    two (invoke, stream). `keep_handwritten: true` is a sub-filter applied
    later — those methods are still tagged with a real kind so the manifest
    captures their ABI shape, but Swift codegen skips them (they retain a
    hand-written facade in CppBridge+ModalityProtoABI.swift)."""
    return method.get("kind") in {
        "invoke",
        "stream",
        "getWithContext",
        "voidCall",
        "createHandle",
        "invokeOutOnly",
    }


def should_emit(method: dict[str, Any]) -> bool:
    """Emit only when codegen-eligible AND not flagged `keep_handwritten: true`."""
    if not is_codegen_eligible(method):
        return False
    return not bool(method.get("keep_handwritten"))


def first_arg_label(method: dict[str, Any]) -> str:
    """Default `_` (positional/unlabeled first arg)."""
    return method.get("swift_first_arg_label") or "_"


def first_arg_name(method: dict[str, Any]) -> str:
    """Default `request`."""
    return method.get("swift_first_arg_name") or "request"


def first_arg_clause(method: dict[str, Any], type_name: str) -> str:
    """Render the first-arg declaration: `label name: Type` or `_ name: Type`."""
    label = first_arg_label(method)
    name = first_arg_name(method)
    if label == name:
        return f"{label}: {type_name}"
    return f"{label} {name}: {type_name}"


def visibility(method: dict[str, Any]) -> str:
    return method.get("swift_visibility") or "public"


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
// Covers {method_count} codegen-emitted methods across {modality_count} modality
// entries. The remaining `kind: custom` entries stay hand-written in
// CppBridge+ModalityProtoABI.swift.
//
// Phase B (aggressive): emits proto-first APIs directly onto
// `extension CppBridge.<Modality>`. Callers thread the handle (or request
// proto) explicitly — no facade variants exist. Shared scaffolding types
// (ProtoStreamYielder, protoStreamTrampoline, ProtoStreamContext,
// runRequestStream) live in the hand-written `+ModalityProtoABI.swift` and
// are reused here.
//
// Phase C: adds 4 new render kinds — getWithContext (handle+out -> proto),
// voidCall (handle[+req] -> rc only), createHandle (req -> new handle),
// invokeOutOnly (no req, no handle, out -> proto). Migrated 11 of the 18
// former custom entries onto these new templates.

import CRACommons
import Foundation
import SwiftProtobuf

// MARK: - Generated C symbol tables

"""


# ----------------------------------------------------------------------------
# Per-modality dlsym table


def render_generated_enum(modality: dict[str, Any]) -> str:
    """Emit a private dlsym table for one modality's emitted methods.

    Stream entries get a stream-shaped function-pointer typealias; invoke
    entries reuse the shared `NativeProtoABI.ProtoRequest` typealias for
    context-less calls or a fresh function-pointer typealias for
    context-threaded ones.

    Returns "" if the modality has no emitted methods (e.g. all flagged
    `keep_handwritten: true`).
    """
    name = modality["name"]
    methods = [m for m in modality.get("methods", []) if should_emit(m)]
    if not methods:
        return ""

    enum_name = f"{name}GeneratedProtoABI"

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
            # Stream functions take (bytes, size, callback, userData) and
            # use the canonical hand-written `@convention(c)` callback shape.
            type_lines.append(
                f"    typealias {type_alias} = @convention(c) (\n"
                f"        UnsafePointer<UInt8>?,\n"
                f"        Int,\n"
                f"        @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?) -> Void,\n"
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
        elif kind == "getWithContext":
            # (Ctx handle, outBuffer*) -> rc
            type_lines.append(
                f"    typealias {type_alias} = @convention(c) (\n"
                f"        {context}?,\n"
                f"        UnsafeMutablePointer<rac_proto_buffer_t>?\n"
                f"    ) -> rac_result_t"
            )
        elif kind == "voidCall":
            # Two shapes:
            #   - (Ctx handle) -> rc                                  [no request]
            #   - (Ctx handle, const uint8_t* bytes, size_t size) -> rc [with request]
            if method.get("request"):
                type_lines.append(
                    f"    typealias {type_alias} = @convention(c) (\n"
                    f"        {context}?,\n"
                    f"        UnsafePointer<UInt8>?,\n"
                    f"        Int\n"
                    f"    ) -> rac_result_t"
                )
            else:
                type_lines.append(
                    f"    typealias {type_alias} = @convention(c) ({context}?) -> rac_result_t"
                )
        elif kind == "createHandle":
            # (bytes, size, outHandle*) -> rc
            out_handle = method.get("output_handle", "rac_handle_t")
            type_lines.append(
                f"    typealias {type_alias} = @convention(c) (\n"
                f"        UnsafePointer<UInt8>?,\n"
                f"        Int,\n"
                f"        UnsafeMutablePointer<{out_handle}?>?\n"
                f"    ) -> rac_result_t"
            )
        elif kind == "invokeOutOnly":
            # (outBuffer*) -> rc -- no request, no context
            type_lines.append(
                f"    typealias {type_alias} = @convention(c) (\n"
                f"        UnsafeMutablePointer<rac_proto_buffer_t>?\n"
                f"    ) -> rac_result_t"
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
    enum_ref = f"{name}GeneratedProtoABI"
    swift = method["swift_name"]
    request_proto = method.get("request")
    response_proto = method.get("response")
    context = method.get("context")
    is_static = bool(method.get("static"))

    # Visibility / static-ness. Methods without `static: true` become instance
    # methods on the actor/enum extension (matching the hand-written shape).
    vis = visibility(method)
    keyword = f"{vis} static func" if is_static else f"{vis} func"

    if context:
        # Context-threaded invocation: `(handle:, request:)` shape. The handle
        # is always a leading labeled argument; the second arg respects
        # `swift_first_arg_label` / `swift_first_arg_name` overrides.
        second = first_arg_clause(method, request_proto)
        head = (
            f"    {keyword} {swift}(handle: {context}, {second}) "
            f"throws -> {response_proto} {{"
        )
    else:
        first = first_arg_clause(method, request_proto)
        head = (
            f"    {keyword} {swift}({first}) "
            f"throws -> {response_proto} {{"
        )

    request_var = first_arg_name(method)

    body_lines: list[str] = []
    if context:
        body_lines.append("        return try NativeProtoABI.invoke(")
        body_lines.append(f"            {request_var},")
        body_lines.append("            on: handle,")
        body_lines.append(f"            symbol: {enum_ref}.{swift},")
        body_lines.append(f"            symbolName: {enum_ref}.{swift}Name,")
        body_lines.append(f"            responseType: {response_proto}.self")
        body_lines.append("        )")
    else:
        body_lines.append("        return try NativeProtoABI.invoke(")
        body_lines.append(f"            {request_var},")
        body_lines.append(f"            symbol: {enum_ref}.{swift},")
        body_lines.append(f"            symbolName: {enum_ref}.{swift}Name,")
        body_lines.append(f"            responseType: {response_proto}.self")
        body_lines.append("        )")

    body_lines.append("    }")
    return head + "\n" + "\n".join(body_lines)


def render_stream_method(modality: dict[str, Any], method: dict[str, Any]) -> str:
    name = modality["name"]
    enum_ref = f"{name}GeneratedProtoABI"
    swift = method["swift_name"]
    c_symbol = method["c_symbol"]
    request_proto = method.get("request")
    response_proto = method.get("response")
    is_static = bool(method.get("static"))

    factory = STREAM_ON_ERROR_FACTORIES.get(c_symbol)
    if factory is None:
        on_error_clause = ""
    else:
        on_error_clause = f"\n            onError: {factory},"

    # pass3-syn-038: every stream method must emit an `onCancel:` closure so
    # consumer cancellation tears down the native producer. Per-method bodies
    # live in STREAM_ON_CANCEL_FACTORIES; methods without an entry fall
    # through to an empty closure so the parameter contract is still
    # satisfied (no special-case handling at the call site).
    cancel_factory = STREAM_ON_CANCEL_FACTORIES.get(c_symbol)
    if cancel_factory is None:
        on_cancel_clause = "\n            onCancel: { },"
    else:
        on_cancel_clause = f"\n            onCancel: {cancel_factory},"

    vis = visibility(method)
    keyword = f"{vis} static func" if is_static else f"{vis} func"
    # Category mirrors the hand-written file: `CppBridge.<Name>.ProtoStream`
    # (no `Generated` suffix anymore — the hand-written copy was deleted).
    category = f"CppBridge.{name}.ProtoStream"

    first = first_arg_clause(method, request_proto)
    head = (
        f"    {keyword} {swift}({first}) throws "
        f"-> AsyncStream<{response_proto}> {{"
    )

    request_var = first_arg_name(method)

    body = f"""
        let stream = try NativeProtoABI.require(
            {enum_ref}.{swift},
            named: {enum_ref}.{swift}Name
        )
        return try ProtoStreamContext<{response_proto}>.runRequestStream(
            request: {request_var},
            category: "{category}",{on_error_clause}{on_cancel_clause}
            body: {{ bytes, size, trampoline, userData in
                stream(bytes, size, trampoline, userData)
            }}
        )
    }}"""

    return head + body


# ----------------------------------------------------------------------------
# Phase C — 4 new render functions
#
# Each emits a method onto the modality's extension. None of these go through
# the higher-level `NativeProtoABI.invoke` helpers because the ABI shapes
# differ; the proto-buffer / handle / void dance is inlined directly using
# only the primitive helpers (`require`, `withSerializedBytes`, `decode`,
# `free`, `canReceiveProtoBuffer`, `missingSymbolMessage`).


def render_get_with_context_method(
    modality: dict[str, Any], method: dict[str, Any]
) -> str:
    """getWithContext: `(Ctx handle, outBuffer*) -> rc` -> Response.

    Generated Swift signature:
        public func <name>(handle: Ctx) throws -> Response
    """
    name = modality["name"]
    enum_ref = f"{name}GeneratedProtoABI"
    swift = method["swift_name"]
    response_proto = method["response"]
    context = method["context"]
    is_static = bool(method.get("static"))
    vis = visibility(method)
    keyword = f"{vis} static func" if is_static else f"{vis} func"

    head = (
        f"    {keyword} {swift}(handle: {context}) "
        f"throws -> {response_proto} {{"
    )

    body = f"""
        let symbol = try NativeProtoABI.require(
            {enum_ref}.{swift},
            named: {enum_ref}.{swift}Name
        )
        var outBuffer = rac_proto_buffer_t()
        defer {{ NativeProtoABI.free(&outBuffer) }}
        let status = symbol(handle, &outBuffer)
        guard status == RAC_SUCCESS else {{
            let message = outBuffer.error_message.map {{ String(cString: $0) }}
                ?? "Native proto request failed: \\({enum_ref}.{swift}Name) rc=\\(status)"
            throw SDKException(code: .processingFailed, message: message, category: .internal)
        }}
        return try NativeProtoABI.decode({response_proto}.self, from: outBuffer)
    }}"""

    return head + body


def render_void_call_method(
    modality: dict[str, Any], method: dict[str, Any]
) -> str:
    """voidCall: `(Ctx handle) -> rc` or `(Ctx handle, bytes, size) -> rc`.

    Generated Swift signature (no request):
        public func <name>(handle: Ctx) throws
    Generated Swift signature (with request):
        public func <name>(handle: Ctx, request: Request) throws
    """
    name = modality["name"]
    enum_ref = f"{name}GeneratedProtoABI"
    swift = method["swift_name"]
    request_proto = method.get("request")
    context = method["context"]
    is_static = bool(method.get("static"))
    vis = visibility(method)
    keyword = f"{vis} static func" if is_static else f"{vis} func"

    error_code = method.get("error_code", "processingFailed")
    error_category = method.get("error_category", "internal")
    error_prefix = method.get("error_message_prefix", f"{swift} failed")

    if request_proto:
        # With request bytes
        second = first_arg_clause(method, request_proto)
        request_var = first_arg_name(method)
        head = (
            f"    {keyword} {swift}(handle: {context}, {second}) "
            f"throws {{"
        )
        body = f"""
        let symbol = try NativeProtoABI.require(
            {enum_ref}.{swift},
            named: {enum_ref}.{swift}Name
        )
        let status = try NativeProtoABI.withSerializedBytes({request_var}) {{ bytes, size in
            symbol(handle, bytes, size)
        }}
        guard status == RAC_SUCCESS else {{
            throw SDKException(code: .{error_code}, message: "{error_prefix}: \\(status)", category: .{error_category})
        }}
    }}"""
    else:
        # Handle-only
        head = f"    {keyword} {swift}(handle: {context}) throws {{"
        body = f"""
        let symbol = try NativeProtoABI.require(
            {enum_ref}.{swift},
            named: {enum_ref}.{swift}Name
        )
        let status = symbol(handle)
        guard status == RAC_SUCCESS else {{
            throw SDKException(code: .{error_code}, message: "{error_prefix}: \\(status)", category: .{error_category})
        }}
    }}"""

    return head + body


def render_create_handle_method(
    modality: dict[str, Any], method: dict[str, Any]
) -> str:
    """createHandle: `(bytes, size, outHandle*) -> rc` -> Ctx.

    Generated Swift signature:
        public func <name>(request: Request) throws -> OutputHandle
    """
    name = modality["name"]
    enum_ref = f"{name}GeneratedProtoABI"
    swift = method["swift_name"]
    request_proto = method["request"]
    out_handle = method.get("output_handle", "rac_handle_t")
    is_static = bool(method.get("static"))
    vis = visibility(method)
    keyword = f"{vis} static func" if is_static else f"{vis} func"

    error_code = method.get("error_code", "processingFailed")
    error_category = method.get("error_category", "internal")
    error_prefix = method.get("error_message_prefix", f"{swift} failed")

    first = first_arg_clause(method, request_proto)
    request_var = first_arg_name(method)

    head = (
        f"    {keyword} {swift}({first}) throws -> {out_handle} {{"
    )
    body = f"""
        let symbol = try NativeProtoABI.require(
            {enum_ref}.{swift},
            named: {enum_ref}.{swift}Name
        )
        var newHandle: {out_handle}?
        let status = try NativeProtoABI.withSerializedBytes({request_var}) {{ bytes, size in
            symbol(bytes, size, &newHandle)
        }}
        guard status == RAC_SUCCESS, let newHandle else {{
            throw SDKException(code: .{error_code}, message: "{error_prefix}: \\(status)", category: .{error_category})
        }}
        return newHandle
    }}"""

    return head + body


def render_invoke_out_only_method(
    modality: dict[str, Any], method: dict[str, Any]
) -> str:
    """invokeOutOnly: `(outBuffer*) -> rc` -> Response. No context, no request.

    Generated Swift signature:
        public func <name>() throws -> Response
    """
    name = modality["name"]
    enum_ref = f"{name}GeneratedProtoABI"
    swift = method["swift_name"]
    response_proto = method["response"]
    is_static = bool(method.get("static"))
    vis = visibility(method)
    keyword = f"{vis} static func" if is_static else f"{vis} func"

    head = (
        f"    {keyword} {swift}() throws -> {response_proto} {{"
    )
    body = f"""
        let symbol = try NativeProtoABI.require(
            {enum_ref}.{swift},
            named: {enum_ref}.{swift}Name
        )
        var outBuffer = rac_proto_buffer_t()
        defer {{ NativeProtoABI.free(&outBuffer) }}
        let status = symbol(&outBuffer)
        guard status == RAC_SUCCESS else {{
            let message = outBuffer.error_message.map {{ String(cString: $0) }}
                ?? "Native proto request failed: \\({enum_ref}.{swift}Name) rc=\\(status)"
            throw SDKException(code: .processingFailed, message: message, category: .internal)
        }}
        return try NativeProtoABI.decode({response_proto}.self, from: outBuffer)
    }}"""

    return head + body


# ----------------------------------------------------------------------------
# Top-level rendering per modality


def render_modality_methods(modality: dict[str, Any]) -> str:
    name = modality["name"]
    extension = modality.get("extension", "")
    methods = [m for m in modality.get("methods", []) if should_emit(m)]
    if not methods:
        return ""

    def dispatch(method: dict[str, Any]) -> str:
        kind = method["kind"]
        if kind == "invoke":
            return render_invoke_method(modality, method)
        if kind == "stream":
            return render_stream_method(modality, method)
        if kind == "getWithContext":
            return render_get_with_context_method(modality, method)
        if kind == "voidCall":
            return render_void_call_method(modality, method)
        if kind == "createHandle":
            return render_create_handle_method(modality, method)
        if kind == "invokeOutOnly":
            return render_invoke_out_only_method(modality, method)
        raise ValueError(f"unsupported kind: {kind} for {method.get('swift_name')!r}")

    if extension == "":
        # File-level free functions (RAGFreeFunctions).
        free_funcs: list[str] = []
        for method in methods:
            rendered = dispatch(method)
            # Strip the leading 4-space indentation that the extension renderers
            # emit so the free-function reads at file scope.
            if rendered.startswith("    "):
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

    # Emit directly into the real `extension CppBridge.<Modality>`. The hand-
    # written `+ModalityProtoABI.swift` has dropped its corresponding method
    # bodies, so there is no longer a duplicate-declaration risk.
    rendered_methods: list[str] = [dispatch(method) for method in methods]

    out_lines = [
        f"// MARK: - {name}",
        "",
        f"extension {extension} {{",
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
        emitted = [m for m in modality.get("methods", []) if should_emit(m)]
        if not emitted:
            continue
        method_count += len(emitted)
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
