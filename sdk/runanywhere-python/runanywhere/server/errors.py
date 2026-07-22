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
    """Register handlers turning SDK / validation / unexpected errors into OpenAI-shaped bodies.

    Crucially the catch-all never echoes a traceback or internal path to the client (it logs the
    detail server-side and returns a generic 500), so the response is safe even if the app is
    ever run with ``debug=True``.
    """
    import logging

    from fastapi import Request
    from fastapi.exceptions import RequestValidationError
    from fastapi.responses import JSONResponse

    logger = logging.getLogger("runanywhere.server")

    @app.exception_handler(SDKException)
    async def _handle_sdk_exception(_request: "Request", exc: SDKException) -> "JSONResponse":
        status = http_status_for(exc)
        body = openai_error_body(
            exc.message, status, code=int(exc.code), param=getattr(exc, "field_path", None)
        )
        return JSONResponse(status_code=status, content=body)

    @app.exception_handler(RequestValidationError)
    async def _handle_validation(_request: "Request", exc: RequestValidationError) -> "JSONResponse":
        # Malformed request body / missing fields -> OpenAI-shaped 400 (not FastAPI's 422 shape).
        return JSONResponse(status_code=400, content=openai_error_body(str(exc.errors()), 400))

    @app.exception_handler(Exception)
    async def _handle_unexpected(_request: "Request", exc: Exception) -> "JSONResponse":
        logger.exception("unhandled server error")  # full detail to logs, never to the client
        return JSONResponse(status_code=500, content=openai_error_body("internal server error", 500))
