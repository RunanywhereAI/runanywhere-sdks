"""Chat example: the ``llm`` namespace — unary, streaming, multi-turn and tool calling."""
from __future__ import annotations

import sys

import runanywhere as ra
from runanywhere import (
    ChatMessage,
    DownloadEventKind,
    LlmOptions,
    ReasoningMode,
    ReasoningOptions,
    Role,
    ToolDefinition,
)

from _env import initialize_from_env

DEFAULT_MODEL = "smollm2-135m"


def ensure(model: str) -> None:
    """Download ``model`` up front so the first generate is not blocked on the network."""
    info = ra.models.get(model)
    if info is None or info.downloaded:
        return
    for event in ra.models.download(model):
        if event.kind == DownloadEventKind.PROGRESS:
            print(f"\rdownloading {event.file}: {event.percent}%", end="", flush=True)
    print()


def unary(model: str) -> None:
    result = ra.llm.generate(
        "In one sentence, what is on-device AI?",
        LlmOptions(model=model, max_output_tokens=64),
    )
    print(result.text.strip())
    print(
        f"[{result.output_tokens} tokens, first token {result.time_to_first_token_ms:.0f} ms, "
        f"{result.tokens_per_second:.1f} tok/s, finish {result.finish_reason.name}]"
    )


def streaming(model: str) -> None:
    for event in ra.llm.generate_stream(
        "List three advantages of running an LLM locally.",
        LlmOptions(model=model, max_output_tokens=128),
    ):
        if event.is_token:
            print(event.text, end="", flush=True)
        elif event.is_completed and event.result is not None:
            r = event.result
            print(f"\n[{r.output_tokens} tokens, {r.tokens_per_second:.1f} tok/s]")


def streaming_with_thoughts(model: str) -> None:
    options = LlmOptions(
        model=model,
        max_output_tokens=256,
        reasoning=ReasoningOptions(mode=ReasoningMode.ON, include_in_output=True),
    )
    for event in ra.llm.generate_stream("What is 17 * 23? Answer with just the number.", options):
        if event.is_token:
            print(("~" if event.is_thought else "") + event.text, end="", flush=True)
        elif event.is_completed and event.result is not None:
            thinking = event.result.thinking_text
            print(f"\n[thinking was {len(thinking)} chars]" if thinking else "\n[no thinking block]")


def multi_turn(model: str) -> None:
    messages = [
        ChatMessage(Role.SYSTEM, "You answer in at most five words."),
        ChatMessage(Role.USER, "Name a European capital."),
        ChatMessage(Role.ASSISTANT, "Paris."),
        ChatMessage(Role.USER, "And its river?"),
    ]
    print(ra.llm.generate(messages, LlmOptions(model=model, max_output_tokens=32)).text.strip())


def tool_calling(model: str) -> None:
    weather = ToolDefinition(
        name="get_weather",
        parameters={
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"],
        },
        description="Current weather for a city",
    )
    ra.llm.tools.register(weather, lambda args: {"city": args.get("city"), "celsius": 18})
    try:
        result = ra.llm.generate(
            "What is the weather in Paris?",
            LlmOptions(model=model, max_output_tokens=64),
        )
        for call in result.tool_calls:
            print(f"called {call.name}({call.arguments}) -> {call.result}")
        if not result.tool_calls:
            print("[the model answered without calling a tool — small models often do]")
        print(result.text.strip() or "[no final text]")
    finally:
        ra.llm.tools.unregister(weather.name)


def main() -> int:
    model = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MODEL
    initialize_from_env()
    try:
        print(f"runanywhere {ra.version()} — model {model}")
        ensure(model)

        print("\n== unary generate ==")
        unary(model)

        print("\n== streaming generate (thinking stripped, the default) ==")
        streaming(model)

        print("\n== streaming generate (thoughts prefixed with ~) ==")
        streaming_with_thoughts(model)

        print("\n== multi-turn messages ==")
        multi_turn(model)

        print("\n== tool calling ==")
        tool_calling(model)
    finally:
        ra.reset()
    return 0


if __name__ == "__main__":
    sys.exit(main())
