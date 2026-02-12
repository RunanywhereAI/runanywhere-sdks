/**
 * Chat Tab - Full chat interface matching iOS ChatInterfaceView
 *
 * Features: model overlay, model selection sheet, message bubbles,
 * streaming, thinking mode, typing indicator, input area, toolbar.
 */

import { ModelManager, type ModelInfo } from '../services/model-manager';
import { showModelSelectionSheet } from '../components/model-selection';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  thinking?: string;
  timestamp: number;
  modelId?: string;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

let messages: ChatMessage[] = [];
let isGenerating = false;
let container: HTMLElement;
let messagesEl: HTMLElement;
let inputEl: HTMLTextAreaElement;
let sendBtn: HTMLButtonElement;
let overlayEl: HTMLElement;
let toolbarModelEl: HTMLElement;

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export function initChatTab(el: HTMLElement): void {
  container = el;
  container.innerHTML = `
    <!-- Toolbar -->
    <div class="toolbar">
      <div class="toolbar-actions">
        <button class="btn btn-icon" id="chat-history-btn" title="Conversations">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><path d="M12 8v4l3 3m6-3a9 9 0 1 1-18 0 9 9 0 0 1 18 0z"/></svg>
        </button>
      </div>
      <div class="toolbar-title" id="chat-toolbar-model" style="cursor:pointer;">Select Model</div>
      <div class="toolbar-actions">
        <button class="btn btn-icon" id="chat-info-btn" title="Info">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>
        </button>
      </div>
    </div>

    <!-- Messages -->
    <div class="scroll-area" id="chat-messages" style="padding-top:var(--space-md);padding-bottom:var(--space-md);"></div>

    <!-- Input -->
    <div class="chat-input-area">
      <textarea class="chat-input" id="chat-input" placeholder="Message..." rows="1"></textarea>
      <button class="send-btn" id="chat-send-btn" disabled>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>
      </button>
    </div>

    <!-- Model Required Overlay -->
    <div class="model-overlay" id="chat-model-overlay">
      <div class="model-overlay-bg" id="chat-floating-bg"></div>
      <div class="model-overlay-content">
        <div class="sparkle-icon">&#10024;</div>
        <h2>Welcome!</h2>
        <p>Start chatting with on-device AI. Everything runs privately in your browser.</p>
        <button class="btn btn-primary btn-lg" id="chat-get-started-btn">Get Started</button>
        <div class="privacy-note">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          <span>100% Private &mdash; Runs on your device</span>
        </div>
      </div>
    </div>
  `;

  // Build floating circles for overlay
  buildFloatingCircles();

  // Cache references
  messagesEl = container.querySelector('#chat-messages')!;
  inputEl = container.querySelector('#chat-input')!;
  sendBtn = container.querySelector('#chat-send-btn')!;
  overlayEl = container.querySelector('#chat-model-overlay')!;
  toolbarModelEl = container.querySelector('#chat-toolbar-model')!;

  // Event listeners
  sendBtn.addEventListener('click', sendMessage);
  inputEl.addEventListener('input', onInputChange);
  inputEl.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  });

  container.querySelector('#chat-get-started-btn')!.addEventListener('click', openModelSheet);
  toolbarModelEl.addEventListener('click', openModelSheet);

  // Subscribe to model changes
  ModelManager.onChange(onModelsChanged);
  onModelsChanged(ModelManager.getModels());
}

// ---------------------------------------------------------------------------
// Floating circles background
// ---------------------------------------------------------------------------

function buildFloatingCircles(): void {
  const bg = container.querySelector('#chat-floating-bg')!;
  const colors = ['#FF5500', '#3B82F6', '#8B5CF6', '#10B981', '#EAB308'];
  for (let i = 0; i < 8; i++) {
    const circle = document.createElement('div');
    circle.className = 'floating-circle';
    const size = 60 + Math.random() * 120;
    circle.style.cssText = `
      width:${size}px; height:${size}px;
      background:${colors[i % colors.length]};
      left:${Math.random() * 100}%;
      top:${Math.random() * 100}%;
      animation-delay:${Math.random() * 4}s;
      animation-duration:${6 + Math.random() * 6}s;
    `;
    bg.appendChild(circle);
  }
}

// ---------------------------------------------------------------------------
// Model Sheet
// ---------------------------------------------------------------------------

function openModelSheet(): void {
  showModelSelectionSheet('text');
}

function onModelsChanged(_models: ModelInfo[]): void {
  const loaded = ModelManager.getLoadedModel();
  if (loaded) {
    overlayEl.style.display = 'none';
    toolbarModelEl.textContent = loaded.name;
  } else {
    overlayEl.style.display = '';
    toolbarModelEl.textContent = 'Select Model';
  }
}

// ---------------------------------------------------------------------------
// Input Handling
// ---------------------------------------------------------------------------

function onInputChange(): void {
  const hasText = inputEl.value.trim().length > 0;
  sendBtn.disabled = !hasText || isGenerating;
  // Auto-resize
  inputEl.style.height = 'auto';
  inputEl.style.height = Math.min(inputEl.scrollHeight, 120) + 'px';
}

// ---------------------------------------------------------------------------
// Send Message
// ---------------------------------------------------------------------------

async function sendMessage(): Promise<void> {
  const text = inputEl.value.trim();
  if (!text || isGenerating) return;

  const loaded = ModelManager.getLoadedModel();
  if (!loaded) {
    openModelSheet();
    return;
  }

  // Add user message
  const userMsg: ChatMessage = {
    id: crypto.randomUUID(),
    role: 'user',
    content: text,
    timestamp: Date.now(),
  };
  messages.push(userMsg);
  renderMessage(userMsg);
  inputEl.value = '';
  onInputChange();

  // Show typing indicator
  isGenerating = true;
  sendBtn.disabled = true;
  showTypingIndicator();

  try {
    // Import the SDK TextGeneration extension
    const { TextGeneration } = await import(
      '../../../../../sdk/runanywhere-web/packages/core/src/index'
    );

    if (!TextGeneration.isModelLoaded) {
      throw new Error('Model not loaded in WASM backend');
    }

    // Use streaming generation for token-by-token display (like the iOS app).
    // In single-threaded WASM, the ccall blocks while generating all tokens
    // (callbacks fire synchronously). After it returns, we drain the token queue
    // with small delays to create a streaming visual effect.
    const { stream, result: resultPromise } = TextGeneration.generateStream(text, {
      maxTokens: 512,
      temperature: 0.7,
    });

    hideTypingIndicator();

    // Create an empty assistant bubble to stream tokens into
    const assistantMsg: ChatMessage = {
      id: crypto.randomUUID(),
      role: 'assistant',
      content: '',
      timestamp: Date.now(),
      modelId: loaded.id,
    };
    messages.push(assistantMsg);
    const { bubbleEl, rowEl } = renderStreamingBubble(assistantMsg);

    // Animate tokens appearing one by one
    for await (const token of stream) {
      assistantMsg.content += token;
      bubbleEl.innerHTML = renderMarkdown(assistantMsg.content);
      scrollToBottom();
      // Yield to the browser between tokens so each one paints
      await new Promise(r => setTimeout(r, 12));
    }

    const finalResult = await resultPromise;
    console.log(
      `[Chat] Generation complete: ${finalResult.tokensUsed} tokens in ` +
      `${finalResult.latencyMs.toFixed(0)}ms (${finalResult.tokensPerSecond.toFixed(1)} tok/s)`,
    );

    // Show metrics below the message
    appendMetrics(rowEl, {
      tokens: finalResult.tokensUsed,
      latencyMs: finalResult.latencyMs,
      tokensPerSecond: finalResult.tokensPerSecond,
    });
    scrollToBottom();

  } catch (err) {
    hideTypingIndicator();

    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('[Chat] Generation failed:', errorMessage);

    // Show error as assistant message
    const errorMsg: ChatMessage = {
      id: crypto.randomUUID(),
      role: 'assistant',
      content: `**Error:** ${errorMessage}\n\nPlease make sure a model is downloaded and loaded.`,
      timestamp: Date.now(),
      modelId: loaded.id,
    };
    messages.push(errorMsg);
    renderMessage(errorMsg);
  }

  isGenerating = false;
  sendBtn.disabled = inputEl.value.trim().length === 0;
}

// ---------------------------------------------------------------------------
// Render Messages
// ---------------------------------------------------------------------------

function renderMessage(msg: ChatMessage): void {
  const row = document.createElement('div');
  row.className = `message-row ${msg.role}`;

  let html = '';

  if (msg.role === 'assistant' && msg.thinking) {
    html += `
      <div class="thinking-section" onclick="this.classList.toggle('expanded')">
        <div class="thinking-header">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14"><path d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 1 1 7.072 0l-.548.547A3.374 3.374 0 0 0 12 18.469V19"/></svg>
          <span>Thinking...</span>
        </div>
        <div class="thinking-content">${escapeHtml(msg.thinking)}</div>
      </div>
    `;
  }

  html += `<div class="message-bubble ${msg.role}">${renderMarkdown(msg.content)}</div>`;

  row.innerHTML = html;
  messagesEl.appendChild(row);
  scrollToBottom();
}

/**
 * Create a streaming assistant bubble (starts empty, tokens appended later).
 * Returns references to the bubble and the row so we can update content and
 * append metrics after generation completes.
 */
function renderStreamingBubble(msg: ChatMessage): { bubbleEl: HTMLElement; rowEl: HTMLElement } {
  const row = document.createElement('div');
  row.className = 'message-row assistant';

  let html = '';
  if (msg.modelId) {
    const displayName = formatModelName(msg.modelId);
    html += `<div class="model-badge">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9.75 3.104v5.714a2.25 2.25 0 0 1-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.301 24.301 0 0 1 4.5 0m0 0v5.714c0 .597.237 1.17.659 1.591L19.8 15.3M14.25 3.104c.251.023.501.05.75.082M19.8 15.3l-1.57.393A9.065 9.065 0 0 1 12 15a9.065 9.065 0 0 0-6.23.693L5 14.5m14.8.8l1.402 1.402c1.232 1.232.65 3.318-1.067 3.611A48.309 48.309 0 0 1 12 21c-2.773 0-5.491-.235-8.135-.687-1.718-.293-2.3-2.379-1.067-3.61L5 14.5"/></svg>
      ${escapeHtml(displayName)}
    </div>`;
  }
  html += `<div class="message-bubble assistant" id="streaming-bubble-${msg.id}"></div>`;

  row.innerHTML = html;
  messagesEl.appendChild(row);
  scrollToBottom();

  const bubbleEl = row.querySelector<HTMLElement>(`#streaming-bubble-${msg.id}`)!;
  return { bubbleEl, rowEl: row };
}

/**
 * Append a metrics footer below a message bubble.
 */
function appendMetrics(rowEl: HTMLElement, metrics: {
  tokens: number;
  latencyMs: number;
  tokensPerSecond: number;
}): void {
  const metricsEl = document.createElement('div');
  metricsEl.className = 'message-metrics';
  metricsEl.innerHTML = `
    <span class="metric">
      <span class="metric-value">${metrics.tokensPerSecond.toFixed(1)}</span> tok/s
    </span>
    <span class="metric-separator">&middot;</span>
    <span class="metric">
      <span class="metric-value">${metrics.tokens}</span> tokens
    </span>
    <span class="metric-separator">&middot;</span>
    <span class="metric">
      <span class="metric-value">${(metrics.latencyMs / 1000).toFixed(1)}s</span>
    </span>
  `;
  rowEl.appendChild(metricsEl);
}

/**
 * Format a model ID into a shorter, display-friendly name.
 * e.g. "lfm2-350m-q4_k_m" -> "LFM2 350M"
 */
function formatModelName(modelId: string): string {
  // Try to use the loaded model's display name first
  const loaded = ModelManager.getLoadedModel();
  if (loaded && loaded.id === modelId) return loaded.name;
  // Fallback: capitalize and shorten
  return modelId
    .replace(/-q\d.*$/i, '')  // strip quantization suffix
    .replace(/-/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
}

function showTypingIndicator(): void {
  const indicator = document.createElement('div');
  indicator.className = 'message-row assistant';
  indicator.id = 'typing-indicator';
  indicator.innerHTML = `
    <div class="typing-indicator">
      <div class="typing-dots">
        <div class="typing-dot"></div>
        <div class="typing-dot"></div>
        <div class="typing-dot"></div>
      </div>
      <span class="typing-text">AI is thinking...</span>
    </div>
  `;
  messagesEl.appendChild(indicator);
  scrollToBottom();
}

function hideTypingIndicator(): void {
  const indicator = document.getElementById('typing-indicator');
  indicator?.remove();
}

function scrollToBottom(): void {
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function renderMarkdown(text: string): string {
  // Simple markdown: bold, italic, code, newlines
  return escapeHtml(text)
    .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
    .replace(/\*(.*?)\*/g, '<em>$1</em>')
    .replace(/`(.*?)`/g, '<code style="background:rgba(0,0,0,0.2);padding:1px 4px;border-radius:3px;font-family:var(--font-mono);font-size:0.85em;">$1</code>')
    .replace(/\n/g, '<br>');
}
