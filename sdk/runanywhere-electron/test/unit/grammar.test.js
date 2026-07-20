const { test } = require('node:test');
const assert = require('node:assert/strict');

const { jsonSchemaToGrammar } = require('../../dist/grammar');

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------

/** Return the RHS (text right of '::=') for the line defining `ruleName`. */
function rhsOf(grammar, ruleName) {
  const line = grammar
    .split('\n')
    .find((l) => l.split('::=')[0].trim() === ruleName);
  assert.ok(line, `expected a rule named "${ruleName}" in:\n${grammar}`);
  return line.slice(line.indexOf('::=') + 3).trim();
}

/** The set of defined rule names (text left of '::=' on each line). */
function definedRuleNames(grammar) {
  const names = new Set();
  for (const line of grammar.split('\n')) {
    if (!line.includes('::=')) continue;
    names.add(line.split('::=')[0].trim());
  }
  return names;
}

/**
 * CROWN-JEWEL INVARIANT: the grammar is closed.
 * Every identifier referenced on any RHS (after stripping quoted string
 * literals and [...] char-classes) must be a defined rule name. Also there
 * must be exactly one `root ::=` line, and no rule name is defined twice
 * (the generator dedups primitives via a Set and hands out unique n-suffixed
 * names, so a duplicate LHS would be a real regression).
 */
function assertClosed(grammar) {
  const lines = grammar.split('\n').filter((l) => l.includes('::='));

  // exactly one root ::= line
  const rootLines = lines.filter((l) => l.split('::=')[0].trim() === 'root');
  assert.equal(rootLines.length, 1, `expected exactly one root ::= line in:\n${grammar}`);

  // no rule name defined more than once (LHS uniqueness)
  const seen = new Map();
  for (const line of lines) {
    const lhs = line.split('::=')[0].trim();
    seen.set(lhs, (seen.get(lhs) || 0) + 1);
  }
  for (const [lhs, count] of seen) {
    assert.equal(count, 1, `rule "${lhs}" defined ${count} times in:\n${grammar}`);
  }

  const defined = definedRuleNames(grammar);

  for (const line of lines) {
    let rhs = line.slice(line.indexOf('::=') + 3);
    // strip all double-quoted literals (handles escaped \" inside)
    rhs = rhs.replace(/"(?:\\.|[^"\\])*"/g, ' ');
    // strip all [...] char-classes
    rhs = rhs.replace(/\[[^\]]*\]/g, ' ');
    const ids = rhs.match(/[A-Za-z_][A-Za-z0-9_]*/g) || [];
    for (const id of ids) {
      assert.ok(
        defined.has(id),
        `dangling reference "${id}" on line "${line.trim()}" — defined rules: ${[...defined].join(', ')}`,
      );
    }
  }
}

// --------------------------------------------------------------------------
// Primitive root types
// --------------------------------------------------------------------------

test('string: root references string and the string primitive rule is present', () => {
  const g = jsonSchemaToGrammar({ type: 'string' });
  assert.equal(rhsOf(g, 'root'), 'string');
  assert.ok(definedRuleNames(g).has('string'));
  assert.match(g, /^string ::= "\\""/m);
  assertClosed(g);
});

test('number: root references number and the number primitive rule is present', () => {
  const g = jsonSchemaToGrammar({ type: 'number' });
  assert.equal(rhsOf(g, 'root'), 'number');
  assert.ok(definedRuleNames(g).has('number'));
  assert.match(g, /^number ::= /m);
  assertClosed(g);
});

test('integer: root references integer and the integer primitive rule is present', () => {
  const g = jsonSchemaToGrammar({ type: 'integer' });
  assert.equal(rhsOf(g, 'root'), 'integer');
  assert.ok(definedRuleNames(g).has('integer'));
  assert.match(g, /^integer ::= "-"\? /m);
  assertClosed(g);
});

test('boolean: root references boolean and the boolean primitive rule is present', () => {
  const g = jsonSchemaToGrammar({ type: 'boolean' });
  assert.equal(rhsOf(g, 'root'), 'boolean');
  assert.ok(definedRuleNames(g).has('boolean'));
  assert.match(g, /^boolean ::= "true" \| "false"$/m);
  assertClosed(g);
});

test('unknown/missing type defaults to string', () => {
  const g = jsonSchemaToGrammar({});
  assert.equal(rhsOf(g, 'root'), 'string');
  assert.ok(definedRuleNames(g).has('string'));
  assertClosed(g);
});

test('null: root is the inline literal "null" and no extra primitive rule is added', () => {
  const g = jsonSchemaToGrammar({ type: 'null' });
  assert.equal(rhsOf(g, 'root'), '"null"');
  // only the root line should exist — no primitive rule for null
  assert.equal(g.split('\n').length, 1);
  assertClosed(g);
});

// --------------------------------------------------------------------------
// Objects
// --------------------------------------------------------------------------

test('object: keys appear as GBNF-escaped quoted literals, comma-separated, ws present, wrapped in braces', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: { name: { type: 'string' }, age: { type: 'integer' } },
  });
  const objRhs = rhsOf(g, 'obj0');
  // the key "name" appears as the literal for \"name\"
  assert.ok(objRhs.includes('"\\"name\\""'), `objRhs=${objRhs}`);
  assert.ok(objRhs.includes('"\\"age\\""'), `objRhs=${objRhs}`);
  // wrapped in { and }
  assert.ok(objRhs.startsWith('"{" ws'));
  assert.ok(objRhs.endsWith('ws "}"'));
  // properties are comma-separated (the between-properties separator)
  assert.ok(objRhs.includes(' ws "," ws '), `objRhs=${objRhs}`);
  // ws primitive present
  assert.ok(definedRuleNames(g).has('ws'));
  assert.match(g, /^ws ::= \[ \\t\\n\]\*$/m);
  assertClosed(g);
});

test('empty object -> rule is { ws }', () => {
  const g = jsonSchemaToGrammar({ type: 'object' });
  assert.equal(rhsOf(g, 'obj0'), '"{" ws "}"');
  assert.ok(definedRuleNames(g).has('ws'));
  assertClosed(g);
});

test('empty object via explicit empty properties -> { ws }', () => {
  const g = jsonSchemaToGrammar({ type: 'object', properties: {} });
  assert.equal(rhsOf(g, 'obj0'), '"{" ws "}"');
  assertClosed(g);
});

test('object property values resolve to their type rules', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: { flag: { type: 'boolean' }, n: { type: 'number' } },
  });
  const objRhs = rhsOf(g, 'obj0');
  assert.ok(objRhs.includes('boolean'));
  assert.ok(objRhs.includes('number'));
  assertClosed(g);
});

test('single-property object has NO between-property comma separator', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: { only: { type: 'string' } },
  });
  const objRhs = rhsOf(g, 'obj0');
  assert.equal(objRhs, '"{" ws "\\"only\\"" ws ":" ws string ws "}"');
  // the between-properties separator ` ws "," ws ` must be absent for one prop
  assert.ok(!objRhs.includes(' ws "," ws '), `objRhs=${objRhs}`);
  assertClosed(g);
});

test('property keys preserve insertion order', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: {
      zeta: { type: 'string' },
      alpha: { type: 'string' },
      mid: { type: 'string' },
    },
  });
  const objRhs = rhsOf(g, 'obj0');
  assert.ok(
    objRhs.indexOf('zeta') < objRhs.indexOf('alpha') &&
      objRhs.indexOf('alpha') < objRhs.indexOf('mid'),
    `objRhs=${objRhs}`,
  );
  assertClosed(g);
});

test('required array is ignored (does not affect the emitted grammar)', () => {
  const withReq = jsonSchemaToGrammar({
    type: 'object',
    properties: { a: { type: 'string' }, b: { type: 'integer' } },
    required: ['a', 'b'],
  });
  const withoutReq = jsonSchemaToGrammar({
    type: 'object',
    properties: { a: { type: 'string' }, b: { type: 'integer' } },
  });
  assert.equal(withReq, withoutReq);
  assertClosed(withReq);
});

test('object property whose value is null -> inline "null" literal, no null rule', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: { x: { type: 'null' } },
  });
  const objRhs = rhsOf(g, 'obj0');
  assert.equal(objRhs, '"{" ws "\\"x\\"" ws ":" ws "null" ws "}"');
  // no separate rule named "null"
  assert.ok(!definedRuleNames(g).has('null'));
  assertClosed(g);
});

// --------------------------------------------------------------------------
// Arrays
// --------------------------------------------------------------------------

test('array with items -> [ item ( "," item )* ] shape', () => {
  const g = jsonSchemaToGrammar({ type: 'array', items: { type: 'integer' } });
  const arrRhs = rhsOf(g, 'arr0');
  assert.ok(arrRhs.startsWith('"[" ws'));
  assert.ok(arrRhs.endsWith('ws "]"'));
  assert.ok(arrRhs.includes('integer ( ws "," ws integer )*'), `arrRhs=${arrRhs}`);
  assertClosed(g);
});

test('array WITHOUT items -> item defaults to the string rule', () => {
  const g = jsonSchemaToGrammar({ type: 'array' });
  const arrRhs = rhsOf(g, 'arr0');
  assert.ok(arrRhs.includes('string ( ws "," ws string )*'), `arrRhs=${arrRhs}`);
  // string primitive must be defined since it is referenced
  assert.ok(definedRuleNames(g).has('string'));
  assertClosed(g);
});

test('array of integer does NOT emit the string primitive (only for the no-items default)', () => {
  const g = jsonSchemaToGrammar({ type: 'array', items: { type: 'integer' } });
  assert.ok(definedRuleNames(g).has('integer'));
  assert.ok(!definedRuleNames(g).has('string'));
  assertClosed(g);
});

test('array of null -> inline "null" item, no null/string primitive', () => {
  const g = jsonSchemaToGrammar({ type: 'array', items: { type: 'null' } });
  const arrRhs = rhsOf(g, 'arr0');
  assert.equal(arrRhs, '"[" ws ( "null" ( ws "," ws "null" )* )? ws "]"');
  assert.ok(!definedRuleNames(g).has('null'));
  assert.ok(!definedRuleNames(g).has('string'));
  assertClosed(g);
});

test('empty array literal is allowed (item group is optional)', () => {
  // the ( ... )? wrapper means the array may be empty; assert the optional group is present
  const g = jsonSchemaToGrammar({ type: 'array', items: { type: 'string' } });
  const arrRhs = rhsOf(g, 'arr0');
  assert.match(arrRhs, /\( string \( ws "," ws string \)\* \)\?/);
  assertClosed(g);
});

// --------------------------------------------------------------------------
// Enum
// --------------------------------------------------------------------------

test('enum of strings -> alternation of quoted string literals', () => {
  const g = jsonSchemaToGrammar({ enum: ['a', 'b', 'c'] });
  const enumRhs = rhsOf(g, 'enum0');
  assert.equal(enumRhs, '"\\"a\\"" | "\\"b\\"" | "\\"c\\""');
  assert.equal(rhsOf(g, 'root'), 'enum0');
  assertClosed(g);
});

test('enum of numbers -> numeric literals', () => {
  const g = jsonSchemaToGrammar({ enum: [1, 2, 3] });
  const enumRhs = rhsOf(g, 'enum0');
  assert.equal(enumRhs, '"1" | "2" | "3"');
  assertClosed(g);
});

test('mixed enum (string + number + boolean)', () => {
  const g = jsonSchemaToGrammar({ enum: ['x', 7, true] });
  const enumRhs = rhsOf(g, 'enum0');
  assert.equal(enumRhs, '"\\"x\\"" | "7" | "true"');
  assertClosed(g);
});

test('enum of a single value -> single literal (no alternation bar)', () => {
  const g = jsonSchemaToGrammar({ enum: ['only'] });
  assert.equal(rhsOf(g, 'enum0'), '"\\"only\\""');
  assertClosed(g);
});

test('enum of booleans -> "true" | "false" literals (not the boolean primitive)', () => {
  const g = jsonSchemaToGrammar({ enum: [true, false] });
  assert.equal(rhsOf(g, 'enum0'), '"true" | "false"');
  // it is an enum rule, NOT the shared boolean primitive
  assert.ok(!definedRuleNames(g).has('boolean'));
  assertClosed(g);
});

test('empty enum falls through to type handling (defaults to string)', () => {
  const g = jsonSchemaToGrammar({ enum: [] });
  // enum.length is 0 -> skipped; no type -> string default
  assert.equal(rhsOf(g, 'root'), 'string');
  assert.ok(!definedRuleNames(g).has('enum0'));
  assertClosed(g);
});

test('empty enum with a co-present type uses that type', () => {
  const g = jsonSchemaToGrammar({ enum: [], type: 'boolean' });
  assert.equal(rhsOf(g, 'root'), 'boolean');
  assert.ok(definedRuleNames(g).has('boolean'));
  assertClosed(g);
});

// --------------------------------------------------------------------------
// const
// --------------------------------------------------------------------------

test('const string -> single literal rule', () => {
  const g = jsonSchemaToGrammar({ const: 'hello' });
  assert.equal(rhsOf(g, 'const0'), '"\\"hello\\""');
  assert.equal(rhsOf(g, 'root'), 'const0');
  assertClosed(g);
});

test('const number -> single literal rule', () => {
  const g = jsonSchemaToGrammar({ const: 42 });
  assert.equal(rhsOf(g, 'const0'), '"42"');
  assertClosed(g);
});

test('const boolean -> single literal rule', () => {
  const g = jsonSchemaToGrammar({ const: false });
  assert.equal(rhsOf(g, 'const0'), '"false"');
  assertClosed(g);
});

test('const falsy values (0, empty string) still emit a const rule (uses !== undefined)', () => {
  const gZero = jsonSchemaToGrammar({ const: 0 });
  // JSON.stringify(0) === "0" -> lit -> "0"
  assert.equal(rhsOf(gZero, 'const0'), '"0"');
  assert.equal(rhsOf(gZero, 'root'), 'const0');
  assertClosed(gZero);

  const gEmpty = jsonSchemaToGrammar({ const: '' });
  // JSON.stringify('') === '""' -> lit escapes the two quotes -> "\"\""
  assert.equal(rhsOf(gEmpty, 'const0'), '"\\"\\""');
  assert.equal(rhsOf(gEmpty, 'root'), 'const0');
  assertClosed(gEmpty);
});

test('const with a special-character string is JSON-escaped then GBNF-escaped', () => {
  // JSON.stringify('a"b') === '"a\\"b"' (a quote and a backslash-quote);
  // lit then escapes the backslash and both quotes.
  const g = jsonSchemaToGrammar({ const: 'a"b' });
  assert.equal(rhsOf(g, 'const0'), '"\\"a\\\\\\"b\\""');
  assertClosed(g);
});

// --------------------------------------------------------------------------
// Precedence: anyOf > const > enum > type
// --------------------------------------------------------------------------

test('const wins over a co-present type (type is ignored)', () => {
  const g = jsonSchemaToGrammar({ type: 'string', const: 'x' });
  assert.equal(rhsOf(g, 'root'), 'const0');
  assert.equal(rhsOf(g, 'const0'), '"\\"x\\""');
  // the string primitive rule is NOT emitted (type branch never ran)
  assert.ok(!definedRuleNames(g).has('string'));
  assertClosed(g);
});

test('const wins over a co-present enum', () => {
  const g = jsonSchemaToGrammar({ const: 'k', enum: ['a', 'b'] });
  assert.equal(rhsOf(g, 'root'), 'const0');
  assert.ok(!definedRuleNames(g).has('enum0'));
  assertClosed(g);
});

test('enum wins over a co-present type (type is ignored)', () => {
  const g = jsonSchemaToGrammar({ type: 'integer', enum: [1, 2] });
  assert.equal(rhsOf(g, 'root'), 'enum0');
  assert.equal(rhsOf(g, 'enum0'), '"1" | "2"');
  // integer primitive NOT emitted
  assert.ok(!definedRuleNames(g).has('integer'));
  assertClosed(g);
});

test('anyOf wins over co-present const/enum/type', () => {
  const g = jsonSchemaToGrammar({
    type: 'string',
    const: 'x',
    enum: ['a'],
    anyOf: [{ type: 'boolean' }, { type: 'null' }],
  });
  assert.equal(rhsOf(g, 'root'), 'any0');
  assert.equal(rhsOf(g, 'any0'), 'boolean | "null"');
  assert.ok(!definedRuleNames(g).has('const0'));
  assert.ok(!definedRuleNames(g).has('enum0'));
  assertClosed(g);
});

// --------------------------------------------------------------------------
// anyOf
// --------------------------------------------------------------------------

test('anyOf -> alternation of the sub-schema rule references', () => {
  const g = jsonSchemaToGrammar({
    anyOf: [{ type: 'string' }, { type: 'integer' }, { type: 'boolean' }],
  });
  const anyRhs = rhsOf(g, 'any0');
  assert.equal(anyRhs, 'string | integer | boolean');
  assert.equal(rhsOf(g, 'root'), 'any0');
  assertClosed(g);
});

test('anyOf with object sub-schemas references the generated obj rules', () => {
  const g = jsonSchemaToGrammar({
    anyOf: [
      { type: 'object', properties: { a: { type: 'string' } } },
      { type: 'object', properties: { b: { type: 'integer' } } },
    ],
  });
  const anyRhs = rhsOf(g, 'any0');
  // two object rules were built and alternated
  assert.match(anyRhs, /^obj\d+ \| obj\d+$/);
  assertClosed(g);
});

test('anyOf with a single member -> alternation of one (no leading/trailing |)', () => {
  const g = jsonSchemaToGrammar({ anyOf: [{ type: 'string' }] });
  assert.equal(rhsOf(g, 'any0'), 'string');
  assert.equal(rhsOf(g, 'root'), 'any0');
  assertClosed(g);
});

test('empty anyOf falls through to type handling (defaults to string)', () => {
  const g = jsonSchemaToGrammar({ anyOf: [] });
  // anyOf.length is 0 -> skipped; no type -> string default
  assert.equal(rhsOf(g, 'root'), 'string');
  assert.ok(!definedRuleNames(g).has('any0'));
  assertClosed(g);
});

test('empty anyOf with a co-present type uses that type', () => {
  const g = jsonSchemaToGrammar({ anyOf: [], type: 'integer' });
  assert.equal(rhsOf(g, 'root'), 'integer');
  assert.ok(definedRuleNames(g).has('integer'));
  assert.ok(!definedRuleNames(g).has('any0'));
  assertClosed(g);
});

// --------------------------------------------------------------------------
// Nesting
// --------------------------------------------------------------------------

test('object within object', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: {
      user: { type: 'object', properties: { id: { type: 'integer' } } },
    },
  });
  // outer obj references an inner obj rule
  const rootRule = rhsOf(g, 'root'); // e.g. obj1 (inner built first)
  const outerRhs = rhsOf(g, rootRule);
  assert.match(outerRhs, /obj\d+/);
  assertClosed(g);
});

test('array of objects', () => {
  const g = jsonSchemaToGrammar({
    type: 'array',
    items: { type: 'object', properties: { k: { type: 'string' } } },
  });
  const arrName = rhsOf(g, 'root');
  const arrRhs = rhsOf(g, arrName);
  assert.match(arrRhs, /obj\d+ \( ws "," ws obj\d+ \)\*/);
  assertClosed(g);
});

test('object property whose value is an array of an enum', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: {
      tags: { type: 'array', items: { enum: ['red', 'green'] } },
    },
  });
  // the enum rule exists and the array references it
  assert.ok([...definedRuleNames(g)].some((n) => n.startsWith('enum')));
  assert.ok([...definedRuleNames(g)].some((n) => n.startsWith('arr')));
  assertClosed(g);
});

test('const inside a nested object', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: {
      kind: { const: 'fixed' },
      inner: { type: 'object', properties: { c: { const: 5 } } },
    },
  });
  assert.ok(g.includes('"\\"fixed\\""'));
  assert.ok(g.includes('"5"'));
  assertClosed(g);
});

test('array of anyOf', () => {
  const g = jsonSchemaToGrammar({
    type: 'array',
    items: { anyOf: [{ type: 'string' }, { type: 'number' }] },
  });
  const anyRhs = rhsOf(g, 'any0');
  assert.equal(anyRhs, 'string | number');
  const arrName = rhsOf(g, 'root');
  assert.match(rhsOf(g, arrName), /any0 \( ws "," ws any0 \)\*/);
  assertClosed(g);
});

// --------------------------------------------------------------------------
// Key escaping
// --------------------------------------------------------------------------

test('property key containing a double-quote is escaped inside the literal', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: { 'a"b': { type: 'string' } },
  });
  // key becomes lit('"a"b"') -> backslashes escaped, then quotes escaped.
  // input to lit: `"a"b"`  ; lit escapes \ (none) then " -> \"
  // => "\"a\"b\""
  const objRhs = rhsOf(g, 'obj0');
  assert.ok(objRhs.includes('"\\"a\\"b\\""'), `objRhs=${objRhs}`);
  assertClosed(g);
});

test('property key containing a backslash is escaped inside the literal', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: { 'a\\b': { type: 'string' } },
  });
  // input to lit: `"a\b"` ; lit escapes backslash first -> `"a\\b"` then quotes
  // => "\"a\\b\""
  const objRhs = rhsOf(g, 'obj0');
  assert.ok(objRhs.includes('"\\"a\\\\b\\""'), `objRhs=${objRhs}`);
  assertClosed(g);
});

// --------------------------------------------------------------------------
// Primitive deduplication
// --------------------------------------------------------------------------

test('a primitive used many times is defined exactly once', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: {
      a: { type: 'string' },
      b: { type: 'string' },
      c: { type: 'array', items: { type: 'string' } },
    },
  });
  const stringDefs = g.split('\n').filter((l) => l.split('::=')[0].trim() === 'string');
  assert.equal(stringDefs.length, 1, `string defined ${stringDefs.length} times:\n${g}`);
  // ws is also shared between the object and the array — exactly one definition
  const wsDefs = g.split('\n').filter((l) => l.split('::=')[0].trim() === 'ws');
  assert.equal(wsDefs.length, 1);
  assertClosed(g);
});

test('unused primitives are never emitted (a pure integer schema has no string/ws/boolean/number rules)', () => {
  const g = jsonSchemaToGrammar({ type: 'integer' });
  const names = definedRuleNames(g);
  assert.ok(names.has('integer'));
  for (const absent of ['string', 'ws', 'boolean', 'number']) {
    assert.ok(!names.has(absent), `did not expect "${absent}" in:\n${g}`);
  }
  assertClosed(g);
});

// --------------------------------------------------------------------------
// Determinism
// --------------------------------------------------------------------------

test('determinism: calling twice on the same schema returns identical strings', () => {
  const schema = {
    type: 'object',
    properties: {
      name: { type: 'string' },
      items: { type: 'array', items: { type: 'integer' } },
      mode: { enum: ['x', 'y'] },
      sub: { type: 'object', properties: { flag: { type: 'boolean' } } },
    },
  };
  const a = jsonSchemaToGrammar(schema);
  const b = jsonSchemaToGrammar(schema);
  assert.equal(a, b);
});

// --------------------------------------------------------------------------
// assertClosed over several schemas (crown-jewel invariant)
// --------------------------------------------------------------------------

test('assertClosed holds for a variety of schemas', () => {
  const schemas = [
    { type: 'string' },
    { type: 'null' },
    { type: 'object', properties: { a: { type: 'integer' }, b: { type: 'boolean' } } },
    { type: 'array', items: { type: 'number' } },
    { enum: ['a', 'b'] },
    { anyOf: [{ type: 'string' }, { type: 'object', properties: { x: { const: 1 } } }] },
  ];
  for (const s of schemas) {
    assertClosed(jsonSchemaToGrammar(s));
  }
});

// --------------------------------------------------------------------------
// Tool-call composite
// --------------------------------------------------------------------------

test('tool-call composite: closed, contains get_weather const, both tool rules alternated at root', () => {
  const g = jsonSchemaToGrammar({
    anyOf: [
      {
        type: 'object',
        properties: {
          name: { const: 'get_weather' },
          arguments: {
            type: 'object',
            properties: { city: { type: 'string' } },
            required: ['city'],
          },
        },
        required: ['name', 'arguments'],
      },
      {
        type: 'object',
        properties: {
          name: { const: 'set_timer' },
          arguments: {
            type: 'object',
            properties: { seconds: { type: 'integer' } },
            required: ['seconds'],
          },
        },
        required: ['name', 'arguments'],
      },
    ],
  });

  assertClosed(g);

  // const literal for get_weather present
  assert.ok(g.includes('"\\"get_weather\\""'), `grammar:\n${g}`);
  assert.ok(g.includes('"\\"set_timer\\""'), `grammar:\n${g}`);

  // root points at the anyOf rule; that rule alternates the two tool objects
  const rootTarget = rhsOf(g, 'root');
  const anyRhs = rhsOf(g, rootTarget);
  const alts = anyRhs.split('|').map((x) => x.trim());
  assert.equal(alts.length, 2);
  assert.ok(alts.every((a) => /^obj\d+$/.test(a)), `alts=${JSON.stringify(alts)}`);
  assert.notEqual(alts[0], alts[1]);
});
