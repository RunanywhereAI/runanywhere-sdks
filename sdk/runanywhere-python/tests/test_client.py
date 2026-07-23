"""Tests for the RunAnywhere client (client.py), using a fake native core.

The compiled ``_core`` extension is replaced by a recording fake so these tests run
with NO native build: we monkeypatch ``runanywhere._native.get_core`` to return an
object that records the calls the client makes and hands back fake int handles. This
exercises the client's lifecycle (idempotent per-instance initialize, process-wide
ref-counting, context-manager teardown) and one load path end to end.
"""

from __future__ import annotations

import os
import sys

# Make the package importable regardless of the pytest invocation cwd (the `runanywhere`
# package resolves even before its __init__.py is authored in parallel).
_PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_PARENT not in sys.path:
    sys.path.insert(0, _PKG_PARENT)

import pytest  # noqa: E402

import runanywhere._native as _native  # noqa: E402
import runanywhere.client as client_mod  # noqa: E402
from runanywhere.client import RunAnywhere  # noqa: E402
from runanywhere.errors import ErrorCode, SDKException  # noqa: E402
from runanywhere.models import LLMModel  # noqa: E402


class FakeCore:
    """A recording stand-in for the native ``_core`` extension.

    Records every call as ``(method, args)`` in ``.calls`` and returns fake int handles
    from the load/create methods so the client can wrap them in model objects.
    """

    def __init__(self) -> None:
        self.calls: list[tuple[str, tuple]] = []
        self._next_handle = 1

    def _record(self, method: str, *args: object) -> None:
        self.calls.append((method, args))

    def count(self, method: str) -> int:
        return sum(1 for m, _ in self.calls if m == method)

    # -- lifecycle --
    def version(self) -> str:
        return "x"

    def initialize(self, secure_dir: str, base_dir: str) -> None:
        self._record("initialize", secure_dir, base_dir)

    def shutdown(self) -> None:
        self._record("shutdown")

    # -- loads (return a fake handle) --
    def _handle(self) -> int:
        h = self._next_handle
        self._next_handle += 1
        return h

    def load_model(self, path: str, id: object = None, name: object = None) -> int:
        self._record("load_model", path, id, name)
        return self._handle()

    def load_vlm_model(self, path: str, mmproj: str, id: object = None, name: object = None) -> int:
        self._record("load_vlm_model", path, mmproj, id, name)
        return self._handle()

    def load_embedding_model(self, path: str) -> int:
        self._record("load_embedding_model", path)
        return self._handle()

    def load_stt_model(self, path: str, id: object = None, name: object = None) -> int:
        self._record("load_stt_model", path, id, name)
        return self._handle()

    def load_tts_voice(self, path: str, id: object = None, name: object = None) -> int:
        self._record("load_tts_voice", path, id, name)
        return self._handle()

    def create_vad(self, threshold: object = None) -> int:
        self._record("create_vad", threshold)
        return self._handle()

    # -- unloads (called on shutdown via model wrappers) --
    def unload_model(self, handle: int) -> None:
        self._record("unload_model", handle)

    def unload_vlm_model(self, handle: int) -> None:
        self._record("unload_vlm_model", handle)

    def unload_embedding_model(self, handle: int) -> None:
        self._record("unload_embedding_model", handle)

    def unload_stt_model(self, handle: int) -> None:
        self._record("unload_stt_model", handle)

    def unload_tts_voice(self, handle: int) -> None:
        self._record("unload_tts_voice", handle)

    def unload_vad(self, handle: int) -> None:
        self._record("unload_vad", handle)

    # -- secure store --
    def secure_set(self, key: str, value: str) -> None:
        self._record("secure_set", key, value)

    def secure_get(self, key: str) -> object:
        self._record("secure_get", key)
        return None

    def secure_delete(self, key: str) -> None:
        self._record("secure_delete", key)


@pytest.fixture()
def fake_core(monkeypatch: pytest.MonkeyPatch) -> FakeCore:
    """Install a shared FakeCore for the module's lazy loader and reset the global state.

    The native lifecycle is reference counted in module globals; reset them before and
    after each test so ordering never leaks across tests.
    """
    core = FakeCore()
    monkeypatch.setattr(_native, "get_core", lambda: core)

    client_mod._init_count = 0
    client_mod._native_up = False
    try:
        yield core
    finally:
        client_mod._init_count = 0
        client_mod._native_up = False


def test_initialize_is_idempotent_per_instance(fake_core: FakeCore) -> None:
    ra = RunAnywhere()
    assert ra.is_initialized is False

    returned = ra.initialize()
    assert returned is ra  # chainable
    assert ra.is_initialized is True

    # A second initialize on the same instance is a no-op (no extra native init).
    ra.initialize()
    assert ra.is_initialized is True
    assert fake_core.count("initialize") == 1

    ra.shutdown()
    assert ra.is_initialized is False


def test_two_clients_ref_count_native_lifecycle(fake_core: FakeCore) -> None:
    a = RunAnywhere()
    b = RunAnywhere()

    a.initialize()
    b.initialize()
    # Only the first client actually starts the shared native core.
    assert fake_core.count("initialize") == 1
    assert fake_core.count("shutdown") == 0

    # First client down: core still up (b holds a reference).
    a.shutdown()
    assert fake_core.count("shutdown") == 0
    assert a.is_initialized is False
    assert b.is_initialized is True

    # Last client down: core is torn down exactly once.
    b.shutdown()
    assert fake_core.count("shutdown") == 1
    assert b.is_initialized is False


def test_context_manager_initializes_and_shuts_down(fake_core: FakeCore) -> None:
    with RunAnywhere() as ra:
        assert ra.is_initialized is True
        assert fake_core.count("initialize") == 1
    # Exiting the context tears the native core down.
    assert fake_core.count("shutdown") == 1


def test_initialize_passes_secure_and_base_dirs(fake_core: FakeCore, tmp_path) -> None:
    base = str(tmp_path / "home")
    secure = str(tmp_path / "vault")
    ra = RunAnywhere(base_dir=base, secure_dir=secure)
    ra.initialize()
    method, args = next(c for c in fake_core.calls if c[0] == "initialize")
    assert args == (secure, base)
    ra.shutdown()


def test_load_llm_local_path_calls_core_and_returns_llmmodel(
    fake_core: FakeCore, tmp_path
) -> None:
    # A concrete local file resolves without any download; resolve_model returns it as-is.
    model_path = tmp_path / "model.gguf"
    model_path.write_bytes(b"gguf")

    ra = RunAnywhere().initialize()
    model = ra.load_llm(str(model_path))

    assert isinstance(model, LLMModel)
    assert fake_core.count("load_model") == 1
    method, args = next(c for c in fake_core.calls if c[0] == "load_model")
    # Primary path is forwarded; id/name default to None.
    assert args[0] == str(model_path)
    assert args[1] is None and args[2] is None

    ra.shutdown()


def test_load_before_initialize_raises_not_initialized(fake_core: FakeCore, tmp_path) -> None:
    model_path = tmp_path / "model.gguf"
    model_path.write_bytes(b"gguf")

    ra = RunAnywhere()  # not initialized
    with pytest.raises(SDKException) as ei:
        ra.load_llm(str(model_path))
    assert ei.value.code == ErrorCode.NOT_INITIALIZED
    # No native load was attempted.
    assert fake_core.count("load_model") == 0


def test_version_requires_initialize(fake_core: FakeCore) -> None:
    ra = RunAnywhere()
    with pytest.raises(SDKException) as ei:
        _ = ra.version
    assert ei.value.code == ErrorCode.NOT_INITIALIZED

    ra.initialize()
    assert ra.version == "x"
    ra.shutdown()


def test_secure_store_delegates_to_core(fake_core: FakeCore) -> None:
    ra = RunAnywhere().initialize()
    ra.secure_set("api_key", "s3cr3t")
    assert ra.secure_get("api_key") is None  # fake returns None
    ra.secure_delete("api_key")
    assert fake_core.count("secure_set") == 1
    assert fake_core.count("secure_get") == 1
    assert fake_core.count("secure_delete") == 1
    ra.shutdown()


def test_secure_store_rejects_traversal_keys(fake_core: FakeCore) -> None:
    from runanywhere.client import _validate_secure_key

    ra = RunAnywhere().initialize()
    for bad in ("../evil", "..\\evil", "/etc/passwd", "a/b", "", ".", "..", "sub\\x", "x\x00y"):
        with pytest.raises(SDKException) as ei:
            ra.secure_set(bad, "v")
        assert ei.value.code == ErrorCode.INVALID_INPUT
    # No traversal key ever reached the store.
    assert fake_core.count("secure_set") == 0
    # A simple flat name is accepted and delegates to the core.
    ra.secure_set("api_key", "ok")
    assert fake_core.count("secure_set") == 1
    ra.shutdown()
    assert _validate_secure_key("api_key") == "api_key"


def test_shutdown_before_initialize_is_noop(fake_core: FakeCore) -> None:
    ra = RunAnywhere()
    ra.shutdown()  # must not raise, must not touch the core
    assert fake_core.count("shutdown") == 0
    assert client_mod._init_count == 0
