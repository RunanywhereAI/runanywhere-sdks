"""Convert a (subset of) JSON Schema to a GBNF grammar for constrained decoding."""

# grammar.py — convert a (subset of) JSON Schema to a GBNF grammar so a llama.cpp
# style decoder can *constrain* decoding to valid JSON of the requested shape
# (guaranteed parseable output, not prompt-and-hope). Supports object/array/
# string/number/integer/boolean/null/enum/const/anyOf and nesting — enough for
# structured extraction. Ported verbatim from the Electron SDK's grammar.ts.

from __future__ import annotations

import json
import math
from typing import Any, Dict

# A JSON Schema is just a dict here (matching the Electron `JsonSchema` interface):
#   type?: 'object'|'array'|'string'|'number'|'integer'|'boolean'|'null'
#   properties?: dict[str, JsonSchema]
#   required?: list[str]
#   items?: JsonSchema
#   enum?: list[str|int|float|bool]
#   const?: str|int|float|bool
#   anyOf?: list[JsonSchema]
#   maxItems?: int   (only applies to type 'array')
JsonSchema = dict

PRIMITIVES: Dict[str, str] = {
    "ws": "ws ::= [ \\t\\n]*",
    "string": 'string ::= "\\"" ( [^"\\\\] | "\\\\" ["\\\\/bfnrt] )* "\\""',
    "integer": 'integer ::= "-"? ( "0" | [1-9] [0-9]* )',
    "number": 'number ::= "-"? ( "0" | [1-9] [0-9]* ) ( "." [0-9]+ )? ( [eE] [-+]? [0-9]+ )?',
    "boolean": 'boolean ::= "true" | "false"',
}


def _lit(s: str) -> str:
    """Wrap literal text `s` as a GBNF double-quoted literal (escaping \\ and ")."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _json_stringify(v: Any) -> str:
    """Match JS JSON.stringify for the scalar const/enum values we support.

    JS has no int/float distinction, so an integer-valued float renders as
    `5` (not `5.0`), and JSON.stringify never escapes non-ASCII. Mirror both so
    a schema with non-ASCII or float-integer const/enum literals produces the
    identical GBNF the Electron SDK emits.
    """
    if isinstance(v, float) and math.isfinite(v) and v.is_integer():
        v = int(v)
    return json.dumps(v, ensure_ascii=False)


def json_schema_to_grammar(schema: dict) -> str:
    """Port of Electron grammar.ts jsonSchemaToGrammar — produces identical GBNF."""
    rules: list[str] = []
    # `used` mirrors the JS Set: insertion-ordered membership. Python's set is
    # unordered, so we use a dict (insertion order preserved) to keep the
    # emitted primitive order identical to the Electron output.
    used: Dict[str, None] = {}
    # `n` is a mutable counter shared across the nested build() calls.
    counter = {"n": 0}

    def build(s: dict) -> str:
        # A JSON Schema value may legally be a bool (`{"properties": {"x": true}}`) or otherwise
        # non-dict. JS reads missing keys off it as undefined and falls through to `string`;
        # Python would raise AttributeError on `.get`, so coerce to that same "no constraint" path.
        if not isinstance(s, dict):
            used["string"] = None
            return "string"
        any_of = s.get("anyOf")
        if any_of:
            name = f"any{counter['n']}"
            counter["n"] += 1
            rules.append(f"{name} ::= " + " | ".join(build(sub) for sub in any_of))
            return name
        # JS uses `s.const !== undefined`; Python's equivalent is "key present".
        if "const" in s:
            name = f"const{counter['n']}"
            counter["n"] += 1
            rules.append(f"{name} ::= {_lit(_json_stringify(s['const']))}")
            return name
        enum = s.get("enum")
        if enum:
            name = f"enum{counter['n']}"
            counter["n"] += 1
            rules.append(
                f"{name} ::= " + " | ".join(_lit(_json_stringify(v)) for v in enum)
            )
            return name

        t = s.get("type")
        if t == "object":
            props = s.get("properties") or {}
            keys = list(props.keys())
            name = f"obj{counter['n']}"
            counter["n"] += 1
            used["ws"] = None
            if not keys:
                rules.append(f'{name} ::= "{{" ws "}}"')
                return name
            parts = [f'{_lit(chr(34) + k + chr(34))} ws ":" ws {build(props[k])}' for k in keys]
            rules.append(f'{name} ::= "{{" ws ' + ' ws "," ws '.join(parts) + ' ws "}"')
            return name

        if t == "array":
            item = build(s["items"]) if s.get("items") else "string"
            if not s.get("items"):
                used["string"] = None
            name = f"arr{counter['n']}"
            counter["n"] += 1
            used["ws"] = None
            raw_max = s.get("maxItems")
            # JS `typeof maxItems === 'number'` excludes booleans; in Python bool
            # is an int subclass, so guard against it explicitly (maxItems: true
            # must be treated as unbounded, not as a bound of 1).
            max_items = (
                math.floor(raw_max)
                if isinstance(raw_max, (int, float)) and not isinstance(raw_max, bool)
                else None
            )
            if max_items is None:
                rules.append(
                    f'{name} ::= "[" ws ( {item} ( ws "," ws {item} )* )? ws "]"'
                )
            elif max_items <= 0:
                rules.append(f'{name} ::= "[" ws "]"')
            else:
                # Bound the length with a chain of nested optional tails (portable
                # GBNF — uses only `?`, no {m,n} repetition): tail_k allows up to k
                # items, and the array is an optional tail_max. 0..max items.
                prev = ""
                for k in range(1, max_items + 1):
                    tn = f"{name}t{k}"
                    if k == 1:
                        rules.append(f"{tn} ::= {item}")
                    else:
                        rules.append(f'{tn} ::= {item} ( ws "," ws {prev} )?')
                    prev = tn
                rules.append(f'{name} ::= "[" ws ( {prev} )? ws "]"')
            return name

        if t == "integer":
            used["integer"] = None
            return "integer"
        if t == "number":
            used["number"] = None
            return "number"
        if t == "boolean":
            used["boolean"] = None
            return "boolean"
        if t == "null":
            return '"null"'
        # 'string' and default
        used["string"] = None
        return "string"

    root = build(schema)
    lines = [f"root ::= {root}", *rules]
    for p in used:
        lines.append(PRIMITIVES[p])
    return "\n".join(lines)
