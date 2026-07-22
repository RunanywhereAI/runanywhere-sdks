"""Tests for the JSON-Schema -> GBNF grammar converter (ported from Electron)."""
from __future__ import annotations

import re

from runanywhere.grammar import json_schema_to_grammar


# --------------------------------------------------------------------------
# Helpers (ported from Electron grammar.test.js)
# --------------------------------------------------------------------------

def rhs_of(grammar: str, rule_name: str) -> str:
    """Return the RHS (text right of '::=') for the line defining `rule_name`."""
    line = None
    for candidate in grammar.split("\n"):
        if candidate.split("::=")[0].strip() == rule_name:
            line = candidate
            break
    assert line is not None, f'expected a rule named "{rule_name}" in:\n{grammar}'
    return line[line.index("::=") + 3 :].strip()


def defined_rule_names(grammar: str) -> set[str]:
    """The set of defined rule names (text left of '::=' on each line)."""
    names: set[str] = set()
    for line in grammar.split("\n"):
        if "::=" not in line:
            continue
        names.add(line.split("::=")[0].strip())
    return names


def assert_closed(grammar: str) -> None:
    """Every referenced identifier must be a defined rule; exactly one root; no dup LHS."""
    lines = [l for l in grammar.split("\n") if "::=" in l]

    root_lines = [l for l in lines if l.split("::=")[0].strip() == "root"]
    assert len(root_lines) == 1, f"expected exactly one root ::= line in:\n{grammar}"

    seen: dict[str, int] = {}
    for line in lines:
        lhs = line.split("::=")[0].strip()
        seen[lhs] = seen.get(lhs, 0) + 1
    for lhs, count in seen.items():
        assert count == 1, f'rule "{lhs}" defined {count} times in:\n{grammar}'

    defined = defined_rule_names(grammar)
    for line in lines:
        rhs = line[line.index("::=") + 3 :]
        # strip all double-quoted literals (handles escaped \" inside)
        rhs = re.sub(r'"(?:\\.|[^"\\])*"', " ", rhs)
        # strip all [...] char-classes
        rhs = re.sub(r"\[[^\]]*\]", " ", rhs)
        ids = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", rhs)
        for id_ in ids:
            assert id_ in defined, (
                f'dangling reference "{id_}" on line "{line.strip()}" '
                f'— defined rules: {", ".join(sorted(defined))}'
            )


# --------------------------------------------------------------------------
# Primitive root types
# --------------------------------------------------------------------------

def test_string_root_and_primitive():
    g = json_schema_to_grammar({"type": "string"})
    assert rhs_of(g, "root") == "string"
    assert "string" in defined_rule_names(g)
    assert re.search(r'^string ::= "\\""', g, re.M)
    assert_closed(g)


def test_number_root_and_primitive():
    g = json_schema_to_grammar({"type": "number"})
    assert rhs_of(g, "root") == "number"
    assert re.search(r"^number ::= ", g, re.M)
    assert_closed(g)


def test_integer_root_and_primitive():
    g = json_schema_to_grammar({"type": "integer"})
    assert rhs_of(g, "root") == "integer"
    assert re.search(r'^integer ::= "-"\? ', g, re.M)
    assert_closed(g)


def test_boolean_root_and_primitive():
    g = json_schema_to_grammar({"type": "boolean"})
    assert rhs_of(g, "root") == "boolean"
    assert re.search(r'^boolean ::= "true" \| "false"$', g, re.M)
    assert_closed(g)


def test_missing_type_defaults_to_string():
    g = json_schema_to_grammar({})
    assert rhs_of(g, "root") == "string"
    assert_closed(g)


def test_null_root_is_inline_literal():
    g = json_schema_to_grammar({"type": "null"})
    assert rhs_of(g, "root") == '"null"'
    # only the root line should exist — no primitive rule for null
    assert len(g.split("\n")) == 1
    assert_closed(g)


# --------------------------------------------------------------------------
# Objects (with required keys)
# --------------------------------------------------------------------------

def test_object_keys_escaped_comma_separated_braced():
    g = json_schema_to_grammar(
        {
            "type": "object",
            "properties": {"name": {"type": "string"}, "age": {"type": "integer"}},
            "required": ["name", "age"],
        }
    )
    obj_rhs = rhs_of(g, "obj0")
    assert '"\\"name\\""' in obj_rhs
    assert '"\\"age\\""' in obj_rhs
    assert obj_rhs.startswith('"{" ws')
    assert obj_rhs.endswith('ws "}"')
    assert ' ws "," ws ' in obj_rhs
    assert "ws" in defined_rule_names(g)
    assert re.search(r"^ws ::= \[ \\t\\n\]\*$", g, re.M)
    assert_closed(g)


def test_empty_object():
    g = json_schema_to_grammar({"type": "object"})
    assert rhs_of(g, "obj0") == '"{" ws "}"'
    assert_closed(g)


def test_empty_object_explicit_props():
    g = json_schema_to_grammar({"type": "object", "properties": {}})
    assert rhs_of(g, "obj0") == '"{" ws "}"'
    assert_closed(g)


def test_single_property_object_has_no_comma_separator():
    g = json_schema_to_grammar(
        {"type": "object", "properties": {"only": {"type": "string"}}}
    )
    obj_rhs = rhs_of(g, "obj0")
    assert obj_rhs == '"{" ws "\\"only\\"" ws ":" ws string ws "}"'
    assert ' ws "," ws ' not in obj_rhs
    assert_closed(g)


def test_property_keys_preserve_insertion_order():
    g = json_schema_to_grammar(
        {
            "type": "object",
            "properties": {
                "zeta": {"type": "string"},
                "alpha": {"type": "string"},
                "mid": {"type": "string"},
            },
        }
    )
    obj_rhs = rhs_of(g, "obj0")
    assert obj_rhs.index("zeta") < obj_rhs.index("alpha") < obj_rhs.index("mid")
    assert_closed(g)


def test_required_array_is_ignored():
    with_req = json_schema_to_grammar(
        {
            "type": "object",
            "properties": {"a": {"type": "string"}, "b": {"type": "integer"}},
            "required": ["a", "b"],
        }
    )
    without_req = json_schema_to_grammar(
        {
            "type": "object",
            "properties": {"a": {"type": "string"}, "b": {"type": "integer"}},
        }
    )
    assert with_req == without_req
    assert_closed(with_req)


def test_object_property_null_is_inline_literal():
    g = json_schema_to_grammar(
        {"type": "object", "properties": {"x": {"type": "null"}}}
    )
    obj_rhs = rhs_of(g, "obj0")
    assert obj_rhs == '"{" ws "\\"x\\"" ws ":" ws "null" ws "}"'
    assert "null" not in defined_rule_names(g)
    assert_closed(g)


# --------------------------------------------------------------------------
# Arrays (with maxItems)
# --------------------------------------------------------------------------

def test_array_with_items_star_form():
    g = json_schema_to_grammar({"type": "array", "items": {"type": "integer"}})
    arr_rhs = rhs_of(g, "arr0")
    assert arr_rhs.startswith('"[" ws')
    assert arr_rhs.endswith('ws "]"')
    assert 'integer ( ws "," ws integer )*' in arr_rhs
    assert_closed(g)


def test_array_without_items_defaults_to_string():
    g = json_schema_to_grammar({"type": "array"})
    arr_rhs = rhs_of(g, "arr0")
    assert 'string ( ws "," ws string )*' in arr_rhs
    assert "string" in defined_rule_names(g)
    assert_closed(g)


def test_array_of_integer_no_string_primitive():
    g = json_schema_to_grammar({"type": "array", "items": {"type": "integer"}})
    assert "integer" in defined_rule_names(g)
    assert "string" not in defined_rule_names(g)
    assert_closed(g)


def test_maxitems_zero_only_empty_array():
    g = json_schema_to_grammar(
        {"type": "array", "items": {"type": "string"}, "maxItems": 0}
    )
    assert_closed(g)
    assert re.search(r'::= "\[" ws "\]"', g)


def test_maxitems_n_generates_n_tail_rules():
    g = json_schema_to_grammar(
        {"type": "array", "items": {"type": "string"}, "maxItems": 3}
    )
    assert_closed(g)
    assert re.search(r"arr\d+t1 ::=", g)
    assert re.search(r"arr\d+t2 ::=", g)
    assert re.search(r"arr\d+t3 ::=", g)
    assert not re.search(r"arr\d+t4 ::=", g)
    # the unbounded `*` form is gone
    assert not re.search(r'\( ws "," ws string \)\*', g)


def test_maxitems_one_allows_zero_or_one():
    g = json_schema_to_grammar(
        {"type": "array", "items": {"type": "integer"}, "maxItems": 1}
    )
    assert_closed(g)
    assert re.search(r"arr\d+t1 ::= integer", g)
    assert re.search(r'::= "\[" ws \( arr\d+t1 \)\? ws "\]"', g)


def test_maxitems_bounds_array_nested_in_object():
    g = json_schema_to_grammar(
        {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}, "maxItems": 4},
            },
            "required": ["title", "tags"],
        }
    )
    assert_closed(g)
    assert re.search(r"arr\d+t4 ::=", g)
    assert not re.search(r"arr\d+t5 ::=", g)


def test_no_maxitems_keeps_unbounded_star():
    g = json_schema_to_grammar({"type": "array", "items": {"type": "string"}})
    assert_closed(g)
    assert re.search(r'\( ws "," ws string \)\*', g)


def test_maxitems_ignored_for_non_array():
    g = json_schema_to_grammar({"type": "string", "maxItems": 3})
    assert_closed(g)
    assert re.search(r"root ::= string", g)
    assert not re.search(r"t1 ::=", g)


# --------------------------------------------------------------------------
# Enum
# --------------------------------------------------------------------------

def test_enum_of_strings():
    g = json_schema_to_grammar({"enum": ["a", "b", "c"]})
    assert rhs_of(g, "enum0") == '"\\"a\\"" | "\\"b\\"" | "\\"c\\""'
    assert rhs_of(g, "root") == "enum0"
    assert_closed(g)


def test_enum_of_numbers():
    g = json_schema_to_grammar({"enum": [1, 2, 3]})
    assert rhs_of(g, "enum0") == '"1" | "2" | "3"'
    assert_closed(g)


def test_enum_mixed():
    g = json_schema_to_grammar({"enum": ["x", 7, True]})
    assert rhs_of(g, "enum0") == '"\\"x\\"" | "7" | "true"'
    assert_closed(g)


def test_enum_single_value():
    g = json_schema_to_grammar({"enum": ["only"]})
    assert rhs_of(g, "enum0") == '"\\"only\\""'
    assert_closed(g)


def test_enum_of_booleans_not_boolean_primitive():
    g = json_schema_to_grammar({"enum": [True, False]})
    assert rhs_of(g, "enum0") == '"true" | "false"'
    assert "boolean" not in defined_rule_names(g)
    assert_closed(g)


def test_empty_enum_defaults_to_string():
    g = json_schema_to_grammar({"enum": []})
    assert rhs_of(g, "root") == "string"
    assert "enum0" not in defined_rule_names(g)
    assert_closed(g)


def test_empty_enum_with_type():
    g = json_schema_to_grammar({"enum": [], "type": "boolean"})
    assert rhs_of(g, "root") == "boolean"
    assert "boolean" in defined_rule_names(g)
    assert_closed(g)


# --------------------------------------------------------------------------
# const
# --------------------------------------------------------------------------

def test_const_string():
    g = json_schema_to_grammar({"const": "hello"})
    assert rhs_of(g, "const0") == '"\\"hello\\""'
    assert rhs_of(g, "root") == "const0"
    assert_closed(g)


def test_const_number():
    g = json_schema_to_grammar({"const": 42})
    assert rhs_of(g, "const0") == '"42"'
    assert_closed(g)


def test_const_boolean():
    g = json_schema_to_grammar({"const": False})
    assert rhs_of(g, "const0") == '"false"'
    assert_closed(g)


def test_const_falsy_values():
    g_zero = json_schema_to_grammar({"const": 0})
    assert rhs_of(g_zero, "const0") == '"0"'
    assert rhs_of(g_zero, "root") == "const0"
    assert_closed(g_zero)

    g_empty = json_schema_to_grammar({"const": ""})
    assert rhs_of(g_empty, "const0") == '"\\"\\""'
    assert rhs_of(g_empty, "root") == "const0"
    assert_closed(g_empty)


def test_const_special_char_string():
    g = json_schema_to_grammar({"const": 'a"b'})
    assert rhs_of(g, "const0") == '"\\"a\\\\\\"b\\""'
    assert_closed(g)


# --------------------------------------------------------------------------
# Precedence: anyOf > const > enum > type
# --------------------------------------------------------------------------

def test_const_wins_over_type():
    g = json_schema_to_grammar({"type": "string", "const": "x"})
    assert rhs_of(g, "root") == "const0"
    assert rhs_of(g, "const0") == '"\\"x\\""'
    assert "string" not in defined_rule_names(g)
    assert_closed(g)


def test_const_wins_over_enum():
    g = json_schema_to_grammar({"const": "k", "enum": ["a", "b"]})
    assert rhs_of(g, "root") == "const0"
    assert "enum0" not in defined_rule_names(g)
    assert_closed(g)


def test_enum_wins_over_type():
    g = json_schema_to_grammar({"type": "integer", "enum": [1, 2]})
    assert rhs_of(g, "root") == "enum0"
    assert rhs_of(g, "enum0") == '"1" | "2"'
    assert "integer" not in defined_rule_names(g)
    assert_closed(g)


def test_anyof_wins_over_const_enum_type():
    g = json_schema_to_grammar(
        {
            "type": "string",
            "const": "x",
            "enum": ["a"],
            "anyOf": [{"type": "boolean"}, {"type": "null"}],
        }
    )
    assert rhs_of(g, "root") == "any0"
    assert rhs_of(g, "any0") == 'boolean | "null"'
    assert "const0" not in defined_rule_names(g)
    assert "enum0" not in defined_rule_names(g)
    assert_closed(g)


# --------------------------------------------------------------------------
# anyOf
# --------------------------------------------------------------------------

def test_anyof_alternation():
    g = json_schema_to_grammar(
        {"anyOf": [{"type": "string"}, {"type": "integer"}, {"type": "boolean"}]}
    )
    assert rhs_of(g, "any0") == "string | integer | boolean"
    assert rhs_of(g, "root") == "any0"
    assert_closed(g)


def test_anyof_with_object_subschemas():
    g = json_schema_to_grammar(
        {
            "anyOf": [
                {"type": "object", "properties": {"a": {"type": "string"}}},
                {"type": "object", "properties": {"b": {"type": "integer"}}},
            ]
        }
    )
    assert re.match(r"^obj\d+ \| obj\d+$", rhs_of(g, "any0"))
    assert_closed(g)


def test_anyof_single_member():
    g = json_schema_to_grammar({"anyOf": [{"type": "string"}]})
    assert rhs_of(g, "any0") == "string"
    assert rhs_of(g, "root") == "any0"
    assert_closed(g)


def test_empty_anyof_defaults_to_string():
    g = json_schema_to_grammar({"anyOf": []})
    assert rhs_of(g, "root") == "string"
    assert "any0" not in defined_rule_names(g)
    assert_closed(g)


# --------------------------------------------------------------------------
# Nesting
# --------------------------------------------------------------------------

def test_array_of_objects():
    g = json_schema_to_grammar(
        {"type": "array", "items": {"type": "object", "properties": {"k": {"type": "string"}}}}
    )
    arr_name = rhs_of(g, "root")
    arr_rhs = rhs_of(g, arr_name)
    assert re.search(r'obj\d+ \( ws "," ws obj\d+ \)\*', arr_rhs)
    assert_closed(g)


def test_array_of_anyof():
    g = json_schema_to_grammar(
        {"type": "array", "items": {"anyOf": [{"type": "string"}, {"type": "number"}]}}
    )
    assert rhs_of(g, "any0") == "string | number"
    arr_name = rhs_of(g, "root")
    assert re.search(r'any0 \( ws "," ws any0 \)\*', rhs_of(g, arr_name))
    assert_closed(g)


# --------------------------------------------------------------------------
# Key escaping
# --------------------------------------------------------------------------

def test_property_key_with_double_quote_escaped():
    g = json_schema_to_grammar({"type": "object", "properties": {'a"b': {"type": "string"}}})
    obj_rhs = rhs_of(g, "obj0")
    assert '"\\"a\\"b\\""' in obj_rhs
    assert_closed(g)


def test_property_key_with_backslash_escaped():
    g = json_schema_to_grammar({"type": "object", "properties": {"a\\b": {"type": "string"}}})
    obj_rhs = rhs_of(g, "obj0")
    assert '"\\"a\\\\b\\""' in obj_rhs
    assert_closed(g)


# --------------------------------------------------------------------------
# Primitive deduplication + determinism
# --------------------------------------------------------------------------

def test_primitive_defined_once():
    g = json_schema_to_grammar(
        {
            "type": "object",
            "properties": {
                "a": {"type": "string"},
                "b": {"type": "string"},
                "c": {"type": "array", "items": {"type": "string"}},
            },
        }
    )
    string_defs = [l for l in g.split("\n") if l.split("::=")[0].strip() == "string"]
    assert len(string_defs) == 1
    ws_defs = [l for l in g.split("\n") if l.split("::=")[0].strip() == "ws"]
    assert len(ws_defs) == 1
    assert_closed(g)


def test_determinism():
    schema = {
        "type": "object",
        "properties": {
            "name": {"type": "string"},
            "items": {"type": "array", "items": {"type": "integer"}},
            "mode": {"enum": ["x", "y"]},
            "sub": {"type": "object", "properties": {"flag": {"type": "boolean"}}},
        },
    }
    assert json_schema_to_grammar(schema) == json_schema_to_grammar(schema)


def test_determinism_with_maxitems():
    schema = {"type": "array", "items": {"type": "string"}, "maxItems": 3}
    assert json_schema_to_grammar(schema) == json_schema_to_grammar(schema)


# --------------------------------------------------------------------------
# Tool-call composite
# --------------------------------------------------------------------------

def test_tool_call_composite():
    g = json_schema_to_grammar(
        {
            "anyOf": [
                {
                    "type": "object",
                    "properties": {
                        "name": {"const": "get_weather"},
                        "arguments": {
                            "type": "object",
                            "properties": {"city": {"type": "string"}},
                            "required": ["city"],
                        },
                    },
                    "required": ["name", "arguments"],
                },
                {
                    "type": "object",
                    "properties": {
                        "name": {"const": "set_timer"},
                        "arguments": {
                            "type": "object",
                            "properties": {"seconds": {"type": "integer"}},
                            "required": ["seconds"],
                        },
                    },
                    "required": ["name", "arguments"],
                },
            ]
        }
    )
    assert_closed(g)
    assert '"\\"get_weather\\""' in g
    assert '"\\"set_timer\\""' in g

    root_target = rhs_of(g, "root")
    any_rhs = rhs_of(g, root_target)
    alts = [x.strip() for x in any_rhs.split("|")]
    assert len(alts) == 2
    assert all(re.match(r"^obj\d+$", a) for a in alts)
    assert alts[0] != alts[1]


# --------------------------------------------------------------------------
# Non-dict sub-schemas (a boolean is a legal JSON Schema) must not crash — the
# JS original reads missing keys off a boolean as undefined and falls through
# to `string`; the Python port must do the same, not raise AttributeError.
# --------------------------------------------------------------------------

def test_boolean_property_subschema_does_not_raise():
    g = json_schema_to_grammar({"type": "object", "properties": {"x": True}})
    assert "root ::=" in g  # built a grammar instead of crashing


def test_boolean_items_subschema_does_not_raise():
    g = json_schema_to_grammar({"type": "array", "items": True})
    assert "root ::=" in g


def test_top_level_boolean_schema_does_not_raise():
    assert "root ::=" in json_schema_to_grammar(True)
