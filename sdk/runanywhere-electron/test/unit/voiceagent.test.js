const { test } = require('node:test');
const assert = require('node:assert/strict');

const { VoiceAgent } = require('../../dist/VoiceAgent');

// --- fake-model helpers -----------------------------------------------------

// Build a set of fake models plus a shared call log so tests can assert the
// orchestration order and the exact arguments each stage received.
function makeModels(opts = {}) {
  const {
    transcript = 'hello there',
    tokens = ['Hi', ' ', 'there'],
    audio = { sampleRate: 16000, samples: new Float32Array([0.1, 0.2, 0.3]) },
  } = opts;

  const calls = [];

  const stt = {
    transcribe(pcm) {
      calls.push({ name: 'stt.transcribe', pcm, argCount: arguments.length });
      return transcript;
    },
  };

  const llm = {
    generate(prompt) {
      // Record how many arguments processTurn actually passed: the source calls
      // generate(prompt) with a single argument, and the fake must not silently
      // hide a regression that starts passing extras.
      calls.push({ name: 'llm.generate', prompt, argCount: arguments.length });
      // async generator yielding the configured tokens in order
      return (async function* () {
        for (const t of tokens) {
          yield t;
        }
      })();
    },
  };

  const tts = {
    synthesize(text) {
      calls.push({ name: 'tts.synthesize', text, argCount: arguments.length });
      return audio;
    },
  };

  return { stt, llm, tts, calls, audio };
}

// ---------------------------------------------------------------------------

test('orchestration order: stt.transcribe -> llm.generate -> tts.synthesize', async () => {
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  await agent.processTurn(new Uint8Array([1, 2, 3]));

  const order = m.calls.map((c) => c.name);
  assert.deepEqual(order, ['stt.transcribe', 'llm.generate', 'tts.synthesize']);
});

test('each stage is invoked exactly once', async () => {
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  await agent.processTurn(new Uint8Array([0]));

  const counts = m.calls.reduce((acc, c) => {
    acc[c.name] = (acc[c.name] || 0) + 1;
    return acc;
  }, {});
  assert.equal(counts['stt.transcribe'], 1);
  assert.equal(counts['llm.generate'], 1);
  assert.equal(counts['tts.synthesize'], 1);
});

test('transcript is trimmed', async () => {
  const m = makeModels({ transcript: '  hello there  ' });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const turn = await agent.processTurn(new Uint8Array([1]));

  assert.equal(turn.transcript, 'hello there');
});

test('transcript trimming strips tabs/newlines too', async () => {
  const m = makeModels({ transcript: '\n\t hello \t\n' });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const turn = await agent.processTurn(new Uint8Array([1]));

  assert.equal(turn.transcript, 'hello');
});

test('onTranscript is called once with the trimmed transcript', async () => {
  const m = makeModels({ transcript: '  hi world  ' });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  const seen = [];
  await agent.processTurn(new Uint8Array([1]), {
    onTranscript: (t) => seen.push(t),
  });

  assert.equal(seen.length, 1);
  assert.equal(seen[0], 'hi world');
});

test('onToken is called once per token, in order', async () => {
  const tokens = ['a', 'b', 'c', 'd'];
  const m = makeModels({ tokens });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  const seen = [];
  await agent.processTurn(new Uint8Array([1]), {
    onToken: (t) => seen.push(t),
  });

  assert.deepEqual(seen, tokens);
});

test('onTranscript fires before any onToken', async () => {
  const m = makeModels({ transcript: 'q', tokens: ['x', 'y'] });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  const order = [];
  await agent.processTurn(new Uint8Array([1]), {
    onTranscript: () => order.push('transcript'),
    onToken: () => order.push('token'),
  });

  assert.deepEqual(order, ['transcript', 'token', 'token']);
});

test('callbacks are optional (no cb argument at all)', async () => {
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  // Should not throw when called with no callbacks object.
  const turn = await agent.processTurn(new Uint8Array([1]));
  assert.equal(turn.transcript, 'hello there');
});

test('callbacks object present but missing handlers does not throw', async () => {
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  const turn = await agent.processTurn(new Uint8Array([1]), {});
  assert.equal(turn.response, 'Hi there');
});

test('systemPrompt: prompt === systemPrompt + \\n\\n + transcript', async () => {
  const m = makeModels({ transcript: 'what time is it' });
  const agent = new VoiceAgent(
    { stt: m.stt, llm: m.llm, tts: m.tts },
    { systemPrompt: 'SYS' }
  );
  await agent.processTurn(new Uint8Array([1]));

  const gen = m.calls.find((c) => c.name === 'llm.generate');
  assert.equal(gen.prompt, 'SYS\n\nwhat time is it');
});

test('systemPrompt uses the trimmed transcript in the prompt', async () => {
  const m = makeModels({ transcript: '   padded   ' });
  const agent = new VoiceAgent(
    { stt: m.stt, llm: m.llm, tts: m.tts },
    { systemPrompt: 'SYS' }
  );
  await agent.processTurn(new Uint8Array([1]));

  const gen = m.calls.find((c) => c.name === 'llm.generate');
  assert.equal(gen.prompt, 'SYS\n\npadded');
});

test('without systemPrompt: prompt === transcript', async () => {
  const m = makeModels({ transcript: 'just this' });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  await agent.processTurn(new Uint8Array([1]));

  const gen = m.calls.find((c) => c.name === 'llm.generate');
  assert.equal(gen.prompt, 'just this');
});

test('empty-string systemPrompt is falsy -> prompt === transcript', async () => {
  const m = makeModels({ transcript: 'body' });
  const agent = new VoiceAgent(
    { stt: m.stt, llm: m.llm, tts: m.tts },
    { systemPrompt: '' }
  );
  await agent.processTurn(new Uint8Array([1]));

  const gen = m.calls.find((c) => c.name === 'llm.generate');
  assert.equal(gen.prompt, 'body');
});

test('default options (no opts argument) behaves as no systemPrompt', async () => {
  const m = makeModels({ transcript: 'plain' });
  // Construct with only models to exercise the default opts = {}.
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  await agent.processTurn(new Uint8Array([1]));

  const gen = m.calls.find((c) => c.name === 'llm.generate');
  assert.equal(gen.prompt, 'plain');
});

test('return shape has exactly transcript, response, audio', async () => {
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const turn = await agent.processTurn(new Uint8Array([1]));

  assert.deepEqual(Object.keys(turn).sort(), ['audio', 'response', 'transcript']);
});

test('response equals concatenated tokens, trimmed', async () => {
  const m = makeModels({ tokens: ['  Hello', ', ', 'world  '] });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const turn = await agent.processTurn(new Uint8Array([1]));

  // raw concat is '  Hello, world  ' -> trimmed
  assert.equal(turn.response, 'Hello, world');
});

test('response with no leading/trailing space is unchanged', async () => {
  const m = makeModels({ tokens: ['abc', 'def'] });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const turn = await agent.processTurn(new Uint8Array([1]));

  assert.equal(turn.response, 'abcdef');
});

test('zero tokens yields empty response', async () => {
  const m = makeModels({ tokens: [] });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  const seen = [];
  const turn = await agent.processTurn(new Uint8Array([1]), {
    onToken: (t) => seen.push(t),
  });

  assert.equal(turn.response, '');
  assert.deepEqual(seen, []);
});

test('audio is the exact object returned by tts.synthesize', async () => {
  const audio = { sampleRate: 22050, samples: new Float32Array([1, 2, 3, 4]) };
  const m = makeModels({ audio });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const turn = await agent.processTurn(new Uint8Array([1]));

  // Same reference, not merely a structural copy.
  assert.equal(turn.audio, audio);
  assert.equal(turn.audio.sampleRate, 22050);
  assert.equal(turn.audio.samples, audio.samples);
});

test('tts.synthesize receives the trimmed concatenated response', async () => {
  const m = makeModels({ tokens: ['  spoke', 'n  '] });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  await agent.processTurn(new Uint8Array([1]));

  const syn = m.calls.find((c) => c.name === 'tts.synthesize');
  assert.equal(syn.text, 'spoken');
});

test('pcm16 passed to stt.transcribe is the same bytes given to processTurn', async () => {
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const pcm = new Uint8Array([9, 8, 7, 6, 5]);
  await agent.processTurn(pcm);

  const stt = m.calls.find((c) => c.name === 'stt.transcribe');
  // Same reference passed straight through.
  assert.equal(stt.pcm, pcm);
  assert.deepEqual(Array.from(stt.pcm), [9, 8, 7, 6, 5]);
});

test('full turn: transcript/response/audio consistent end-to-end', async () => {
  const audio = { sampleRate: 16000, samples: new Float32Array([0.5]) };
  const m = makeModels({
    transcript: '  ask me  ',
    tokens: [' answer', ' here '],
    audio,
  });
  const agent = new VoiceAgent(
    { stt: m.stt, llm: m.llm, tts: m.tts },
    { systemPrompt: 'BE NICE' }
  );

  const transcripts = [];
  const toks = [];
  const turn = await agent.processTurn(new Uint8Array([1, 2]), {
    onTranscript: (t) => transcripts.push(t),
    onToken: (t) => toks.push(t),
  });

  assert.equal(turn.transcript, 'ask me');
  assert.equal(turn.response, 'answer here');
  assert.equal(turn.audio, audio);
  assert.deepEqual(transcripts, ['ask me']);
  assert.deepEqual(toks, [' answer', ' here ']);

  const gen = m.calls.find((c) => c.name === 'llm.generate');
  assert.equal(gen.prompt, 'BE NICE\n\nask me');
  const syn = m.calls.find((c) => c.name === 'tts.synthesize');
  assert.equal(syn.text, 'answer here');
});

test('processTurn rejects when stt.transcribe throws', async () => {
  const m = makeModels();
  m.stt.transcribe = () => {
    throw new Error('stt boom');
  };
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  await assert.rejects(
    () => agent.processTurn(new Uint8Array([1])),
    /stt boom/
  );
});

test('processTurn rejects when the llm generator throws mid-stream', async () => {
  const m = makeModels();
  m.llm.generate = () =>
    (async function* () {
      yield 'ok';
      throw new Error('llm boom');
    })();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  const seen = [];
  await assert.rejects(
    () => agent.processTurn(new Uint8Array([1]), { onToken: (t) => seen.push(t) }),
    /llm boom/
  );
  // The token yielded before the throw was still delivered.
  assert.deepEqual(seen, ['ok']);
});

test('processTurn rejects when tts.synthesize throws', async () => {
  const m = makeModels();
  m.tts.synthesize = () => {
    throw new Error('tts boom');
  };
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  await assert.rejects(
    () => agent.processTurn(new Uint8Array([1])),
    /tts boom/
  );
});

test('processTurn returns a Promise', () => {
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const p = agent.processTurn(new Uint8Array([1]));
  assert.ok(p instanceof Promise);
  return p; // settle it so the test runner does not flag a dangling promise
});

// --- exact call arity: processTurn must not leak extra args into the models ---

test('stt.transcribe is called with exactly one argument (the pcm)', async () => {
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  await agent.processTurn(new Uint8Array([1]));

  const stt = m.calls.find((c) => c.name === 'stt.transcribe');
  assert.equal(stt.argCount, 1);
});

test('llm.generate is called with exactly one argument (the prompt)', async () => {
  // processTurn calls this.models.llm.generate(prompt) with a single arg; a
  // regression that forwards options/callbacks would bump this count.
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  await agent.processTurn(new Uint8Array([1]));

  const gen = m.calls.find((c) => c.name === 'llm.generate');
  assert.equal(gen.argCount, 1);
});

test('tts.synthesize is called with exactly one argument (the response text)', async () => {
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  await agent.processTurn(new Uint8Array([1]));

  const syn = m.calls.find((c) => c.name === 'tts.synthesize');
  assert.equal(syn.argCount, 1);
});

// --- whitespace-only / empty edge cases ------------------------------------

test('whitespace-only transcript trims to empty string', async () => {
  const m = makeModels({ transcript: '   \t\n  ' });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  const seen = [];
  const turn = await agent.processTurn(new Uint8Array([1]), {
    onTranscript: (t) => seen.push(t),
  });

  assert.equal(turn.transcript, '');
  // onTranscript still fires exactly once, with the empty (trimmed) transcript.
  assert.deepEqual(seen, ['']);
});

test('empty transcript without systemPrompt yields empty prompt', async () => {
  const m = makeModels({ transcript: '   ' });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  await agent.processTurn(new Uint8Array([1]));

  const gen = m.calls.find((c) => c.name === 'llm.generate');
  assert.equal(gen.prompt, '');
});

test('systemPrompt with an empty (trimmed) transcript still appends the separator', async () => {
  // systemPrompt is truthy so the template branch is taken even though the
  // trimmed transcript is empty: 'SYS' + '\n\n' + '' === 'SYS\n\n'.
  const m = makeModels({ transcript: '   ' });
  const agent = new VoiceAgent(
    { stt: m.stt, llm: m.llm, tts: m.tts },
    { systemPrompt: 'SYS' }
  );
  await agent.processTurn(new Uint8Array([1]));

  const gen = m.calls.find((c) => c.name === 'llm.generate');
  assert.equal(gen.prompt, 'SYS\n\n');
});

test('multiline systemPrompt is inserted verbatim (no trimming of the prompt)', async () => {
  const m = makeModels({ transcript: 'hi' });
  const agent = new VoiceAgent(
    { stt: m.stt, llm: m.llm, tts: m.tts },
    { systemPrompt: '  line1\nline2  ' }
  );
  await agent.processTurn(new Uint8Array([1]));

  const gen = m.calls.find((c) => c.name === 'llm.generate');
  // systemPrompt itself is not trimmed; only transcript/response are.
  assert.equal(gen.prompt, '  line1\nline2  \n\nhi');
});

// --- token streaming detail --------------------------------------------------

test('onToken receives raw (untrimmed) tokens even though response is trimmed', async () => {
  const m = makeModels({ tokens: ['  lead', ' mid ', 'tail  '] });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  const seen = [];
  const turn = await agent.processTurn(new Uint8Array([1]), {
    onToken: (t) => seen.push(t),
  });

  // Callback sees the original tokens verbatim...
  assert.deepEqual(seen, ['  lead', ' mid ', 'tail  ']);
  // ...but the assembled response is trimmed at the outer edges only.
  assert.equal(turn.response, 'lead mid tail');
});

test('response of only whitespace tokens trims to empty and reaches tts', async () => {
  const m = makeModels({ tokens: ['  ', '\t', '\n'] });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const turn = await agent.processTurn(new Uint8Array([1]));

  assert.equal(turn.response, '');
  const syn = m.calls.find((c) => c.name === 'tts.synthesize');
  assert.equal(syn.text, '');
});

test('single-token response is preserved (concat of one)', async () => {
  const m = makeModels({ tokens: ['solo'] });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const turn = await agent.processTurn(new Uint8Array([1]));

  assert.equal(turn.response, 'solo');
});

test('interior whitespace inside tokens is preserved (only outer edges trimmed)', async () => {
  const tokens = ['a  ', '  b'];
  const m = makeModels({ tokens });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const turn = await agent.processTurn(new Uint8Array([1]));

  // response === tokens.join('').trim(); interior spaces (2 + 2 = 4) survive.
  assert.equal(turn.response, tokens.join('').trim());
  assert.equal(turn.response, 'a    b'); // 4 interior spaces, no edge whitespace
});

// --- audio pass-through variants --------------------------------------------

test('empty audio samples pass through unchanged', async () => {
  const audio = { sampleRate: 8000, samples: new Float32Array([]) };
  const m = makeModels({ audio });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });
  const turn = await agent.processTurn(new Uint8Array([1]));

  assert.equal(turn.audio, audio);
  assert.equal(turn.audio.samples.length, 0);
});

// --- callbacks that throw must not be swallowed -----------------------------

test('an onTranscript that throws rejects the turn before the llm runs', async () => {
  const m = makeModels();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  await assert.rejects(
    () =>
      agent.processTurn(new Uint8Array([1]), {
        onTranscript: () => {
          throw new Error('cb transcript boom');
        },
      }),
    /cb transcript boom/
  );

  // The failure happens right after transcription, so the llm never runs.
  assert.ok(!m.calls.some((c) => c.name === 'llm.generate'));
});

test('an onToken that throws rejects the turn and stops before tts', async () => {
  const m = makeModels({ tokens: ['one', 'two'] });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  await assert.rejects(
    () =>
      agent.processTurn(new Uint8Array([1]), {
        onToken: () => {
          throw new Error('cb token boom');
        },
      }),
    /cb token boom/
  );

  // Throwing inside the for-await loop aborts before synthesis.
  assert.ok(!m.calls.some((c) => c.name === 'tts.synthesize'));
});

// --- error-path ordering: a failing stage stops the pipeline -----------------

test('when stt throws, neither llm nor tts is invoked', async () => {
  const m = makeModels();
  m.stt.transcribe = () => {
    throw new Error('stt boom');
  };
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  await assert.rejects(() => agent.processTurn(new Uint8Array([1])), /stt boom/);
  assert.ok(!m.calls.some((c) => c.name === 'llm.generate'));
  assert.ok(!m.calls.some((c) => c.name === 'tts.synthesize'));
});

test('when the llm generator throws, tts is never invoked', async () => {
  const m = makeModels();
  m.llm.generate = () =>
    (async function* () {
      throw new Error('llm boom');
    })();
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  await assert.rejects(() => agent.processTurn(new Uint8Array([1])), /llm boom/);
  assert.ok(!m.calls.some((c) => c.name === 'tts.synthesize'));
});

// --- statelessness: the same agent can run multiple independent turns --------

test('the same agent instance handles sequential turns independently', async () => {
  const m = makeModels({ transcript: 'first', tokens: ['A', 'B'] });
  const agent = new VoiceAgent({ stt: m.stt, llm: m.llm, tts: m.tts });

  const t1 = await agent.processTurn(new Uint8Array([1]));
  assert.equal(t1.transcript, 'first');
  assert.equal(t1.response, 'AB');

  const t2 = await agent.processTurn(new Uint8Array([2]));
  // Response is not accumulated across turns — each turn starts from ''.
  assert.equal(t2.response, 'AB');

  const generates = m.calls.filter((c) => c.name === 'llm.generate');
  assert.equal(generates.length, 2);
});
