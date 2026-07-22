"""Optional OpenAI-compatible HTTP server for the RunAnywhere SDK.

Requires the extra: ``pip install runanywhere[server]`` (fastapi + uvicorn + python-multipart).
This subpackage is NEVER imported by ``import runanywhere`` — it's an explicit opt-in, so the core
package stays fastapi-free and native-lazy.

    from runanywhere.server import create_app, serve
    serve(host="0.0.0.0", port=8000)          # or: runanywhere serve
"""
from __future__ import annotations

from typing import Optional

from .app import create_app
from .manager import ModelManager

__all__ = ["create_app", "serve", "ModelManager"]


def serve(
    host: str = "127.0.0.1",
    port: int = 8000,
    *,
    api_key: Optional[str] = None,
    default_llm: Optional[str] = None,
    default_vlm: Optional[str] = None,
    default_embedder: Optional[str] = None,
    default_stt: Optional[str] = None,
    default_tts: Optional[str] = None,
    log_level: str = "info",
) -> None:
    """Build the app and run it with uvicorn (imported lazily so it's only needed to serve)."""
    import uvicorn

    app = create_app(
        api_key=api_key,
        default_llm=default_llm,
        default_vlm=default_vlm,
        default_embedder=default_embedder,
        default_stt=default_stt,
        default_tts=default_tts,
    )
    uvicorn.run(app, host=host, port=port, log_level=log_level)
