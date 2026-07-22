"""The ``runanywhere`` CLI: ``runanywhere serve`` / ``runanywhere models`` / ``--version``.

``serve`` needs the optional server extra; ``models`` and ``--version`` work in a base install
(they touch only pure-Python catalog/download code, never fastapi or the native core).

    runanywhere serve --port 8000
    runanywhere models
    python -m runanywhere serve
"""
from __future__ import annotations

import argparse
import sys
from typing import Optional

from . import __version__

_INSTALL_HINT = (
    "The OpenAI-compatible server needs extra dependencies.\n"
    "Install them with:\n\n    pip install runanywhere[server]\n"
)


def _cmd_serve(args: argparse.Namespace) -> int:
    try:
        from .server import serve
    except ImportError:
        print(_INSTALL_HINT, file=sys.stderr)
        return 1
    serve(
        host=args.host,
        port=args.port,
        api_key=args.api_key,
        default_llm=args.default_llm,
        default_vlm=args.default_vlm,
        default_embedder=args.default_embedder,
        default_stt=args.default_stt,
        default_tts=args.default_tts,
        allow_image_urls=args.allow_image_urls,
        allow_arbitrary_models=args.allow_arbitrary_models,
        log_level=args.log_level,
    )
    return 0


def _cmd_models(_args: argparse.Namespace) -> int:
    # Pure: catalog metadata + on-disk download state. No native, no server extra.
    from .catalog import CATALOG
    from .download import model_status

    status = model_status()
    print(f"{'MODEL':<26} {'TYPE':<9} {'SIZE':>8}  DOWNLOADED")
    for mid, entry in sorted(CATALOG.items()):
        st = status.get(mid)
        size = f"{entry.size_mb} MB" if getattr(entry, "size_mb", None) else "-"
        mark = "yes" if (st and st.downloaded) else "no"
        print(f"{mid:<26} {entry.type:<9} {size:>8}  {mark}")
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="runanywhere", description="RunAnywhere on-device AI — CLI"
    )
    parser.add_argument("--version", action="store_true", help="print the SDK version and exit")
    sub = parser.add_subparsers(dest="command")

    serve = sub.add_parser("serve", help="run the local OpenAI-compatible server")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8000)
    serve.add_argument("--api-key", default=None, help="require this bearer token on /v1/*")
    serve.add_argument("--default-llm", default=None)
    serve.add_argument("--default-vlm", default=None)
    serve.add_argument("--default-embedder", default=None)
    serve.add_argument("--default-stt", default=None)
    serve.add_argument("--default-tts", default=None)
    serve.add_argument("--allow-image-urls", action="store_true",
                       help="fetch http(s) image_url inputs (off by default; SSRF surface)")
    serve.add_argument("--allow-arbitrary-models", action="store_true",
                       help="allow non-catalog model ids (local paths / HF repos) from clients")
    serve.add_argument("--log-level", default="info")

    sub.add_parser("models", help="list the built-in catalog models + download state")
    return parser


def main(argv: Optional[list] = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    if args.version:
        print(__version__)
        return 0
    if args.command == "serve":
        return _cmd_serve(args)
    if args.command == "models":
        return _cmd_models(args)
    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
