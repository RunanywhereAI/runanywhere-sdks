"""Tiny stdlib .env loader + credential-aware initialize for the examples.

Mirrors the Android example's local.properties contract: with both a base URL and
an API key set, initialize in PRODUCTION (org-scoped, authed telemetry); with
neither, initialize in DEVELOPMENT (keyless — telemetry goes to the public org).
Copy .env.example to .env and fill in real values, or export the same names.
"""
from __future__ import annotations

import os
from pathlib import Path

import runanywhere as ra
from runanywhere import Environment


def load_dotenv(path: str | os.PathLike[str] | None = None) -> None:
    """Load KEY=VALUE lines from a .env file into os.environ (never overriding it)."""
    env_path = Path(path) if path else Path(__file__).with_name(".env")
    if not env_path.is_file():
        return
    for raw in env_path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def initialize_from_env() -> None:
    """Initialize the SDK with backend creds from .env / the environment."""
    load_dotenv()
    api_key = os.environ.get("RUNANYWHERE_API_KEY", "").strip() or None
    base_url = os.environ.get("RUNANYWHERE_BASE_URL", "").strip() or None
    # Keyed → production (authed telemetry); keyless → development (public org).
    environment = (
        Environment.PRODUCTION if (api_key and base_url) else Environment.DEVELOPMENT
    )
    ra.initialize(api_key=api_key, base_url=base_url, environment=environment)
