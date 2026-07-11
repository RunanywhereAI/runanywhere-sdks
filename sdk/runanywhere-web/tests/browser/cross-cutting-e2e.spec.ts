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
 *   - Storage           (browser backend, isLocalStorageSupported)
 *   - SDK Events        (poll + publish proto)
 */
import { test, expect, type Page } from '@playwright/test';

const shouldRun = process.env.RA_RUN_CROSS_CUTTING_E2E === '1'
  || process.env.RA_RUN_SPEECH_E2E === '1'
  || process.env.RA_RUN_FULL_E2E === '1';

interface AppReadinessSnapshot {
  state: 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
  backend: 'pending' | 'registered' | 'unavailable';
  backendError?: string;
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
        ): { preparedPrompt?: string; errorCode?: number };
        validate(
          text: string,
          options?: { jsonSchema?: string },
        ): { isValid: boolean; errorMessage?: string; parsedJson?: Uint8Array };
      };
      lora: {
        supportsNative(): boolean;
        supportsNativeCatalog(): boolean;
        missingExports(): string[];
      };
      storage: {
        backend: 'fsAccess' | 'opfs' | 'memory';
        isLocalStorageSupported: boolean;
        supportsNativeAnalyzer(): boolean;
      };
      sdkEvents: {
        poll(): unknown | null;
        publishFailure(options: {
          errorCode: number;
          message: string;
          component: string;
          operation: string;
          recoverable: boolean;
        }): boolean;
        clearQueue(): void;
      };
    };
  }
}

async function bootApplication(page: Page): Promise<void> {
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
  expect(
    readiness?.backend,
    `backend registration failed: ${readiness?.backendError ?? 'unknown error'}`,
  ).toBe('registered');
  await page.waitForFunction(() => !!window.__RUNANYWHERE_SDK__?.isInitialized, null, {
    timeout: 30_000,
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
  test.skip(
    !shouldRun,
    'Cross-cutting E2E is opt-in (set RA_RUN_CROSS_CUTTING_E2E=1); backend WASM artifacts are required.',
  );
  test('exposes tool calling, structured output, LoRA, storage, and event APIs', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    await bootApplication(page);

    const result = await page.evaluate((schema) => {
      const sdk = window.__RUNANYWHERE_SDK__!;

      const toolCalling = {
        supportsProto: sdk.toolCalling.supportsProtoToolCalling(),
        formatted: sdk.toolCalling.formatToolsForPrompt([
          {
            name: 'get_weather',
            description: 'Get current weather for a city',
            jsonSchema: JSON.stringify({
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
        supportsNative: sdk.lora.supportsNative(),
        supportsNativeCatalog: sdk.lora.supportsNativeCatalog(),
        missingExports: sdk.lora.missingExports(),
      };

      const storage = {
        backend: sdk.storage.backend,
        isLocalStorageSupported: sdk.storage.isLocalStorageSupported,
        supportsNativeAnalyzer: sdk.storage.supportsNativeAnalyzer(),
      };

      let sdkEventsPublished = false;
      let sdkEventsPolled = false;
      try {
        sdk.sdkEvents.clearQueue();
        sdkEventsPublished = sdk.sdkEvents.publishFailure({
          errorCode: -1,
          message: 'Cross-cutting browser event probe',
          component: 'browser-e2e',
          operation: 'sdkEvents',
          recoverable: true,
        });
        sdkEventsPolled = sdk.sdkEvents.poll() !== null;
      } catch {
        sdkEventsPublished = false;
        sdkEventsPolled = false;
      }

      return {
        toolCalling,
        structured,
        lora,
        storage,
        sdkEventsPublished,
        sdkEventsPolled,
        version: sdk.version,
      };
    }, PERSON_SCHEMA);

    expect(result.version, 'SDK version exposed').toMatch(/^[0-9]+\./);

    expect(result.toolCalling.supportsProto, 'tool calling proto exports').toBe(true);
    expect(result.toolCalling.formatted.length, 'tool calling formatted prompt non-empty').toBeGreaterThan(0);
    expect(result.toolCalling.formatted, 'tool schema preserved in prompt').toContain('city');
    expect(result.toolCalling.parsed.hasToolCall, 'tool call parser detects call').toBe(true);
    expect(result.toolCalling.parsed.toolCalls[0]?.name).toBe('get_weather');

    expect(result.structured.supportsProto, 'structured output proto exports').toBe(true);
    expect((result.structured.prompt.preparedPrompt ?? '').length, 'structured prompt non-empty').toBeGreaterThan(0);
    expect(result.structured.validation.isValid, 'JSON validates against schema').toBe(true);

    expect(result.lora.supportsNative, 'native LoRA ABI').toBe(true);
    expect(result.lora.supportsNativeCatalog, 'native LoRA catalog ABI').toBe(true);
    expect(result.lora.missingExports, 'all LoRA exports present').toEqual([]);

    expect(['opfs', 'memory', 'fsAccess']).toContain(result.storage.backend);
    expect(typeof result.storage.isLocalStorageSupported).toBe('boolean');
    expect(result.storage.supportsNativeAnalyzer, 'native storage analyzer').toBe(true);

    expect(result.sdkEventsPublished, 'sdkEvents.publishFailure succeeds').toBe(true);
    expect(result.sdkEventsPolled, 'sdkEvents.poll returns the published event').toBe(true);

    const fatalErrors = consoleErrors.filter(
      (err) => !err.includes('NO_COLOR')
        // Credential-less local initialization intentionally defers the
        // assignment fetch; backend/facade assertions above remain valid.
        && !err.includes('model assignment base URL is not configured'),
    );
    expect(fatalErrors, `unexpected console errors:\n${fatalErrors.join('\n')}`).toHaveLength(0);
  });
});
