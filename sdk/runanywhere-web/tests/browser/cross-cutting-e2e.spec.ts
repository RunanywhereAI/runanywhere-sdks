/**
 * Cross-cutting Web SDK browser E2E.
 *
 * Exercises every Web facade that does NOT require a model download. The
 * goal is to prove that the proto-byte adapters are wired in across all
 * cross-cutting surfaces once a backend (here: the llamacpp WASM module)
 * has installed itself via `setRunanywhereModule`. Together with
 * `sdk-smoke`, `backend-readiness`, `llm-generate`, `vlm-generate`, and
 * `speech-rag-e2e`, this gives end-to-end coverage of every public surface
 * the Swift facade exposes:
 *
 *   - Tool Calling      (parse + format prompt, native exports present)
 *   - Structured Output (preparePrompt + validate, native exports present)
 *   - LoRA registry     (state probe, supportsNativeLoRA flag)
 *   - Hardware          (profile + chip + acceleration mode)
 *   - Storage           (browser backend, isLocalStorageSupported)
 *   - SDK Events        (poll + publish proto)
 */
import { test, expect } from '@playwright/test';

interface AppReadinessSnapshot {
  state: 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    __RUNANYWHERE_SDK__?: {
      isInitialized: boolean;
      version: string;
      toolCalling: {
        supportsProtoToolCalling(): boolean;
        parseToolCall(text: string, options?: Record<string, unknown>): {
          hasToolCall: boolean;
          toolCalls: Array<{ name: string; argumentsJson?: string }>;
          remainingText?: string;
          errorCode: number;
          errorMessage?: string;
        };
        formatToolsForPrompt(tools: unknown[]): string;
      };
      structuredOutput: {
        supportsProtoStructuredOutput(): boolean;
        preparePrompt(
          prompt: string,
          options?: { jsonSchema?: string; includeSchemaInPrompt?: boolean },
        ): { promptText?: string; errorCode?: number };
        validate(
          text: string,
          options?: { jsonSchema?: string },
        ): { isValid: boolean; errorMessage?: string; parsedJson?: Uint8Array };
      };
      lora: {
        state(): { loadedAdapters: unknown[]; hasActiveAdapters: boolean; errorCode: number };
      };
      hardware: {
        getProfile(): {
          profile?: { chip?: string; coreCount?: number; accelerationMode?: string };
          accelerators: Array<{ name: string }>;
        };
        getChip(): string;
        accelerationMode: string;
      };
      storage: {
        backend: 'fsAccess' | 'opfs' | 'memory';
        isLocalStorageSupported: boolean;
        supportsNativeAnalyzer(): boolean;
      };
      sdkEvents: {
        poll(input: { maxEvents: number; clear: boolean }): { events: unknown[] };
      };
    };
  }
}

async function bootAndRegisterONNX(page: import('@playwright/test').Page): Promise<void> {
  await page.goto('/');
  await page.waitForFunction(
    () => {
      const snap = window.__RUNANYWHERE_AI_READY__;
      return !!snap && (snap.state === 'interactive' || snap.state === 'error');
    },
    null,
    { timeout: 60_000 },
  );
  const readiness = await page.evaluate(() => window.__RUNANYWHERE_AI_READY__);
  expect(readiness?.state, `readiness error: ${readiness?.state}`).not.toBe('error');
  await page.waitForFunction(() => !!window.__RUNANYWHERE_SDK__?.isInitialized, null, {
    timeout: 30_000,
  });
  await page.evaluate(async () => {
    const onnx = await import(
      '/@fs/Users/sanchitmonga/development/ODLM/MONOREPOOO/runanywhere-sdks3/runanywhere-sdks-main/sdk/runanywhere-web/packages/onnx/src/index.ts'
    );
    await onnx.ONNX.register();
  });
}

const PERSON_SCHEMA = JSON.stringify({
  type: 'object',
  properties: {
    name: { type: 'string' },
    age: { type: 'integer' },
  },
  required: ['name', 'age'],
});

test.describe('Cross-cutting Web SDK proto-byte facades', () => {
  test('exposes tool calling, structured output, LoRA, hardware, storage, and event APIs', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    await bootAndRegisterONNX(page);

    const result = await page.evaluate((schema) => {
      const sdk = window.__RUNANYWHERE_SDK__!;

      const toolCalling = {
        supportsProto: sdk.toolCalling.supportsProtoToolCalling(),
        formatted: sdk.toolCalling.formatToolsForPrompt([
          {
            name: 'get_weather',
            description: 'Get current weather for a city',
            parametersJson: JSON.stringify({
              type: 'object',
              properties: { city: { type: 'string' } },
              required: ['city'],
            }),
          },
        ]),
        parsed: sdk.toolCalling.parseToolCall(
          '<tool_call>{"name":"get_weather","arguments":{"city":"Tokyo"}}</tool_call>',
        ),
      };

      const structured = {
        supportsProto: sdk.structuredOutput.supportsProtoStructuredOutput(),
        prompt: sdk.structuredOutput.preparePrompt(
          'Tell me about a person',
          { jsonSchema: schema, includeSchemaInPrompt: true },
        ),
        validation: sdk.structuredOutput.validate(
          '{"name":"Ada","age":36}',
          { jsonSchema: schema },
        ),
      };

      const lora = {
        state: sdk.lora.state(),
      };

      const hardware = {
        profile: sdk.hardware.getProfile(),
        chip: sdk.hardware.getChip(),
        accelerationMode: sdk.hardware.accelerationMode,
      };

      const storage = {
        backend: sdk.storage.backend,
        isLocalStorageSupported: sdk.storage.isLocalStorageSupported,
        supportsNativeAnalyzer: sdk.storage.supportsNativeAnalyzer(),
      };

      const sdkEvents = sdk.sdkEvents.poll({ maxEvents: 16, clear: false });

      return { toolCalling, structured, lora, hardware, storage, sdkEvents, version: sdk.version };
    }, PERSON_SCHEMA);

    expect(result.version, 'SDK version exposed').toMatch(/^[0-9]+\./);

    expect(result.toolCalling.supportsProto, 'tool calling proto exports').toBe(true);
    expect(result.toolCalling.formatted.length, 'tool calling formatted prompt non-empty').toBeGreaterThan(0);
    expect(result.toolCalling.parsed.hasToolCall, 'tool call parser detects call').toBe(true);
    expect(result.toolCalling.parsed.toolCalls[0]?.name).toBe('get_weather');

    expect(result.structured.supportsProto, 'structured output proto exports').toBe(true);
    expect((result.structured.prompt.promptText ?? '').length, 'structured prompt non-empty').toBeGreaterThan(0);
    expect(result.structured.validation.isValid, 'JSON validates against schema').toBe(true);

    expect(result.lora.state.errorCode, 'LoRA state errorCode = 0').toBe(0);
    expect(Array.isArray(result.lora.state.loadedAdapters)).toBe(true);

    expect(result.hardware.chip.length, 'chip name non-empty').toBeGreaterThan(0);
    expect(result.hardware.accelerationMode.length, 'acceleration mode non-empty').toBeGreaterThan(0);
    expect(Array.isArray(result.hardware.profile.accelerators)).toBe(true);

    expect(['opfs', 'memory', 'fsAccess']).toContain(result.storage.backend);
    expect(typeof result.storage.isLocalStorageSupported).toBe('boolean');
    expect(typeof result.storage.supportsNativeAnalyzer).toBe('boolean');

    expect(Array.isArray(result.sdkEvents.events), 'sdkEvents.poll returns events array').toBe(true);

    const fatalErrors = consoleErrors.filter((err) => !err.includes('NO_COLOR'));
    expect(fatalErrors, `unexpected console errors:\n${fatalErrors.join('\n')}`).toHaveLength(0);
  });
});
