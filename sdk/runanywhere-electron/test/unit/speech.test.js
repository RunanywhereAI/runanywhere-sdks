const { test } = require('node:test');
const assert = require('node:assert/strict');

const { speakableText } = require('../../dist/speech');

test('strips bold/italic so the voice does not say "asterisk"', () => {
  assert.equal(speakableText('**Paris** is the *capital* of France.'), 'Paris is the capital of France.');
  assert.equal(speakableText('__really__ and _quite_ good'), 'really and quite good');
  assert.ok(!speakableText('**a** *b* _c_ ~~d~~').includes('*'));
});

test('removes list markers and headings but keeps the words', () => {
  assert.equal(speakableText('## Steps\n- one\n- two\n1. three'), 'Steps one two three');
  assert.equal(speakableText('* bullet with a * inside'), 'bullet with a inside');
});

test('drops code blocks entirely and unwraps inline code', () => {
  assert.equal(speakableText('Run `npm test` now.'), 'Run npm test now.');
  // The removed block leaves a sentence break, which is what you want to hear.
  assert.equal(speakableText('Before\n```\nconst x = 1;\n```\nAfter'), 'Before. After');
});

test('links and images read as their text, not their URL', () => {
  assert.equal(speakableText('See [the docs](https://example.com/a_b) please.'), 'See the docs please.');
  assert.equal(speakableText('![a red circle](x.png)'), 'a red circle');
});

test('speaks arithmetic between numbers', () => {
  assert.equal(speakableText('5 * 3 = 15'), '5 times 3 equals 15');
  assert.equal(speakableText('10 / 2 = 5'), '10 divided by 2 equals 5');
  assert.equal(speakableText('7 + 1'), '7 plus 1');
  assert.equal(speakableText('9 - 4'), '9 minus 4');
});

test('leaves ordinary hyphenated prose alone', () => {
  // The arithmetic rules must not turn "well-known" into "well minus known".
  assert.equal(speakableText('A well-known state-of-the-art result.'), 'A well-known state-of-the-art result.');
});

test('says units and symbols out loud', () => {
  assert.equal(speakableText('It is 20°C and 30% humid.'), 'It is 20 degrees Celsius and 30 percent humid.');
  assert.equal(speakableText('≈ 5 ± 1'), 'approximately 5 plus or minus 1');
  assert.equal(speakableText('cats & dogs'), 'cats and dogs');
  assert.equal(speakableText('costs $20 today'), 'costs 20 dollars today');
});

test('drops emoji rather than pronouncing them', () => {
  assert.equal(speakableText('Done ✅ and shipped 🚀'), 'Done and shipped');
});

test('table rows become comma-separated speech', () => {
  assert.equal(speakableText('| a | b |\n| --- | --- |\n| 1 | 2 |'), 'a, b. 1, 2');
});

test('paragraph breaks become a spoken pause', () => {
  assert.equal(speakableText('First idea.\n\nSecond idea.'), 'First idea. Second idea.');
});

test('empty and nullish input is safe', () => {
  assert.equal(speakableText(''), '');
  assert.equal(speakableText(undefined), '');
});

test('a realistic markdown answer comes out clean', () => {
  const raw = '**Gravity** is not a force — it is *curvature*.\n\n' +
    '- Mass bends spacetime\n- Objects follow the straightest path\n\n' +
    'So `F = ma` still works at 9.8 m/s² (about 32 ft/s²).';
  const out = speakableText(raw);
  assert.ok(!/[*_`#|]/.test(out), 'no markdown marks survive: ' + out);
  assert.match(out, /^Gravity is not a force/);
  assert.match(out, /Mass bends spacetime/);
});
