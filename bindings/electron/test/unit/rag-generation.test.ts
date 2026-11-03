// RAG query generation options: what the Electron facade encodes into RAGQueryOptions.
//
// `createRagNamespace` hands commons one serialized RAGQueryOptions per query, and a knob
// the facade does not copy is dropped without a sound: `toRagGeneration` returns a named
// interface that is assigned into a DeepPartial, so tsc cannot catch a missing or
// misnamed field. These tests decode the exact bytes the backend receives instead.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';
import { RAGQueryOptions, RAGResult } from '@runanywhere/proto-ts/rag';
import { ReasoningMode as ProtoReasoningMode } from '@runanywhere/proto-ts/thinking_tag_pattern';

import type { RaBackend } from '../../dist/api/backend';
import { createRagNamespace } from '../../dist/api/data';
import type { RagSession } from '../../dist/api/data';
import { SdkEventHub } from '../../dist/api/hub';
import { toProtoOptions } from '../../dist/api/llm-abi';
import type { LlmOptions } from '../../dist/api/options';
import { ReasoningMode } from '../../dist/api/types';

/**
 * The calls `rag.open` and one query make, and nothing else. Both query routes record
 * the bytes they are handed; any other backend method is a bug in the test, so it throws.
 */
function recordingBackend(sent: Uint8Array[]): RaBackend {
  const stub = {
    resolveModel: async (id: string) => ({ id, primary: `/models/${id}.gguf` }),
    registerModel: async () => undefined,
    ragOpen: async () => 'session-1',
    ragQuery: async (_session: string, queryBytes: Uint8Array) => {
      sent.push(queryBytes);
      return RAGResult.encode(RAGResult.fromPartial({ answer: 'Paris' })).finish();
    },
    ragQueryStream: async (_session: string, queryBytes: Uint8Array) => {
      sent.push(queryBytes);
    },
    ragClose: async () => undefined,
  };
  return new Proxy(stub, {
    get(target, prop: string, receiver) {
      if (prop in target) return Reflect.get(target, prop, receiver);
      return () => {
        throw new Error(`a RAG query must not call backend.${prop}`);
      };
    },
  }) as unknown as RaBackend;
}

async function openSession(sent: Uint8Array[]): Promise<RagSession> {
  const rag = createRagNamespace({
    backend: recordingBackend(sent),
    hub: new SdkEventHub(),
    requireReady: () => undefined,
  });
  return rag.open({ id: 'embedder' }, { id: 'answerer' });
}

function generationSent(sent: Uint8Array[]): LLMGenerationOptions {
  assert.equal(sent.length, 1, 'exactly one query reaches the backend');
  const bytes = sent[0];
  assert.ok(bytes, 'the backend received query bytes');
  const query = RAGQueryOptions.decode(bytes);
  assert.ok(query.generation, 'the query carries a generation message');
  return query.generation;
}

type Route = 'query' | 'queryStream';
const ROUTES: readonly Route[] = ['query', 'queryStream'];

/** The generation message a query with `options` puts on the wire, via `route`. */
async function generationFor(route: Route, options: LlmOptions): Promise<LLMGenerationOptions> {
  const sent: Uint8Array[] = [];
  const session = await openSession(sent);
  if (route === 'query') {
    await session.query('What is the capital of France?', options);
  } else {
    const events: unknown[] = [];
    for await (const event of session.queryStream('What is the capital of France?', options)) {
      events.push(event);
    }
  }
  return generationSent(sent);
}

// Values are dyadic fractions so the float32 round trip is exact.
const ALL_KNOBS: LlmOptions = {
  maxOutputTokens: 64,
  temperature: 0.5,
  topP: 0.75,
  topK: 20,
  minP: 0.125,
  frequencyPenalty: 0.25,
  presencePenalty: 0.375,
  repetitionPenalty: 1.25,
  seed: 42,
  stopSequences: ['</s>', '###'],
  systemPrompt: 'Answer in one word.',
  reasoning: { mode: ReasoningMode.OFF },
};

for (const route of ROUTES) {
  test(`${route} forwards every generation knob, reasoning included`, async () => {
    const generation = await generationFor(route, ALL_KNOBS);
    assert.equal(generation.maxOutputTokens, 64);
    assert.equal(generation.temperature, 0.5);
    assert.equal(generation.topP, 0.75);
    assert.equal(generation.topK, 20);
    assert.equal(generation.minP, 0.125);
    assert.equal(generation.frequencyPenalty, 0.25);
    assert.equal(generation.presencePenalty, 0.375);
    assert.equal(generation.repeatPenalty, 1.25);
    assert.equal(generation.seed, 42);
    assert.deepEqual(generation.stopSequences, ['</s>', '###']);
    assert.equal(generation.systemPrompt, 'Answer in one word.');
    assert.equal(generation.reasoning?.mode, ProtoReasoningMode.REASONING_MODE_OFF);
  });

  test(`${route} leaves every unset generation knob absent`, async () => {
    const generation = await generationFor(route, {});
    for (const name of [
      'maxOutputTokens',
      'temperature',
      'topP',
      'topK',
      'minP',
      'frequencyPenalty',
      'presencePenalty',
      'repeatPenalty',
      'seed',
      'systemPrompt',
      'reasoning',
    ] as const) {
      assert.equal(generation[name], undefined, `${name} must stay absent so commons applies its default`);
    }
    assert.deepEqual(generation.stopSequences, []);
  });
}

test('an explicit reasoning ON keeps its tag pattern and includeInOutput', async () => {
  const generation = await generationFor('query', {
    reasoning: {
      mode: ReasoningMode.ON,
      includeInOutput: true,
      pattern: { open: '<think>', close: '</think>' },
    },
  });
  assert.equal(generation.reasoning?.mode, ProtoReasoningMode.REASONING_MODE_ON);
  assert.equal(generation.reasoning?.includeInOutput, true);
  assert.equal(generation.reasoning?.pattern?.openTag, '<think>');
  assert.equal(generation.reasoning?.pattern?.closeTag, '</think>');
});

test('a RAG query encodes reasoning exactly as the LLM path does', async () => {
  const cases: LlmOptions['reasoning'][] = [
    {},
    { mode: ReasoningMode.OFF },
    { mode: ReasoningMode.ON, includeInOutput: true },
    { mode: ReasoningMode.ON, pattern: { open: '<think>', close: '</think>' } },
  ];
  for (const reasoning of cases) {
    const viaRag = (await generationFor('query', { reasoning })).reasoning;
    const viaLlm = toProtoOptions({ reasoning }).reasoning;
    assert.ok(viaLlm, 'the LLM path encodes the option');
    assert.deepEqual(viaRag, viaLlm, `reasoning ${JSON.stringify(reasoning)} must encode the same on both paths`);
  }
});
