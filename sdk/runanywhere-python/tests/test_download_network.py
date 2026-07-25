"""Network download tests against REAL endpoints (Hugging Face) — opt-in.

Skipped unless ``RUN_NETWORK_TESTS=1`` (so the hermetic CI suite never hits the network). Run:

    RUN_NETWORK_TESTS=1 pytest tests/test_download_network.py -v

The URL + resume test is small (a few KB). The full-model tests download the smallest catalog
GGUF (~92 MB SmolLM2-135M) into a temp dir and are additionally gated by ``RUN_NETWORK_HEAVY=1``.
"""
from __future__ import annotations

import os
import struct
from pathlib import Path

import pytest

from runanywhere.catalog import CATALOG
from runanywhere.download import download_file, is_remote_source, resolve_model

pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_NETWORK_TESTS") != "1",
    reason="network tests are opt-in (set RUN_NETWORK_TESTS=1)",
)

_HEAVY = pytest.mark.skipif(
    os.environ.get("RUN_NETWORK_HEAVY") != "1",
    reason="full-model download is opt-in (set RUN_NETWORK_HEAVY=1)",
)

# A small, stable public HF file (config.json, ~1 KB) for the fast URL + resume path.
_SMALL_URL = (
    "https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct/resolve/main/config.json"
)
_GGUF_MAGIC = b"GGUF"


def test_is_remote_source_on_real_shapes():
    assert is_remote_source("bartowski/SmolLM2-135M-Instruct-GGUF") is True
    assert is_remote_source(_SMALL_URL) is True
    assert is_remote_source("/models/local.gguf") is False


def test_download_file_small_url(tmp_path: Path):
    dest = tmp_path / "config.json"
    download_file(_SMALL_URL, str(dest))
    data = dest.read_bytes()
    assert len(data) > 0 and data.lstrip().startswith(b"{")  # real JSON body


def test_download_file_resumes_from_partial(tmp_path: Path):
    dest = tmp_path / "config.json"
    download_file(_SMALL_URL, str(dest))
    full = dest.read_bytes()
    assert len(full) > 20

    # Simulate an interrupted download: leave the first half in the .part file, drop the final.
    dest.unlink()
    part = tmp_path / "config.json.part"
    part.write_bytes(full[: len(full) // 2])

    # Re-download: the client must send a Range request and resume to the exact same bytes.
    download_file(_SMALL_URL, str(dest))
    assert dest.read_bytes() == full
    assert not part.exists()  # finalized


@_HEAVY
def test_resolve_model_catalog_id_downloads_gguf(tmp_path: Path):
    resolved = resolve_model("smollm2-135m", dir=str(tmp_path))
    primary = Path(resolved.primary)
    assert primary.is_file()
    with primary.open("rb") as f:
        assert f.read(4) == _GGUF_MAGIC  # a real GGUF was fetched
    assert resolved.type == "llm"


@_HEAVY
def test_resolve_model_hf_repo_picks_q4_k_m(tmp_path: Path):
    repo = "bartowski/SmolLM2-135M-Instruct-GGUF"
    resolved = resolve_model(repo, dir=str(tmp_path))
    primary = Path(resolved.primary)
    assert primary.is_file()
    # The HF resolver lists the repo and prefers a Q4_K_M quant.
    assert "q4_k_m" in primary.name.casefold()
    with primary.open("rb") as f:
        assert f.read(4) == _GGUF_MAGIC


def test_catalog_smollm2_135m_url_matches_expected():
    # Guards the catalog entry the heavy tests rely on.
    entry = CATALOG["smollm2-135m"]
    assert entry.files[0].url.startswith(
        "https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/"
    )


if __name__ == "__main__":
    os.environ.setdefault("RUN_NETWORK_TESTS", "1")
    raise SystemExit(pytest.main([__file__, "-v"]))
