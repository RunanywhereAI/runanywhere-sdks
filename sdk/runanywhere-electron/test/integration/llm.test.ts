// End-to-end LLM inference through NativeBackend against a real local GGUF.
//
// Gated: skipped unless RUNANYWHERE_NATIVE_PATH points at a built addon and a
// small model exists on disk. This is the only test that proves the proto-byte
// path all the way down to llama.cpp, so it never silently passes — it skips
// loudly when its prerequisites are absent.
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import test from 'node:test';

import {
  InferenceFramework,
  ModelCategory,
  ModelFormat,
  ModelInfo,
  ModelLoadRequest,
  ModelLoadResult,
  ModelSource,
} from '@runanywhere/proto-ts/model_types';
import { LLMGenerateRequest, LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
import { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';

import { loadAddon } from '../../src/native/load.js';
import { NativeBackend } from '../../src/native/backend.js';

const MODEL_ID = 'smollm2-135m';
const MODEL_PATH = path.join(os.homedir(), '.runanywhere', 'models', MODEL_ID, 'model.gguf');
const BASE = path.join(os.homedir(), '.runanywhere');
const ready = Boolean(process.env.RUNANYWHERE_NATIVE_PATH) && fs.existsSync(MODEL_PATH);

test(
  'NativeBackend: initialize -> register -> load -> generate (unary + stream)',
  { skip: ready ? false : 'set RUNANYWHERE_NATIVE_PATH and provide a local GGUF to run' },
  async () => {
    const backend = new NativeBackend(loadAddon());
    await backend.initialize({ baseDir: BASE });

    await backend.registerModel(
      ModelInfo.encode(
        ModelInfo.fromPartial({
          id: MODEL_ID,
          name: 'SmolLM2 135M',
          category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
          format: ModelFormat.MODEL_FORMAT_GGUF,
          framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
          localPath: MODEL_PATH,
          source: ModelSource.MODEL_SOURCE_LOCAL,
          isDownloaded: true,
        })
      ).finish()
    );

    const loadRes = ModelLoadResult.decode(
      await backend.loadModel(
        ModelLoadRequest.encode(
          ModelLoadRequest.fromPartial({
            modelId: MODEL_ID,
            framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
            category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
            validateAvailability: false,
          })
        ).finish()
      )
    );
    assert.ok(!loadRes.error?.message, `load failed: ${loadRes.error?.message}`);

    const options = { maxOutputTokens: 48, temperature: 0.7, topP: 0.9 };
    const buildReq = () =>
      LLMGenerateRequest.encode(
        LLMGenerateRequest.fromPartial({ prompt: 'Say hello in one short sentence.', options })
      ).finish();

    const gen = LLMGenerationResult.decode(await backend.llmGenerate(buildReq()));
    assert.ok(gen.text.length > 0, 'unary generation produced no text');

    let streamed = '';
    let tokens = 0;
    await backend.llmGenerateStream(buildReq(), (bytes) => {
      const ev = LLMStreamEvent.decode(bytes);
      if (ev.token) {
        streamed += ev.token;
        tokens += 1;
      }
    });
    assert.ok(tokens > 0 && streamed.length > 0, 'streaming produced no tokens');

    await backend.shutdown();
  }
);
