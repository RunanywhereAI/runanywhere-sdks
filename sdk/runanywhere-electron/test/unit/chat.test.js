const { test } = require('node:test');
const assert = require('node:assert/strict');

const { Chat } = require('../../dist/Chat');

// A fake LLM whose generate() records the prompt it receives and streams a
// fixed sequence of string tokens back via an async generator.
function makeLlm(tokens) {
  const calls = [];
  const llm = {
    calls,
    generate(prompt) {
      calls.push(prompt);
      return (async function* () {
        for (const t of tokens) yield t;
      })();
    },
  };
  return llm;
}

// Helper that yields a distinct single token per generate() call, in order,
// so each turn's recorded assistant reply is different.
function makeLlmSequential(replies) {
  const calls = [];
  let i = 0;
  return {
    calls,
    generate(prompt) {
      calls.push(prompt);
      const token = replies[i++];
      return (async function* () {
        yield token;
      })();
    },
  };
}

async function drain(iter) {
  const out = [];
  for await (const t of iter) out.push(t);
  return out;
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

test('construction with { system } stores a system message visible in messages', () => {
  const llm = makeLlm(['x']);
  const chat = new Chat(llm, { system: 'You are helpful.' });
  const msgs = chat.messages;
  assert.equal(msgs.length, 1);
  assert.deepEqual(msgs[0], { role: 'system', content: 'You are helpful.' });
});

test('construction without system has empty messages', () => {
  const llm = makeLlm(['x']);
  const chat = new Chat(llm);
  assert.deepEqual(chat.messages, []);
});

test('construction with empty-string system does NOT store a message', () => {
  const llm = makeLlm(['x']);
  const chat = new Chat(llm, { system: '' });
  assert.deepEqual(chat.messages, []);
});

test('construction with empty opts object has empty messages', () => {
  const llm = makeLlm(['x']);
  const chat = new Chat(llm, {});
  assert.deepEqual(chat.messages, []);
});

test('construction does NOT call generate (nothing sent yet)', () => {
  const llm = makeLlm(['x']);
  // eslint-disable-next-line no-new
  new Chat(llm, { system: 'S' });
  assert.equal(llm.calls.length, 0);
});

// ---------------------------------------------------------------------------
// Streaming behavior
// ---------------------------------------------------------------------------

test('send streams the tokens exactly in order', async () => {
  const llm = makeLlm(['Hello', ' world']);
  const chat = new Chat(llm, { system: 'S' });
  const streamed = await drain(chat.send('hi'));
  assert.deepEqual(streamed, ['Hello', ' world']);
});

test('send calls generate exactly once per turn', async () => {
  const llm = makeLlm(['Hello', ' world']);
  const chat = new Chat(llm, { system: 'S' });
  await drain(chat.send('hi'));
  assert.equal(llm.calls.length, 1);
});

test('send grows internal history by 2 (user then assistant)', async () => {
  const llm = makeLlm(['Hello', ' world']);
  const chat = new Chat(llm, { system: 'S' });
  assert.equal(chat.messages.length, 1); // just the system
  await drain(chat.send('hi'));
  const msgs = chat.messages;
  assert.equal(msgs.length, 3);
  assert.equal(msgs[1].role, 'user');
  assert.equal(msgs[1].content, 'hi');
  assert.equal(msgs[2].role, 'assistant');
});

test('recorded assistant content equals concatenated tokens, trimmed', async () => {
  // Leading/trailing whitespace in the concatenation must be trimmed in history.
  const llm = makeLlm(['  Hello', ' world  ']);
  const chat = new Chat(llm);
  await drain(chat.send('hi'));
  const msgs = chat.messages;
  assert.equal(msgs[msgs.length - 1].role, 'assistant');
  assert.equal(msgs[msgs.length - 1].content, 'Hello world');
});

test('trim on recorded assistant content strips newlines and tabs, not just spaces', async () => {
  // String.prototype.trim() removes all leading/trailing whitespace incl. \n \t.
  const llm = makeLlm(['\n\t Hello', ' world \t\n']);
  const chat = new Chat(llm);
  await drain(chat.send('hi'));
  const msgs = chat.messages;
  assert.equal(msgs[msgs.length - 1].content, 'Hello world');
});

test('interior whitespace in the assistant reply is preserved (only edges trimmed)', async () => {
  const llm = makeLlm(['  a  ', '  b  ']);
  const chat = new Chat(llm);
  await drain(chat.send('hi'));
  const msgs = chat.messages;
  // Concatenation is '  a    b  '; trimming edges leaves 'a    b'.
  assert.equal(msgs[msgs.length - 1].content, 'a    b');
});

test('history is NOT appended until the stream is fully drained', async () => {
  const llm = makeLlm(['a', 'b']);
  const chat = new Chat(llm);
  const iter = chat.send('hi');
  // Pull only the first token; done has not yet been reached.
  const first = await iter.next();
  assert.equal(first.done, false);
  assert.equal(first.value, 'a');
  assert.deepEqual(chat.messages, []); // nothing recorded yet
  // Finish it.
  await iter.next(); // 'b'
  const last = await iter.next(); // done
  assert.equal(last.done, true);
  assert.equal(last.value, undefined);
  assert.equal(chat.messages.length, 2);
});

test('send() returns a fresh iterator object on each call (not a shared singleton)', async () => {
  const llm = makeLlm(['a']);
  const chat = new Chat(llm);
  const a = chat.send('one');
  const b = chat.send('two');
  assert.notEqual(a, b);
  // Both were invoked, so generate ran twice already (prompt captured at call time).
  assert.equal(llm.calls.length, 2);
  await drain(a);
  await drain(b);
});

test('send is itself an async iterable (Symbol.asyncIterator returns this)', async () => {
  const llm = makeLlm(['t']);
  const chat = new Chat(llm);
  const iter = chat.send('hi');
  assert.equal(typeof iter[Symbol.asyncIterator], 'function');
  assert.equal(iter[Symbol.asyncIterator](), iter);
  await drain(iter);
});

test('empty token stream yields nothing and records an empty assistant turn', async () => {
  const llm = makeLlm([]);
  const chat = new Chat(llm);
  const streamed = await drain(chat.send('hi'));
  assert.deepEqual(streamed, []);
  const msgs = chat.messages;
  assert.equal(msgs.length, 2);
  assert.equal(msgs[0].content, 'hi');
  assert.equal(msgs[1].role, 'assistant');
  assert.equal(msgs[1].content, ''); // ''.trim() === ''
});

test('calling next() again after done double-records the turn (actual iterator behavior)', async () => {
  // The custom iterator has no terminal guard: once the underlying generator is
  // exhausted, every extra next() sees done=true again and pushes another
  // user+assistant pair. `for await` stops at the first done, so drain() never
  // triggers this — but a manual over-pull does. Documenting the real behavior.
  const llm = makeLlm(['a']);
  const chat = new Chat(llm);
  const iter = chat.send('hi');
  assert.deepEqual(await iter.next(), { value: 'a', done: false });
  assert.deepEqual(await iter.next(), { value: undefined, done: true });
  assert.equal(chat.messages.length, 2); // first done recorded one pair
  // Over-pull once more: a second pair is appended.
  assert.deepEqual(await iter.next(), { value: undefined, done: true });
  assert.equal(chat.messages.length, 4);
  const msgs = chat.messages;
  assert.deepEqual(msgs[2], { role: 'user', content: 'hi' });
  assert.deepEqual(msgs[3], { role: 'assistant', content: 'a' });
});

// ---------------------------------------------------------------------------
// Prompt formatting
// ---------------------------------------------------------------------------

test('prompt format: begins with system text and ends with new user line + Assistant:', async () => {
  const llm = makeLlm(['reply']);
  const chat = new Chat(llm, { system: 'You are helpful.' });
  await drain(chat.send('What is 2+2?'));
  const prompt = llm.calls[0];
  // Exact format from buildPrompt: system + '\n\n' + turns + 'User: ' + text + '\nAssistant:'
  assert.equal(prompt, 'You are helpful.\n\nUser: What is 2+2?\nAssistant:');
  assert.ok(prompt.startsWith('You are helpful.'));
  assert.ok(prompt.includes('User: '));
  assert.ok(prompt.endsWith('\nAssistant:'));
});

test('prompt uses User: and Assistant: turn markers', async () => {
  const llm = makeLlm(['4']);
  const chat = new Chat(llm, { system: 'sys' });
  await drain(chat.send('q'));
  const prompt = llm.calls[0];
  assert.ok(prompt.includes('User: q'));
  assert.ok(prompt.includes('\nAssistant:'));
});

test('no-system prompt has no system prefix (starts directly with User: )', async () => {
  const llm = makeLlm(['ok']);
  const chat = new Chat(llm);
  await drain(chat.send('hello'));
  const prompt = llm.calls[0];
  assert.equal(prompt, 'User: hello\nAssistant:');
  assert.ok(prompt.startsWith('User: '));
  assert.ok(!prompt.startsWith('\n'));
});

test('prompt is captured at send() call time, before any iteration', () => {
  // buildPrompt() runs synchronously inside send(); generate() is called with
  // the prompt immediately, so the recorded prompt exists before we iterate.
  const llm = makeLlm(['x']);
  const chat = new Chat(llm, { system: 'S' });
  chat.send('hi'); // not drained
  assert.equal(llm.calls.length, 1);
  assert.equal(llm.calls[0], 'S\n\nUser: hi\nAssistant:');
});

test('user text is inserted verbatim, including embedded newlines and role markers', async () => {
  const llm = makeLlm(['ok']);
  const chat = new Chat(llm);
  await drain(chat.send('line1\nUser: fake'));
  const prompt = llm.calls[0];
  // No sanitization: the raw text is placed after 'User: ' and before '\nAssistant:'.
  assert.equal(prompt, 'User: line1\nUser: fake\nAssistant:');
});

test('empty user text still produces a well-formed prompt', async () => {
  const llm = makeLlm(['ok']);
  const chat = new Chat(llm, { system: 'S' });
  await drain(chat.send(''));
  assert.equal(llm.calls[0], 'S\n\nUser: \nAssistant:');
});

test('multi-turn memory: turn 2 prompt contains turn 1 user and assistant reply', async () => {
  const llm = makeLlm(['Paris']);
  const chat = new Chat(llm, { system: 'You are a geographer.' });

  await drain(chat.send('Capital of France?'));

  // Second turn reuses the same llm; tokens do not matter here.
  await drain(chat.send('And of Spain?'));

  const secondPrompt = llm.calls[1];
  assert.ok(secondPrompt.includes('User: Capital of France?'));
  assert.ok(secondPrompt.includes('Assistant: Paris'));
  assert.ok(secondPrompt.includes('User: And of Spain?'));
  // Full exact prompt for turn 2.
  assert.equal(
    secondPrompt,
    'You are a geographer.\n\n' +
      'User: Capital of France?\n' +
      'Assistant: Paris\n' +
      'User: And of Spain?\n' +
      'Assistant:'
  );
});

test('turn-2 prompt records the TRIMMED assistant reply, matching stored history', async () => {
  // The assistant turn stored in history is trimmed, so the next prompt must
  // echo the trimmed form, not the raw streamed tokens.
  const llm = makeLlm(['  Paris  ']);
  const chat = new Chat(llm, { system: 'S' });
  await drain(chat.send('q1'));
  await drain(chat.send('q2'));
  const secondPrompt = llm.calls[1];
  assert.equal(
    secondPrompt,
    'S\n\nUser: q1\nAssistant: Paris\nUser: q2\nAssistant:'
  );
});

test('three-turn conversation accumulates all prior turns in the prompt', async () => {
  const rec = makeLlmSequential(['r1', 'r2', 'r3']);
  const c = new Chat(rec, { system: 'S' });
  await drain(c.send('u1'));
  await drain(c.send('u2'));
  await drain(c.send('u3'));
  const p3 = rec.calls[2];
  assert.equal(
    p3,
    'S\n\n' +
      'User: u1\nAssistant: r1\n' +
      'User: u2\nAssistant: r2\n' +
      'User: u3\nAssistant:'
  );
});

// ---------------------------------------------------------------------------
// messages getter (defensive copy)
// ---------------------------------------------------------------------------

test('messages getter returns a COPY: mutating array and objects does not change internal state', async () => {
  const llm = makeLlm(['reply']);
  const chat = new Chat(llm, { system: 'S' });
  await drain(chat.send('hi'));

  const snapshot = chat.messages;
  assert.equal(snapshot.length, 3);

  // Mutate the returned array.
  snapshot.push({ role: 'user', content: 'INJECTED' });
  // Mutate an object inside the returned array.
  snapshot[0].content = 'TAMPERED';
  snapshot[1].role = 'assistant';

  const again = chat.messages;
  assert.equal(again.length, 3, 'array length unchanged');
  assert.equal(again[0].content, 'S', 'object content unchanged');
  assert.equal(again[1].role, 'user', 'object role unchanged');
});

test('messages getter yields distinct object instances on each access', () => {
  const llm = makeLlm(['x']);
  const chat = new Chat(llm, { system: 'S' });
  const a = chat.messages;
  const b = chat.messages;
  assert.notEqual(a, b); // new array each time
  assert.notEqual(a[0], b[0]); // new element objects each time
  assert.deepEqual(a[0], b[0]); // ...but equal by value
});

test('messages on an empty history returns a new empty array (not the internal one)', () => {
  const llm = makeLlm(['x']);
  const chat = new Chat(llm);
  const a = chat.messages;
  const b = chat.messages;
  assert.deepEqual(a, []);
  assert.notEqual(a, b);
});

// ---------------------------------------------------------------------------
// reset()
// ---------------------------------------------------------------------------

test('reset() removes user/assistant turns but keeps the system message', async () => {
  const llm = makeLlm(['a', 'b']);
  const chat = new Chat(llm, { system: 'keep me' });
  await drain(chat.send('hi'));
  assert.equal(chat.messages.length, 3);

  chat.reset();
  const msgs = chat.messages;
  assert.equal(msgs.length, 1);
  assert.deepEqual(msgs[0], { role: 'system', content: 'keep me' });
});

test('reset() on a no-system chat leaves an empty history', async () => {
  const llm = makeLlm(['a']);
  const chat = new Chat(llm);
  await drain(chat.send('hi'));
  assert.equal(chat.messages.length, 2);
  chat.reset();
  assert.deepEqual(chat.messages, []);
});

test('reset() is idempotent and safe on a fresh chat', () => {
  const llm = makeLlm(['a']);
  const chat = new Chat(llm, { system: 'S' });
  chat.reset();
  chat.reset();
  assert.deepEqual(chat.messages, [{ role: 'system', content: 'S' }]);
});

test('after reset the next prompt drops old turns but keeps system', async () => {
  const llm = makeLlm(['x']);
  const chat = new Chat(llm, { system: 'sys' });
  await drain(chat.send('first'));
  chat.reset();
  await drain(chat.send('second'));
  const prompt = llm.calls[1];
  assert.equal(prompt, 'sys\n\nUser: second\nAssistant:');
  assert.ok(!prompt.includes('first'));
});

test('reset() mid-stream still records into the pre-reset history array (closure capture)', async () => {
  // send() captures `this.history` in a closure at call time. reset() replaces
  // this.history with a NEW array, so the in-flight iterator records into the
  // now-detached old array — the live (post-reset) history is unaffected.
  const llm = makeLlm(['a', 'b']);
  const chat = new Chat(llm, { system: 'S' });
  const iter = chat.send('hi');
  await iter.next(); // pull 'a' (not done yet)
  chat.reset(); // swaps this.history to a fresh [system] array

  // After reset, only the system message is live.
  assert.deepEqual(chat.messages, [{ role: 'system', content: 'S' }]);

  // Finish the in-flight stream; its appends land in the detached old array.
  await iter.next(); // 'b'
  await iter.next(); // done -> pushes into the OLD array

  // Live history is still just the system message; the recorded turns went to
  // the orphaned array and are NOT visible here.
  assert.deepEqual(chat.messages, [{ role: 'system', content: 'S' }]);
});

// ---------------------------------------------------------------------------
// sendText()
// ---------------------------------------------------------------------------

test('sendText returns the full concatenated reply (untrimmed accumulation)', async () => {
  const llm = makeLlm(['Hello', ' world']);
  const chat = new Chat(llm);
  const reply = await chat.sendText('hi');
  assert.equal(reply, 'Hello world');
});

test('sendText concatenation is the raw stream (surrounding spaces preserved in return value)', async () => {
  // sendText does `out += t` with no trim; only the stored history is trimmed.
  const llm = makeLlm(['  Hi', ' there  ']);
  const chat = new Chat(llm);
  const reply = await chat.sendText('q');
  assert.equal(reply, '  Hi there  '); // returned value NOT trimmed
  const msgs = chat.messages;
  assert.equal(msgs[msgs.length - 1].content, 'Hi there'); // stored value trimmed
});

test('sendText records both turns in history', async () => {
  const llm = makeLlm(['done']);
  const chat = new Chat(llm, { system: 'S' });
  await chat.sendText('question');
  const msgs = chat.messages;
  assert.equal(msgs.length, 3);
  assert.deepEqual(msgs[1], { role: 'user', content: 'question' });
  assert.deepEqual(msgs[2], { role: 'assistant', content: 'done' });
});

test('sendText on an empty token stream returns an empty string', async () => {
  const llm = makeLlm([]);
  const chat = new Chat(llm);
  const reply = await chat.sendText('hi');
  assert.equal(reply, '');
  // Turn is still recorded (empty assistant content).
  assert.equal(chat.messages.length, 2);
  assert.equal(chat.messages[1].content, '');
});

test('sendText across two calls threads history into the second prompt', async () => {
  const rec = makeLlmSequential(['A', 'B']);
  const chat = new Chat(rec, { system: 'S' });
  await chat.sendText('first');
  await chat.sendText('second');
  assert.equal(
    rec.calls[1],
    'S\n\nUser: first\nAssistant: A\nUser: second\nAssistant:'
  );
});
