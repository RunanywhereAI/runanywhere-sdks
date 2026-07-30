"""Hermetic tests for the ``runanywhere`` CLI — pure-Python, no native, no models.

The handlers call the SDK namespaces, so the namespaces are monkeypatched on the package with
fakes: command dispatch, output discipline, exit codes and the ``--json`` shapes are all
covered without a native build.
"""
from __future__ import annotations

import json
import sys

import numpy as np
import pytest

import runanywhere
from runanywhere.audio import encode_wav
from runanywhere.cli import main
from runanywhere.events import GenerationEvent, GenerationEventKind
from runanywhere.results import (
    Audio,
    Embedding,
    GenerationResult,
    Match,
    RagResult,
    Segment,
    TokenKind,
    Transcription,
    VadResult,
)


# --------------------------------------------------------------------------- fakes
def _events(text="Paris", thinking=None):
    yield GenerationEvent(kind=GenerationEventKind.STARTED, request_id="r")
    if thinking:
        yield GenerationEvent(
            kind=GenerationEventKind.TOKEN, text=thinking, token_kind=TokenKind.THOUGHT
        )
    yield GenerationEvent(kind=GenerationEventKind.TOKEN, text=text)
    yield GenerationEvent(
        kind=GenerationEventKind.COMPLETED,
        result=GenerationResult(text=text, output_tokens=2, thinking_text=thinking),
    )


class FakeLlm:
    def __init__(self, thinking=None, raises=None) -> None:
        self.thinking = thinking
        self.raises = raises
        self.options = None

    def generate_stream(self, prompt, options=None):
        self.options = options
        if self.raises is not None:
            raise self.raises
        return _events(thinking=self.thinking)

    def generate(self, prompt, options=None):
        return GenerationResult(text="Paris", output_tokens=2)


class FakeVlm:
    def generate_stream(self, image, prompt, options=None):
        return _events(text="a cat")


class FakeStt:
    def transcribe(self, audio, options=None):
        return Transcription(text="hello world", duration_ms=1000)


class FakeTts:
    def synthesize(self, text, options=None):
        return Audio(data=encode_wav(np.zeros(2400, dtype=np.float32), 24000),
                     sample_rate=24000, duration_ms=100)


class FakeVad:
    def __init__(self, segments=None) -> None:
        self.segments = segments if segments is not None else [Segment(100, 400)]

    def detect(self, audio, options=None):
        return VadResult(is_speech=bool(self.segments), probability=1.0, segments=self.segments)


class FakeEmbeddings:
    def embed(self, texts, options=None):
        return [
            Embedding(index=i, vector=np.arange(4, dtype=np.float32) + float(len(text)))
            for i, text in enumerate(texts)
        ]


class FakeRagSession:
    def __init__(self) -> None:
        self.documents = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def ingest(self, documents):
        self.documents.extend(documents)

    def query(self, question, options=None):
        return RagResult(answer="Paris", sources=[Match(text="context", score=0.9)])


class FakeRag:
    def __init__(self) -> None:
        self.session = FakeRagSession()

    def open(self, embedding_model, llm_model=None, config=None):
        return self.session


@pytest.fixture()
def cli(monkeypatch):
    """Patch the namespaces plus lifecycle so the CLI runs without native code."""
    fakes = {
        "llm": FakeLlm(),
        "vlm": FakeVlm(),
        "stt": FakeStt(),
        "tts": FakeTts(),
        "vad": FakeVad(),
        "embeddings": FakeEmbeddings(),
        "rag": FakeRag(),
    }
    for name, fake in fakes.items():
        monkeypatch.setattr(runanywhere, name, fake)
    monkeypatch.setattr(runanywhere, "initialize", lambda *a, **k: None)
    monkeypatch.setattr(runanywhere, "reset", lambda: None)
    monkeypatch.setattr(runanywhere, "backends", lambda: ["llamacpp", "onnx"])
    return fakes


# --------------------------------------------------------------------------- pure (no SDK)
def test_version(capsys) -> None:
    assert main(["--version"]) == 0
    assert capsys.readouterr().out.strip() == runanywhere.__version__


def test_version_subcommand_json(capsys) -> None:
    assert main(["version", "--json"]) == 0
    assert json.loads(capsys.readouterr().out) == {"runanywhere": runanywhere.__version__}


def test_models_lists_the_catalog(capsys) -> None:
    assert main(["models"]) == 0
    out = capsys.readouterr().out
    assert "MODEL" in out and "minilm" in out


def test_list_all_json_shape(capsys) -> None:
    assert main(["list", "--all", "--json"]) == 0
    data = json.loads(capsys.readouterr().out)
    assert data["models"]
    assert all({"id", "category", "downloaded"} <= set(model) for model in data["models"])


def test_show_unknown_model_is_error(capsys) -> None:
    assert main(["show", "nope-not-a-model"]) == 1
    assert "not found" in capsys.readouterr().err


def test_no_command_prints_help_and_returns_1() -> None:
    assert main([]) == 1


def test_unknown_command_is_usage_error_2() -> None:
    assert main(["frobnicate"]) == 2  # argparse -> exit 2


def test_serve_without_the_extra_prints_the_install_hint(capsys, monkeypatch) -> None:
    monkeypatch.setitem(sys.modules, "runanywhere.server", None)  # force ImportError
    assert main(["serve"]) == 1
    assert "pip install runanywhere[server]" in capsys.readouterr().err


# --------------------------------------------------------------------------- generation
def test_run_streams_the_answer_to_stdout(cli, capsys) -> None:
    assert main(["run", "m", "Capital of France?"]) == 0
    assert capsys.readouterr().out.startswith("Paris")


def test_run_json(cli, capsys) -> None:
    assert main(["run", "m", "hi", "--json"]) == 0
    body = json.loads(capsys.readouterr().out)
    assert body["response"] == "Paris" and body["model"] == "m"
    assert body["usage"]["output_tokens"] == 2


def test_run_forwards_options(cli) -> None:
    assert main(["run", "m", "hi", "--max-tokens", "16", "--temp", "0.1", "--system", "terse"]) == 0
    options = cli["llm"].options
    assert options.model == "m" and options.max_output_tokens == 16
    assert options.temperature == 0.1 and options.system_prompt == "terse"


def test_run_routes_thinking_to_stderr(cli, monkeypatch, capsys) -> None:
    monkeypatch.setattr(runanywhere, "llm", FakeLlm(thinking="why"))
    assert main(["run", "m", "hi"]) == 0
    captured = capsys.readouterr()
    assert captured.out.startswith("Paris")
    assert "why" in captured.err and "why" not in captured.out


def test_no_think_switches_reasoning_off(cli) -> None:
    from runanywhere import ReasoningMode

    assert main(["run", "m", "hi", "--no-think"]) == 0
    assert cli["llm"].options.reasoning.mode == ReasoningMode.OFF


def test_global_json_flag_before_the_subcommand(cli, capsys) -> None:
    assert main(["--json", "run", "m", "hi"]) == 0
    assert json.loads(capsys.readouterr().out)["response"] == "Paris"


def test_run_image_uses_the_vlm(cli, capsys, tmp_path) -> None:
    image = tmp_path / "x.png"
    image.write_bytes(b"\x89PNG\r\n\x1a\n")
    assert main(["run", "m", "what is this?", "--image", str(image), "--json"]) == 0
    assert json.loads(capsys.readouterr().out)["response"] == "a cat"


def test_backends(cli, capsys) -> None:
    assert main(["backends", "--json"]) == 0
    assert json.loads(capsys.readouterr().out) == {"backends": ["llamacpp", "onnx"]}


def test_keyboard_interrupt_returns_130(cli, monkeypatch) -> None:
    monkeypatch.setattr(runanywhere, "llm", FakeLlm(raises=KeyboardInterrupt()))
    assert main(["run", "m", "hi"]) == 130


# --------------------------------------------------------------------------- audio + embeddings
def test_embed_json(cli, capsys) -> None:
    assert main(["embed", "hello", "--json"]) == 0
    body = json.loads(capsys.readouterr().out)
    assert body["dimension"] == 4 and body["count"] == 1
    assert body["vectors"][0]["values"][0] == 5.0  # arange(4)[0] + len("hello")


def test_embed_no_input_is_usage_error_2(cli) -> None:
    assert main(["embed"]) == 2


def test_stt(cli, capsys, tmp_path) -> None:
    wav = tmp_path / "a.wav"
    wav.write_bytes(encode_wav(np.zeros(16000, dtype=np.float32), 16000))
    assert main(["stt", "-i", str(wav), "--json"]) == 0
    assert json.loads(capsys.readouterr().out)["text"] == "hello world"


def test_stt_bad_input_path_is_an_error(cli) -> None:
    assert main(["stt", "-i", "/no/such/file.wav"]) == 1


def test_tts_writes_wav(cli, tmp_path) -> None:
    out = tmp_path / "o.wav"
    assert main(["tts", "-t", "hello", "-o", str(out)]) == 0
    assert out.exists() and out.read_bytes()[:4] == b"RIFF"


def test_tts_missing_output_is_usage_error_2() -> None:
    assert main(["tts", "-t", "hi"]) == 2  # argparse: -o is required


def test_vad_segments(cli, capsys, tmp_path) -> None:
    wav = tmp_path / "a.wav"
    wav.write_bytes(encode_wav(np.zeros(16000, dtype=np.float32), 16000))
    assert main(["vad", "-i", str(wav), "--json"]) == 0
    segments = json.loads(capsys.readouterr().out)["segments"]
    assert len(segments) == 1 and segments[0]["start_ms"] < segments[0]["end_ms"]


def test_voice_turn_composes_the_three_namespaces(cli, capsys, tmp_path) -> None:
    wav = tmp_path / "a.wav"
    wav.write_bytes(encode_wav(np.zeros(16000, dtype=np.float32), 16000))
    out = tmp_path / "reply.wav"
    assert main(["voice", "-i", str(wav), "-o", str(out), "--json"]) == 0
    body = json.loads(capsys.readouterr().out)
    assert body["transcription"] == "hello world" and body["response"] == "Paris"
    assert out.read_bytes()[:4] == b"RIFF"


def test_rag_answers_over_files(cli, capsys, tmp_path) -> None:
    doc = tmp_path / "notes.txt"
    doc.write_text("Paris is the capital of France.", encoding="utf-8")
    assert main(["rag", "Capital of France?", str(doc), "--json"]) == 0
    body = json.loads(capsys.readouterr().out)
    assert body["answer"] == "Paris" and body["sources"][0]["score"] == 0.9
    assert cli["rag"].session.documents[0].text.startswith("Paris")


# --------------------------------------------------------------------------- guards
def test_rm_path_traversal_is_rejected(cli, capsys) -> None:
    assert main(["rm", "-f", "../../evil"]) == 2  # must NOT delete outside the models root
    assert "invalid model name" in capsys.readouterr().err
