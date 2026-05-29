/**
 * Chat Tab — minimal LLM chat over the V2 proto-byte LLM adapter.
 *
 * Once `LlamaCPP.register()` resolves AND the user loads a model via the
 * toolbar model selector, the public surface in `@runanywhere/web`
 * (`RunAnywhere.generateStream`) flows through the proto-byte LLM adapter
 * into the WASM module.
 *
 * The toolbar model pill + "Get Started" overlay are built by
 * `components/model-selection.ts`. They expose the DOM ids the readiness
 * probe in `main.ts` looks for (`#chat-toolbar-model`, `#chat-model-overlay`,
 * `#chat-get-started-btn`).
 */

import type { TabLifecycle } from '../app';
import {
  RunAnywhere,
  isSDKException,
} from '@runanywhere/web';
import {
  buildGetStartedOverlay,
  buildToolbarModelButton,
  ensureCatalogRegistered,
  onModelStateChange,
} from '../components/model-selection';
import { formatError } from '../services/format-error';

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

  // Register the catalog as soon as the chat tab is mounted. This is
  // best-effort — if the WASM backend has not yet installed the proto-byte
  // registry adapter, the call returns false and the toolbar button
  // displays "Loading…" until a later call succeeds.
  ensureCatalogRegistered();

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title" id="chat-toolbar-title-host"></div>
      <div class="toolbar-actions" id="chat-toolbar-actions-host"></div>
    </div>
    <div class="scroll-area" id="chat-messages"></div>
    <div class="chat-input-area">
      <textarea class="chat-input" id="chat-input" placeholder="Message..." rows="1"></textarea>
      <button class="send-btn" id="chat-send-btn" disabled>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>
      </button>
    </div>
  `;

  // Mount the toolbar model pill in the title slot so the probe finds the
  // #chat-toolbar-model element even when the panel becomes the active tab.
  const titleHost = container.querySelector('#chat-toolbar-title-host') as HTMLElement;
  titleHost.appendChild(buildToolbarModelButton());

  // Mount the "Get Started" overlay directly inside the panel host so the
  // readiness probe's overlay visibility check works. The overlay is shown
  // whenever no model is loaded and hidden once a model enters the loaded
  // state.
  container.appendChild(buildGetStartedOverlay());

  const messagesEl = container.querySelector('#chat-messages') as HTMLElement;
  const inputEl = container.querySelector('#chat-input') as HTMLTextAreaElement;
  const sendBtn = container.querySelector('#chat-send-btn') as HTMLButtonElement;
  const clearBtn = buildClearButton();
  (container.querySelector('#chat-toolbar-actions-host') as HTMLElement).appendChild(clearBtn);

  const refreshSendButton = () => {
    const hasInput = inputEl.value.trim().length > 0;
    const modelLoaded = isModelLoaded();
    sendBtn.disabled = isGenerating || !hasInput || !modelLoaded;
    // Tooltip clarifies why the button is disabled. The textbox stays
    // enabled so users may compose while a model is loading.
    if (!modelLoaded) {
      sendBtn.title = 'Load a model first';
    } else if (!hasInput) {
      sendBtn.title = 'Type a message to send';
    } else if (isGenerating) {
      sendBtn.title = 'Generation in progress';
    } else {
      sendBtn.title = 'Send';
    }
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

  // Apply the initial disabled / tooltip state so the Send button reflects
  // "Load a model first" before any user interaction.
  refreshSendButton();

  // Re-render when the model state changes so disabled/enabled states stay
  // consistent with what the toolbar reports.
  const unsubscribeState = onModelStateChange(() => refreshSendButton());

  async function onSend(): Promise<void> {
    const prompt = inputEl.value.trim();
    if (!prompt || isGenerating) return;

    if (!isLLMBackendAvailable()) {
      messages.push({
        role: 'assistant',
        content: 'No LLM backend available. Check the console for backend load errors.',
      });
      renderMessages(messagesEl);
      return;
    }

    inputEl.value = '';
    refreshSendButton();

    messages.push({ role: 'user', content: prompt });
    const assistantMsg: ChatMessage = { role: 'assistant', content: '' };
    messages.push(assistantMsg);
    renderMessages(messagesEl);

    isGenerating = true;
    refreshSendButton();

    try {
      const stream = await RunAnywhere.generateStream({
        prompt,
        maxTokens: 256,
      });
      cancelGeneration = stream.cancel;
      for await (const token of stream.stream) {
        assistantMsg.content += token;
        updateLastMessageContent(messagesEl, assistantMsg.content);
      }
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

  // Tear down the model-state subscription if the panel element ever
  // detaches (e.g. a full app-shell re-render). Kept minimal since the
  // tab framework does not call a dispose hook today.
  const disposeObserver = new MutationObserver(() => {
    if (!container.isConnected) {
      disposeObserver.disconnect();
      unsubscribeState();
    }
  });
  const rootParent = container.parentElement;
  if (rootParent) disposeObserver.observe(rootParent, { childList: true });

  return {
    onDeactivate: () => {
      if (cancelGeneration) cancelGeneration();
    },
    onActivate: () => {
      // Re-try catalog registration on tab activation in case the backend
      // was not ready when the tab was first mounted.
      ensureCatalogRegistered();
    },
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isLLMBackendAvailable(): boolean {
  try {
    return RunAnywhere.textGeneration.supportsProtoLLM();
  } catch {
    return false;
  }
}

/**
 * True when the C++ lifecycle reports a model loaded. Used to gate the chat
 * Send button so users can't click into a silent no-op before loading a
 * model from the toolbar picker.
 */
function isModelLoaded(): boolean {
  try {
    return Boolean(RunAnywhere.currentModel()?.modelId);
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
      <div class="chat-bubble">${escapeHTML(msg.content) || '<span class="chat-bubble-typing">&hellip;</span>'}</div>
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
  return `Error: ${formatError(error)}`;
}

function buildClearButton(): HTMLButtonElement {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.id = 'chat-clear-btn';
  btn.className = 'btn btn-secondary';
  btn.textContent = 'Clear';
  return btn;
}
