"""Per-request and per-call option dataclasses, plus generate-kwargs assembly."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from .results import DownloadProgress


@dataclass
class InitOptions:
    """Runtime bring-up options (all optional)."""

    secure_dir: str | None = None
    base_dir: str | None = None
    api_key: str | None = None
    base_url: str | None = None
    environment: str = "production"


@dataclass
class GenerateOptions:
    """Per-request generation controls (all optional)."""

    max_tokens: int | None = None
    temperature: float | None = None
    top_p: float | None = None
    top_k: int | None = None
    system_prompt: str | None = None
    grammar: str | None = None


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
    """Energy threshold in [0,1] for the built-in energy VAD."""

    threshold: float | None = None


@dataclass
class ChatOptions:
    """System instruction, kept at the head of every prompt."""

    system: str | None = None


# The only keys forwarded to the native ``_core.generate`` call. A value of None
# means "unset" and is dropped so the backend applies its own default.
_GENERATE_KEYS = ("max_tokens", "temperature", "top_p", "top_k", "system_prompt", "grammar")


def generate_kwargs(**opts: object) -> dict:
    """Build the ``_core.generate`` kwargs, keeping only known keys with non-None values.

    Unknown keys are ignored; any of ``max_tokens``/``temperature``/``top_p``/``top_k``/
    ``system_prompt``/``grammar`` whose value is None is dropped (backend default applies).
    """
    return {k: opts[k] for k in _GENERATE_KEYS if opts.get(k) is not None}
