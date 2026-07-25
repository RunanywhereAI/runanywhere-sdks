"""Optional OpenAI-compatible HTTP server for the RunAnywhere SDK.

Requires the extra: ``pip install runanywhere[server]`` (fastapi + uvicorn + python-multipart).
This subpackage is NEVER imported by ``import runanywhere`` — it's an explicit opt-in, so the core
package stays fastapi-free and native-lazy.

    from runanywhere.server import create_app, serve
    serve(host="0.0.0.0", port=8000)          # or: runanywhere serve
"""
from __future__ import annotations

import os

from .app import create_app
from .manager import ModelManager

__all__ = ["create_app", "serve", "ModelManager"]


def serve(
    host: str = "127.0.0.1",
    port: int = 8000,
    *,
    api_key: str | None = None,
    default_llm: str | None = None,
    default_vlm: str | None = None,
    default_embedder: str | None = None,
    default_stt: str | None = None,
    default_tts: str | None = None,
    allow_image_urls: bool = False,
    allow_arbitrary_models: bool = False,
    log_level: str = "info",
) -> None:
    """Build the app and run it with uvicorn (imported lazily so it's only needed to serve).

    Run single-process only: the model cache + native core are per-process and non-shareable, so
    ``--workers N`` would load N independent copies of every model. ``api_key`` falls back to the
    ``RUNANYWHERE_API_KEY`` env var (so the token need not appear on the command line).
    """
    import uvicorn

    app = create_app(
        api_key=api_key or os.environ.get("RUNANYWHERE_API_KEY"),
        default_llm=default_llm,
        default_vlm=default_vlm,
        default_embedder=default_embedder,
        default_stt=default_stt,
        default_tts=default_tts,
        allow_image_urls=allow_image_urls,
        allow_arbitrary_models=allow_arbitrary_models,
    )
    uvicorn.run(app, host=host, port=port, log_level=log_level)
