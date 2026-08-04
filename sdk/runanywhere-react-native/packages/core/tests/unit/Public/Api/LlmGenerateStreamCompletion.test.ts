/**
 * Characterizes and locks in the native-stream-completion contract for
 * `llm.generateStream`.
 *
 * The native boundary can legitimately resolve the stream call without ever
 * sending an `isFinal` proto event (see PR #605 review issue #4). Swift
 * treats that as a successful completion and synthesizes a wall-clock
 * result (`RunAnywhere.synthesizeResult` in
 * `runanywhere-swift/Sources/RunAnywhere/Public/API/Namespaces/LLMNamespace.swift`)
 * rather than throwing, as long as at least one native event was observed.
 * RN must mirror that contract instead of silently ending the iterator with
 * no `completed` event.
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

function encodeEvent(partial: Partial<LLMStreamEventMessage>): ArrayBuffer {
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

  test('characterization: native resolving without isFinal is not surfaced as an error today', async () => {
    // Native sends tokens, then the promise from `llmGenerateStreamProto`
    // resolves without ever sending a terminal `isFinal` event -- a
    // legitimate native-boundary shutdown (e.g. backend cooperative stop),
    // not a bridge failure.
    mockNative.llmGenerateStreamProto.mockImplementation(
      async (_bytes, onEvent) => {
        onEvent(encodeEvent({ token: 'Hel', isFinal: false }));
        onEvent(encodeEvent({ token: 'lo', isFinal: false }));
      }
    );

    const events = await collect(llm.generateStream('hi'));

    // The stream must not throw and must still report a `completed` event
    // synthesized from the tokens actually observed -- never a silent stop.
    expect(events.map((e) => e.type)).toEqual([
      'started',
      'token',
      'token',
      'completed',
    ]);
    const completed = events[events.length - 1];
    if (completed?.type !== 'completed') {
      throw new Error('expected a completed event');
    }
    expect(completed.result.text).toBe('Hello');
    expect(completed.result.outputTokens).toBe(2);
    expect(completed.result.finishReason).toBe('stop');
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

  test('thinking tokens are folded into thinkingText on a synthesized completion', async () => {
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
    const completed = events[events.length - 1];
    if (completed?.type !== 'completed') {
      throw new Error('expected a completed event');
    }
    expect(completed.result.text).toBe('answer');
    expect(completed.result.thinkingText).toBe('thinking...');
  });
});
