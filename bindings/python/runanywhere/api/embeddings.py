"""The ``embeddings`` namespace: turn text into vectors."""

from __future__ import annotations

import asyncio
from typing import List, Optional, Sequence

from .._options_bridge import check_embed_options
from .._runtime import runtime
from ..errors import SDKException
from ..options import EmbedOptions
from ..results import Embedding

__all__ = ["embeddings"]


class Embeddings:
    """Text embedding over the resident embedding model."""

    def embed(
        self, texts: Sequence[str], options: Optional[EmbedOptions] = None
    ) -> List[Embedding]:
        """Embed one or more texts, returning them in input order.

        Raises:
            SDKException: no embedding model is available, or an unsupported option is set.

        Example:
            >>> vectors = runanywhere.embeddings.embed(["hello", "world"])
            >>> print(vectors[0].index, vectors[0].vector.shape)
        """
        check_embed_options(options)
        items = list(texts)
        if not items:
            raise SDKException.invalid_input("texts must not be empty")
        model = runtime.embedder(options.model if options else None)
        vectors = model.embed_batch(items)
        return [Embedding(index=i, vector=v) for i, v in enumerate(vectors)]

    async def aembed(
        self, texts: Sequence[str], options: Optional[EmbedOptions] = None
    ) -> List[Embedding]:
        """Async form of :meth:`embed` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, lambda: self.embed(texts, options))


#: The ``embeddings`` namespace.
embeddings = Embeddings()
