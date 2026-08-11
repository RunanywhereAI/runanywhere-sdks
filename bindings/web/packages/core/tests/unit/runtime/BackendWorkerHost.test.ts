import { describe, expect, it } from 'vitest';

import {
  BackendWorkerCrashedError,
  BackendWorkerHost,
  type BackendWorkerLike,
} from '../../../src/runtime/BackendWorkerHost';
import { runBackendWorker, type BackendWorkerScope } from '../../../src/runtime/BackendWorker';
import type {
  BackendWorkerRequest,
  BackendWorkerResponse,
} from '../../../src/runtime/BackendWorkerProtocol';

class FakeWorker implements BackendWorkerLike {
  onmessage: ((event: MessageEvent<BackendWorkerResponse>) => void) | null = null;
  onerror: ((event: ErrorEvent) => void) | null = null;
  readonly requests: BackendWorkerRequest[] = [];
  private readonly scope: BackendWorkerScope;

  constructor(options: { ready?: boolean; crashOnInfer?: boolean } = {}) {
    this.scope = {
      onmessage: null,
      postMessage: (response) => this.onmessage?.({ data: response } as MessageEvent<BackendWorkerResponse>),
    };
    if (options.ready !== false) {
      runBackendWorker(this.scope, {
        init: () => undefined,
        infer: (_kind, payload) => {
          if (options.crashOnInfer) {
            this.onerror?.({ message: 'simulated crash' } as ErrorEvent);
            return undefined;
          }
          return payload;
        },
        stream: async function* () {
          yield undefined;
          await new Promise<void>(() => {});
        },
        cancel: () => undefined,
      });
    }
  }

  postMessage(request: BackendWorkerRequest): void {
    this.requests.push(request);
    this.scope.onmessage?.({ data: request } as MessageEvent<BackendWorkerRequest>);
  }

  terminate(): void {}
}

describe('BackendWorkerHost', () => {
  it('rejects a missing init handshake within its configured timeout', async () => {
    const host = new BackendWorkerHost(() => new FakeWorker({ ready: false }), { initTimeoutMs: 5 });
    await expect(host.init()).rejects.toThrow(/handshake timed out/);
    expect(host.diagnostics.executionContext).toBe('main');
  });

  it('round-trips a unary inference RPC through runBackendWorker', async () => {
    const worker = new FakeWorker();
    const host = new BackendWorkerHost(() => worker);

    await expect(host.infer('llm.generate', { prompt: 'hello' })).resolves.toEqual({ prompt: 'hello' });
    expect(host.diagnostics).toEqual({ executionContext: 'worker', queueDepth: 0 });
  });

  it('posts a cancel RPC for an active stream', async () => {
    const worker = new FakeWorker();
    const host = new BackendWorkerHost(() => worker);
    const iterator = host.stream('tts.synthesize', { text: 'hello' })[Symbol.asyncIterator]();

    // Start the stream and wait for its init/stream post before cancelling.
    const pending = iterator.next().catch(() => undefined);
    await new Promise((resolve) => setTimeout(resolve, 0));
    await iterator.return?.();
    await pending;

    expect(worker.requests.some((request) => request.type === 'cancel')).toBe(true);
  });

  it('rejects active work on crash then starts a fresh worker', async () => {
    const first = new FakeWorker({ crashOnInfer: true });
    const second = new FakeWorker();
    let calls = 0;
    const host = new BackendWorkerHost(() => (calls++ === 0 ? first : second));

    await expect(host.infer('stt.transcribe', { audio: 'first' }))
      .rejects.toBeInstanceOf(BackendWorkerCrashedError);
    expect(host.diagnostics.executionContext).toBe('main');

    await expect(host.infer('stt.transcribe', { audio: 'recovered' }))
      .resolves.toEqual({ audio: 'recovered' });
    expect(host.diagnostics.executionContext).toBe('worker');
  });
});
