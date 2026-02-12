/**
 * More Tab - Transcribe (STT), Speak (TTS), Storage management
 * Matches iOS MoreHubView with NavigationLink list.
 */

import { MicCapture } from '../services/audio';
import { ModelManager } from '../services/model-manager';

let container: HTMLElement;

// Funny texts for TTS "Surprise me" (matching iOS)
const SURPRISE_TEXTS = [
  "Why don't scientists trust atoms? Because they make up everything!",
  "I told my wife she was drawing her eyebrows too high. She looked surprised.",
  "Parallel lines have so much in common. It's a shame they'll never meet.",
  "I'm reading a book on anti-gravity. It's impossible to put down!",
  "Did you hear about the mathematician who's afraid of negative numbers? He'll stop at nothing to avoid them.",
  "What do you call a fake noodle? An impasta!",
  "I would tell you a construction joke, but I'm still working on it.",
];

export function initMoreTab(el: HTMLElement): void {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">More</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area" id="more-content">
      <div class="feature-list">
        <div class="feature-row" id="more-transcribe-btn">
          <div class="feature-icon" style="background:var(--color-blue);">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><path d="M2 13a2 2 0 0 0 2-2V7a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V4a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V7a2 2 0 0 1 2-2"/></svg>
          </div>
          <div class="feature-text">
            <h3>Transcribe</h3>
            <p>Convert speech to text</p>
          </div>
        </div>
        <div class="feature-row" id="more-speak-btn">
          <div class="feature-icon" style="background:var(--color-green);">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>
          </div>
          <div class="feature-text">
            <h3>Speak</h3>
            <p>Convert text to speech</p>
          </div>
        </div>
        <div class="feature-row" id="more-storage-btn">
          <div class="feature-icon" style="background:var(--color-primary);">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
          </div>
          <div class="feature-text">
            <h3>Storage</h3>
            <p>Manage models and files</p>
          </div>
        </div>
      </div>
    </div>

    <!-- Transcribe Sub-view -->
    <div class="sub-view" id="more-transcribe-view">
      <div class="toolbar">
        <button class="back-btn" id="transcribe-back">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><polyline points="15 18 9 12 15 6"/></svg>
          More
        </button>
        <div class="toolbar-title">Transcribe</div>
        <div class="toolbar-actions"></div>
      </div>
      <div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:var(--space-xl);padding:var(--space-3xl);">
        <div class="waveform-bars" id="transcribe-waveform" style="height:60px;">
          ${Array.from({ length: 20 }, () => '<div class="waveform-bar" style="height:4px;"></div>').join('')}
        </div>
        <button class="mic-btn" id="transcribe-mic-btn">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="28" height="28">
            <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
            <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
          </svg>
        </button>
        <p style="color:var(--text-secondary);font-size:var(--font-size-sm);">Tap to start recording</p>
        <div id="transcribe-result" style="min-height:80px;padding:var(--space-lg);background:var(--bg-secondary);border-radius:var(--radius-lg);width:100%;max-width:400px;color:var(--text-secondary);text-align:center;">
          Transcription will appear here...
        </div>
      </div>
    </div>

    <!-- Speak Sub-view -->
    <div class="sub-view" id="more-speak-view">
      <div class="toolbar">
        <button class="back-btn" id="speak-back">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><polyline points="15 18 9 12 15 6"/></svg>
          More
        </button>
        <div class="toolbar-title">Speak</div>
        <div class="toolbar-actions"></div>
      </div>
      <div class="scroll-area" style="display:flex;flex-direction:column;align-items:center;gap:var(--space-xl);padding:var(--space-3xl);">
        <textarea class="chat-input" id="speak-text" placeholder="Enter text to speak..." rows="5" style="max-width:400px;width:100%;min-height:120px;"></textarea>
        <button class="btn btn-sm" id="speak-surprise-btn" style="color:var(--color-purple);">Surprise me</button>
        <div style="display:flex;align-items:center;gap:var(--space-lg);width:100%;max-width:400px;">
          <label style="font-size:var(--font-size-sm);color:var(--text-secondary);min-width:50px;">Speed</label>
          <input type="range" id="speak-speed" min="0.5" max="2" step="0.1" value="1" style="flex:1;">
          <span id="speak-speed-val" style="font-size:var(--font-size-sm);min-width:30px;text-align:right;">1.0x</span>
        </div>
        <button class="btn btn-primary btn-lg" id="speak-btn" style="width:100%;max-width:400px;background:var(--color-purple);border-color:var(--color-purple);">
          Speak
        </button>
      </div>
    </div>

    <!-- Storage Sub-view -->
    <div class="sub-view" id="more-storage-view">
      <div class="toolbar">
        <button class="back-btn" id="storage-back">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><polyline points="15 18 9 12 15 6"/></svg>
          More
        </button>
        <div class="toolbar-title">Storage</div>
        <div class="toolbar-actions"></div>
      </div>
      <div class="scroll-area">
        <div class="storage-overview" id="storage-overview">
          <div class="storage-stat"><div class="value" id="storage-count">0</div><div class="label">Models</div></div>
          <div class="storage-stat"><div class="value" id="storage-size">0 MB</div><div class="label">Total Size</div></div>
          <div class="storage-stat"><div class="value" id="storage-available">-- GB</div><div class="label">Available</div></div>
        </div>
        <div id="storage-models" style="padding:var(--space-lg);"></div>
        <div style="padding:0 var(--space-lg) var(--space-lg);">
          <button class="btn" id="storage-clear-btn" style="width:100%;color:var(--color-red);">Clear All Models</button>
        </div>
      </div>
    </div>
  `;

  // Navigation
  setupNav('more-transcribe-btn', 'more-transcribe-view', 'transcribe-back');
  setupNav('more-speak-btn', 'more-speak-view', 'speak-back');
  setupNav('more-storage-btn', 'more-storage-view', 'storage-back');

  // Transcribe mic
  let isRecording = false;
  const micBtn = container.querySelector('#transcribe-mic-btn')!;
  const waveformBars = container.querySelectorAll('#transcribe-waveform .waveform-bar') as NodeListOf<HTMLElement>;

  micBtn.addEventListener('click', async () => {
    if (isRecording) {
      MicCapture.stop();
      micBtn.classList.remove('listening');
      isRecording = false;
      waveformBars.forEach((b) => (b.style.height = '4px'));
    } else {
      try {
        await MicCapture.start((level) => {
          waveformBars.forEach((bar) => {
            const h = 4 + Math.random() * level * 56;
            bar.style.height = h + 'px';
          });
        });
        micBtn.classList.add('listening');
        isRecording = true;
      } catch {
        // mic access denied
      }
    }
  });

  // Speak
  const speedSlider = container.querySelector('#speak-speed') as HTMLInputElement;
  const speedVal = container.querySelector('#speak-speed-val')!;
  speedSlider.addEventListener('input', () => {
    speedVal.textContent = parseFloat(speedSlider.value).toFixed(1) + 'x';
  });

  container.querySelector('#speak-surprise-btn')!.addEventListener('click', () => {
    const textArea = container.querySelector('#speak-text') as HTMLTextAreaElement;
    textArea.value = SURPRISE_TEXTS[Math.floor(Math.random() * SURPRISE_TEXTS.length)];
  });

  // Storage
  container.querySelector('#storage-back')!.addEventListener('click', refreshStorage);
  refreshStorage();
}

function setupNav(triggerBtnId: string, subViewId: string, backBtnId: string): void {
  container.querySelector(`#${triggerBtnId}`)!.addEventListener('click', () => {
    container.querySelector(`#${subViewId}`)!.classList.add('active');
  });
  container.querySelector(`#${backBtnId}`)!.addEventListener('click', () => {
    container.querySelector(`#${subViewId}`)!.classList.remove('active');
  });
}

async function refreshStorage(): Promise<void> {
  const info = await ModelManager.getStorageInfo();
  const countEl = container.querySelector('#storage-count')!;
  const sizeEl = container.querySelector('#storage-size')!;
  const availEl = container.querySelector('#storage-available')!;

  countEl.textContent = String(info.modelCount);
  sizeEl.textContent = formatBytes(info.totalSize);
  availEl.textContent = formatBytes(info.available);

  // List downloaded models
  const modelsEl = container.querySelector('#storage-models')!;
  const downloaded = ModelManager.getModels().filter((m) => m.status === 'downloaded' || m.status === 'loaded');
  if (downloaded.length === 0) {
    modelsEl.innerHTML = '<p style="text-align:center;color:var(--text-tertiary);padding:var(--space-xl);">No downloaded models</p>';
  } else {
    modelsEl.innerHTML = downloaded
      .map(
        (m) => `
        <div class="model-row">
          <div class="model-logo">&#129302;</div>
          <div class="model-info">
            <div class="model-name">${m.name}</div>
            <div class="model-meta">
              <span class="model-framework-badge">${m.framework}</span>
              ${m.sizeBytes ? `<span class="model-size">${formatBytes(m.sizeBytes)}</span>` : ''}
            </div>
          </div>
          <button class="btn btn-sm" style="color:var(--color-red);" data-delete="${m.id}">Delete</button>
        </div>
      `
      )
      .join('');

    modelsEl.querySelectorAll('[data-delete]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        await ModelManager.deleteModel((btn as HTMLElement).dataset.delete!);
        refreshStorage();
      });
    });
  }
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[i];
}
