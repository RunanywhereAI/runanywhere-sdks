"""The ``models`` namespace: catalog, download, load and unload."""

from __future__ import annotations

import asyncio
import os
import shutil
import urllib.parse
from typing import AsyncIterator, Iterator, List, Optional

from .._runtime import runtime
from .._streaming import aiter_tokens, iter_tokens
from ..catalog import CATALOG, CatalogEntry, CatalogFile
from ..download import models_root
from ..errors import SDKException
from ..events import DownloadEvent, DownloadEventKind
from ..inputs import ModelCategory, ModelFilter, ModelRegistration
from ..options import LoadOptions
from ..results import DownloadProgress, ModelInfo, ModelsState

__all__ = ["models"]

# Catalog entries carry a coarse type string; these are the categories it maps to.
_TYPE_FOR_CATEGORY = {
    ModelCategory.LANGUAGE: "llm",
    ModelCategory.VISION: "vlm",
    ModelCategory.EMBEDDING: "embedder",
    ModelCategory.SPEECH_RECOGNITION: "stt",
    ModelCategory.SPEECH_SYNTHESIS: "tts",
}


def _basename(url: str) -> str:
    path = urllib.parse.urlparse(url).path
    return os.path.basename(urllib.parse.unquote(path)) or "model.bin"


def _entry(registration: ModelRegistration) -> CatalogEntry:
    """Build the catalog entry a registration describes."""
    kind = _TYPE_FOR_CATEGORY.get(registration.category)
    if kind is None:
        raise SDKException.not_implemented(
            f"registering a {registration.category.name} model: this SDK loads language, "
            "vision, embedding, speech-recognition and speech-synthesis models"
        )
    urls = ([registration.url] if registration.url else []) + list(registration.files)
    if not urls:
        raise SDKException.validation_failed(
            field_path="ModelRegistration",
            message="give a url, a list of files, or a local path",
        )
    files = [CatalogFile(url=u, name=_basename(u)) for u in urls]
    primary = registration.primary or files[0].name
    return CatalogEntry(
        type=kind,
        files=files,
        primary=primary,
        archive=registration.archive,
        label=registration.label,
        size_mb=(registration.size_bytes // (1024 * 1024)) or None,
    )


class Models:
    """The model catalog and everything that changes what is on disk or resident."""

    def list(self, filter: Optional[ModelFilter] = None) -> List[ModelInfo]:
        """Every known model, narrowed by ``filter``.

        Example:
            >>> downloaded = runanywhere.models.list(ModelFilter(downloaded=True))
            >>> print([m.id for m in downloaded])
        """
        out = [runtime.model_info(model_id) for model_id in sorted(CATALOG)]
        if filter is None:
            return out
        if filter.category is not None:
            out = [m for m in out if m.category == filter.category]
        if filter.downloaded is not None:
            out = [m for m in out if m.downloaded == filter.downloaded]
        return out

    def get(self, id: str) -> Optional[ModelInfo]:
        """Describe one model, or None when it is unknown."""
        if id not in CATALOG:
            return None
        return runtime.model_info(id)

    def register(self, model: ModelRegistration) -> ModelInfo:
        """Add a model to the catalog so it can be downloaded and loaded by id.

        A local ``path`` is also written into the native registry, which is what lets a RAG
        session resolve the id. The catalog itself lives in this process only.

        Raises:
            SDKException: the registration is incomplete or the category is unsupported.
        """
        if not model.id:
            raise SDKException.validation_failed(field_path="id", message="a model needs an id")
        if model.path:
            resolved = runtime.resolve(model.path)
            resolved.id = model.id
            runtime.register_native(resolved, model.category)
            return ModelInfo(
                id=model.id,
                category=model.category,
                name=model.label,
                downloaded=os.path.exists(model.path),
                size_bytes=(os.path.getsize(model.path) if os.path.isfile(model.path) else 0),
                local_path=model.path,
                framework=model.framework,
            )
        CATALOG[model.id] = _entry(model)
        return runtime.model_info(model.id)

    def download(self, id: str) -> Iterator[DownloadEvent]:
        """Download a model, streaming progress then a terminal ``completed`` event.

        Raises:
            SDKException: the id is unknown or the download fails.

        Example:
            >>> for event in runanywhere.models.download("smollm2-135m"):
            ...     print(event.percent)
        """
        entry = CATALOG.get(id)
        holder: dict = {}

        def native_call(on_progress) -> None:
            holder["resolved"] = runtime.resolve(id, on_progress)

        last_percent = -1
        for progress in iter_tokens(native_call):
            if isinstance(progress, DownloadProgress) and progress.percent != last_percent:
                last_percent = progress.percent
                yield DownloadEvent(
                    kind=DownloadEventKind.PROGRESS,
                    file=progress.file,
                    bytes_done=progress.received,
                    bytes_total=progress.total,
                    percent=progress.percent,
                )
        if entry is not None and entry.archive:
            yield DownloadEvent(kind=DownloadEventKind.EXTRACTING)
        yield DownloadEvent(kind=DownloadEventKind.COMPLETED, model=runtime.model_info(id))

    async def adownload(self, id: str) -> AsyncIterator[DownloadEvent]:
        """Async form of :meth:`download`."""
        entry = CATALOG.get(id)

        def native_call(on_progress) -> None:
            runtime.resolve(id, on_progress)

        last_percent = -1
        inner = aiter_tokens(native_call)
        try:
            async for progress in inner:
                if isinstance(progress, DownloadProgress) and progress.percent != last_percent:
                    last_percent = progress.percent
                    yield DownloadEvent(
                        kind=DownloadEventKind.PROGRESS,
                        file=progress.file,
                        bytes_done=progress.received,
                        bytes_total=progress.total,
                        percent=progress.percent,
                    )
        finally:
            await inner.aclose()
        if entry is not None and entry.archive:
            yield DownloadEvent(kind=DownloadEventKind.EXTRACTING)
        yield DownloadEvent(kind=DownloadEventKind.COMPLETED, model=runtime.model_info(id))

    def delete(self, id: str) -> None:
        """Remove a downloaded model's files.

        Raises:
            SDKException: the id escapes the models directory, or nothing is downloaded.
        """
        root = os.path.realpath(models_root())
        directory = os.path.realpath(os.path.join(root, id))
        try:
            contained = directory != root and os.path.commonpath([root, directory]) == root
        except ValueError:  # different drives on Windows
            contained = False
        if not contained:
            raise SDKException.invalid_input(f"invalid model id: {id!r}")
        if not os.path.isdir(directory):
            raise SDKException.model_not_found(id)
        shutil.rmtree(directory, ignore_errors=True)
        if runtime.is_ready:
            runtime.core().remove_model(id)

    def load(self, id: str, options: Optional[LoadOptions] = None) -> None:
        """Load a model into its category now, instead of on first use.

        Raises:
            SDKException: the model cannot be resolved or loaded.
        """
        runtime.load(id, options)

    async def aload(self, id: str, options: Optional[LoadOptions] = None) -> None:
        """Async form of :meth:`load` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, lambda: runtime.load(id, options))

    def unload(self, category: Optional[ModelCategory] = None) -> None:
        """Unload one category's resident model, or all of them."""
        runtime.unload(category)

    def state(self) -> ModelsState:
        """What is resident, plus disk used and free."""
        return runtime.state()


#: The ``models`` namespace.
models = Models()
