"""Shared fixtures + skip guards for the gated integration/system smoke tests.

The smoke tests exercise the REAL native ``_core`` extension against REAL models cached
under ``~/.runanywhere/models``. Neither is present in a plain checkout / CI-without-native
run, so every smoke test is gated:

* the whole ``test_smoke`` module is skipped unless the native core imports (see
  :func:`native_available`), and
* each individual test is skipped unless the specific model it needs is already downloaded
  (see :func:`model_ready` / the ``requires_model`` marker helper).

Nothing here downloads a model or builds native code — the gates only observe what already
exists so the suite is a no-op (all skipped) on a clean machine.
"""

from __future__ import annotations

import os
from typing import Optional

import pytest

# The package resolves even before its native build exists — these imports are pure Python.
from runanywhere.catalog import CATALOG
from runanywhere.download import models_root as _models_root


def native_available() -> bool:
    """True iff the compiled ``runanywhere._core`` extension loads.

    Tries the lazy loader exactly the way the client does on ``initialize()``. A missing
    build (or an unloadable dependent DLL) surfaces as an ``SDKException`` from
    :func:`runanywhere._native.get_core`; any failure means "no native", so we skip.
    """
    try:
        from runanywhere._native import get_core

        get_core()
        return True
    except Exception:
        # SDKException (service-not-available / IO) when unbuilt, or any import-time error.
        return False


# Cache the (expensive-ish, DLL-loading) probe so the module-level skipif + fixtures agree
# and we don't re-run the loader repeatedly.
_NATIVE_AVAILABLE = native_available()

# Module-level guard: import into a test module as
# ``pytestmark = pytest.mark.skipif(not native_available(), reason=...)`` — or reuse this.
requires_native = pytest.mark.skipif(
    not _NATIVE_AVAILABLE,
    reason="native runanywhere._core extension is not built/loadable",
)


def model_dir(model_id: str, root: Optional[str] = None) -> str:
    """On-disk directory a catalog model is cached into (``<models_root>/<id>``)."""
    base = root if root is not None else _models_root()
    return os.path.join(base, model_id)


def model_ready(model_id: str, root: Optional[str] = None) -> bool:
    """True iff catalog ``model_id`` is already fully downloaded under the models root.

    Mirrors ``download.model_status`` completeness: for an archive model the extracted
    ``primary`` (a directory) must exist; for everything else EVERY declared file must be
    present (a VLM missing its mmproj, or an embedder missing vocab.txt, is not loadable).
    Returns False for an unknown id.
    """
    entry = CATALOG.get(model_id)
    if entry is None:
        return False
    directory = model_dir(model_id, root)
    if not os.path.isdir(directory):
        return False
    if entry.archive:
        return os.path.exists(os.path.join(directory, entry.primary))
    return all(os.path.exists(os.path.join(directory, f.name)) for f in entry.files)


def requires_model(model_id: str) -> pytest.MarkDecorator:
    """A ``skipif`` marker that also skips when ``model_id`` is not yet downloaded.

    Combines the native gate with a per-model cache check so a test only runs when BOTH
    the native core loads and the exact model it needs is present locally.
    """
    reason: str
    if not _NATIVE_AVAILABLE:
        reason = "native runanywhere._core extension is not built/loadable"
        skip = True
    elif not model_ready(model_id):
        reason = f"model {model_id!r} is not cached under {model_dir(model_id)!r}"
        skip = True
    else:
        reason = ""
        skip = False
    return pytest.mark.skipif(skip, reason=reason)


@pytest.fixture(scope="session")
def models_root() -> str:
    """The models cache root (``~/.runanywhere/models``)."""
    return _models_root()


# --------------------------------------------------------------------------- hermetic fixtures
@pytest.fixture()
def fake_core(monkeypatch: pytest.MonkeyPatch):
    """Install a :class:`FakeCore` behind the lazy loader and reset the process-wide runtime.

    The runtime and the event bus are process-global, so both are torn down before and after
    every test — ordering never leaks between tests.
    """
    from fake_core import FakeCore

    import runanywhere._native as _native
    from runanywhere.audio import set_audio_native_for_tests
    from runanywhere._runtime import runtime
    from runanywhere.events import bus

    core = FakeCore()
    monkeypatch.setattr(_native, "get_core", lambda: core)
    set_audio_native_for_tests(core)
    runtime._resident.clear()
    runtime._core = None
    runtime._device_id = None
    bus.remove_all()
    try:
        yield core
    finally:
        set_audio_native_for_tests(None)
        runtime._resident.clear()
        runtime._core = None
        runtime._device_id = None
        bus.remove_all()


@pytest.fixture(autouse=True)
def _hermetic_audio_native(request):
    """Inject FakeCore audio bindings when the compiled ``_core`` lacks ``rac_audio_*``.

    Hermetic tests (CLI / server / options) call ``encode_wav`` / ``pcm16_to_float32``
    without going through the ``sdk`` fixture. Live smoke keeps real native audio when present.
    """
    if "test_smoke" in getattr(request.node, "nodeid", ""):
        yield
        return
    from fake_core import FakeCore
    from runanywhere.audio import set_audio_native_for_tests

    needs_inject = True
    try:
        from runanywhere._native import get_core

        core = get_core()
        if hasattr(core, "audio_float32_to_wav") and hasattr(core, "audio_pcm16_to_float32"):
            needs_inject = False
    except Exception:
        needs_inject = True
    if not needs_inject:
        yield
        return
    # Prefer an already-installed FakeCore from the fake_core fixture when present.
    injected = FakeCore()
    set_audio_native_for_tests(injected)
    try:
        yield
    finally:
        set_audio_native_for_tests(None)


@pytest.fixture()
def sdk(fake_core, monkeypatch: pytest.MonkeyPatch, tmp_path):
    """An initialized SDK over the fake core, with its home directory inside ``tmp_path``."""
    import runanywhere
    from runanywhere.audio import set_audio_native_for_tests

    monkeypatch.setenv("RUNANYWHERE_HOME", str(tmp_path / "home"))
    set_audio_native_for_tests(fake_core)
    runanywhere.initialize()
    try:
        yield fake_core
    finally:
        runanywhere.reset()
        set_audio_native_for_tests(fake_core)  # fake_core fixture tear-down clears this


@pytest.fixture()
def gguf(tmp_path) -> str:
    """A local ``.gguf`` path, which resolves without any download."""
    path = tmp_path / "model.gguf"
    path.write_bytes(b"gguf")
    return str(path)
