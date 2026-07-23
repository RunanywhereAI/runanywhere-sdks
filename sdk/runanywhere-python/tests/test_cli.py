"""Hermetic tests for the ``runanywhere`` CLI — pure-Python, no native, no models.

Handlers that need the SDK are exercised by monkeypatching ``cli.handlers._client`` with a fake
client + fake models, so the command dispatch, output discipline, exit codes, and --json shapes are
all covered without a native build.
"""
from __future__ import annotations

import json
import sys

import numpy as np
import pytest

import runanywhere
from runanywhere.audio import encode_wav
from runanywhere.cli import main
from runanywhere.results import LLMGenerationResult, LLMStreamEvent, Synthesis


# --------------------------------------------------------------------------- fakes
class FakeLLM:
    def __init__(self, events=None):
        self._events = events or [
            LLMStreamEvent("Par", False), LLMStreamEvent("is", False),
            LLMStreamEvent("", True, LLMGenerationResult("Paris", 2, 0.0, 0.0, 0.0)),
        ]

    def generate_stream(self, prompt, **opts):
        yield from self._events


class FakeEmbedder:
    def embed(self, text):
        return np.arange(4, dtype=np.float32) + float(len(text))


class FakeSTT:
    def transcribe(self, pcm16):
        return "hello world"


class FakeTTS:
    def synthesize(self, text):
        return Synthesis(np.zeros(2400, dtype=np.float32), 24000)


class FakeVLM:
    def caption(self, image_path, prompt):
        yield from ("a ", "cat")


class FakeVAD:
    def __init__(self, pattern=None):
        self._pattern = pattern  # list[bool] per frame; None -> all speech
        self._i = 0

    def detect(self, frame):
        v = True if self._pattern is None else self._pattern[min(self._i, len(self._pattern) - 1)]
        self._i += 1
        return v

    def close(self):
        pass


class FakeRA:
    """Doubles as the client AND its own context manager (like the real RunAnywhere)."""

    def __init__(self, **models):
        self._m = models

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def available_backends(self):
        return ["llamacpp", "onnx"]

    def load_llm(self, mid):
        return self._m.get("llm", FakeLLM())

    def load_vlm(self, mid):
        return self._m.get("vlm", FakeVLM())

    def load_embedder(self, mid):
        return self._m.get("emb", FakeEmbedder())

    def load_stt(self, mid):
        return self._m.get("stt", FakeSTT())

    def load_tts(self, mid):
        return self._m.get("tts", FakeTTS())

    def create_vad(self, threshold=None):
        return self._m.get("vad", FakeVAD())


@pytest.fixture()
def fake_client(monkeypatch):
    ra = FakeRA()
    from runanywhere.cli import handlers
    monkeypatch.setattr(handlers, "_client", lambda args: ra)
    return ra


# --------------------------------------------------------------------------- pure (no native)
def test_version(capsys):
    assert main(["--version"]) == 0
    assert capsys.readouterr().out.strip() == runanywhere.__version__


def test_version_subcommand_json(capsys):
    assert main(["version", "--json"]) == 0
    assert json.loads(capsys.readouterr().out) == {"runanywhere": runanywhere.__version__}


def test_models_lists_catalog(capsys):
    assert main(["models"]) == 0
    out = capsys.readouterr().out
    assert "MODEL" in out and "minilm" in out


def test_list_all_json_shape(capsys):
    assert main(["list", "--all", "--json"]) == 0
    data = json.loads(capsys.readouterr().out)
    assert data["models"] and all({"id", "type", "downloaded"} <= set(m) for m in data["models"])


def test_show_unknown_model_is_error(capsys):
    assert main(["show", "nope-not-a-model"]) == 1
    assert "not found" in capsys.readouterr().err


def test_no_command_prints_help_and_returns_1():
    assert main([]) == 1


def test_unknown_command_is_usage_error_2():
    assert main(["frobnicate"]) == 2  # argparse -> exit 2


def test_serve_without_extra_prints_install_hint(capsys, monkeypatch):
    monkeypatch.setitem(sys.modules, "runanywhere.server", None)  # force ImportError
    assert main(["serve"]) == 1
    assert "pip install runanywhere[server]" in capsys.readouterr().err


# --------------------------------------------------------------------------- mocked SDK
def test_run_streams_answer_to_stdout(fake_client, capsys):
    assert main(["run", "m", "Capital of France?"]) == 0
    cap = capsys.readouterr()
    assert cap.out.startswith("Paris")


def test_run_json(fake_client, capsys):
    assert main(["run", "m", "hi", "--json"]) == 0
    body = json.loads(capsys.readouterr().out)
    assert body["response"] == "Paris" and body["model"] == "m"


def test_run_routes_thinking_to_stderr(monkeypatch, capsys):
    events = [
        LLMStreamEvent("why", False, is_thinking=True),
        LLMStreamEvent("Paris", False),
        LLMStreamEvent("", True, LLMGenerationResult("Paris", 2, 0.0, 0.0, 0.0, thinking_content="why")),
    ]
    from runanywhere.cli import handlers
    monkeypatch.setattr(handlers, "_client", lambda args: FakeRA(llm=FakeLLM(events)))
    assert main(["run", "m", "hi"]) == 0
    cap = capsys.readouterr()
    assert cap.out.startswith("Paris")
    assert "why" in cap.err  # reasoning went to stderr, not stdout
    assert "why" not in cap.out


def test_backends(fake_client, capsys):
    assert main(["backends", "--json"]) == 0
    assert json.loads(capsys.readouterr().out) == {"backends": ["llamacpp", "onnx"]}


def test_embed_json(fake_client, capsys):
    assert main(["embed", "hello", "--json"]) == 0
    body = json.loads(capsys.readouterr().out)
    assert body["dimension"] == 4 and body["count"] == 1
    assert body["vectors"][0]["values"][0] == 5.0  # arange(4)[0] + len("hello")


def test_stt(fake_client, capsys, tmp_path):
    wav = tmp_path / "a.wav"
    wav.write_bytes(encode_wav(np.zeros(16000, dtype=np.float32), 16000))
    assert main(["stt", "-i", str(wav), "--json"]) == 0
    assert json.loads(capsys.readouterr().out)["text"] == "hello world"


def test_tts_writes_wav(fake_client, capsys, tmp_path):
    out = tmp_path / "o.wav"
    assert main(["tts", "-t", "hello", "-o", str(out)]) == 0
    assert out.exists() and out.read_bytes()[:4] == b"RIFF"


def test_stt_bad_input_path_is_error(fake_client, capsys):
    assert main(["stt", "-i", "/no/such/file.wav"]) == 1


def test_stt_malformed_wav_is_clean_error(fake_client, capsys, tmp_path):
    # A non-RIFF / non-16-bit WAV makes decode_wav raise ValueError; it must surface as a
    # clean `error:` + exit 1, NOT an uncaught traceback.
    bad = tmp_path / "bad.wav"
    bad.write_bytes(b"not a riff wave file at all")
    assert main(["stt", "-i", str(bad)]) == 1
    assert "error:" in capsys.readouterr().err.lower()


# --------------------------------------------------------------------------- review-gap coverage
def test_rm_path_traversal_is_rejected(fake_client, capsys):
    assert main(["rm", "-f", "../../evil"]) == 2  # must NOT delete outside the models root
    assert "invalid model name" in capsys.readouterr().err


def test_global_json_flag_before_subcommand(fake_client, capsys):
    # The clobbering bug made `--json` before the subcommand a no-op; assert it's honoured.
    assert main(["--json", "run", "m", "hi"]) == 0
    assert json.loads(capsys.readouterr().out)["response"] == "Paris"


def test_run_image_uses_vlm(fake_client, capsys, tmp_path):
    img = tmp_path / "x.png"
    img.write_bytes(b"\x89PNG\r\n\x1a\n")
    assert main(["run", "m", "what is this?", "--image", str(img), "--json"]) == 0
    assert json.loads(capsys.readouterr().out)["response"] == "a cat"


def test_vad_segments(monkeypatch, capsys, tmp_path):
    wav = tmp_path / "a.wav"
    wav.write_bytes(encode_wav(np.zeros(16000, dtype=np.float32), 16000))
    # frames: silence, speech, speech, silence -> one segment
    from runanywhere.cli import handlers
    monkeypatch.setattr(handlers, "_client",
                        lambda args: FakeRA(vad=FakeVAD([False, True, True, False])))
    assert main(["vad", "-i", str(wav), "--json"]) == 0
    segs = json.loads(capsys.readouterr().out)["segments"]
    assert len(segs) == 1 and segs[0]["start_s"] < segs[0]["end_s"]


def test_embed_no_input_is_usage_error_2(fake_client, capsys):
    assert main(["embed"]) == 2


def test_tts_missing_output_is_usage_error_2(capsys):
    assert main(["tts", "-t", "hi"]) == 2  # argparse: -o is required


def test_keyboard_interrupt_returns_130(monkeypatch):
    class Boom(FakeLLM):
        def generate_stream(self, prompt, **opts):
            raise KeyboardInterrupt
            yield  # pragma: no cover
    from runanywhere.cli import handlers
    monkeypatch.setattr(handlers, "_client", lambda args: FakeRA(llm=Boom()))
    assert main(["run", "m", "hi"]) == 130
