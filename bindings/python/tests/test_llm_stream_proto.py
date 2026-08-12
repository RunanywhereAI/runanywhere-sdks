"""Proto-path LLM request mapping — real generated messages, not FakeCore legacy."""

from __future__ import annotations

from typing import Callable, List, Optional

from runanywhere._handles import LLMModel
from runanywhere._llm_stream import build_llm_generate_request
from runanywhere._proto import finish_reason_pb2 as fr_pb
from runanywhere._proto import llm_options_pb2 as opts_pb
from runanywhere._proto import llm_service_pb2 as llm_pb
from runanywhere._proto import structured_output_pb2 as so_pb
from runanywhere._proto import thinking_tag_pattern_pb2 as think_pb


def _parse_request(raw: bytes) -> llm_pb.LLMGenerateRequest:
    req = llm_pb.LLMGenerateRequest()
    req.ParseFromString(raw)
    return req


def test_build_maps_disable_thinking_true_to_reasoning_mode_off() -> None:
    req = _parse_request(build_llm_generate_request("hi", disable_thinking=True))
    assert req.HasField("options")
    assert req.options.HasField("reasoning")
    assert req.options.reasoning.mode == think_pb.REASONING_MODE_OFF


def test_build_leaves_reasoning_absent_when_disable_thinking_false_or_unset() -> None:
    unset = _parse_request(build_llm_generate_request("hi"))
    assert not unset.options.HasField("reasoning")

    off = _parse_request(build_llm_generate_request("hi", disable_thinking=False))
    assert not off.options.HasField("reasoning")


def test_build_maps_grammar_to_structured_output_constrained() -> None:
    gbnf = 'root ::= "ok"'
    req = _parse_request(build_llm_generate_request("hi", grammar=gbnf))
    so = req.options.structured_output
    assert req.options.HasField("structured_output")
    assert so.WhichOneof("constraint") == "grammar"
    assert so.grammar == gbnf
    assert so.HasField("mode")
    assert so.mode == so_pb.STRUCTURED_OUTPUT_MODE_CONSTRAINED


def test_build_maps_structured_schema_to_schema_arm() -> None:
    schema = '{"type":"object"}'
    req = _parse_request(build_llm_generate_request("hi", structured_schema=schema))
    so = req.options.structured_output
    assert so.WhichOneof("constraint") == "schema"
    assert so.schema == schema
    assert so.mode == so_pb.STRUCTURED_OUTPUT_MODE_CONSTRAINED


def test_build_does_not_invent_sampler_defaults() -> None:
    req = _parse_request(build_llm_generate_request("prompt only"))
    opts = req.options
    assert not opts.HasField("max_output_tokens")
    assert not opts.HasField("temperature")
    assert not opts.HasField("top_p")
    assert not opts.HasField("top_k")
    assert not opts.HasField("system_prompt")
    assert not opts.HasField("structured_output")
    assert not opts.HasField("reasoning")
    assert list(opts.stop_sequences) == []


def test_build_merges_include_thoughts_with_disable_thinking() -> None:
    req = _parse_request(
        build_llm_generate_request("hi", disable_thinking=True, include_thoughts=True)
    )
    assert req.options.reasoning.mode == think_pb.REASONING_MODE_OFF
    assert req.options.reasoning.include_in_output is True


class _RecordingProtoCore:
    """Minimal core that captures the proto request bytes."""

    prefer_legacy_generate = False

    def __init__(self) -> None:
        self.last_request: Optional[bytes] = None
        self.cancelled = False

    def llm_generate_stream_proto(self, request: bytes, on_event: Callable[[bytes], bool]) -> None:
        self.last_request = bytes(request)
        event = llm_pb.LLMStreamEvent()
        event.event_kind = llm_pb.LLM_STREAM_EVENT_KIND_TOKEN
        event.token = "ok"
        on_event(event.SerializeToString())
        done = llm_pb.LLMStreamEvent()
        done.event_kind = llm_pb.LLM_STREAM_EVENT_KIND_COMPLETED
        done.finish_reason = fr_pb.FINISH_REASON_STOP
        done.result.text = "ok"
        done.result.finish_reason = fr_pb.FINISH_REASON_STOP
        on_event(done.SerializeToString())

    def cancel_generate(self, handle: int) -> None:
        self.cancelled = True

    def llm_cancel_proto(self) -> None:
        self.cancelled = True


def test_iter_proto_wires_reasoning_off_and_grammar() -> None:
    core = _RecordingProtoCore()
    model = LLMModel(core, handle=1)
    gbnf = 'root ::= object'
    deltas: List = list(
        model._iter_proto(
            "hello",
            {"disable_thinking": True, "grammar": gbnf},
        )
    )
    assert core.last_request is not None
    req = _parse_request(core.last_request)
    assert isinstance(req.options, opts_pb.LLMGenerationOptions)
    assert req.options.reasoning.mode == think_pb.REASONING_MODE_OFF
    assert req.options.structured_output.grammar == gbnf
    assert (
        req.options.structured_output.mode
        == so_pb.STRUCTURED_OUTPUT_MODE_CONSTRAINED
    )
    assert any(d.text == "ok" and not d.is_terminal for d in deltas)
    assert any(d.is_terminal for d in deltas)


def test_iter_proto_wires_structured_schema() -> None:
    core = _RecordingProtoCore()
    model = LLMModel(core, handle=1)
    schema = '{"type":"string"}'
    list(model._iter_proto("hello", {"structured_schema": schema}))
    req = _parse_request(core.last_request or b"")
    assert req.options.structured_output.schema == schema
    assert req.options.structured_output.WhichOneof("constraint") == "schema"
