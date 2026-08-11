// F4 — LLM inference over the commons proto ABI, against the real addon and a
// real model.
//
// Everything here goes through the public `llm` namespace, so what is under test
// is the whole path: models.load puts the model in commons' lifecycle store,
// rac_llm_generate_proto reads it from there, and the result carries the finish
// reason, the token accounting, the thinking split, and the extracted JSON
// already normalized.
//
// smollm2-135m is not a reasoning model, so the thinking cases assert the wiring
// and the invariants (no thought tokens when reasoning is off; tags never leak
// into the answer) rather than the presence of thoughts, which would need a
// reasoning model to be true.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as os from 'node:os';
import * as path from 'node:path';

import { createRunAnywhere, NativeBackend, registerCatalog, clearCatalog } from '../../dist';
import type { Catalog, JsonSchema, RunAnywhereApi } from '../../dist';
import { exists, nativeAddon } from './support';

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const MODEL_ID = 'smollm2-135m';
const MODEL_FILE = path.join(os.homedir(), '.runanywhere', 'models', MODEL_ID, 'model.gguf');

const SKIP: { skip?: string } = exists(NATIVE_PATH)
  ? exists(MODEL_FILE)
    ? {}
    : { skip: `model missing: ${MODEL_FILE}` }
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

const CATALOG: Catalog = {
  [MODEL_ID]: {
    type: 'llm',
    files: [{ url: 'https://example.invalid/smollm2-135m.gguf', as: 'model.gguf' }],
    primary: 'model.gguf',
    label: 'SmolLM2 135M',
    sizeMB: 100,
  },
};

/** One initialized SDK with the model resident, plus its teardown. */
async function withModel(run: (sdk: RunAnywhereApi) => Promise<void>): Promise<void> {
  clearCatalog();
  registerCatalog(CATALOG);
  const sdk = createRunAnywhere(new NativeBackend(nativeAddon()));
  await sdk.initialize({ environment: 'production' });
  try {
    await sdk.models.load(MODEL_ID);
    await run(sdk);
  } finally {
    await sdk.reset();
    clearCatalog();
  }
}

test('generate: text, engine metrics, and a token ceiling that is honoured',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      const result = await sdk.llm.generate('Name one colour.', { maxOutputTokens: 32 });
      assert.ok(result.text.length > 0, 'the model answered');
      assert.equal(result.model, MODEL_ID, 'the result names the model commons used');
      assert.equal(result.toolCalls.length, 0, 'no tools were registered');

      // Metrics come from the engine, not from wall-clock guessing in TypeScript.
      assert.ok(result.inputTokens > 0, 'the prompt was tokenized');
      assert.ok(result.outputTokens > 0, 'the engine counted output tokens');
      assert.ok(result.tokensPerSecond > 0, 'the engine reported decode throughput');

      // The pre-F4 component path ignored maxOutputTokens: a request for 8
      // produced 38. The proto path stops on the budget and says why.
      const capped = await sdk.llm.generate('Count from one to fifty.', {
        maxOutputTokens: 8,
        temperature: 0,
      });
      assert.equal(capped.outputTokens, 8, 'generation stopped on the token budget');
      assert.equal(capped.finishReason, 'LENGTH', 'and reported hitting the ceiling');
    });
  }
);

test('generateStream: token by token, then one completed event carrying the result',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      // Answer text and reasoning are separate arms of the event grammar, so the
      // kind a token carries IS its event type — that is what the "text only"
      // assertion below reads.
      const deltaTypes: string[] = [];
      const pieces: string[] = [];
      let started = 0;
      let completed: Awaited<ReturnType<typeof sdk.llm.generate>> | null = null;
      for await (const event of sdk.llm.generateStream('Name three colours.', {
        maxOutputTokens: 32,
      })) {
        if (event.type === 'started') started += 1;
        if (event.type === 'textDelta') {
          deltaTypes.push(event.type);
          pieces.push(event.text);
        }
        if (event.type === 'reasoningDelta') deltaTypes.push(event.type);
        if (event.type === 'completed') completed = event.result;
      }

      assert.equal(started, 1, 'exactly one started event');
      assert.ok(pieces.length > 1, 'the answer arrived in pieces rather than all at once');
      assert.ok(completed, 'the stream terminated with a completed event');
      assert.equal(completed.text, pieces.join(''), 'the pieces reassemble into the answer');
      assert.ok(completed.outputTokens > 0, 'the terminal result carries engine metrics');
      assert.ok(completed.timeToFirstTokenMs > 0, 'and a measured time to first token');
      assert.deepEqual(
        [...new Set(deltaTypes)],
        ['textDelta'],
        'a non-reasoning model emits only text'
      );
    });
  }
);

test('reasoning: off emits no thoughts, and a custom tag pair never leaks into the answer',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      const off = await sdk.llm.generate('Say hello.', {
        maxOutputTokens: 24,
        reasoning: { mode: 'OFF' },
      });
      assert.ok(off.text.length > 0, 'the model still answers with reasoning off');
      assert.equal(off.thinkingText, undefined, 'reasoning off means no thoughts');

      const deltaTypes = new Set<string>();
      for await (const event of sdk.llm.generateStream('Say hello.', {
        maxOutputTokens: 24,
        reasoning: { mode: 'OFF', includeInOutput: true },
      })) {
        if (event.type === 'textDelta' || event.type === 'reasoningDelta') {
          deltaTypes.add(event.type);
        }
      }
      assert.ok(
        !deltaTypes.has('reasoningDelta'),
        'no thought tokens are streamed with reasoning off'
      );

      // A custom pair is what a model family whose markers are not <think> needs.
      // Whatever this model emits, commons splits on these tags, so the answer
      // must never contain them.
      const custom = await sdk.llm.generate('Reply with a greeting.', {
        maxOutputTokens: 32,
        reasoning: { mode: 'ON', includeInOutput: true, pattern: { open: '<t>', close: '</t>' } },
      });
      assert.ok(custom.text.length > 0, 'a custom pattern does not break generation');
      assert.ok(!custom.text.includes('<t>'), 'the opening tag is not part of the answer');
      assert.ok(!custom.text.includes('</t>'), 'the closing tag is not part of the answer');
      if (custom.thinkingText !== undefined) {
        assert.ok(custom.thinkingText.length > 0, 'a reported thought block is never empty');
      }
    });
  }
);

test('generateStructured: decoding is constrained, so the JSON always parses',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      const schema: JsonSchema = {
        type: 'object',
        properties: { name: { type: 'string' }, age: { type: 'integer' } },
        required: ['name', 'age'],
      };
      const result = await sdk.llm.generateStructured<{ name: string; age: number }>(
        'Give a person with a name and an age.',
        schema,
        { maxOutputTokens: 64, temperature: 0 }
      );
      assert.equal(result.valid, true, `commons validated the document: ${result.raw}`);
      assert.equal(typeof result.value.name, 'string', 'name came back as a string');
      assert.equal(Number.isInteger(result.value.age), true, 'age came back as an integer');
      assert.deepEqual(JSON.parse(result.raw), result.value, 'raw and value agree');
      assert.ok(result.outputTokens > 0, 'the structured call reports engine metrics too');
    });
  }
);

test('cancel: breaking out of the stream stops native work and frees the model',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      let tokens = 0;
      const startedAt = Date.now();
      for await (const event of sdk.llm.generateStream('Count from one to five hundred.', {
        maxOutputTokens: 500,
      })) {
        if (event.type === 'textDelta' && ++tokens === 5) break;
      }
      const cancelledAfterMs = Date.now() - startedAt;
      assert.equal(tokens, 5, 'the loop stopped where the caller stopped it');
      // 500 tokens on this model takes several seconds; returning promptly is
      // what proves the native generation was cancelled rather than drained.
      assert.ok(cancelledAfterMs < 3000, `cancel returned promptly (${cancelledAfterMs}ms)`);

      // KNOWN COMMONS RACE, not a test-timing nicety. The llama.cpp backend
      // clears cancel_requested_ when a generation starts, but the cancelled
      // decode loop is still unwinding and stores `true` back into it
      // (llamacpp_backend.cpp:949/968) after the next generation has already
      // cleared it, so that generation returns 0 tokens. The SDK already waits
      // for rac_llm_generate_stream_proto to return before this line; the
      // remaining window is inside the engine. Without this settle the next
      // generation is clipped, which is exactly what a chat app hits when a
      // user presses stop and immediately sends another message.
      await new Promise((resolve) => setTimeout(resolve, 300));

      // The real proof that nothing was left running: the next generation works.
      const after = await sdk.llm.generate('Say ok.', { maxOutputTokens: 8 });
      assert.ok(after.text.length > 0, `the model is usable after a cancel: ${after.text}`);
    });
  }
);

test('tools: a registered tool is selected, executed, and its result reaches the answer',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      let ran = 0;
      sdk.llm.tools.register(
        {
          name: 'get_time',
          description: 'Get the current time',
          parameters: { type: 'object', properties: {}, required: [] },
        },
        async () => {
          ran += 1;
          return { time: '12:00' };
        }
      );
      assert.deepEqual(
        sdk.llm.tools.list().map((t) => t.name),
        ['get_time'],
        'the registry lists what was registered'
      );

      const result = await sdk.llm.generate('What time is it?', {
        maxOutputTokens: 48,
        temperature: 0,
        toolChoice: 'REQUIRED',
      });
      assert.equal(ran, 1, 'the executor ran exactly once');
      assert.equal(result.toolCalls.length, 1, 'the call is reported to the caller');
      assert.equal(result.toolCalls[0].name, 'get_time');
      assert.deepEqual(result.toolCalls[0].result, { time: '12:00' }, 'with its typed result');
      assert.equal(result.finishReason, 'TOOL_CALLS');

      sdk.llm.tools.unregister('get_time');
      assert.deepEqual(sdk.llm.tools.list(), [], 'unregister empties the registry');
    });
  }
);

// F5 — the loop itself is commons'. What is worth asserting from here is the
// seam: the executor trampoline reaches JavaScript and its answer reaches the
// model, tool choice is honoured, and a throwing executor is reported to the
// model as a failed call rather than failing the run.

test('tools: a forced choice calls that tool even when another one fits better',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      const ran: string[] = [];
      const define = (name: string) => ({
        name,
        description: `Get the current ${name.replace('get_', '')}`,
        parameters: { type: 'object', properties: {}, required: [] },
      });
      sdk.llm.tools.register(define('get_time'), async () => {
        ran.push('get_time');
        return { time: '12:00' };
      });
      sdk.llm.tools.register(define('get_weather'), async () => {
        ran.push('get_weather');
        return { weather: 'sunny' };
      });

      // The prompt asks about time; the choice forces weather. Commons narrows
      // the decoding grammar to the forced tool, so this is a constraint on the
      // sampler rather than a hint in the prompt.
      const result = await sdk.llm.generate('What time is it?', {
        maxOutputTokens: 48,
        temperature: 0,
        toolChoice: { forced: 'get_weather' },
      });
      assert.deepEqual(ran, ['get_weather'], 'only the forced tool ran');
      assert.equal(result.toolCalls[0].name, 'get_weather');
      assert.deepEqual(result.toolCalls[0].result, { weather: 'sunny' });

      await assert.rejects(
        () => sdk.llm.generate('Anything.', { toolChoice: { forced: 'get_stock_price' } }),
        /not registered/,
        'forcing a tool nobody registered is rejected before any generation'
      );
    });
  }
);

test('tools: streaming reports each call as it runs, then one completed result',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      sdk.llm.tools.register(
        {
          name: 'get_time',
          description: 'Get the current time',
          parameters: { type: 'object', properties: {}, required: [] },
        },
        async () => ({ time: '12:00' })
      );

      const types: string[] = [];
      let completed: Awaited<ReturnType<typeof sdk.llm.generate>> | null = null;
      let streamedCall: { name: string; result?: Record<string, unknown> } | null = null;
      for await (const event of sdk.llm.generateStream('What time is it?', {
        maxOutputTokens: 48,
        temperature: 0,
        toolChoice: 'REQUIRED',
      })) {
        types.push(event.type);
        if (event.type === 'toolCallAdded') streamedCall = event.call;
        if (event.type === 'completed') completed = event.result;
      }

      assert.equal(types[0], 'started', 'the stream opens with started');
      assert.equal(types[types.length - 1], 'completed', 'and closes with completed');
      assert.ok(streamedCall, 'the call was reported while the loop was still running');
      assert.equal(streamedCall.name, 'get_time');
      assert.deepEqual(streamedCall.result, { time: '12:00' }, 'with the executor result');
      assert.ok(completed, 'the stream terminated with a completed event');
      assert.ok(completed.text.length > 0, 'the loop produced an answer');
      assert.deepEqual(
        completed.toolCalls.map((c) => c.name),
        ['get_time'],
        'the terminal result carries the same call'
      );

      // A tool-enabled turn does not stream tokens: commons runs its
      // generations inside the loop with streaming_enabled = RAC_FALSE
      // (tool_calling_generation_internal.h), so claiming token events here
      // would be claiming something the ABI does not deliver.
      assert.ok(!types.includes('textDelta'), 'no token events during a tool turn');
    });
  }
);

test('tools: a throwing executor is reported to the model, not raised at the caller',
  { timeout: 300000, ...SKIP },
  async () => {
    await withModel(async (sdk) => {
      let ran = 0;
      sdk.llm.tools.register(
        {
          name: 'get_time',
          description: 'Get the current time',
          parameters: { type: 'object', properties: {}, required: [] },
        },
        async () => {
          ran += 1;
          throw new Error('clock unavailable');
        }
      );

      const result = await sdk.llm.generate('What time is it?', {
        maxOutputTokens: 48,
        temperature: 0,
        toolChoice: 'REQUIRED',
      });
      assert.equal(ran, 1, 'the executor was invoked');
      assert.equal(result.toolCalls.length, 1, 'the failed call is still reported');
      // isError travels on the wire so commons tells the model the call failed
      // instead of feeding the message back as the tool's answer; the run
      // itself completes with whatever the model made of that.
      assert.equal(typeof result.text, 'string', 'the run completed rather than throwing');
    });
  }
);
