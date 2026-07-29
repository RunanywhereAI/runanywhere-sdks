"""Per-request and per-call option dataclasses, plus generate-kwargs assembly."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Callable

from .results import DownloadProgress


@dataclass
class InitOptions:
    """Runtime bring-up options (all optional). Local paths + environment label only."""

    secure_dir: str | None = None
    base_dir: str | None = None
    environment: str = "production"


class ReasoningMode(IntEnum):
    """Reasoning/thinking control mode (mirrors runanywhere.v1.ReasoningMode)."""

    UNSPECIFIED = 0
    OFF = 1
    ON = 2


@dataclass
class ReasoningOptions:
    """Reasoning/thinking control (mirrors runanywhere.v1.ReasoningOptions).

    ``mode=OFF`` suppresses the model's thinking phase (commons prepends the model's
    no-think directive). ``include_in_output`` governs whether thought tokens and
    ``thinking_content`` are emitted by the stream helpers — when False (the default)
    thinking is stripped from the output.
    """

    mode: ReasoningMode = ReasoningMode.UNSPECIFIED
    include_in_output: bool = False


@dataclass
class GenerateOptions:
    """Per-request generation controls (all optional).

    Output constraints (JSON schema / grammar) have no loose knob here — use
    ``generate_structured`` / ``generate_tool_call``, the structured-output surface.
    """

    max_output_tokens: int | None = None
    temperature: float | None = None
    top_p: float | None = None
    top_k: int | None = None
    system_prompt: str | None = None
    reasoning: ReasoningOptions | None = None


@dataclass
class LoadOptions:
    """Optional model identity/name overrides for a load call."""

    id: str | None = None
    name: str | None = None


@dataclass
class DownloadOptions:
    """Base dir + progress callback for a download."""

    dir: str | None = None
    on_progress: Callable[[DownloadProgress], None] | None = None


@dataclass
class VadOptions:
    """Activation threshold in [0,1] for the built-in energy VAD."""

    activation_threshold: float | None = None


@dataclass
class ChatOptions:
    """System instruction, kept at the head of every prompt."""

    system: str | None = None


# Keys forwarded verbatim to the native ``_core.generate`` call. A value of None means
# "unset" and is dropped so the backend applies its own default. ``grammar`` stays a
# bridge-level key (the C struct ABI's constrained-decoding slot) — it is how
# ``generate_structured``/``generate_tool_call`` implement structured output, not a
# public option.
_PASSTHROUGH_KEYS = (
    "temperature",
    "top_p",
    "top_k",
    "system_prompt",
    "grammar",
)


def generate_kwargs(**opts: object) -> dict:
    """Build the ``_core.generate`` kwargs from facade options.

    Maps the v2 option names onto the C-struct bridge: ``max_output_tokens`` →
    ``max_tokens`` (the ``rac_llm_options_t`` field), ``reasoning.mode == OFF`` →
    ``disable_thinking=True``. Unknown keys are ignored; None values are dropped
    (backend default applies).
    """
    out = {k: opts[k] for k in _PASSTHROUGH_KEYS if opts.get(k) is not None}
    if opts.get("max_output_tokens") is not None:
        out["max_tokens"] = opts["max_output_tokens"]
    reasoning = opts.get("reasoning")
    if isinstance(reasoning, ReasoningOptions) and reasoning.mode == ReasoningMode.OFF:
        out["disable_thinking"] = True
    return out


def include_thoughts(**opts: object) -> bool:
    """Whether the stream helpers should emit thought tokens / ``thinking_content``.

    Per the v2 contract, thoughts are emitted only when
    ``reasoning.include_in_output`` is True; unset reasoning strips thinking.
    """
    reasoning = opts.get("reasoning")
    return isinstance(reasoning, ReasoningOptions) and reasoning.include_in_output
