"""Tests for the multi-turn Chat wrapper using a fake LLM."""
from __future__ import annotations

import asyncio
from typing import AsyncIterator, Iterator

from runanywhere.chat import Chat, ChatMessage


class FakeLLM:
    """Stub LLMModel: yields a fixed token list per generate() and records prompts."""

    def __init__(self, tokens: list[str] | None = None) -> None:
        self._tokens = tokens if tokens is not None else ["Hello", " ", "there"]
        self.prompts: list[str] = []

    def generate(self, prompt: str, **_opts: object) -> Iterator[str]:
        self.prompts.append(prompt)
        for t in self._tokens:
            yield t

    async def agenerate(self, prompt: str, **_opts: object) -> AsyncIterator[str]:
        self.prompts.append(prompt)
        for t in self._tokens:
            yield t

    def generate_text(self, prompt: str, **_opts: object) -> str:
        self.prompts.append(prompt)
        return "".join(self._tokens)


# --- history growth --------------------------------------------------------

def test_send_grows_history_with_user_and_assistant():
    llm = FakeLLM(["Hi", "!"])
    chat = Chat(llm)
    out = "".join(chat.send("hello"))

    assert out == "Hi!"
    msgs = chat.messages
    assert len(msgs) == 2
    assert msgs[0] == ChatMessage(role="user", content="hello")
    assert msgs[1] == ChatMessage(role="assistant", content="Hi!")


def test_send_text_returns_full_reply_and_records_turns():
    llm = FakeLLM(["a", "b", "c"])
    chat = Chat(llm)
    assert chat.send_text("q") == "abc"
    assert [m.role for m in chat.messages] == ["user", "assistant"]


def test_assistant_content_is_trimmed():
    # Accumulated reply is stripped before being stored (matches acc.trim()).
    llm = FakeLLM(["  spaced ", " reply  "])
    chat = Chat(llm)
    reply = chat.send_text("hey")
    # Streamed tokens are yielded verbatim...
    assert reply == "  spaced  reply  "
    # ...but the recorded assistant turn is stripped.
    assert chat.messages[-1].content == "spaced  reply"


def test_multiple_turns_accumulate():
    llm = FakeLLM(["ok"])
    chat = Chat(llm)
    chat.send_text("first")
    chat.send_text("second")
    roles = [m.role for m in chat.messages]
    assert roles == ["user", "assistant", "user", "assistant"]
    assert chat.messages[0].content == "first"
    assert chat.messages[2].content == "second"


# --- messages is a defensive copy -----------------------------------------

def test_messages_is_a_copy():
    llm = FakeLLM(["x"])
    chat = Chat(llm, system="sys")
    chat.send_text("hi")

    snapshot = chat.messages
    # Mutating the returned list does not affect the chat.
    snapshot.clear()
    assert len(chat.messages) == 3  # system + user + assistant

    # Mutating a returned message does not affect internal state.
    again = chat.messages
    again[0].content = "TAMPERED"
    assert chat.messages[0].content == "sys"


# --- reset keeps system ----------------------------------------------------

def test_reset_keeps_system_only():
    llm = FakeLLM(["r"])
    chat = Chat(llm, system="you are helpful")
    chat.send_text("one")
    chat.send_text("two")
    assert len(chat.messages) == 5  # system + 2*(user+assistant)

    chat.reset()
    msgs = chat.messages
    assert len(msgs) == 1
    assert msgs[0] == ChatMessage(role="system", content="you are helpful")


def test_reset_with_no_system_clears_all():
    llm = FakeLLM(["r"])
    chat = Chat(llm)
    chat.send_text("one")
    chat.reset()
    assert chat.messages == []


# --- build_prompt matches the electron format ------------------------------

def test_build_prompt_first_turn_no_system():
    chat = Chat(FakeLLM())
    assert chat.build_prompt("hello") == "User: hello\nAssistant:"


def test_build_prompt_first_turn_with_system():
    chat = Chat(FakeLLM(), system="be brief")
    assert chat.build_prompt("hello") == "be brief\n\nUser: hello\nAssistant:"


def test_build_prompt_includes_prior_turns():
    llm = FakeLLM(["Paris"])
    chat = Chat(llm, system="be brief")
    chat.send_text("capital of France?")

    # First turn's prompt (captured by the fake) has just system + the new user line.
    assert llm.prompts[0] == "be brief\n\nUser: capital of France?\nAssistant:"

    # The next prompt embeds the recorded prior user/assistant turns.
    prompt = chat.build_prompt("and Germany?")
    assert prompt == (
        "be brief\n\n"
        "User: capital of France?\n"
        "Assistant: Paris\n"
        "User: and Germany?\nAssistant:"
    )


def test_build_prompt_does_not_mutate_history():
    llm = FakeLLM(["y"])
    chat = Chat(llm, system="s")
    chat.send_text("q")
    before = chat.messages
    _ = chat.build_prompt("another")
    assert chat.messages == before  # build_prompt is pure


# --- async variants --------------------------------------------------------

def test_asend_grows_history():
    llm = FakeLLM(["Hi", "!"])
    chat = Chat(llm)

    async def run() -> str:
        out = ""
        async for t in chat.asend("hello"):
            out += t
        return out

    out = asyncio.run(run())
    assert out == "Hi!"
    msgs = chat.messages
    assert msgs[0] == ChatMessage(role="user", content="hello")
    assert msgs[1] == ChatMessage(role="assistant", content="Hi!")


def test_asend_text():
    llm = FakeLLM(["a", "b"])
    chat = Chat(llm, system="s")
    result = asyncio.run(chat.asend_text("q"))
    assert result == "ab"
    assert [m.role for m in chat.messages] == ["system", "user", "assistant"]
