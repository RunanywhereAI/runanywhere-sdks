/**
 * Speak Tab — V2 canonical proto-byte TTS.
 *
 * Once `ONNX.register()` resolves, the public surface in `@runanywhere/web`
 * (`RunAnywhere.synthesize`, `RunAnywhere.tts.*`) dispatches synthesis
 * through the proto-byte TTS adapter. The PCM bytes returned are played
 * through `AudioPlayback`. Until the WASM module is rebuilt with
 * `RAC_WASM_ONNX=ON`, registration fails with a typed
 * `BackendNotAvailable` error and the view falls back to a diagnostics
 * panel that surfaces the underlying status.
 */

import type { TabLifecycle } from '../app';
import {
  AudioPlayback,
  RunAnywhere,
  TTSProtoAdapter,
  isSDKException,
  tryRunanywhereModule,
} from '@runanywhere/web';
import { ONNX } from '@runanywhere/web-onnx';

let container: HTMLElement;
let unmounted = false;
let playback: AudioPlayback | null = null;
let isSynthesizing = false;
let lastError: string | null = null;
let lastDurationMs: number | null = null;

const DEFAULT_TEXT =
  'Hello — this synthesis was generated entirely on-device through the ' +
  'RunAnywhere Web SDK and the proto-byte TTS adapter.';

export function initSpeakTab(el: HTMLElement): TabLifecycle {
  container = el;
  unmounted = false;
  renderSpeak();
  return {
    onDeactivate: () => {
      unmounted = true;
      playback?.dispose();
      playback = null;
    },
  };
}

interface SpeakStatus {
  moduleInstalled: boolean;
  registered: boolean;
  supportsProto: boolean;
}

function inspectStatus(): SpeakStatus {
  const moduleInstalled = tryRunanywhereModule() != null;
  const registered = ONNX.isRegistered;
  const supportsProto = TTSProtoAdapter.tryDefault()?.supportsProtoTTS() ?? false;
  return { moduleInstalled, registered, supportsProto };
}

function renderSpeak(): void {
  const status = inspectStatus();
  const showLive = status.registered && status.supportsProto;

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Speak</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="onnx-register-btn">${
          status.registered ? 'Re-register ONNX' : 'Register ONNX backend'
        }</button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Backend status</h3>
        <ul class="feature-unavailable__list">
          <li><code>RACommons module installed</code>: <strong>${
            status.moduleInstalled ? 'yes' : 'no'
          }</strong></li>
          <li><code>ONNX.isRegistered</code>: <strong>${
            status.registered ? 'yes' : 'no'
          }</strong></li>
          <li><code>TTSProtoAdapter.supportsProtoTTS()</code>: <strong>${
            status.supportsProto ? 'yes' : 'no'
          }</strong></li>
        </ul>
        <div id="onnx-register-status" class="docs-status"></div>
      </div>

      ${showLive
        ? `
          <div class="docs-section">
            <h3>Synthesize</h3>
            <p class="text-secondary">Type some text and let on-device TTS render it. Audio is decoded as PCM and played through <code>AudioPlayback</code>.</p>
            <textarea class="chat-input" id="speak-text" rows="3" ${
              isSynthesizing ? 'disabled' : ''
            }>${escape(DEFAULT_TEXT)}</textarea>
            <div class="toolbar-actions">
              <button class="btn btn-primary" id="speak-btn" ${
                isSynthesizing ? 'disabled' : ''
              }>${isSynthesizing ? 'Synthesizing...' : 'Speak'}</button>
              <button class="btn btn-secondary" id="stop-btn" ${
                isSynthesizing ? '' : 'disabled'
              }>Stop</button>
            </div>
            <div id="speak-status" class="docs-status">${
              lastError ? `Error: ${escape(lastError)}` : ''
            }${
              lastDurationMs != null && !lastError
                ? `Last synthesis: ${(lastDurationMs / 1000).toFixed(2)}s of audio.`
                : ''
            }</div>
          </div>`
        : `
          <div class="docs-section">
            <h3>Synthesis</h3>
            <p class="text-secondary">
              Real TTS calls dispatch through <code>RunAnywhere.synthesize(text, options)</code>
              once the ONNX backend is registered against a WASM build that
              includes <code>RAC_WASM_ONNX=ON</code>. PCM samples are played via
              <code>AudioPlayback</code>.
            </p>
            <ul class="feature-unavailable__list">
              <li><code>RunAnywhere.modelLifecycle.load(...)</code></li>
              <li><code>RunAnywhere.synthesize(text, { voicePath })</code></li>
              <li><code>AudioPlayback.play(samples, sampleRate)</code></li>
            </ul>
          </div>`}
    </div>
  `;

  container
    .querySelector('#onnx-register-btn')!
    .addEventListener('click', () => void registerOnnx());

  if (showLive) {
    container.querySelector('#speak-btn')?.addEventListener('click', () => {
      void runSynthesize();
    });
    container.querySelector('#stop-btn')?.addEventListener('click', () => {
      playback?.stop();
    });
  }
}

async function registerOnnx(): Promise<void> {
  const banner = container.querySelector<HTMLDivElement>('#onnx-register-status');
  if (!banner) return;
  banner.textContent = 'Registering ONNX backend...';
  try {
    await ONNX.register();
    if (unmounted) return;
    banner.textContent = 'ONNX backend registered.';
    renderSpeak();
  } catch (err) {
    banner.textContent = `Failed to register ONNX backend: ${formatErr(err)}`;
  }
}

async function runSynthesize(): Promise<void> {
  const textarea = container.querySelector<HTMLTextAreaElement>('#speak-text');
  const text = (textarea?.value ?? '').trim();
  if (!text) return;

  isSynthesizing = true;
  lastError = null;
  lastDurationMs = null;
  renderSpeak();

  try {
    const result = await RunAnywhere.synthesize(text);
    lastDurationMs = result.durationMs ?? 0;
    const samples = pcmBytesToFloat32(result.audioData);
    const sampleRate = result.sampleRate || 22050;
    playback = playback ?? new AudioPlayback({ sampleRate });
    await playback.play(samples, sampleRate);
  } catch (err) {
    lastError = formatErr(err);
  } finally {
    isSynthesizing = false;
    if (!unmounted) renderSpeak();
  }
}

/** Decode little-endian Int16 PCM bytes into a Float32Array in [-1, 1]. */
function pcmBytesToFloat32(bytes: Uint8Array): Float32Array {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const samples = new Float32Array(bytes.byteLength / 2);
  for (let i = 0; i < samples.length; i += 1) {
    samples[i] = view.getInt16(i * 2, true) / 0x7fff;
  }
  return samples;
}

function formatErr(err: unknown): string {
  if (isSDKException(err)) return err.message;
  if (err instanceof Error) return err.message;
  return String(err);
}

function escape(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
