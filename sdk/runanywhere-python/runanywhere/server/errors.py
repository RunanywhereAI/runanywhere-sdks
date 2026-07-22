"""Map SDK errors to OpenAI-shaped HTTP responses.

The pure parts (``http_status_for`` / ``openai_error_body``) import no web deps so they can be
unit-tested standalone; ``install_error_handlers`` imports fastapi lazily.
"""
from __future__ import annotations

from typing import Any, Optional

from ..errors import ErrorCode, SDKException

# SDK ErrorCode -> HTTP status. Chosen so client-fault codes are 4xx and server/model faults
# are 5xx (NOT_INITIALIZED is 503 "not ready", MODEL_LOAD_FAILED is 502 "upstream/model").
_STATUS: dict[ErrorCode, int] = {
    ErrorCode.NOT_INITIALIZED: 503,
    ErrorCode.MODEL_NOT_FOUND: 404,
    ErrorCode.MODEL_LOAD_FAILED: 502,
    ErrorCode.GENERATION_FAILED: 500,
    ErrorCode.INVALID_STATE: 409,
    ErrorCode.INVALID_INPUT: 400,
    ErrorCode.INVALID_ARGUMENT: 400,
    ErrorCode.CANCELLED: 499,
    ErrorCode.NOT_IMPLEMENTED: 501,
}


def http_status_for(exc: SDKException) -> int:
    """HTTP status for an SDK exception (default 500)."""
    return _STATUS.get(exc.code, 500)


def openai_error_body(
    message: str, status: int, *, code: Optional[int] = None, param: Optional[str] = None
) -> dict[str, Any]:
    """OpenAI-shaped error envelope. ``type`` follows the status class."""
    etype = "invalid_request_error" if status < 500 else "server_error"
    return {"error": {"message": message, "type": etype, "code": code, "param": param}}


def install_error_handlers(app: Any) -> None:
    """Register a handler turning any ``SDKException`` into an OpenAI-shaped HTTP error."""
    from fastapi import Request
    from fastapi.responses import JSONResponse

    @app.exception_handler(SDKException)
    async def _handle_sdk_exception(_request: "Request", exc: SDKException) -> "JSONResponse":
        status = http_status_for(exc)
        body = openai_error_body(
            exc.message, status, code=int(exc.code), param=getattr(exc, "field_path", None)
        )
        return JSONResponse(status_code=status, content=body)
