"""The ``runanywhere`` CLI — a Python CLI over the SDK with parity for the C++ rcli's core commands.

Exit codes match rcli: ``0`` success, ``1`` runtime/SDK error, ``2`` usage error, ``130`` Ctrl-C.
Global flags (``--json -v -q --no-progress --home``) work before *and* after the subcommand.
"""
from __future__ import annotations

import argparse
import os
from typing import Optional

from . import handlers, output


# Global flags are shared (via parents=) by BOTH the top parser and every subparser, so they work
# before OR after the subcommand. They use SUPPRESS defaults so the subparser doesn't clobber a
# value the top parser already captured (the classic argparse-parents footgun); main() then fills
# any that were never supplied with real defaults.
_GLOBAL_DEFAULTS = {"json": False, "verbose": False, "quiet": False, "no_progress": False, "home": None}


def _global_flags() -> argparse.ArgumentParser:
    """A parent parser carrying the flags every subcommand also accepts."""
    gp = argparse.ArgumentParser(add_help=False)
    s = argparse.SUPPRESS
    gp.add_argument("--json", action="store_true", default=s, help="machine-readable JSON output")
    gp.add_argument("-v", "--verbose", action="store_true", default=s, help="debug logging on stderr")
    gp.add_argument("-q", "--quiet", action="store_true", default=s, help="errors only")
    gp.add_argument("--no-progress", action="store_true", default=s, help="disable progress rendering")
    gp.add_argument("--home", default=s, help="RunAnywhere home directory override")
    return gp


def build_parser() -> argparse.ArgumentParser:
    gp = _global_flags()
    parser = argparse.ArgumentParser(
        prog="runanywhere", description="RunAnywhere on-device AI — CLI", parents=[gp]
    )
    parser.add_argument("--version", action="store_true", help="print the SDK version and exit")
    sub = parser.add_subparsers(dest="command", metavar="<command>")
    handlers.register(sub, gp)
    return parser


def main(argv: Optional[list] = None) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:  # argparse exits 2 on a usage error
        return int(exc.code) if exc.code is not None else 0
    for flag, default in _GLOBAL_DEFAULTS.items():  # fill SUPPRESS'd globals that weren't passed
        if not hasattr(args, flag):
            setattr(args, flag, default)
    # Wire the verbosity flags (previously parsed but unused): --verbose raises the runtime log
    # level (the native core reads RUNANYWHERE_LOG_LEVEL at init), --quiet lowers it AND suppresses
    # CLI status/progress lines. Respect a log level the user already set in the environment.
    if args.verbose and "RUNANYWHERE_LOG_LEVEL" not in os.environ:
        os.environ["RUNANYWHERE_LOG_LEVEL"] = "debug"
    elif args.quiet and "RUNANYWHERE_LOG_LEVEL" not in os.environ:
        os.environ["RUNANYWHERE_LOG_LEVEL"] = "error"
    output.set_quiet(args.quiet)
    if getattr(args, "version", False):
        from .. import __version__

        print(__version__)
        return 0
    if not args.command:
        parser.print_help()
        return 1
    try:
        return args.handler(args)
    except KeyboardInterrupt:
        return 130


__all__ = ["main", "build_parser"]
