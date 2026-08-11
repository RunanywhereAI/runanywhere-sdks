// toPublicGenerationMetrics — copy commons TokenUsage verbatim; never invent fields.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { TokenUsage } from '@runanywhere/proto-ts/token_usage';
import { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import { VLMResult } from '@runanywhere/proto-ts/vlm_options';
import { RAGResult } from '@runanywhere/proto-ts/rag';

import {
  toPublicGenerationMetrics,
  toPublicMetrics,
} from '../../dist/api/llm-abi';
import { toPublicVlmMetrics } from '../../dist/api/vlm-abi';

const FULL_USAGE: TokenUsage = {
  inputTokens: 12,
  outputTokens: 34,
  totalTokens: 46,
  decodeTokensPerSecond: 57.5,
  prefillMs: 88,
  ttftMs: 120,
  timeToFirstContentTokenMs: 210,
  contentTokensPerSecond: 41.25,
  batchBuffered: true,
  countsEstimated: true,
};

test('toPublicGenerationMetrics copies every TokenUsage field verbatim', () => {
  const metrics = toPublicGenerationMetrics(FULL_USAGE, 'req-1', 'model-a');

  assert.deepEqual(metrics.usage, FULL_USAGE);
  assert.equal(metrics.inputTokens, FULL_USAGE.inputTokens);
  assert.equal(metrics.outputTokens, FULL_USAGE.outputTokens);
  assert.equal(metrics.timeToFirstTokenMs, FULL_USAGE.ttftMs);
  assert.equal(metrics.tokensPerSecond, FULL_USAGE.decodeTokensPerSecond);
  assert.equal(metrics.requestId, 'req-1');
  assert.equal(metrics.model, 'model-a');
});

test('toPublicGenerationMetrics does not invent totals or zero-fill prefill when usage is absent', () => {
  const metrics = toPublicGenerationMetrics(undefined, 'req-2', 'model-b');
  const empty = TokenUsage.create();

  assert.deepEqual(metrics.usage, empty);
  assert.equal(metrics.inputTokens, 0);
  assert.equal(metrics.outputTokens, 0);
  assert.equal(metrics.timeToFirstTokenMs, 0);
  assert.equal(metrics.tokensPerSecond, 0);
  assert.equal(metrics.usage.totalTokens, 0);
  assert.equal(metrics.usage.prefillMs, 0);
  assert.equal(metrics.usage.timeToFirstContentTokenMs, 0);
  assert.equal(metrics.usage.contentTokensPerSecond, 0);
  assert.equal(metrics.usage.batchBuffered, false);
  assert.equal(metrics.usage.countsEstimated, false);
});

test('toPublicMetrics does not substitute responseTokens for missing usage.outputTokens', () => {
  const result = LLMGenerationResult.fromPartial({
    modelUsed: 'from-result',
    responseTokens: 999,
    usage: {
      inputTokens: 1,
      outputTokens: 2,
      totalTokens: 3,
      decodeTokensPerSecond: 4,
      prefillMs: 5,
      ttftMs: 6,
      timeToFirstContentTokenMs: 7,
      contentTokensPerSecond: 8,
      batchBuffered: false,
      countsEstimated: true,
    },
  });

  const metrics = toPublicMetrics(result, 'req-3', 'fallback-model');
  assert.deepEqual(metrics.usage, result.usage);
  assert.equal(metrics.outputTokens, 2);
  assert.notEqual(metrics.outputTokens, 999);
  assert.equal(metrics.model, 'from-result');
});

test('toPublicVlmMetrics preserves the complete commons TokenUsage', () => {
  const result = VLMResult.fromPartial({ usage: FULL_USAGE });
  const metrics = toPublicVlmMetrics(result, 'req-4', 'vlm-model');
  assert.deepEqual(metrics.usage, FULL_USAGE);
  assert.equal(metrics.tokensPerSecond, FULL_USAGE.decodeTokensPerSecond);
});

test('RAG-shaped usage projection keeps ABI v9 fields (via shared helper)', () => {
  const raw = RAGResult.fromPartial({
    requestId: 'rag-req',
    usage: FULL_USAGE,
  });
  const metrics = toPublicGenerationMetrics(raw.usage, raw.requestId || 'fallback', 'rag-llm');
  assert.equal(metrics.requestId, 'rag-req');
  assert.equal(metrics.usage.batchBuffered, true);
  assert.equal(metrics.usage.countsEstimated, true);
  assert.equal(metrics.usage.prefillMs, 88);
  assert.equal(metrics.usage.timeToFirstContentTokenMs, 210);
  assert.equal(metrics.usage.contentTokensPerSecond, 41.25);
  assert.equal(metrics.usage.totalTokens, 46);
});
