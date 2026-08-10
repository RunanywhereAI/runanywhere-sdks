"""Helpers shared by the namespaces: prompt assembly and option copying."""

from __future__ import annotations

import copy
from typing import List, Optional, Sequence, Tuple, Union

from ..errors import SDKException
from ..inputs import ChatMessage, Role
from ..options import LlmOptions

__all__ = ["Prompt", "prepare"]

#: What every generation verb accepts as its first argument.
Prompt = Union[str, Sequence[ChatMessage]]

_PREFIX = {Role.USER: "User: ", Role.ASSISTANT: "Assistant: ", Role.TOOL: "Tool: "}


def _transcript(messages: Sequence[ChatMessage]) -> Tuple[Optional[str], str]:
    system = "\n".join(m.content for m in messages if m.role == Role.SYSTEM) or None
    turns: List[ChatMessage] = [m for m in messages if m.role != Role.SYSTEM]
    if not turns:
        raise SDKException.invalid_input("messages must contain at least one non-system turn")
    if len(turns) == 1 and turns[0].role == Role.USER:
        # One user turn goes through verbatim so the engine applies the model's chat template.
        return system, turns[0].content
    lines = [f"{_PREFIX.get(m.role, '')}{m.content}" for m in turns]
    lines.append("Assistant:")
    return system, "\n".join(lines)


def prepare(prompt: Prompt, options: Optional[LlmOptions]) -> Tuple[str, LlmOptions]:
    """Return the prompt text plus a private copy of ``options`` carrying any system message.

    Raises:
        SDKException: the prompt is empty or holds no usable turn.
    """
    effective = copy.copy(options) if options is not None else LlmOptions()
    if isinstance(prompt, str):
        if not prompt:
            raise SDKException.invalid_input("prompt must not be empty")
        return prompt, effective
    messages = list(prompt)
    if not messages:
        raise SDKException.invalid_input("messages must not be empty")
    system, text = _transcript(messages)
    if system and not effective.system_prompt:
        effective.system_prompt = system
    return text, effective
