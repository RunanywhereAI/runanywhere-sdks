"""Entry point for the ``runanywhere`` CLI (console script + ``python -m runanywhere``).

The command surface lives in :mod:`runanywhere.cli`; this module is just the entry shim.
"""
from __future__ import annotations

import sys

from .cli import main

if __name__ == "__main__":
    sys.exit(main())
