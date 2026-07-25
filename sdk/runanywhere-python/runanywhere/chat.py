"""Multi-turn conversation over an LLMModel (port of Chat.ts).

Keeps history (system + user/assistant turns), formats it into the model's prompt
each turn, streams the reply, and appends it to the history so the next turn has
context.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, AsyncIterator, Iterator, Literal

from .stream_metrics import astream_with_metrics, stream_with_metrics

if TYPE_CHECKING:
    from .models import LLMModel
    from .results import LLMStreamEvent

ChatRole = Literal["system", "user", "assistant"]


@dataclass
class ChatMessage:
    """A single conversation turn: role is 'system', 'user' or 'assistant'."""

    role: ChatRole
    content: str


class Chat:
    """Stateful multi-turn chat wrapper around an :class:`LLMModel`.

    Mirrors the Electron SDK ``Chat``: the system message (if any) is pinned at the
    head of every prompt, each user turn is formatted into a flat ``User:``/
    ``Assistant:`` transcript, and the streamed reply is recorded once complete so
    the next turn carries context.
    """

    def __init__(self, llm: "LLMModel", system: str | None = None) -> None:
        self._llm = llm
        self._history: list[ChatMessage] = []
        if system:
            self._history.append(ChatMessage(role="system", content=system))

    @property
    def messages(self) -> list[ChatMessage]:
        """A defensive copy of the conversation so far."""
        return [ChatMessage(role=m.role, content=m.content) for m in self._history]

    def reset(self) -> None:
        """Clear the conversation, keeping the system message."""
        self._history = [m for m in self._history if m.role == "system"]

    def build_prompt(self, user_text: str) -> str:
        """Format the history + a new user turn into a flat prompt (matches Chat.ts)."""
        system = next((m for m in self._history if m.role == "system"), None)
        turns = [m for m in self._history if m.role != "system"]
        p = system.content + "\n\n" if system else ""
        for m in turns:
            prefix = "User: " if m.role == "user" else "Assistant: "
            p += prefix + m.content + "\n"
        p += "User: " + user_text + "\nAssistant:"
        return p

    def send_stream(self, user_text: str) -> Iterator["LLMStreamEvent"]:
        """Send a user message; stream :class:`LLMStreamEvent`s (incl. thinking), then record.

        History stores the cleaned answer text (thinking stripped). Callers that need to
        dim/suppress reasoning tokens should inspect ``ev.is_thinking``.
        """
        prompt = self.build_prompt(user_text)
        answer = ""
        for ev in stream_with_metrics(self._llm.generate(prompt)):
            if ev.is_final and ev.result is not None:
                answer = ev.result.text
            yield ev
        self._history.append(ChatMessage(role="user", content=user_text))
        self._history.append(ChatMessage(role="assistant", content=answer.strip()))

    def send(self, user_text: str) -> Iterator[str]:
        """Send a user message; stream answer tokens only, then record both turns.

        Thinking / reasoning tokens are filtered out (use :meth:`send_stream` to observe them).
        """
        for ev in self.send_stream(user_text):
            if ev.is_final or ev.is_thinking:
                continue
            yield ev.token

    async def asend_stream(self, user_text: str) -> AsyncIterator["LLMStreamEvent"]:
        """Async twin of :meth:`send_stream`."""
        prompt = self.build_prompt(user_text)
        answer = ""
        async for ev in astream_with_metrics(self._llm.agenerate(prompt)):
            if ev.is_final and ev.result is not None:
                answer = ev.result.text
            yield ev
        self._history.append(ChatMessage(role="user", content=user_text))
        self._history.append(ChatMessage(role="assistant", content=answer.strip()))

    async def asend(self, user_text: str) -> AsyncIterator[str]:
        """Async twin of :meth:`send`."""
        async for ev in self.asend_stream(user_text):
            if ev.is_final or ev.is_thinking:
                continue
            yield ev.token

    def send_text(self, user_text: str) -> str:
        """Convenience: send and collect the full reply as a string."""
        out = ""
        for token in self.send(user_text):
            out += token
        return out

    async def asend_text(self, user_text: str) -> str:
        """Async convenience: send and collect the full reply as a string."""
        out = ""
        async for token in self.asend(user_text):
            out += token
        return out
