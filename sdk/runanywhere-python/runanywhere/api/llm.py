"""The ``llm`` namespace: text generation, streaming, structured output and tool calling."""

from __future__ import annotations

import asyncio
import json
from typing import Any, AsyncIterator, Awaitable, Callable, Dict, Iterator, List, Optional

from .. import _generation
from .._options_bridge import llm_kwargs, wants_thoughts
from .._runtime import runtime
from ..errors import SDKException
from ..events import GenerationEvent, GenerationEventKind
from ..inputs import JsonSchema, ModelCategory, ToolDefinition
from ..options import LlmOptions, StructuredOutput, ToolChoice, ToolChoiceMode
from ..results import FinishReason, GenerationResult, StructuredResult, ToolCall
from ..structured import ToolSpec, parse_structured, tool_call_prompt, tool_call_schema
from ._common import Prompt, prepare

__all__ = ["Tools", "llm"]

#: A tool implementation: takes the parsed arguments, returns a JSON-serializable mapping.
Executor = Callable[[Dict[str, Any]], "Dict[str, Any] | Awaitable[Dict[str, Any]]"]


class Tools:
    """The process-wide tool registry consulted when a generation enables tool calling."""

    def __init__(self) -> None:
        self._tools: Dict[str, ToolDefinition] = {}
        self._executors: Dict[str, Executor] = {}

    def register(self, tool: ToolDefinition, executor: Executor) -> None:
        """Register a tool and the function that runs it."""
        if not tool.name:
            raise SDKException.validation_failed(field_path="tool.name", message="a tool needs a name")
        self._tools[tool.name] = tool
        self._executors[tool.name] = executor

    def unregister(self, name: str) -> None:
        """Remove a tool from the registry (a missing name is a no-op)."""
        self._tools.pop(name, None)
        self._executors.pop(name, None)

    def list(self) -> List[ToolDefinition]:
        """Every registered tool."""
        return list(self._tools.values())

    def executor(self, name: str) -> Optional[Executor]:
        """The executor registered for ``name``, if any."""
        return self._executors.get(name)


def _specs(tools: List[ToolDefinition]) -> List[ToolSpec]:
    return [ToolSpec(name=t.name, parameters=t.parameters, description=t.description) for t in tools]


def _active_tools(options: LlmOptions, registry: Tools) -> List[ToolDefinition]:
    if options.tool_choice.mode == ToolChoiceMode.NONE:
        return []
    tools = list(options.tools) if options.tools else registry.list()
    if options.tool_choice.mode == ToolChoiceMode.FORCED:
        name = options.tool_choice.name
        tools = [t for t in tools if t.name == name]
        if not tools:
            raise SDKException.invalid_input(f"tool_choice forced an unknown tool: {name!r}")
    return tools


def _parse_call(text: str, names: set) -> Optional[ToolCall]:
    """Pull a ``{name, arguments}`` object out of a free-form reply, if there is one."""
    body = text.strip()
    if body.startswith("```"):
        body = body.strip("`")
        if body.lstrip().lower().startswith("json"):
            body = body.lstrip()[4:]
    start, end = body.find("{"), body.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        obj = json.loads(body[start : end + 1])
    except (TypeError, ValueError):
        return None
    if not isinstance(obj, dict) or obj.get("name") not in names:
        return None
    args = obj.get("arguments")
    return ToolCall(name=str(obj["name"]), arguments=args if isinstance(args, dict) else {})


def _tool_prompt(prompt: str, tools: List[ToolDefinition]) -> str:
    doc = "\n".join(
        f"- {t.name}: {t.description or ''} (arguments: {json.dumps(t.parameters)})" for t in tools
    )
    return (
        f"{prompt}\n\nYou may call one of these tools if it helps answer:\n{doc}\n\n"
        'If a tool is needed, reply with ONLY a JSON object {"name": <tool>, "arguments": {...}} '
        "and nothing else. Otherwise, answer the user normally."
    )


def _model_id() -> str:
    """The id of the resident language model, for the result's ``model`` field."""
    return runtime.resident_id(ModelCategory.LANGUAGE) or ""


def _observation(call: ToolCall) -> str:
    return f"Tool {call.name} returned: {json.dumps(call.result)}"


class Llm:
    """Text generation over the resident language model."""

    def __init__(self) -> None:
        self.tools = Tools()

    # -- one-shot ------------------------------------------------------------
    def generate(self, prompt: Prompt, options: Optional[LlmOptions] = None) -> GenerationResult:
        """Generate a completion for a prompt or a list of chat messages.

        Loads (and downloads) ``options.model`` when it is not already resident.

        Raises:
            SDKException: no model is available, or generation fails.

        Example:
            >>> runanywhere.initialize()
            >>> print(runanywhere.llm.generate("Hi", LlmOptions(model="smollm2-135m")).text)
        """
        return _generation.collect(self.generate_stream(prompt, options))

    async def agenerate(
        self, prompt: Prompt, options: Optional[LlmOptions] = None
    ) -> GenerationResult:
        """Async form of :meth:`generate`."""
        return await _generation.acollect(self.agenerate_stream(prompt, options))

    # -- streaming -----------------------------------------------------------
    def generate_stream(
        self, prompt: Prompt, options: Optional[LlmOptions] = None
    ) -> Iterator[GenerationEvent]:
        """Stream a completion as ``started`` → token deltas → ``completed``.

        Raises:
            SDKException: no model is available, or generation fails.

        Example:
            >>> for event in runanywhere.llm.generate_stream("Hi"):
            ...     print(event.text, end="")
        """
        text, opts = prepare(prompt, options)
        tools = _active_tools(opts, self.tools)
        if tools:
            return self._with_tools(text, opts, tools)
        return self._plain(text, opts)

    async def agenerate_stream(
        self, prompt: Prompt, options: Optional[LlmOptions] = None
    ) -> AsyncIterator[GenerationEvent]:
        """Async form of :meth:`generate_stream`."""
        text, opts = prepare(prompt, options)
        tools = _active_tools(opts, self.tools)
        if tools:
            for event in self._with_tools(text, opts, tools):
                yield event
            return
        inner = self._aplain(text, opts)
        try:
            async for event in inner:
                yield event
        finally:
            await inner.aclose()

    # -- structured ----------------------------------------------------------
    def generate_structured(
        self, prompt: Prompt, schema: JsonSchema, options: Optional[LlmOptions] = None
    ) -> StructuredResult:
        """Constrain decoding to ``schema`` and return the parsed value.

        Raises:
            SDKException: no model is available, or generation fails.
        """
        text, opts = prepare(prompt, options)
        opts.structured_output = StructuredOutput(schema=schema)
        opts.tools = []
        opts.tool_choice = ToolChoice(ToolChoiceMode.NONE)
        result = _generation.collect(self._plain(text, opts))
        return _structured(result)

    async def agenerate_structured(
        self, prompt: Prompt, schema: JsonSchema, options: Optional[LlmOptions] = None
    ) -> StructuredResult:
        """Async form of :meth:`generate_structured`."""
        text, opts = prepare(prompt, options)
        opts.structured_output = StructuredOutput(schema=schema)
        opts.tools = []
        opts.tool_choice = ToolChoice(ToolChoiceMode.NONE)
        result = await _generation.acollect(self._aplain(text, opts))
        return _structured(result)

    # -- internals -----------------------------------------------------------
    def _plain(self, text: str, opts: LlmOptions) -> Iterator[GenerationEvent]:
        kwargs = llm_kwargs(opts)
        model = runtime.llm(opts.model)
        model_id = _model_id()
        return _generation.run(
            model.generate(text, kwargs),
            model=model_id,
            request_id=runtime.new_request_id(),
            include_thoughts=wants_thoughts(opts),
            stop_sequences=opts.stop_sequences,
            max_output_tokens=opts.max_output_tokens,
        )

    async def _aplain(self, text: str, opts: LlmOptions) -> AsyncIterator[GenerationEvent]:
        kwargs = llm_kwargs(opts)
        model = runtime.llm(opts.model)
        model_id = _model_id()
        inner = _generation.arun(
            model.agenerate(text, kwargs),
            model=model_id,
            request_id=runtime.new_request_id(),
            include_thoughts=wants_thoughts(opts),
            stop_sequences=opts.stop_sequences,
            max_output_tokens=opts.max_output_tokens,
        )
        try:
            async for event in inner:
                yield event
        finally:
            await inner.aclose()

    def _one_call(self, text: str, opts: LlmOptions, tools: List[ToolDefinition]) -> Optional[ToolCall]:
        """Ask the model for a tool call; None when it chose to answer instead."""
        forced = opts.tool_choice.mode in (ToolChoiceMode.REQUIRED, ToolChoiceMode.FORCED)
        probe = LlmOptions(**{**opts.__dict__, "tools": [], "tool_choice": ToolChoice(ToolChoiceMode.NONE)})
        if forced:
            probe.structured_output = StructuredOutput(schema=tool_call_schema(_specs(tools)))
            reply = _generation.collect(self._plain(tool_call_prompt(text, _specs(tools)), probe)).text
            parsed = parse_structured(reply)
            if not isinstance(parsed, dict) or not isinstance(parsed.get("name"), str):
                raise SDKException.generation_failed(f"tool call was malformed: {reply!r}")
            args = parsed.get("arguments")
            return ToolCall(name=parsed["name"], arguments=args if isinstance(args, dict) else {})
        reply = _generation.collect(self._plain(_tool_prompt(text, tools), probe)).text
        return _parse_call(reply, {t.name for t in tools})

    def _with_tools(
        self, text: str, opts: LlmOptions, tools: List[ToolDefinition]
    ) -> Iterator[GenerationEvent]:
        """Run the tool loop, then stream the model's final answer."""
        request_id = runtime.new_request_id()
        yield GenerationEvent(kind=GenerationEventKind.STARTED, request_id=request_id)
        calls: List[ToolCall] = []
        seen: set = set()
        prompt = text
        for _ in range(max(1, opts.max_tool_calls)):
            call = self._one_call(prompt, opts, tools)
            if call is None:
                break
            fingerprint = (call.name, json.dumps(call.arguments, sort_keys=True, default=str))
            if fingerprint in seen:
                # The same call with the same arguments makes no further progress; the
                # observation is already in the prompt, so go straight to the answer.
                break
            seen.add(fingerprint)
            executor = self.tools.executor(call.name)
            if executor is not None:
                outcome = executor(call.arguments)
                if asyncio.iscoroutine(outcome):
                    outcome = asyncio.run(outcome)
                call.result = outcome if isinstance(outcome, dict) else {"value": outcome}
            calls.append(call)
            yield GenerationEvent(
                kind=GenerationEventKind.TOOL_CALL, request_id=request_id, tool_call=call
            )
            if executor is None:
                # Nothing to feed back — the caller runs the tool and continues the loop.
                result = GenerationResult(
                    tool_calls=calls,
                    finish_reason=FinishReason.TOOL_CALLS,
                    request_id=request_id,
                    model=_model_id(),
                )
                yield GenerationEvent(
                    kind=GenerationEventKind.COMPLETED, request_id=request_id, result=result
                )
                return
            prompt = f"{prompt}\n{_observation(call)}"
        final = LlmOptions(**{**opts.__dict__, "tools": [], "tool_choice": ToolChoice(ToolChoiceMode.NONE)})
        for event in self._plain(prompt, final):
            if event.kind == GenerationEventKind.STARTED:
                continue
            if event.kind == GenerationEventKind.COMPLETED and event.result is not None:
                event.result.tool_calls = calls
                event.result.request_id = request_id
            yield GenerationEvent(
                kind=event.kind,
                request_id=request_id,
                text=event.text,
                token_kind=event.token_kind,
                tool_call=event.tool_call,
                result=event.result,
            )


def _structured(result: GenerationResult) -> StructuredResult:
    """Parse a grammar-constrained generation into a :class:`StructuredResult`."""
    try:
        value = parse_structured(result.text)
        valid = True
    except SDKException:
        value, valid = None, False
    return StructuredResult(
        value=value,
        raw=result.text,
        valid=valid,
        input_tokens=result.input_tokens,
        output_tokens=result.output_tokens,
        time_to_first_token_ms=result.time_to_first_token_ms,
        tokens_per_second=result.tokens_per_second,
        request_id=result.request_id,
        model=result.model,
    )


#: The ``llm`` namespace.
llm = Llm()
