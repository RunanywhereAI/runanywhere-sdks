"""Model download + resolution — stdlib-only (urllib) HTTP with resume, HF listing, extraction."""
from __future__ import annotations

import hashlib
import os
import re
import json
import tarfile
import urllib.error
import urllib.parse
import urllib.request
from typing import Callable

from .catalog import CATALOG, is_catalog_id
from .errors import ErrorCode, SDKException
from .results import DownloadProgress, ModelStatus, ResolvedModel

# Idle timeouts (seconds): applied per socket read, so they only fire on a genuinely
# stalled connection (a mid-stream reset / half-open socket), never on a slow-but-
# steady download. urllib has no cross-read idle timer, so we pass this as the
# per-operation socket timeout on each read() — every chunk resets the clock.
_DOWNLOAD_IDLE_S = 60.0
_JSON_IDLE_S = 30.0

_USER_AGENT = "runanywhere-python"
_CHUNK = 64 * 1024


def models_root() -> str:
    """~/.runanywhere/models."""
    return os.path.join(os.path.expanduser("~"), ".runanywhere", "models")


def path_exists(p: str) -> bool:
    """Does a path exist on disk? (Used to check a custom model's downloaded state.)"""
    try:
        return os.path.exists(p)
    except OSError:
        return False


def _dir_size(directory: str, depth: int = 0) -> int:
    """Recursively sum file sizes under a directory (best-effort, bounded depth)."""
    if depth > 4:
        return 0
    total = 0
    try:
        names = os.listdir(directory)
    except OSError:
        return 0
    for name in names:
        p = os.path.join(directory, name)
        try:
            if os.path.isdir(p) and not os.path.islink(p):
                total += _dir_size(p, depth + 1)
            else:
                total += os.path.getsize(p)
        except OSError:
            pass
    return total


def model_status(root: str | None = None) -> dict[str, ModelStatus]:
    """Downloaded state + on-disk size for every catalog model."""
    base = root if root is not None else models_root()
    out: dict[str, ModelStatus] = {}
    for model_id, entry in CATALOG.items():
        directory = os.path.join(base, model_id)
        # Archives: the extracted primary is the completeness signal (the .tar.bz2 is
        # removed after extract). Everything else: EVERY file must be present — a VLM
        # missing its mmproj, or an embedder missing vocab.txt, is not loadable, so a
        # primary-only check would wrongly report it downloaded.
        if entry.archive:
            downloaded = path_exists(os.path.join(directory, entry.primary))
        else:
            downloaded = all(path_exists(os.path.join(directory, f.name)) for f in entry.files)
        out[model_id] = ModelStatus(downloaded=downloaded, size_bytes=_dir_size(directory))
    return out


def _open(url: str, headers: dict[str, str], timeout: float):
    """Open a urllib request; urllib follows redirects transparently via HTTPRedirectHandler."""
    req = urllib.request.Request(url, headers=headers, method="GET")
    return urllib.request.urlopen(req, timeout=timeout)


def _content_range_total(value: str | None) -> float:
    """Parse the total from a Content-Range header ('bytes */12345' or 'bytes 0-1/12345')."""
    if not value:
        return float("nan")
    m = re.search(r"/\s*(\d+)\s*$", value)
    return float(int(m.group(1))) if m else float("nan")


def download_file(
    url: str,
    dest: str,
    on_progress: Callable[[DownloadProgress], None] | None = None,
) -> None:
    """
    Stream a URL to ``dest`` (urllib follows redirects), reporting byte progress.

    Downloads to ``dest + '.part'`` and renames on success. If a ``.part`` from an
    interrupted attempt survives, resumes it with a Range request (falls back to a full
    restart if the server ignores Range, and finalizes on 416 when the part is already
    complete). A failed attempt LEAVES the ``.part`` so the next call can resume — a
    ``.part`` is only ever renamed after a completeness check, never loaded directly.
    """
    tmp = dest + ".part"
    try:
        start_at = os.path.getsize(tmp)
    except OSError:
        start_at = 0

    def finalize() -> None:
        # os.replace can throw (Windows EPERM/EBUSY from AV/indexer, or EXDEV across
        # volumes). KEEP the completed .part on failure so a retry finalizes it (via
        # 416) rather than refetching.
        try:
            os.replace(tmp, dest)
        except OSError as e:
            raise SDKException.generation_failed(f"failed to finalize {dest}", cause=e) from e

    headers = {"User-Agent": _USER_AGENT}
    if start_at > 0:
        headers["Range"] = f"bytes={start_at}-"

    try:
        resp = _open(url, headers, _DOWNLOAD_IDLE_S)
    except urllib.error.HTTPError as e:
        # 416: only finalize if the `.part` is EXACTLY the whole file. A 416 whose
        # Content-Range total doesn't match our size means the `.part` is stale/oversized
        # — discard it and restart, rather than caching wrong bytes.
        if e.code == 416 and start_at > 0:
            total = _content_range_total(e.headers.get("Content-Range"))
            if total == total and start_at == int(total):  # not NaN and equal
                finalize()
                return
            try:
                os.remove(tmp)
            except OSError:
                pass
            headers.pop("Range", None)
            try:
                resp = _open(url, headers, _DOWNLOAD_IDLE_S)
            except urllib.error.HTTPError as e2:
                raise _http_error(e2, url) from e2
            start_at = 0
        else:
            raise _http_error(e, url) from e

    with resp:
        code = getattr(resp, "status", None) or resp.getcode() or 0
        if code not in (200, 206):
            raise _status_error(code, url)
        # 206 => resuming (its content-length is the REMAINING bytes); 200 => the server
        # ignored Range, so restart from scratch (truncate the `.part`).
        resuming = code == 206 and start_at > 0
        try:
            length = int(resp.headers.get("Content-Length") or "0")
        except (TypeError, ValueError):
            length = 0
        total = start_at + length if resuming else length
        received = start_at if resuming else 0
        base = os.path.basename(dest)

        parent = os.path.dirname(tmp)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(tmp, "ab" if resuming else "wb") as out:
            if not resuming:
                out.truncate(0)
            while True:
                try:
                    chunk = resp.read(_CHUNK)
                except (urllib.error.URLError, TimeoutError, OSError) as e:
                    # A mid-stream reset / read timeout leaves the .part so the next
                    # attempt resumes instead of refetching.
                    raise SDKException.generation_failed(
                        f"download interrupted for {url}", cause=e
                    ) from e
                if not chunk:
                    break
                out.write(chunk)
                received += len(chunk)
                if on_progress is not None:
                    try:
                        on_progress(
                            DownloadProgress(
                                file=base,
                                received=received,
                                total=total,
                                percent=round(100 * received / total) if total else 0,
                            )
                        )
                    except Exception:
                        # a throwing progress callback must not crash the host or abort
                        pass

        # A clean-but-early EOF (proxy cutoff, disk-full) still ends the read; reject on a
        # byte-count mismatch so a truncated file is never renamed.
        if total > 0 and received != total:
            raise SDKException.generation_failed(
                f"incomplete download for {url}: got {received} of {total} bytes"
            )
    finalize()


def _http_error(e: urllib.error.HTTPError, url: str) -> SDKException:
    return SDKException.of(ErrorCode.STORAGE_ERROR, f"HTTP {e.code} for {url}")


def _status_error(code: int, url: str) -> SDKException:
    return SDKException.of(ErrorCode.STORAGE_ERROR, f"HTTP {code} for {url}")


def _extract_tar_bz2(archive: str, dest_dir: str) -> None:
    """Extract a .tar.bz2 in place via the stdlib tarfile module."""
    try:
        with tarfile.open(archive, "r:bz2") as tar:
            _safe_extract(tar, dest_dir)
    except (tarfile.TarError, OSError) as e:
        raise SDKException.generation_failed(
            f"tar extraction failed for {archive}", cause=e
        ) from e


def _safe_extract(tar: tarfile.TarFile, dest_dir: str) -> None:
    """Extract, refusing any member whose resolved path escapes dest_dir (path traversal)."""
    base = os.path.realpath(dest_dir)
    for member in tar.getmembers():
        target = os.path.realpath(os.path.join(dest_dir, member.name))
        if target != base and not target.startswith(base + os.sep):
            raise SDKException.generation_failed(
                f"unsafe path in archive: {member.name}"
            )
    # Python 3.12 supports the 'data' filter; use it when available for defence in depth.
    try:
        tar.extractall(dest_dir, filter="data")
    except TypeError:
        tar.extractall(dest_dir)


# Dedup concurrent downloads to the SAME destination. Two resolve_model calls for one
# source would otherwise open two write streams on the same `.part` file and corrupt it.
_IN_FLIGHT: dict[str, bool] = {}


def _download_once(
    url: str, dest: str, on_progress: Callable[[DownloadProgress], None] | None
) -> None:
    if _IN_FLIGHT.get(dest):
        return
    _IN_FLIGHT[dest] = True
    try:
        download_file(url, dest, on_progress)
    finally:
        _IN_FLIGHT.pop(dest, None)


_RE_URL = re.compile(r"^https?://", re.IGNORECASE)
# `\Z` (absolute end, unlike `$` which also matches before a trailing newline) +
# re.ASCII (so `\w`/`\s` are ASCII-only, like JS `\w`) mirror the Electron regex
# exactly: a trailing newline or a non-ASCII letter routes to a local path, not HF.
_RE_HF = re.compile(r"^[A-Za-z0-9][\w.-]*/[A-Za-z0-9][\w.-]*(:[^\s]+)?\Z", re.ASCII)
_RE_MODEL_EXT = re.compile(r"\.(gguf|onnx|bin|safetensors)$", re.IGNORECASE)
_RE_WIN_DRIVE = re.compile(r"^[A-Za-z]:")


def is_remote_source(s: str) -> bool:
    """True for a remote model source (a URL or a HuggingFace repo) vs a local path."""
    if _RE_URL.search(s):
        return True
    if not _RE_HF.search(s):
        return False
    if "\\" in s or _RE_WIN_DRIVE.search(s):  # Windows path
        return False
    # `owner/file.gguf` is a local relative path, not a HuggingFace repo id (repo ids
    # never end in a model extension). Guard the pre-`:file` part.
    if _RE_MODEL_EXT.search(s.split(":")[0]):
        return False
    return not os.path.exists(s)


# Model kinds whose on-disk shape is a directory (sherpa STT/TTS) or an ONNX+vocab pair
# (embedder). The remote resolver is GGUF/single-file-only, so a URL/HF source can't
# produce the right shape — reject it up front with one message.
_REMOTE_UNSUPPORTED_KINDS: dict[str, str] = {
    "stt": "speech-to-text",
    "tts": "text-to-speech",
    "embedder": "embedding",
}


def assert_remote_supported(id_or_path: str, kind: str) -> None:
    label = _REMOTE_UNSUPPORTED_KINDS.get(kind)
    if label and is_remote_source(id_or_path):
        raise SDKException.invalid_input(
            f"loading a {label} model from a URL or HuggingFace repo is not supported yet — "
            "use a built-in catalog id or a local path"
        )


def _sanitize_id(s: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", s)[:64]
    a, b = 0, len(cleaned)
    while a < b and cleaned[a] == "-":
        a += 1
    while b > a and cleaned[b - 1] == "-":
        b -= 1
    return cleaned[a:b] or "model"


def _short_hash(s: str) -> str:
    """Short digest of the full source so two sources that sanitize identically differ."""
    return hashlib.sha1(s.encode("utf-8")).hexdigest()[:8]


def _http_text(url: str) -> tuple[dict[str, str], str]:
    """GET a URL body + headers (urllib follows redirects) with an idle timeout."""
    headers = {"User-Agent": _USER_AGENT, "Accept": "application/json"}
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=_JSON_IDLE_S) as resp:
            code = getattr(resp, "status", None) or resp.getcode() or 0
            if code != 200:
                raise _status_error(code, url)
            data = resp.read().decode("utf-8", errors="replace")
            resp_headers = {k: v for k, v in resp.headers.items()}
            return resp_headers, data
    except urllib.error.HTTPError as e:
        raise _http_error(e, url) from e


def _hf_files(repo: str) -> list[str]:
    """List every file path in a HuggingFace repo, following Link rel=next pagination."""
    out: list[str] = []
    url: str | None = f"https://huggingface.co/api/models/{repo}/tree/main?recursive=1"
    page = 0
    while url and page < 20:
        headers, body = _http_text(url)
        try:
            tree = json.loads(body)
        except (ValueError, TypeError):
            break
        if not isinstance(tree, list):
            break
        for e in tree:
            if isinstance(e, dict) and e.get("type") == "file" and isinstance(e.get("path"), str):
                out.append(e["path"])
        link = headers.get("Link") or headers.get("link")
        m = re.search(r"<([^>]+)>;\s*rel=\"next\"", link) if isinstance(link, str) else None
        url = urllib.parse.urljoin(url, m.group(1)) if m else None
        page += 1
    return out


def _pick_gguf(files: list[str]) -> str | None:
    g = [f for f in files if re.search(r"\.gguf$", f, re.I) and not re.search(r"mmproj", f, re.I)]
    for pat in (r"q4_k_m", r"q4_0", r"q8_0"):
        for f in g:
            if re.search(pat, f, re.I):
                return f
    return g[0] if g else None


def _pick_mmproj(files: list[str]) -> str | None:
    m = [f for f in files if re.search(r"mmproj", f, re.I) and re.search(r"\.gguf$", f, re.I)]
    for f in m:
        if re.search(r"q8_0", f, re.I):
            return f
    return m[0] if m else None


def _gguf_shard_set(picked: str, files: list[str]) -> list[str]:
    """If `picked` is one shard of a split GGUF, return the full sorted shard set."""
    m = re.match(r"^(.*)-\d{5}-of-\d{5}\.gguf$", picked, re.I)
    if not m:
        return [picked]
    stem = re.escape(m.group(1))
    rx = re.compile(r"^" + stem + r"-\d{5}-of-\d{5}\.gguf$", re.I)
    shard_set = sorted(f for f in files if rx.match(f))
    return shard_set if shard_set else [picked]


def resolve_model(
    id_or_path: str,
    dir: str | None = None,
    on_progress: Callable[[DownloadProgress], None] | None = None,
) -> ResolvedModel:
    """
    Resolve ``id_or_path`` to concrete file paths, downloading if needed. Accepts a
    catalog id, a direct http(s) URL to a model file, a HuggingFace repo id
    (``owner/repo`` or ``owner/repo:file.gguf``, GGUF + any mmproj auto-resolved, split
    GGUFs downloaded whole), or a local file path.
    """
    root = dir if dir is not None else models_root()

    if not is_catalog_id(id_or_path):
        # Direct URL to a model file.
        if _RE_URL.search(id_or_path):
            try:
                parsed = urllib.parse.urlparse(id_or_path)
                # basename collapses any `../` in the URL so the write stays in `dir`.
                fname = os.path.basename(urllib.parse.unquote(parsed.path)) or "model.bin"
            except Exception as e:  # noqa: BLE001 - surface a clear message
                raise SDKException.invalid_input(f"invalid model URL: {id_or_path}") from e
            stem = re.sub(r"\.[^.]+$", "", fname)
            cid = "url-" + _sanitize_id(stem) + "-" + _short_hash(id_or_path)
            model_dir = os.path.join(root, cid)
            os.makedirs(model_dir, exist_ok=True)
            dest = os.path.join(model_dir, fname)
            if not os.path.exists(dest):
                _download_once(id_or_path, dest, on_progress)
            return ResolvedModel(id=cid, type="path", dir=model_dir, primary=dest)

        # HuggingFace repo — resolve a GGUF (+ mmproj for VLMs, + shards for splits).
        if is_remote_source(id_or_path):
            ci = id_or_path.find(":")  # split on the FIRST colon only
            repo = id_or_path[:ci] if ci >= 0 else id_or_path
            explicit = id_or_path[ci + 1:] if ci >= 0 else None
            files = _hf_files(repo)
            picked = explicit or _pick_gguf(files)
            if not picked:
                raise SDKException.model_not_found(f"no GGUF file found in HuggingFace repo {repo}")
            shards = _gguf_shard_set(picked, files)
            mmproj = None if explicit else _pick_mmproj(files)
            cid = "hf-" + _sanitize_id(repo) + "-" + _short_hash(id_or_path)
            model_dir = os.path.join(root, cid)
            os.makedirs(model_dir, exist_ok=True)
            shard_names = {os.path.basename(g) for g in shards}
            for g in shards:
                d = os.path.join(model_dir, os.path.basename(g))
                if not os.path.exists(d):
                    _download_once(
                        f"https://huggingface.co/{repo}/resolve/main/{g}", d, on_progress
                    )
            mmproj_path: str | None = None
            if mmproj:
                # Namespace the mmproj so a basename collision with a shard never makes us
                # SKIP it and point at the model bytes.
                mm_name = os.path.basename(mmproj)
                target = ("mmproj-" + mm_name) if mm_name in shard_names else mm_name
                mmproj_path = os.path.join(model_dir, target)
                if not os.path.exists(mmproj_path):
                    _download_once(
                        f"https://huggingface.co/{repo}/resolve/main/{mmproj}",
                        mmproj_path,
                        on_progress,
                    )
            return ResolvedModel(
                id=cid,
                type="path",
                dir=model_dir,
                primary=os.path.join(model_dir, os.path.basename(shards[0])),
                mmproj=mmproj_path,
            )

        # Local path (existing or to-be-created).
        return ResolvedModel(
            id=id_or_path, type="path", dir=os.path.dirname(id_or_path), primary=id_or_path
        )

    entry = CATALOG[id_or_path]
    model_dir = os.path.join(root, id_or_path)
    os.makedirs(model_dir, exist_ok=True)
    for f in entry.files:
        dest = os.path.join(model_dir, f.name)
        if entry.archive:
            # For archives, "done" means the EXTRACTED primary exists — gating on the
            # downloaded .tar.bz2 alone would skip forever after a failed extract.
            if os.path.exists(os.path.join(model_dir, entry.primary)):
                continue
            if not os.path.exists(dest):
                _download_once(f.url, dest, on_progress)
            _extract_tar_bz2(dest, model_dir)
            # Drop the archive so it isn't kept (and double-counted by _dir_size) forever.
            try:
                os.remove(dest)
            except OSError:
                pass
        elif not os.path.exists(dest):
            _download_once(f.url, dest, on_progress)

    return ResolvedModel(
        id=id_or_path,
        type=entry.type,
        dir=model_dir,
        primary=os.path.join(model_dir, entry.primary),
        mmproj=os.path.join(model_dir, entry.mmproj) if entry.mmproj else None,
    )
