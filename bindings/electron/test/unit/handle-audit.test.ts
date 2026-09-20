import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  HandleAuditor,
  HANDLE_CATEGORIES,
  detectLeaks,
  type KnownHandleSet,
} from '../../dist/api/handle-audit';

const emptyKnown = (): KnownHandleSet => ({
  slotHandles: new Map(),
  vadHandle: null,
  ragSessions: new Map(),
  voiceSessions: new Map(),
});

test('handle audit categories match the native tracked categories', () => {
  assert.deepEqual(HANDLE_CATEGORIES, [
    'llm', 'vlm', 'embedding', 'stt', 'tts', 'vad', 'rag', 'rerank',
    'diarization', 'segmentation',
  ]);
});

test('HandleAuditor rejects malformed native audit entries', () => {
  const previous = process.env.RAC_HANDLE_AUDIT;
  process.env.RAC_HANDLE_AUDIT = 'debug';
  try {
    const addon = {
      handleAudit: () => [
        { id: 7, category: 'llm', model: 'model.gguf' },
        { id: 8, category: 'not-a-category' },
        { id: Number.MAX_SAFE_INTEGER + 1, category: 'rag' },
        { id: 9, category: 'rag', model: 42 },
      ],
    } as never;
    const leaks = new HandleAuditor(addon).getLeaks(emptyKnown());
    assert.deepEqual(leaks.map((leak) => leak.entry.id), [7]);
  } finally {
    if (previous === undefined) delete process.env.RAC_HANDLE_AUDIT;
    else process.env.RAC_HANDLE_AUDIT = previous;
  }
});

test('HandleAuditor.stop clears the previous snapshot for a later start', () => {
  const previous = process.env.RAC_HANDLE_AUDIT;
  process.env.RAC_HANDLE_AUDIT = 'debug';
  const warnings: string[] = [];
  const originalWarn = console.warn;
  console.warn = (message: string) => warnings.push(message);
  try {
    const addon = { handleAudit: () => [{ id: 7, category: 'llm' }] } as never;
    const auditor = new HandleAuditor(addon);
    auditor.report();
    auditor.stop();
    auditor.report();
    assert.equal(warnings.length, 2);
  } finally {
    console.warn = originalWarn;
    if (previous === undefined) delete process.env.RAC_HANDLE_AUDIT;
    else process.env.RAC_HANDLE_AUDIT = previous;
  }
});

test('detectLeaks preserves the RAG session sentinel', () => {
  const leaks = detectLeaks([
    { id: 12, category: 'rag', model: 'rag_session' },
  ], emptyKnown());
  assert.equal(leaks[0]?.entry.model, 'rag_session');
});