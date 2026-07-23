"""Hermetic tests for download.py: local Range-capable HTTP server, no real network."""
from __future__ import annotations

import http.server
import os
import re
import threading

import pytest

from runanywhere.download import (
    assert_remote_supported,
    download_file,
    is_remote_source,
    models_root,
    resolve_model,
)
from runanywhere.errors import SDKException

PAYLOAD = b"the quick brown fox jumps over the lazy dog" * 500  # 21500 bytes


class _RangeHandler(http.server.BaseHTTPRequestHandler):
    """Serves a single fixed payload with Range support + a 416 when fully requested."""

    body = PAYLOAD

    def log_message(self, *args):  # silence test output
        pass

    def do_GET(self) -> None:
        total = len(self.body)
        rng = self.headers.get("Range")
        if rng:
            m = re.match(r"bytes=(\d+)-(\d*)", rng)
            start = int(m.group(1)) if m else 0
            end = int(m.group(2)) if (m and m.group(2)) else total - 1
            # 416 when the requested start is at/after the end of the resource — this is
            # the "part is already complete" case the resumer must finalize on.
            if start >= total:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{total}")
                self.end_headers()
                return
            chunk = self.body[start : end + 1]
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
            self.send_header("Content-Length", str(len(chunk)))
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            self.wfile.write(chunk)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(total))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        self.wfile.write(self.body)


@pytest.fixture()
def server():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _RangeHandler)
    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()
    host, port = srv.server_address
    try:
        yield f"http://{host}:{port}/file.bin"
    finally:
        srv.shutdown()
        srv.server_close()
        thread.join(timeout=5)


def test_download_full(server, tmp_path):
    dest = os.path.join(tmp_path, "out.bin")
    seen: list[int] = []
    download_file(server, dest, on_progress=lambda p: seen.append(p.percent))
    assert os.path.exists(dest)
    assert not os.path.exists(dest + ".part")  # .part renamed away on success
    with open(dest, "rb") as f:
        assert f.read() == PAYLOAD
    assert seen and seen[-1] == 100


def test_download_resumes_from_partial(server, tmp_path):
    """A surviving .part must be resumed via Range (206) and finalized, not refetched."""
    dest = os.path.join(tmp_path, "out.bin")
    split = 8000
    # Simulate an interrupted attempt: a partial .part on disk.
    with open(dest + ".part", "wb") as f:
        f.write(PAYLOAD[:split])

    progress: list = []
    download_file(server, dest, on_progress=progress.append)

    assert os.path.exists(dest)
    assert not os.path.exists(dest + ".part")
    with open(dest, "rb") as f:
        assert f.read() == PAYLOAD
    # Resume => the first progress report already accounts for the pre-existing bytes,
    # and the total equals the full payload (start_at + remaining).
    assert progress[0].received >= split
    assert progress[-1].total == len(PAYLOAD)
    assert progress[-1].received == len(PAYLOAD)


def test_download_finalizes_complete_part_on_416(server, tmp_path):
    """A .part that is ALREADY the whole file must finalize on a 416, not error."""
    dest = os.path.join(tmp_path, "out.bin")
    with open(dest + ".part", "wb") as f:
        f.write(PAYLOAD)  # exactly complete

    download_file(server, dest)  # server returns 416 for start >= total

    assert os.path.exists(dest)
    assert not os.path.exists(dest + ".part")
    with open(dest, "rb") as f:
        assert f.read() == PAYLOAD


def test_download_restarts_on_stale_oversized_part(server, tmp_path):
    """An oversized .part (416 whose total != our size) is discarded and refetched clean."""
    dest = os.path.join(tmp_path, "out.bin")
    with open(dest + ".part", "wb") as f:
        f.write(PAYLOAD + b"EXTRA-STALE-BYTES")  # larger than the resource -> 416

    download_file(server, dest)

    assert os.path.exists(dest)
    with open(dest, "rb") as f:
        assert f.read() == PAYLOAD  # clean full payload, not the stale oversized bytes


def test_download_http_error(server, tmp_path):
    dest = os.path.join(tmp_path, "out.bin")
    # Point at a path the handler 200s regardless (it serves the same body for any path),
    # so instead exercise the error path via a closed port.
    bad_url = "http://127.0.0.1:1/nope.bin"
    with pytest.raises(Exception):
        download_file(bad_url, dest)


def test_is_remote_source_classification(tmp_path):
    assert is_remote_source("https://huggingface.co/owner/repo/resolve/main/model.gguf") is True
    assert is_remote_source("http://example.com/x.bin") is True
    assert is_remote_source("owner/repo") is True  # bare HF repo id
    assert is_remote_source("owner/repo:model.gguf") is True  # repo:file form
    # `owner/file.gguf` is a local relative path, not an HF repo id.
    assert is_remote_source("owner/model.gguf") is False
    # Windows-style paths are local.
    assert is_remote_source(r"C:\models\x.gguf") is False
    assert is_remote_source(r"models\x.gguf") is False
    # A plain local file that exists is not remote.
    local = os.path.join(tmp_path, "model.gguf")
    with open(local, "wb") as f:
        f.write(b"x")
    assert is_remote_source(local) is False


def test_assert_remote_supported():
    # Remote embedder/stt/tts sources are rejected.
    for kind in ("embedder", "stt", "tts"):
        with pytest.raises(SDKException):
            assert_remote_supported("https://x/y.gguf", kind)
    # llm/vlm remote sources are allowed (no raise).
    assert assert_remote_supported("https://x/y.gguf", "llm") is None
    assert assert_remote_supported("https://x/y.gguf", "vlm") is None
    # A local path is fine for any kind.
    assert assert_remote_supported("/some/local/path", "embedder") is None


def test_resolve_model_local_path_unchanged(tmp_path):
    local = os.path.join(tmp_path, "my-model.gguf")
    with open(local, "wb") as f:
        f.write(b"gguf-bytes")
    resolved = resolve_model(local)
    assert resolved.primary == local
    assert resolved.type == "path"
    assert resolved.id == local
    assert resolved.dir == os.path.dirname(local)
    assert resolved.mmproj is None


def test_resolve_model_direct_url(server, tmp_path):
    """A direct http(s) URL downloads to a hashed cache dir and returns type='path'."""
    resolved = resolve_model(server, dir=str(tmp_path))
    assert resolved.type == "path"
    assert resolved.id.startswith("url-")
    assert os.path.exists(resolved.primary)
    assert os.path.basename(resolved.primary) == "file.bin"
    with open(resolved.primary, "rb") as f:
        assert f.read() == PAYLOAD


def test_models_root_shape():
    root = models_root()
    assert root.endswith(os.path.join(".runanywhere", "models"))


def test_download_once_dedups_concurrent_calls(monkeypatch, tmp_path):
    """Concurrent _download_once for one dest: exactly one real download; waiters return after it
    finishes (never handing back a path to a not-yet-written file)."""
    import os
    import threading
    import time

    from runanywhere import download as dl

    calls = []

    def slow_download(url, dest, on_progress):
        calls.append(dest)
        time.sleep(0.25)
        with open(dest, "w") as f:
            f.write("done")

    monkeypatch.setattr(dl, "download_file", slow_download)
    dest = str(tmp_path / "m.gguf")
    threads = [threading.Thread(target=dl._download_once, args=("u", dest, None)) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert calls.count(dest) == 1  # only one thread actually downloaded
    assert os.path.exists(dest)  # the file is complete once every waiter returned


def test_download_once_propagates_owner_failure(monkeypatch, tmp_path):
    """If the owning download FAILS, every waiter must raise too — never return a path to a file
    that was never written (one transient error must not silently become N broken model loads)."""
    import threading
    import time

    from runanywhere import download as dl

    started = threading.Event()

    def failing_download(url, dest, on_progress):
        started.set()
        time.sleep(0.2)  # hold the slot so the other callers queue as waiters
        raise SDKException.generation_failed("network boom")

    monkeypatch.setattr(dl, "download_file", failing_download)
    dest = str(tmp_path / "m.gguf")
    errors: list = []

    def run():
        try:
            dl._download_once("u", dest, None)
        except BaseException as exc:  # noqa: BLE001 - record whatever propagated
            errors.append(exc)

    threads = [threading.Thread(target=run) for _ in range(4)]
    threads[0].start()
    assert started.wait(3)  # thread 0 owns the download before the others queue behind it
    for t in threads[1:]:
        t.start()
    for t in threads:
        t.join(5)
    # Owner + 3 waiters all fail, all as SDKException (waiters wrap the owner's error).
    assert len(errors) == 4
    assert all(isinstance(e, SDKException) for e in errors)
