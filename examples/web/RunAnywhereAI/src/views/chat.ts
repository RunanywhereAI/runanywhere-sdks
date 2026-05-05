/**
 * Chat Tab — minimal LLM chat over the V2 proto-byte LLM adapter.
 *
 * Once `LlamaCPP.register()` resolves, the public surface in
 * `@runanywhere/web` (`RunAnywhere.generateStream`) flows through the
 * proto-byte LLM adapter into the WASM module. This view keeps a
 * `feature-unavailable` fallback when the backend is missing so the rest
 * of the app shell can still validate.
 *
 * MVP scope: text-only generation with streaming tokens. Tool calling /
 * structured output are exposed via the existing core extensions and can
 * be layered onto this view in a follow-up.
 */

import type { TabLifecycle } from '../app';
import {
  RunAnywhere,
  isSDKException,
} from '@runanywhere/web';
import { renderFeatureUnavailable } from '../components/feature-unavailable';

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

let container: HTMLElement;
let messages: ChatMessage[] = [];
let isGenerating = false;
let cancelGeneration: (() => void) | null = null;

export function initChatTab(el: HTMLElement): TabLifecycle {
  container = el;

  if (!isLLMBackendAvailable()) {
    renderFeatureUnavailable(el, {
      title: 'Chat',
      description:
        'Streaming LLM chat. Backed by `RunAnywhere.generateStream` once a ' +
        'WASM LLM backend is registered (e.g. via `LlamaCPP.register()`).',
      requires: [
        'RunAnywhere.generateStream',
        'RunAnywhere.modelLifecycle.load',
      ],
    });
    return {};
  }

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Chat</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="chat-clear-btn">Clear</button>
      </div>
    </div>
    <div class="scroll-area" id="chat-messages"></div>
    <div class="chat-input-area">
      <textarea class="chat-input" id="chat-input" placeholder="Message..." rows="1"></textarea>
      <button class="send-btn" id="chat-send-btn" disabled>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>
      </button>
    </div>
  `;

  const messagesEl = container.querySelector('#chat-messages') as HTMLElement;
  const inputEl = container.querySelector('#chat-input') as HTMLTextAreaElement;
  const sendBtn = container.querySelector('#chat-send-btn') as HTMLButtonElement;
  const clearBtn = container.querySelector('#chat-clear-btn') as HTMLButtonElement;

  const refreshSendButton = () => {
    sendBtn.disabled = isGenerating || inputEl.value.trim().length === 0;
  };

  inputEl.addEventListener('input', refreshSendButton);
  inputEl.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      void onSend();
    }
  });
  sendBtn.addEventListener('click', () => {
    void onSend();
  });
  clearBtn.addEventListener('click', () => {
    if (cancelGeneration) cancelGeneration();
    messages = [];
    renderMessages(messagesEl);
  });

  renderMessages(messagesEl);

  async function onSend(): Promise<void> {
    const prompt = inputEl.value.trim();
    if (!prompt || isGenerating) return;

    inputEl.value = '';
    refreshSendButton();

    messages.push({ role: 'user', content: prompt });
    const assistantMsg: ChatMessage = { role: 'assistant', content: '' };
    messages.push(assistantMsg);
    renderMessages(messagesEl);

    isGenerating = true;
    refreshSendButton();

    try {
      const stream = await RunAnywhere.generateStream(prompt, {
        maxTokens: 256,
      });
      cancelGeneration = stream.cancel;
      for await (const token of stream.stream) {
        assistantMsg.content += token;
        updateLastMessageContent(messagesEl, assistantMsg.content);
      }
      // Wait for the result to settle (so cancel timing is consistent).
      await stream.result;
    } catch (error) {
      const message = formatChatError(error);
      assistantMsg.content = message;
      updateLastMessageContent(messagesEl, message);
    } finally {
      cancelGeneration = null;
      isGenerating = false;
      refreshSendButton();
    }
  }

  return {
    onDeactivate: () => {
      if (cancelGeneration) cancelGeneration();
    },
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Probes whether an LLM proto-byte backend is registered. When no backend
 * package has called `setRunanywhereModule(...)`, every adapter throws
 * `backendNotAvailable`; we render the feature-unavailable placeholder
 * instead of a useless empty chat.
 */
function isLLMBackendAvailable(): boolean {
  try {
    // The provider-aware availability check on the public surface.
    // A backend is registered iff `LLMProtoAdapter.tryDefault()` is non-null
    // — but rather than reach into the internal adapter, we rely on the
    // `backendNotAvailable` exception flow. Calling `RunAnywhere.textGeneration`
    // is cheap (it's just the namespace object).
    void RunAnywhere.textGeneration;
    // Heuristic: assume the backend is wired if the runtime active mode is
    // populated (the llamacpp bridge sets it post-load). If it's null, the
    // backend hasn't been registered yet.
    return RunAnywhere.runtime.active !== null;
  } catch {
    return false;
  }
}

function renderMessages(host: HTMLElement): void {
  if (messages.length === 0) {
    host.innerHTML = `
      <div class="chat-empty-state">
        <h3>Start chatting</h3>
        <p>Type a message below. Generation streams token-by-token through the
        proto-byte LLM adapter.</p>
      </div>
    `;
    return;
  }

  host.innerHTML = messages.map((msg, idx) => `
    <div class="chat-message chat-message--${msg.role}" data-idx="${idx}">
      <div class="chat-bubble">${escapeHTML(msg.content) || '<span class="chat-bubble-typing">…</span>'}</div>
    </div>
  `).join('');

  host.scrollTop = host.scrollHeight;
}

function updateLastMessageContent(host: HTMLElement, content: string): void {
  const last = host.lastElementChild;
  if (last) {
    const bubble = last.querySelector('.chat-bubble');
    if (bubble) {
      bubble.textContent = content || '…';
    }
  }
  host.scrollTop = host.scrollHeight;
}

function escapeHTML(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatChatError(error: unknown): string {
  if (isSDKException(error)) {
    return `Error: ${error.message}`;
  }
  if (error instanceof Error) {
    return `Error: ${error.message}`;
  }
  return `Error: ${String(error)}`;
}
