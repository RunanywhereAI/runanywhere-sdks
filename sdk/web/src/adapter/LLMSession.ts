// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import { ModelFormat, RunAnywhereError, type LLMToken } from './Types.js';
import { requireNativeSessionBindings } from './NativeBindings.js';

/**
 * Direct LLM text-generation session. Wraps ra_llm_* C ABI via host
 * bindings. Use `ChatSession` for multi-turn message history.
 *
 *     const llm = new LLMSession('qwen3-4b', '/path/to/model.gguf');
 *     for await (const token of llm.generate('Hi')) { console.log(token.text); }
 */
export class LLMSession {
  private handle: number;
  private readonly bindings = requireNativeSessionBindings();

  constructor(public readonly modelId: string,
              public readonly modelPath: string,
              public readonly format: ModelFormat = ModelFormat.GGUF) {
    this.handle = this.bindings.llmCreate(modelId, modelPath, format);
    if (this.handle === 0) {
      throw new RunAnywhereError(
        RunAnywhereError.BACKEND_UNAVAILABLE,
        'ra_llm_create returned null (no engine registered)');
    }
  }

  async *generate(prompt: string): AsyncIterable<LLMToken> {
    const queue: LLMToken[] = [];
    let error: { code: number; msg: string } | null = null;
    let done = false;
    let wake: (() => void) | null = null;

    const rc = this.bindings.llmGenerate(this.handle, prompt,
      (t) => { queue.push(t); if (t.isFinal) done = true; wake?.(); },
      (code, msg) => { error = { code, msg }; done = true; wake?.(); });

    if (rc !== 0) {
      throw new RunAnywhereError(rc, 'ra_llm_generate failed');
    }

    while (true) {
      while (queue.length > 0) yield queue.shift()!;
      if (done) {
        if (error) {
          const e = error as { code: number; msg: string };
          throw new RunAnywhereError(e.code, e.msg);
        }
        return;
      }
      await new Promise<void>((res) => { wake = () => { wake = null; res(); }; });
    }
  }

  async *generateFromContext(query: string): AsyncIterable<LLMToken> {
    const queue: LLMToken[] = [];
    let error: { code: number; msg: string } | null = null;
    let done = false;
    let wake: (() => void) | null = null;

    const rc = this.bindings.llmGenerateFromContext(this.handle, query,
      (t) => { queue.push(t); if (t.isFinal) done = true; wake?.(); },
      (code, msg) => { error = { code, msg }; done = true; wake?.(); });

    if (rc !== 0) throw new RunAnywhereError(rc, 'ra_llm_generate_from_context failed');

    while (true) {
      while (queue.length > 0) yield queue.shift()!;
      if (done) {
        if (error) {
          const e = error as { code: number; msg: string };
          throw new RunAnywhereError(e.code, e.msg);
        }
        return;
      }
      await new Promise<void>((res) => { wake = () => { wake = null; res(); }; });
    }
  }

  cancel(): number { return this.bindings.llmCancel(this.handle); }
  reset(): number { return this.bindings.llmReset(this.handle); }
  injectSystemPrompt(prompt: string): number {
    return this.bindings.llmInjectSystemPrompt(this.handle, prompt);
  }
  appendContext(text: string): number {
    return this.bindings.llmAppendContext(this.handle, text);
  }
  clearContext(): number { return this.bindings.llmClearContext(this.handle); }

  close(): void {
    if (this.handle !== 0) { this.bindings.llmDestroy(this.handle); this.handle = 0; }
  }
}
