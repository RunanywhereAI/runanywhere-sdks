"""Decode commons ``LLMStreamEvent`` bytes into typed generation pieces."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterator, List, Optional, Tuple

from ._generation import StreamDelta, UsageMetrics
from .results import FinishReason


@dataclass
class StreamTerminal:
    """Terminal fields from a commons COMPLETED ``LLMStreamEvent``."""

    finish_reason: FinishReason = FinishReason.UNSPECIFIED
    text: Optional[str] = None
    thinking_text: Optional[str] = None
    usage: Optional[UsageMetrics] = None


@dataclass
class DecodedStream:
    deltas: List[StreamDelta] = field(default_factory=list)
    terminal: StreamTerminal = field(default_factory=StreamTerminal)


def decode_llm_stream_event(raw: bytes) -> Tuple[List[StreamDelta], Optional[StreamTerminal]]:
    """Map one serialized ``LLMStreamEvent`` to deltas and optional terminal."""
    from ._proto import llm_service_pb2 as llm_pb
    from ._proto import finish_reason_pb2 as fr_pb

    event = llm_pb.LLMStreamEvent()
    event.ParseFromString(raw)
    deltas: List[StreamDelta] = []
    terminal: Optional[StreamTerminal] = None

    kind = event.event_kind
    if kind == llm_pb.LLM_STREAM_EVENT_KIND_TOKEN and event.token:
        deltas.append(StreamDelta(text=event.token, is_thinking=False))
    elif kind == llm_pb.LLM_STREAM_EVENT_KIND_THINKING and event.token:
        deltas.append(StreamDelta(text=event.token, is_thinking=True))
    elif kind == llm_pb.LLM_STREAM_EVENT_KIND_COMPLETED:
        term = StreamTerminal(finish_reason=FinishReason(int(event.finish_reason)))
        if event.HasField("result"):
            result = event.result
            term.text = result.text
            if result.HasField("thinking_content"):
                term.thinking_text = result.thinking_content
            if result.HasField("usage"):
                u = result.usage
                term.usage = {
                    "input_tokens": int(u.input_tokens),
                    "output_tokens": int(u.output_tokens),
                    "ttft_ms": float(u.ttft_ms),
                    "decode_tokens_per_second": float(u.decode_tokens_per_second),
                }
            if result.finish_reason != fr_pb.FINISH_REASON_UNSPECIFIED:
                term.finish_reason = FinishReason(int(result.finish_reason))
        terminal = term
    return deltas, terminal


def build_llm_generate_request(
    prompt: str,
    *,
    model_id: str = "",
    request_id: str = "",
    max_tokens: Optional[int] = None,
    temperature: Optional[float] = None,
    top_p: Optional[float] = None,
    top_k: Optional[int] = None,
    system_prompt: Optional[str] = None,
    grammar: Optional[str] = None,
    structured_schema: Optional[str] = None,
    disable_thinking: Optional[bool] = None,
    include_thoughts: bool = False,
    stop_sequences: Optional[List[str]] = None,
) -> bytes:
    """Serialize an ``LLMGenerateRequest`` for ``rac_llm_generate_stream_proto``.

    ``LLMGenerationOptions`` has no top-level ``grammar`` or ``disable_thinking``.
    A GBNF string maps to ``options.structured_output.grammar`` (constrained mode).
    ``structured_schema`` maps to ``options.structured_output.schema`` for commons
    to compile. ``disable_thinking=True`` maps to
    ``options.reasoning.mode = REASONING_MODE_OFF``; false/absent leaves reasoning unset.
    """
    from ._proto import chat_pb2 as chat_pb
    from ._proto import llm_options_pb2 as opts_pb
    from ._proto import llm_service_pb2 as llm_pb
    from ._proto import structured_output_pb2 as so_pb
    from ._proto import thinking_tag_pattern_pb2 as think_pb

    req = llm_pb.LLMGenerateRequest()
    if request_id:
        req.request_id = request_id
    if model_id:
        req.model_id = model_id
    msg = req.messages.add()
    msg.role = chat_pb.MESSAGE_ROLE_USER
    msg.content = prompt

    options = opts_pb.LLMGenerationOptions()
    if max_tokens is not None:
        options.max_output_tokens = int(max_tokens)
    if temperature is not None:
        options.temperature = float(temperature)
    if top_p is not None:
        options.top_p = float(top_p)
    if top_k is not None:
        options.top_k = int(top_k)
    if system_prompt:
        options.system_prompt = system_prompt
    # oneof constraint: grammar and schema are mutually exclusive arms.
    if grammar or structured_schema:
        so = so_pb.StructuredOutputOptions()
        if grammar:
            so.grammar = grammar
        else:
            so.schema = structured_schema  # type: ignore[assignment]
        so.mode = so_pb.STRUCTURED_OUTPUT_MODE_CONSTRAINED
        options.structured_output.CopyFrom(so)
    if disable_thinking:
        reasoning = think_pb.ReasoningOptions()
        reasoning.mode = think_pb.REASONING_MODE_OFF
        options.reasoning.CopyFrom(reasoning)
    if stop_sequences:
        options.stop_sequences.extend(stop_sequences)
    if include_thoughts:
        if not options.HasField("reasoning"):
            options.reasoning.CopyFrom(think_pb.ReasoningOptions())
        options.reasoning.include_in_output = True
    req.options.CopyFrom(options)
    return req.SerializeToString()
