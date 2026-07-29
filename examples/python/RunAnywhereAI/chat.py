"""Chat example: unary and streaming LLM generation with v2 generation options."""
from __future__ import annotations

import sys

from runanywhere import DownloadProgress, ReasoningMode, ReasoningOptions, RunAnywhere

DEFAULT_MODEL = "smollm2-135m"


def _progress(p: DownloadProgress) -> None:
    print(f"\rdownloading {p.file}: {p.percent}%", end="", flush=True)
    if p.percent >= 100:
        print()


def main() -> int:
    model_id = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MODEL
    with RunAnywhere() as ra:
        llm = ra.load_llm(model_id, on_progress=_progress)
        print(f"loaded: {model_id}")

        print("\n== unary generate ==")
        text = llm.generate_text(
            "In one sentence, what is on-device AI?",
            max_output_tokens=64,
            temperature=0.7,
        )
        print(text.strip())

        print("\n== streaming generate (reasoning stripped, the default) ==")
        for event in llm.generate_stream(
            "List three advantages of running an LLM locally.",
            max_output_tokens=128,
            reasoning=ReasoningOptions(include_in_output=False),
        ):
            if event.is_final and event.result is not None:
                r = event.result
                print(
                    f"\n[{r.token_count} tokens, "
                    f"first token {r.time_to_first_token_ms:.0f} ms, "
                    f"{r.tokens_per_second:.1f} tok/s]"
                )
            else:
                print(event.token, end="", flush=True)

        print("\n== streaming generate (reasoning included in output) ==")
        for event in llm.generate_stream(
            "What is 17 * 23? Answer with just the number.",
            max_output_tokens=256,
            reasoning=ReasoningOptions(mode=ReasoningMode.ON, include_in_output=True),
        ):
            if event.is_final and event.result is not None:
                thinking = event.result.thinking_content
                if thinking:
                    print(f"\n[thinking was {len(thinking)} chars]")
                else:
                    print("\n[model emitted no thinking block]")
            else:
                prefix = "~" if event.is_thinking else ""
                print(prefix + event.token, end="", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
