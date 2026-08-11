"""Map the public option dataclasses onto the native bridge's keyword arguments.

The bridge (``native/module.cpp``) accepts a subset of the spec's knobs. Fields it cannot
carry are never silently dropped: setting one raises ``SDKException.not_implemented`` naming
the bridge parameter that is missing, so a caller is never told a knob took effect when it
did not.

Structured JSON Schema is forwarded as typed ``StructuredOutputOptions`` for commons to
compile to GBNF — this bridge never hosts a schema→grammar compiler.
"""

from __future__ import annotations

import json
from typing import Any, Optional

from .errors import SDKException
from .options import (
    EmbedOptions,
    LlmOptions,
    PoolingMode,
    ReasoningMode,
    SttOptions,
    TtsOptions,
)

__all__ = [
    "check_embed_options",
    "check_stt_options",
    "check_tts_options",
    "llm_kwargs",
    "wants_thoughts",
]

# Fields with no slot in rac_llm_options_t as bound by native/module.cpp's `generate`.
_UNBOUND_LLM_FIELDS = {
    "min_p": "min_p",
    "frequency_penalty": "frequency_penalty",
    "presence_penalty": "presence_penalty",
    "repetition_penalty": "repetition_penalty",
    "seed": "seed",
}


def _reject(field: str, parameter: str) -> None:
    raise SDKException.not_implemented(
        f"{field}: the Python bridge's generate() has no {parameter} parameter "
        "(native/module.cpp binds max_tokens/temperature/top_p/top_k/system_prompt/"
        "structured_schema/disable_thinking only)"
    )


def _schema_json(schema: Any) -> str:
    """Serialize a public JSON-schema value for ``StructuredOutputOptions.schema``."""
    if isinstance(schema, str):
        return schema
    return json.dumps(schema, separators=(",", ":"), ensure_ascii=False)


def llm_kwargs(options: Optional[LlmOptions], *, vlm: bool = False) -> dict:
    """Build the ``_core.generate`` / proto-stream keyword arguments for ``options``.

    Raises:
        SDKException: an option is set that the bridge cannot carry.
    """
    if options is None:
        options = LlmOptions()
    for field, parameter in _UNBOUND_LLM_FIELDS.items():
        if getattr(options, field) is not None:
            _reject(field, parameter)

    kwargs: dict = {
        "max_tokens": options.max_output_tokens,
        "temperature": options.temperature,
        "top_p": options.top_p,
    }
    if options.top_k is not None:
        kwargs["top_k"] = options.top_k
    if options.system_prompt is not None:
        kwargs["system_prompt"] = options.system_prompt

    reasoning = options.reasoning
    if reasoning is not None:
        if reasoning.pattern is not None:
            _reject("reasoning.pattern", "thinking-tag pattern")
        if reasoning.mode == ReasoningMode.OFF:
            kwargs["disable_thinking"] = True

    structured = options.structured_output
    if structured is not None:
        if vlm:
            raise SDKException.not_implemented(
                "structured_output on vlm: the bridge's generate_vlm() has no "
                "StructuredOutputOptions parameter"
            )
        if not structured.strict:
            raise SDKException.not_implemented(
                "structured_output.strict=False: only constrained decoding "
                "(StructuredOutputMode.CONSTRAINED) is exposed on this bridge"
            )
        # Commons owns schema→GBNF; pass the typed schema arm only.
        kwargs["structured_schema"] = _schema_json(structured.schema)
    return kwargs


def wants_thoughts(options: Optional[LlmOptions]) -> bool:
    """True when the caller asked for thought tokens in the output."""
    return bool(options and options.reasoning and options.reasoning.include_in_output)


def check_stt_options(options: Optional[SttOptions]) -> None:
    """Reject transcription knobs the bridge cannot carry.

    Raises:
        SDKException: an unsupported option is set.
    """
    if options is None:
        return
    if options.language is not None:
        raise SDKException.not_implemented(
            "SttOptions.language: the bridge's transcribe() takes audio only and binds no "
            "rac_stt_options_t (rac_stt_component_transcribe_proto is not exposed)"
        )
    if not options.punctuation:
        raise SDKException.not_implemented(
            "SttOptions.punctuation=False: the bridge binds no rac_stt_options_t"
        )
    if options.diarization:
        raise SDKException.not_implemented(
            "SttOptions.diarization: the bridge binds no rac_stt_options_t and no "
            "rac_diarization_component_diarize_proto"
        )
    if options.max_speakers is not None:
        raise SDKException.not_implemented("SttOptions.max_speakers: the bridge binds no rac_stt_options_t")
    if options.translate_to_english:
        raise SDKException.not_implemented(
            "SttOptions.translate_to_english: the bridge binds no rac_stt_options_t"
        )


def check_tts_options(options: Optional[TtsOptions]) -> None:
    """Reject synthesis knobs the bridge cannot carry.

    Raises:
        SDKException: an unsupported option is set.
    """
    if options is None:
        return
    if options.speed != 1.0:
        raise SDKException.not_implemented(
            "TtsOptions.speed: the bridge's synthesize() takes text only and binds no "
            "rac_tts_options_t (rac_tts_component_synthesize_proto is not exposed)"
        )
    if options.pitch != 1.0:
        raise SDKException.not_implemented(
            "TtsOptions.pitch: the bridge binds no rac_tts_options_t"
        )


def check_embed_options(options: Optional[EmbedOptions]) -> None:
    """Reject embedding knobs the bridge cannot carry.

    Raises:
        SDKException: an unsupported option is set.
    """
    if options is None:
        return
    if not options.normalize:
        raise SDKException.not_implemented(
            "EmbedOptions.normalize: the bridge's embed() returns L2-normalized vectors and "
            "binds no rac_embeddings_options_t"
        )
    if options.pooling != PoolingMode.MEAN:
        raise SDKException.not_implemented(
            "EmbedOptions.pooling: the bridge binds no rac_embeddings_options_t"
        )
