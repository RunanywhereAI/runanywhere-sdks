"""The ``lora`` namespace: apply adapters to the resident model.

Binds ``native/module.cpp``'s ``lora_apply`` / ``lora_remove`` / ``lora_remove_all`` — thin
wrappers over ``rac_llm_component_load_lora`` / ``remove_lora`` / ``clear_lora`` (the same
write-only LoRA-on-LLM C ABI the ``runanywhere-electron`` addon already exposes as
``loraApply`` / ``loraRemove`` / ``loraList``). Only the LlamaCPP backend implements these
ops today; applying a LoRA adapter while a non-LlamaCPP model is resident surfaces a native
``RAC_ERROR_NOT_SUPPORTED``.

The C ABI has no read-back (apply/remove/clear are write-only), so :meth:`Lora.list` reports
the set mirrored client-side on the resident :class:`~runanywhere._handles.LLMModel` handle —
exactly like the Electron addon's ``g_lora_applied`` map.

``adapter_id`` is a local filesystem path to a LoRA adapter GGUF file: this SDK has no
catalog/download plumbing for adapters yet (only for base models), so there is no id -> path
resolution step here — pass the path directly.
"""

from __future__ import annotations

from typing import Optional

from .._runtime import runtime
from ..results import LoraState

__all__ = ["lora"]


class Lora:
    """LoRA adapter management on the resident LLM."""

    def apply(self, adapter_id: str, scale: Optional[float] = None) -> None:
        """Load and apply a LoRA adapter onto the resident LLM.

        Args:
            adapter_id: path to the LoRA adapter GGUF file.
            scale: adapter scale factor (0.0-1.0); the native default is 1.0 when omitted.

        Raises:
            SDKException: no LLM is resident, this native build predates the LoRA bindings,
                or the backend rejects the adapter (e.g. a non-LlamaCPP model, a bad file).
        """
        model = runtime.llm(verb="applying a LoRA adapter")
        model.lora_apply(adapter_id, scale)

    def remove(self, adapter_id: str) -> None:
        """Remove one adapter previously applied via :meth:`apply`.

        Args:
            adapter_id: the same path passed to :meth:`apply`.

        Raises:
            SDKException: no LLM is resident, this native build predates the LoRA bindings,
                or the adapter is not currently applied.
        """
        model = runtime.llm(verb="removing a LoRA adapter")
        model.lora_remove(adapter_id)

    def remove_all(self) -> None:
        """Remove every LoRA adapter applied to the resident LLM.

        Raises:
            SDKException: no LLM is resident, or this native build predates the LoRA
                bindings.
        """
        model = runtime.llm(verb="clearing LoRA adapters")
        model.lora_remove_all()

    def list(self) -> LoraState:
        """The LoRA adapters currently applied to the resident LLM.

        Returns an empty :class:`LoraState` (rather than raising) when no LLM is resident —
        the same "nothing applied" answer the Electron addon's ``loraList`` gives for an
        unknown handle.
        """
        model = runtime.llm_if_resident()
        if model is None:
            return LoraState()
        return LoraState(applied=model.lora_list())


#: The ``lora`` namespace.
lora = Lora()
