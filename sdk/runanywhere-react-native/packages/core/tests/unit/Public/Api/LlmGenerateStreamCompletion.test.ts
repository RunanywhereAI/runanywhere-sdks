/**
 * Characterizes the native-stream-completion contract for
 * `llm.generateStream` under the v4 public API spec: a stream never
 * fabricates a successful `completed`. The native boundary can legitimately
 * resolve the stream call without ever sending an `isFinal` proto event
 * (see PR #605 review issue #4); that now surfaces as a `failed` event
 * carrying whatever partial text was observed, mirroring Swift's
 * `RunAnywhere.mapGenerationStream`
 * (`runanywhere-swift/Sources/RunAnywhere/Public/API/Namespaces/LLMNamespace.swift`).
 * A native call that never invokes the callback at all still fails outright,
 * since there is no partial `requestId` to report a terminal event against.
 */

const mockNative = {
  initialize: jest.fn<Promise<boolean>, [string]>(),
  completeServicesInitialization: jest.fn<Promise<ArrayBuffer>, []>(),
  destroy: jest.fn<Promise<void>, []>(),
  llmGenerateStreamProto: jest.fn<
    Promise<void>,
    [ArrayBuffer, (eventBytes: ArrayBuffer) => void]
  >(),
  llmCancelProto: jest.fn<Promise<ArrayBuffer>, []>(),
};

jest.mock('react-native', () => ({
  Platform: { OS: 'ios' },
  PermissionsAndroid: {
    PERMISSIONS: {},
    RESULTS: {},
    check: jest.fn(),
    request: jest.fn(),
  },
}));

jest.mock('../../../../src/native', () => ({
  isNativeModuleAvailable: jest.fn(() => true),
  requireNativeModule: jest.fn(() => mockNative),
}));

jest.mock('../../../../src/native/NitroModulesGlobalInit', () => ({
  initializeNitroModulesGlobally: jest.fn(() => Promise.resolve()),
}));

import { SdkInitResult } from '@runanywhere/proto-ts/sdk_init';
import {
  LLMStreamEvent,
  type LLMStreamEvent as LLMStreamEventMessage,
  type DeepPartial,
} from '@runanywhere/proto-ts/llm_service';
import { TokenKind } from '@runanywhere/proto-ts/voice_events';
import {
  RunAnywhere,
  completeServicesInitialization,
} from '../../../../src/Public/RunAnywhere';
import { llm } from '../../../../src/Public/Api/Llm';
import type { GenerationEvent } from '../../../../src/Public/Api/Types';
import { bytesToArrayBuffer } from '../../../../src/services/ProtoBytes';

function phase2Payload(): ArrayBuffer {
  const bytes = SdkInitResult.encode(
    SdkInitResult.create({
      hasCompletedHttpSetup: true,
      httpConfigured: true,
      httpApplicable: true,
    })
  ).finish();
  return bytesToArrayBuffer(bytes);
}

function encodeEvent(partial: DeepPartial<LLMStreamEventMessage>): ArrayBuffer {
  const bytes = LLMStreamEvent.encode(
    LLMStreamEvent.fromPartial(partial)
  ).finish();
  return bytesToArrayBuffer(bytes);
}

async function collect(
  stream: AsyncIterable<GenerationEvent>
): Promise<GenerationEvent[]> {
  const events: GenerationEvent[] = [];
  for await (const event of stream) {
    events.push(event);
  }
  return events;
}

describe('llm.generateStream native-completion contract', () => {
  beforeEach(async () => {
    mockNative.initialize.mockReset().mockResolvedValue(true);
    mockNative.completeServicesInitialization
      .mockReset()
      .mockResolvedValue(phase2Payload());
    mockNative.destroy.mockReset().mockResolvedValue(undefined);
    mockNative.llmGenerateStreamProto.mockReset();
    mockNative.llmCancelProto
      .mockReset()
      .mockResolvedValue(bytesToArrayBuffer(new Uint8Array()));

    jest.spyOn(console, 'debug').mockImplementation(() => undefined);
    jest.spyOn(console, 'info').mockImplementation(() => undefined);
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    jest.spyOn(console, 'error').mockImplementation(() => undefined);

    await RunAnywhere.reset();
    await RunAnywhere.initialize({ apiKey: 'test-key' });
    await completeServicesInitialization();
  });

  afterEach(async () => {
    mockNative.destroy.mockResolvedValue(undefined);
    await RunAnywhere.reset();
    jest.restoreAllMocks();
  });

  test('native resolving without isFinal emits failed instead of a fabricated completion', async () => {
    // Native sends tokens, then the promise from `llmGenerateStreamProto`
    // resolves without ever sending a terminal `isFinal` event -- a
    // legitimate native-boundary shutdown (e.g. backend cooperative stop),
    // not a bridge failure. The v4 grammar reports this as `failed` rather
    // than fabricating a successful `completed`.
    mockNative.llmGenerateStreamProto.mockImplementation(
      async (_bytes, onEvent) => {
        onEvent(encodeEvent({ token: 'Hel', isFinal: false }));
        onEvent(encodeEvent({ token: 'lo', isFinal: false }));
      }
    );

    const events = await collect(llm.generateStream('hi'));

    expect(events.map((e) => e.type)).toEqual([
      'started',
      'token',
      'token',
      'failed',
    ]);
    const failed = events[events.length - 1];
    if (failed?.type !== 'failed') {
      throw new Error('expected a failed event');
    }
    expect(failed.partial).toBe('Hello');
    expect(failed.error.message).toMatch(/terminal event/);
  });

  test('a terminal isFinal event still wins and is not double-emitted', async () => {
    mockNative.llmGenerateStreamProto.mockImplementation(
      async (_bytes, onEvent) => {
        onEvent(encodeEvent({ token: 'Hi', isFinal: false }));
        onEvent(
          encodeEvent({
            token: '',
            isFinal: true,
            result: { text: 'Hi', finishReason: 'stop' },
          })
        );
      }
    );

    const events = await collect(llm.generateStream('hi'));

    expect(events.map((e) => e.type)).toEqual(['started', 'token', 'completed']);
    const completed = events[events.length - 1];
    if (completed?.type !== 'completed') {
      throw new Error('expected a completed event');
    }
    expect(completed.result.text).toBe('Hi');
  });

  test('native resolving without a single event fails instead of synthesizing an empty completion', async () => {
    mockNative.llmGenerateStreamProto.mockImplementation(async () => {
      // Native never invokes the callback at all.
    });

    await expect(collect(llm.generateStream('hi'))).rejects.toThrow(
      /before producing any output/
    );
  });

  test('thinking tokens accumulate into the partial text reported on a terminal failure', async () => {
    mockNative.llmGenerateStreamProto.mockImplementation(
      async (_bytes, onEvent) => {
        onEvent(
          encodeEvent({
            token: 'thinking...',
            isFinal: false,
            kind: TokenKind.TOKEN_KIND_THOUGHT,
          })
        );
        onEvent(encodeEvent({ token: 'answer', isFinal: false }));
      }
    );

    const events = await collect(llm.generateStream('hi'));
    const failed = events[events.length - 1];
    if (failed?.type !== 'failed') {
      throw new Error('expected a failed event');
    }
    expect(failed.partial).toBe('answer');
  });
});
