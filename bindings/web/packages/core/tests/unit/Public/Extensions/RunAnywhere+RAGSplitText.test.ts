import { describe, expect, it, vi } from 'vitest';

vi.mock('@runanywhere/proto-ts/errors', () => ({
  errorCategoryToJSON: () => '',
  errorCodeToJSON: () => '',
  SDKError: class {},
  ProtoErrorCode: { ERROR_CODE_INVALID_INPUT: 1 },
}));
vi.mock('@runanywhere/proto-ts/rag', () => ({
  RAGStreamEventKind: {},
}));
vi.mock('@runanywhere/proto-ts/embeddings_options', () => ({}));
vi.mock('@runanywhere/proto-ts/token_usage', () => ({
  TokenUsage: class {},
}));
vi.mock('@runanywhere/proto-ts/convenience/rag_convenience', () => ({}));
vi.mock('@runanywhere/proto-ts/model_types', () => ({
  ModelCategory: {},
}));

import { __testing__ } from '../../../../src/Public/Extensions/RunAnywhere+RAG';

describe('splitRAGText', () => {
  it('splits whitespace-free CJK text into multiple bounded chunks (#922)', () => {
    // 80 characters of continuous Chinese text with no spaces
    const cjk = '机器学习是人工智能的一个重要分支通过计算机模拟或实现人类的学习行为以获取新的知识或技能重新组织已有的知识结构使之不断改善自身性能这是人工智能的核心';
    const chunks = __testing__.splitRAGText(cjk, 20, 5);

    expect(chunks.length).toBeGreaterThan(1);
    for (const chunk of chunks) {
      expect([...chunk.text].length).toBeLessThanOrEqual(20);
      expect(cjk.slice(chunk.startOffset, chunk.endOffset)).toBe(chunk.text);
    }
  });

  it('preserves standard word token chunking on spaced text', () => {
    const text = 'The quick brown fox jumps over the lazy dog';
    const chunks = __testing__.splitRAGText(text, 4, 1);
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks[0]!.text).toBe('The quick brown fox');
  });

  it('returns empty array for empty string or whitespace only', () => {
    expect(__testing__.splitRAGText('', 10, 2)).toEqual([]);
    expect(__testing__.splitRAGText('   \n\t  ', 10, 2)).toEqual([]);
  });
});
