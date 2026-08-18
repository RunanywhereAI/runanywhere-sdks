#!/usr/bin/env python3
"""Generate the telemetry wire vocabulary header from the published HTTP contract.

The backend repo is private and this one is public, so the two sides cannot
share a module. What they share instead is `idl/http/sdk-openapi.json` — the
device-facing subset of the API — and this script turns the closed enums in it
into a C++ header.

Why it matters: `framework` and `platform` used to be free-text on the wire.
The stored production rows ended up with four spellings of llama.cpp
(llamacpp, llama_cpp, LlamaCpp, llama.cpp), three of ONNX, and binding names
like "react-native" recorded as platforms. Generating the accepted set here
means an unrecognised value is caught in this repo's own tests, not discovered
at ingest time in a database nobody is watching.

Usage (from the repo root):
    python3 idl/codegen/generate_telemetry_vocabulary.py [--check]

--check exits non-zero if the committed header is stale (used by CI).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CONTRACT = REPO_ROOT / "idl" / "http" / "sdk-openapi.json"
HEADER = (
    REPO_ROOT
    / "core"
    / "include"
    / "rac"
    / "infrastructure"
    / "telemetry"
    / "rac_telemetry_vocabulary.h"
)

# schema name -> (C identifier stem, doc line)
VOCABULARIES = {
    "TelemetryEventType": ("event_type", "Every event type the SDK may emit"),
    "TelemetryFramework": ("framework", "Engine that actually executed the work"),
    "TelemetryPlatform": ("platform", "OS family — never the binding"),
    "TelemetrySdkBinding": ("sdk_binding", "Language binding that produced the event"),
    "TelemetryBatteryState": ("battery_state", "Battery state at event time"),
}


def load_vocabularies() -> dict[str, list[str]]:
    if not CONTRACT.exists():
        raise SystemExit(f"missing published contract: {CONTRACT}")
    schemas = json.loads(CONTRACT.read_text())["components"]["schemas"]
    out: dict[str, list[str]] = {}
    for name in VOCABULARIES:
        schema = schemas.get(name)
        if not schema or "enum" not in schema:
            raise SystemExit(f"{name} is missing or carries no enum in {CONTRACT.name}")
        out[name] = list(schema["enum"])
    return out


def render(vocabularies: dict[str, list[str]]) -> str:
    lines = [
        "// GENERATED FILE — DO NOT EDIT.",
        "// Source: idl/http/sdk-openapi.json (the published device-facing API contract)",
        "// Regenerate: python3 idl/codegen/generate_telemetry_vocabulary.py",
        "//",
        "// The accepted values for the telemetry dimensions that used to be free text.",
        "// The backend rejects anything outside these sets, so emitting an unlisted",
        "// value silently drops the event into quarantine — check against these tables",
        "// instead of trusting a string literal.",
        "",
        "#ifndef RAC_TELEMETRY_VOCABULARY_H",
        "#define RAC_TELEMETRY_VOCABULARY_H",
        "",
        "#include <stddef.h>",
        "",
        "#ifdef __cplusplus",
        'extern "C" {',
        "#endif",
        "",
    ]
    for schema_name, (stem, doc) in VOCABULARIES.items():
        values = vocabularies[schema_name]
        upper = stem.upper()
        lines += [
            f"// {doc}. Published as {schema_name}.",
            f"#define RAC_TELEMETRY_{upper}_COUNT {len(values)}",
            f"static const char* const RAC_TELEMETRY_{upper}_VALUES[] = {{",
        ]
        lines += [f'    "{v}",' for v in values]
        lines += ["};", ""]

    lines += [
        "// Returns 1 when `value` is in `table`, 0 otherwise (NULL is not a member;",
        "// an absent field is represented by omitting it, not by an empty string).",
        "static inline int rac_telemetry_vocabulary_contains(const char* const* table, size_t count,",
        "                                                   const char* value) {",
        "    if (!value) {",
        "        return 0;",
        "    }",
        "    for (size_t i = 0; i < count; ++i) {",
        "        const char* a = table[i];",
        "        const char* b = value;",
        "        while (*a && *a == *b) {",
        "            ++a;",
        "            ++b;",
        "        }",
        "        if (*a == '\\0' && *b == '\\0') {",
        "            return 1;",
        "        }",
        "    }",
        "    return 0;",
        "}",
        "",
        "#ifdef __cplusplus",
        "}  // extern \"C\"",
        "#endif",
        "",
        "#endif  // RAC_TELEMETRY_VOCABULARY_H",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the header is stale")
    args = parser.parse_args()

    rendered = render(load_vocabularies())
    if args.check:
        current = HEADER.read_text() if HEADER.exists() else ""
        if current != rendered:
            print(
                f"{HEADER.relative_to(REPO_ROOT)} is stale.\n"
                "Regenerate: python3 idl/codegen/generate_telemetry_vocabulary.py",
                file=sys.stderr,
            )
            sys.exit(1)
        print(f"{HEADER.relative_to(REPO_ROOT)} is current")
        return

    HEADER.parent.mkdir(parents=True, exist_ok=True)
    HEADER.write_text(rendered)
    counts = ", ".join(f"{k}={len(v)}" for k, v in load_vocabularies().items())
    print(f"wrote {HEADER.relative_to(REPO_ROOT)} ({counts})")


if __name__ == "__main__":
    main()
