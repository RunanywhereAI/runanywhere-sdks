"""The ``rerank`` namespace: score documents against a query.

Not reachable from Python yet. Commons implements reranking
(``rac_rerank_component_rerank_proto``), but ``native/module.cpp`` binds no rerank entry
point, so every call raises instead of pretending to rank.
"""

from __future__ import annotations

from typing import List, Optional, Sequence

from ..errors import SDKException
from ..results import RankedResult

__all__ = ["rerank"]

_GAP = (
    "rerank: native/module.cpp binds no rerank entry point "
    "(rac_rerank_component_create / rac_rerank_component_load_model / "
    "rac_rerank_component_rerank_proto are not exposed to Python)"
)


class Rerank:
    """Cross-encoder reranking."""

    def rerank(
        self, query: str, documents: Sequence[str], top_n: Optional[int] = None
    ) -> List[RankedResult]:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge exposes no rerank entry point.
        """
        raise SDKException.not_implemented(_GAP)


#: The ``rerank`` namespace.
rerank = Rerank()
