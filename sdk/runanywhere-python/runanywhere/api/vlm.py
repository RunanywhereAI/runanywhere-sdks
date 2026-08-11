"""The ``vlm`` namespace: answer a prompt about an image."""

from __future__ import annotations

from typing import AsyncIterator, Iterator, Optional

from .. import _generation
from .._options_bridge import llm_kwargs, wants_thoughts
from .._runtime import runtime
from ..events import GenerationEvent
from ..inputs import ImageInput, ModelCategory
from ..options import LlmOptions
from ..results import GenerationResult
from ._common import prepare

__all__ = ["vlm"]


def _model_id() -> str:
    return runtime.resident_id(ModelCategory.VISION) or ""


class Vlm:
    """Vision-language generation over the resident VLM."""

    def generate(
        self, image: ImageInput, prompt: str, options: Optional[LlmOptions] = None
    ) -> GenerationResult:
        """Answer ``prompt`` about ``image``.

        Raises:
            SDKException: no VLM is available, or generation fails.

        Example:
            >>> image = ImageInput.file("cat.jpg")
            >>> print(runanywhere.vlm.generate(image, "What is this?").text)
        """
        return _generation.collect(self.generate_stream(image, prompt, options))

    async def agenerate(
        self, image: ImageInput, prompt: str, options: Optional[LlmOptions] = None
    ) -> GenerationResult:
        """Async form of :meth:`generate`."""
        return await _generation.acollect(self.agenerate_stream(image, prompt, options))

    def generate_stream(
        self, image: ImageInput, prompt: str, options: Optional[LlmOptions] = None
    ) -> Iterator[GenerationEvent]:
        """Stream the answer as ``started`` → token deltas → ``completed``.

        Raises:
            SDKException: no VLM is available, or generation fails.
        """
        text, opts = prepare(prompt, options)
        kwargs = llm_kwargs(opts, vlm=True)
        model = runtime.vlm(opts.model)
        path = image.resolve_path()
        try:
            for event in _generation.run(
                model.generate(path, text, kwargs),
                model=_model_id(),
                request_id=runtime.new_request_id(),
                include_thoughts=wants_thoughts(opts),
                stop_sequences=opts.stop_sequences,
            ):
                yield event
        finally:
            image.release()

    async def agenerate_stream(
        self, image: ImageInput, prompt: str, options: Optional[LlmOptions] = None
    ) -> AsyncIterator[GenerationEvent]:
        """Async form of :meth:`generate_stream`."""
        text, opts = prepare(prompt, options)
        kwargs = llm_kwargs(opts, vlm=True)
        model = runtime.vlm(opts.model)
        path = image.resolve_path()
        inner = _generation.arun(
            model.agenerate(path, text, kwargs),
            model=_model_id(),
            request_id=runtime.new_request_id(),
            include_thoughts=wants_thoughts(opts),
            stop_sequences=opts.stop_sequences,
        )
        try:
            async for event in inner:
                yield event
        finally:
            await inner.aclose()
            image.release()


#: The ``vlm`` namespace.
vlm = Vlm()
