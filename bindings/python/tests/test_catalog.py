"""Tests for the built-in model catalog."""

from __future__ import annotations

from runanywhere.catalog import CATALOG, CatalogEntry, CatalogFile, is_catalog_id

_VALID_TYPES = {"llm", "vlm", "embedder", "stt", "tts"}


def test_every_entry_has_type_files_primary() -> None:
    assert CATALOG, "catalog must not be empty"
    for cid, entry in CATALOG.items():
        assert isinstance(entry, CatalogEntry), cid
        assert entry.type in _VALID_TYPES, f"{cid}: bad type {entry.type!r}"
        assert entry.files, f"{cid}: must have at least one file"
        for f in entry.files:
            assert isinstance(f, CatalogFile), cid
            assert f.url and f.url.startswith("http"), f"{cid}: bad url {f.url!r}"
            assert f.name, f"{cid}: file missing save-as name"
        assert entry.primary, f"{cid}: missing primary"


def test_vlm_entries_have_mmproj() -> None:
    vlms = {cid: e for cid, e in CATALOG.items() if e.type == "vlm"}
    assert vlms, "expected at least one VLM entry"
    for cid, entry in vlms.items():
        assert entry.mmproj, f"{cid}: VLM must set mmproj"
        # mmproj path must be one of the downloaded file save-as names.
        names = {f.name for f in entry.files}
        assert entry.mmproj in names, f"{cid}: mmproj {entry.mmproj!r} not among files {names}"


def test_non_vlm_entries_have_no_mmproj() -> None:
    for cid, entry in CATALOG.items():
        if entry.type != "vlm":
            assert entry.mmproj is None, f"{cid}: non-VLM should not set mmproj"


def test_archive_entries_flagged() -> None:
    # STT (whisper) and TTS (piper) entries ship as .tar.bz2 archives.
    archive_entries = {cid: e for cid, e in CATALOG.items() if e.archive}
    assert archive_entries, "expected some archive entries"
    for cid, entry in archive_entries.items():
        assert entry.archive is True, cid
        assert any(
            f.name.endswith(".tar.bz2") for f in entry.files
        ), f"{cid}: archive entry must download a .tar.bz2"
    # Every whisper / piper entry should be flagged as an archive.
    for cid, entry in CATALOG.items():
        if entry.type in ("stt", "tts"):
            assert entry.archive is True, f"{cid}: {entry.type} entry must be an archive"


def test_is_catalog_id_true_for_known_id() -> None:
    assert is_catalog_id("qwen2.5-1.5b") is True
    # Every catalog key round-trips as a valid id.
    for cid in CATALOG:
        assert is_catalog_id(cid) is True, cid


def test_is_catalog_id_false_for_path_or_url() -> None:
    assert is_catalog_id("https://huggingface.co/foo/bar") is False
    assert is_catalog_id("/some/local/path/model.gguf") is False
    assert is_catalog_id("C:\\models\\model.gguf") is False
    assert is_catalog_id("org/repo") is False
    assert is_catalog_id("") is False
    assert is_catalog_id("not-a-real-id") is False


def test_no_duplicate_ids() -> None:
    # dict keys are unique by construction; assert the set/len invariant holds
    # and that no two entries collide via case-insensitive whitespace slips.
    ids = list(CATALOG.keys())
    assert len(ids) == len(set(ids)), "duplicate catalog ids"
    normalized = [c.strip().lower() for c in ids]
    assert len(normalized) == len(set(normalized)), "case/whitespace-colliding ids"


def test_urls_are_unique_per_entry() -> None:
    for cid, entry in CATALOG.items():
        urls = [f.url for f in entry.files]
        assert len(urls) == len(set(urls)), f"{cid}: duplicate file urls"
