// Unit tests for bounded arrays (maxItems) in the JSON-Schema -> GBNF converter.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { jsonSchemaToGrammar } = require('../../dist/grammar');

// Assert the grammar is "closed": every referenced rule identifier is defined,
// and exactly one `root ::=` rule exists. (Same invariant used by grammar.test.js.)
function assertClosed(grammar) {
  const lines = grammar.split('\n').filter((l) => l.includes('::='));
  const defined = new Set();
  for (const line of lines) {
    const name = line.split('::=')[0].trim();
    assert.ok(!defined.has(name), `rule ${name} defined more than once`);
    defined.add(name);
  }
  const roots = lines.filter((l) => l.split('::=')[0].trim() === 'root');
  assert.equal(roots.length, 1, 'exactly one root rule');
  for (const line of lines) {
    const rhs = line
      .slice(line.indexOf('::=') + 3)
      .replace(/"(\\.|[^"\\])*"/g, ' ') // strip quoted literals
      .replace(/\[[^\]]*\]/g, ' '); // strip char classes
    const ids = rhs.match(/[A-Za-z_][A-Za-z0-9_]*/g) || [];
    for (const id of ids) {
      assert.ok(defined.has(id), `dangling rule reference '${id}' in: ${line}`);
    }
  }
}

test('maxItems: 0 -> only the empty array is allowed', () => {
  const g = jsonSchemaToGrammar({ type: 'array', items: { type: 'string' }, maxItems: 0 });
  assertClosed(g);
  // The array rule is just brackets around whitespace; no item rule referenced.
  assert.match(g, /::= "\[" ws "\]"/);
});

test('maxItems: N generates N nested tail rules and an optional outer tail', () => {
  const g = jsonSchemaToGrammar({ type: 'array', items: { type: 'string' }, maxItems: 3 });
  assertClosed(g);
  // Three tail rules for up to 3 items.
  assert.match(g, /arr\d+t1 ::=/);
  assert.match(g, /arr\d+t2 ::=/);
  assert.match(g, /arr\d+t3 ::=/);
  assert.doesNotMatch(g, /arr\d+t4 ::=/);
  // The array is an optional outer tail (0..max items) — the `*` form is gone.
  assert.doesNotMatch(g, /\( ws "," ws string \)\*/);
});

test('maxItems: 1 allows zero or one item', () => {
  const g = jsonSchemaToGrammar({ type: 'array', items: { type: 'integer' }, maxItems: 1 });
  assertClosed(g);
  assert.match(g, /arr\d+t1 ::= integer/);
  // Outer array wraps the single tail in an optional group.
  assert.match(g, /::= "\[" ws \( arr\d+t1 \)\? ws "\]"/);
});

test('maxItems bounds arrays nested inside an object, grammar stays closed', () => {
  const g = jsonSchemaToGrammar({
    type: 'object',
    properties: {
      title: { type: 'string' },
      tags: { type: 'array', items: { type: 'string' }, maxItems: 4 },
    },
    required: ['title', 'tags'],
  });
  assertClosed(g);
  assert.match(g, /arr\d+t4 ::=/);
  assert.doesNotMatch(g, /arr\d+t5 ::=/);
});

test('no maxItems keeps the unbounded ( ... )* form (regression)', () => {
  const g = jsonSchemaToGrammar({ type: 'array', items: { type: 'string' } });
  assertClosed(g);
  assert.match(g, /\( ws "," ws string \)\*/);
});

test('maxItems is ignored for non-array types', () => {
  // maxItems on a string is meaningless and must not change the string rule.
  const g = jsonSchemaToGrammar({ type: 'string', maxItems: 3 });
  assertClosed(g);
  assert.match(g, /root ::= string/);
  assert.doesNotMatch(g, /t1 ::=/);
});

test('determinism holds with maxItems', () => {
  const schema = { type: 'array', items: { type: 'string' }, maxItems: 3 };
  assert.equal(jsonSchemaToGrammar(schema), jsonSchemaToGrammar(schema));
});
