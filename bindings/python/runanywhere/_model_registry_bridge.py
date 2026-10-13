"""Proto plumbing for the shared native model registry refresh ABI."""

from __future__ import annotations

import logging

from ._runtime import runtime
from .errors import SDKException
from .options import ModelRefreshOptions

_LOG = logging.getLogger("runanywhere")


def refresh(options: ModelRefreshOptions) -> None:
    """Refresh the commons registry, logging operational failures best-effort.

    Raises:
        SDKException: If the loaded native extension does not expose the refresh ABI.
    """
    if not runtime.is_ready:
        return

    try:
        core = runtime.core()
    except SDKException:
        # reset() may clear the core after the readiness check above.
        _LOG.warning("models.refresh failed", exc_info=True)
        return

    refresh_native = getattr(core, "refresh_model_registry", None)
    if refresh_native is None:
        raise SDKException.not_implemented("rac_model_registry_refresh_proto")

    try:
        from ._proto import model_types_pb2 as model_types

        request = model_types.ModelRegistryRefreshRequest(
            include_remote_catalog=options.include_remote_catalog,
            rescan_local=options.rescan_local,
            prune_orphans=options.prune_orphans,
            include_downloaded_state=True,
        )
        response = model_types.ModelRegistryRefreshResult()
        response.ParseFromString(refresh_native(request.SerializeToString()))
        if response.HasField("error"):
            _LOG.warning("models.refresh failed: %s", response.error.message)
        for warning in response.warnings:
            _LOG.warning("models.refresh: %s", warning)
    except Exception:  # noqa: BLE001 — refresh is explicitly best-effort and non-throwing
        _LOG.warning("models.refresh failed", exc_info=True)
