"""Core lifecycle and the ``models`` namespace, over a fake native core.

Replaces the old instantiable-client tests: the v3 surface is module-level
``initialize`` / ``reset`` plus one resident model per category.
"""

from __future__ import annotations

import os
import sys

_PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_PARENT not in sys.path:
    sys.path.insert(0, _PKG_PARENT)

import pytest  # noqa: E402

import runanywhere as ra  # noqa: E402
from runanywhere import ErrorCode, LoadOptions, ModelCategory, SDKException  # noqa: E402
from runanywhere._runtime import runtime  # noqa: E402


# --------------------------------------------------------------------------- lifecycle
def test_initialize_is_idempotent(sdk) -> None:
    assert ra.is_ready() is True
    ra.initialize()  # a second call is a no-op
    assert sdk.count("initialize") == 1


def test_initialize_passes_home_dirs(fake_core, monkeypatch, tmp_path) -> None:
    home = str(tmp_path / "home")
    monkeypatch.setenv("RUNANYWHERE_HOME", home)
    ra.initialize()
    try:
        assert fake_core.args_of("initialize") == (os.path.join(home, "secure"), home)
    finally:
        ra.reset()


def test_reset_unloads_models_and_shuts_down(sdk, gguf) -> None:
    ra.models.load(gguf)
    ra.reset()
    assert sdk.count("unload_model") == 1
    assert sdk.count("shutdown") == 1
    assert ra.is_ready() is False


def test_reset_before_initialize_is_noop(fake_core) -> None:
    ra.reset()
    assert fake_core.count("shutdown") == 0


def test_version_requires_initialize(fake_core) -> None:
    with pytest.raises(SDKException) as error:
        ra.version()
    assert error.value.code == ErrorCode.NOT_INITIALIZED


def test_version_and_backends(sdk) -> None:
    assert ra.version() == "fake-0"
    assert ra.backends() == ["llamacpp", "onnx", "sherpa"]


def test_device_id_is_stable_and_persisted(sdk, tmp_path) -> None:
    first = ra.device_id()
    runtime._device_id = None  # force a re-read from disk
    assert ra.device_id() == first
    assert os.path.exists(os.path.join(str(tmp_path / "home"), "device_id"))


def test_generate_before_initialize_raises_not_initialized(fake_core, gguf) -> None:
    from runanywhere import LlmOptions

    with pytest.raises(SDKException) as error:
        ra.llm.generate("hi", LlmOptions(model=gguf))
    assert error.value.code == ErrorCode.NOT_INITIALIZED
    assert fake_core.count("load_model") == 0


# --------------------------------------------------------------------------- models namespace
def test_load_puts_the_model_in_its_category(sdk, gguf) -> None:
    ra.models.load(gguf)
    assert sdk.count("load_model") == 1
    assert runtime.resident_id(ModelCategory.LANGUAGE) == gguf
    state = ra.models.state()
    assert ModelCategory.LANGUAGE in state.loaded
    assert state.storage_free_bytes >= 0


def test_loading_a_second_id_swaps_the_resident_model(sdk, gguf, tmp_path) -> None:
    other = tmp_path / "other.gguf"
    other.write_bytes(b"gguf")
    ra.models.load(gguf)
    ra.models.load(str(other))
    assert sdk.count("load_model") == 2
    assert sdk.count("unload_model") == 1
    assert runtime.resident_id(ModelCategory.LANGUAGE) == str(other)


def test_unload_category_and_all(sdk, gguf) -> None:
    ra.models.load(gguf)
    ra.models.unload(ModelCategory.LANGUAGE)
    assert sdk.count("unload_model") == 1
    assert runtime.resident_id(ModelCategory.LANGUAGE) is None
    ra.models.unload()  # nothing resident — must not raise


def test_load_options_are_rejected_until_the_bridge_carries_them(sdk, gguf) -> None:
    with pytest.raises(SDKException) as error:
        ra.models.load(gguf, LoadOptions(context_length=4096))
    assert error.value.code == ErrorCode.NOT_IMPLEMENTED
    assert "context_length" in str(error.value)


def test_load_unknown_category_is_rejected(sdk, tmp_path) -> None:
    mystery = tmp_path / "weights.bin"
    mystery.write_bytes(b"x")
    with pytest.raises(SDKException) as error:
        ra.models.load(str(mystery))
    assert error.value.code == ErrorCode.INVALID_INPUT


def test_loading_a_path_that_does_not_exist_is_reported(sdk, tmp_path) -> None:
    with pytest.raises(SDKException):
        ra.models.load(str(tmp_path / "no" / "such" / "model.gguf"))


def test_using_a_handle_after_unload_raises_instead_of_crashing(sdk, gguf) -> None:
    ra.models.load(gguf)
    handle = runtime.llm()
    ra.models.unload(ModelCategory.LANGUAGE)
    with pytest.raises(SDKException) as error:
        list(handle.generate("after unload", {}))
    assert error.value.code == ErrorCode.INVALID_STATE


def test_list_and_get_describe_catalog_models(fake_core) -> None:
    from runanywhere import ModelFilter

    infos = ra.models.list()
    assert infos and all(info.id for info in infos)
    language = ra.models.list(ModelFilter(category=ModelCategory.LANGUAGE))
    assert language and all(i.category == ModelCategory.LANGUAGE for i in language)
    assert ra.models.get("no-such-model") is None
    assert ra.models.get(infos[0].id).id == infos[0].id


def test_aload_puts_the_model_in_its_category(sdk, gguf) -> None:
    import asyncio

    asyncio.run(ra.models.aload(gguf))
    assert runtime.resident_id(ModelCategory.LANGUAGE) == gguf


def test_adownload_reports_completion(sdk, gguf) -> None:
    import asyncio

    from runanywhere import DownloadEventKind

    async def run():
        return [event async for event in ra.models.adownload(gguf)]

    events = asyncio.run(run())
    assert events[-1].kind == DownloadEventKind.COMPLETED


def test_register_local_path_writes_the_native_registry(sdk, gguf) -> None:
    from runanywhere import ModelRegistration

    info = ra.models.register(
        ModelRegistration(id="my-llm", category=ModelCategory.LANGUAGE, path=gguf)
    )
    assert info.id == "my-llm" and info.downloaded is True
    model_id, path, framework, category = sdk.args_of("register_model")
    assert (model_id, path) == ("my-llm", gguf)
    assert category == int(ModelCategory.LANGUAGE)


def test_register_url_adds_a_downloadable_catalog_entry(fake_core) -> None:
    from runanywhere import ModelRegistration
    from runanywhere.catalog import CATALOG

    try:
        info = ra.models.register(
            ModelRegistration(
                id="tmp-url-model",
                category=ModelCategory.LANGUAGE,
                url="https://example.invalid/weights.gguf",
            )
        )
        assert info.id == "tmp-url-model"
        assert CATALOG["tmp-url-model"].primary == "weights.gguf"
    finally:
        CATALOG.pop("tmp-url-model", None)


def test_register_without_a_source_is_rejected(fake_core) -> None:
    from runanywhere import ModelRegistration

    with pytest.raises(SDKException) as error:
        ra.models.register(ModelRegistration(id="x", category=ModelCategory.LANGUAGE))
    assert error.value.code == ErrorCode.INVALID_ARGUMENT


def test_delete_rejects_ids_escaping_the_models_root(fake_core) -> None:
    with pytest.raises(SDKException) as error:
        ra.models.delete("../../etc")
    assert error.value.code == ErrorCode.INVALID_INPUT


def test_delete_missing_model_reports_not_found(fake_core) -> None:
    with pytest.raises(SDKException) as error:
        ra.models.delete("definitely-not-downloaded")
    assert error.value.code == ErrorCode.MODEL_NOT_FOUND
