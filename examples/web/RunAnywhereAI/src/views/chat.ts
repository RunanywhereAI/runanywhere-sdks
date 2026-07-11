/**
 * Chat Tab — LLM chat over the V2 proto-byte LLM adapter.
 *
 * Mirrors the iOS chat experience (LLMViewModel + ChatMessageComponents):
 *   - Generation options come from the Settings tab (temperature, maxTokens,
 *     systemPrompt, thinking mode) — iOS parity: LLMViewModel.swift:579-619
 *     getGenerationOptions().
 *   - Thinking content renders as a collapsible section per assistant
 *     message — iOS parity: ChatMessageComponents.swift:87-179.
 *   - Optional tool calling with the same three demo tools as iOS
 *     (get_weather / get_current_time / calculate) — iOS parity:
 *     ToolSettingsView.swift:32-139 + LLMViewModel+ToolCalling.swift.
 *   - Conversation persists to localStorage — minimal mirror of iOS
 *     ConversationStore semantics (save on update, restore on mount).
 *
 * The toolbar model pill + "Get Started" overlay are built by
 * `components/model-selection.ts`. They expose the DOM ids the readiness
 * probe in `main.ts` looks for (`#chat-toolbar-model`, `#chat-model-overlay`,
 * `#chat-get-started-btn`).
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  ToolParameterType,
  isSDKException,
  type ToolDefinition,
  type ToolValue,
} from '@runanywhere/web';
import {
  buildGetStartedOverlay,
  onModelStateChange,
  openSheet,
  refreshModelSelectionState,
  type OpenSheetOptions,
} from '../components/model-selection';
import { showToast } from '../components/dialogs';
import { getGenerationSettings } from './settings';
import {
  answerDocumentAttachment,
  answerImageAttachment,
  canAnswerImageAttachment,
  cancelActiveDocumentAttachmentAnswer,
  cancelActiveImageAttachmentAnswer,
  validateChatAttachmentFile,
} from '../services/chat-attachments';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

interface ChatToolCallInfo {
  name: string;
  argumentsJson: string;
  resultJson?: string;
  error?: string;
}

interface ChatAttachmentInfo {
  kind: 'image' | 'document';
  name: string;
  detail?: string;
}

interface ChatSourceInfo {
  document: string;
  text: string;
}

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
  attachment?: ChatAttachmentInfo;
  /** Reasoning content shown in the collapsible "Thinking" section. */
  thinking?: string;
  /** Tool calls + results when the message came from generateWithTools. */
  toolCalls?: ChatToolCallInfo[];
  /** RAG citations for document attachments. */
  sources?: ChatSourceInfo[];
}

interface PendingAttachment {
  kind: 'image' | 'document';
  file: File;
  name: string;
  description: string;
}

type JsonObject = Readonly<Record<string, unknown>>;

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasOptionalString(value: JsonObject, key: string): boolean {
  return value[key] === undefined || typeof value[key] === 'string';
}

function isChatToolCallInfo(value: unknown): value is ChatToolCallInfo {
  return isJsonObject(value)
    && typeof value.name === 'string'
    && typeof value.argumentsJson === 'string'
    && hasOptionalString(value, 'resultJson')
    && hasOptionalString(value, 'error');
}

function isChatAttachmentInfo(value: unknown): value is ChatAttachmentInfo {
  return isJsonObject(value)
    && (value.kind === 'image' || value.kind === 'document')
    && typeof value.name === 'string'
    && hasOptionalString(value, 'detail');
}

function isChatSourceInfo(value: unknown): value is ChatSourceInfo {
  return isJsonObject(value)
    && typeof value.document === 'string'
    && typeof value.text === 'string';
}

function isChatMessage(value: unknown): value is ChatMessage {
  return isJsonObject(value)
    && (value.role === 'user' || value.role === 'assistant')
    && typeof value.content === 'string'
    && (value.attachment === undefined || isChatAttachmentInfo(value.attachment))
    && hasOptionalString(value, 'thinking')
    && (value.toolCalls === undefined
      || (Array.isArray(value.toolCalls) && value.toolCalls.every(isChatToolCallInfo)))
    && (value.sources === undefined
      || (Array.isArray(value.sources) && value.sources.every(isChatSourceInfo)));
}

// Chat's picker is scoped to LLMs — iOS parity:
// ModelSelectionSheet(context: .llm) used by the chat screen.
const CHAT_SHEET_OPTIONS: OpenSheetOptions = {
  title: 'Select Model',
  filterCategories: [ModelCategory.MODEL_CATEGORY_LANGUAGE],
};

const VLM_SHEET_OPTIONS: OpenSheetOptions = {
  title: 'Choose Image Model',
  filterCategories: [
    ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    ModelCategory.MODEL_CATEGORY_VISION,
  ],
};

const CHAT_CAPABLE_MODEL_CATEGORIES: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_LANGUAGE,
  ModelCategory.MODEL_CATEGORY_MULTIMODAL,
  ModelCategory.MODEL_CATEGORY_VISION,
];

// Minimal localStorage-backed conversation persistence — mirrors iOS
// ConversationStore (Core/Services/ConversationStore.swift) semantics at MVP
// scope: one current conversation, saved on update, restored on mount.
const CONVERSATION_STORAGE_KEY = 'runanywhere-chat-conversation';
// iOS parity: ToolSettingsView.swift:23 persists "toolCallingEnabled".
const TOOLS_ENABLED_STORAGE_KEY = 'runanywhere-tool-calling-enabled';

let container: HTMLElement;
let messages: ChatMessage[] = [];
let isGenerating = false;
let cancelGeneration: (() => void) | null = null;
let toolsEnabled = false;
let pendingAttachment: PendingAttachment | null = null;

export function initChatTab(el: HTMLElement): TabLifecycle {
  container = el;

  messages = loadConversation();
  toolsEnabled = loadToolsEnabled();

  // Register the demo tools once at chat setup — iOS parity:
  // ToolSettingsViewModel.registerDemoTools (ToolSettingsView.swift:153-159).
  registerDemoTools();

  container.classList.add('chat-panel-consumer');
  container.innerHTML = `
    <div class="scroll-area chat-scroll" id="chat-messages"></div>
    <div class="chat-composer-shell">
      <div class="composer-status-pill hidden" id="chat-attachment-pill"></div>
      <div class="composer-status-pill composer-status-pill--tools hidden" id="chat-tools-status">
        ${svgIcon('<path d="M12 2a10 10 0 0 0 0 20 10 10 0 0 0 0-20z"/><path d="M2 12h20"/><path d="M12 2c3 3.2 3 16.8 0 20"/><path d="M12 2c-3 3.2-3 16.8 0 20"/>')}
        <span><strong>Web & tools on</strong><small>Trace appears in replies</small></span>
      </div>
      <div class="chat-input-area">
        <div class="composer-menu-wrap">
          <button class="composer-icon-btn" id="chat-attach-btn" type="button" aria-label="Attach or open mode" title="Attach or open mode">
            ${svgIcon('<path d="M12 5v14"/><path d="M5 12h14"/>')}
          </button>
          <div class="composer-menu hidden" id="chat-attach-menu">
            <button type="button" data-action="document">
              ${svgIcon('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><path d="M8 13h8"/><path d="M8 17h5"/>')}
              <span><strong>Document</strong><small>Ask questions with sources</small></span>
            </button>
            <button type="button" data-action="image">
              ${svgIcon('<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="10.5" r="1.5"/><path d="M21 15l-4.5-4.5L9 18"/>')}
              <span><strong>Image</strong><small>Ask about a photo</small></span>
            </button>
            <button type="button" data-action="live">
              ${svgIcon('<rect x="5" y="2" width="14" height="20" rx="2"/><path d="M12 18h.01"/><path d="M8 6h8v9H8z"/>')}
              <span><strong>Live camera</strong><small>Look around with vision</small></span>
            </button>
          </div>
        </div>
        <button class="composer-icon-btn" id="chat-tools-btn" type="button" aria-label="Enable web and tools" title="Enable web and tools">
          ${svgIcon('<path d="M12 2a10 10 0 0 0 0 20 10 10 0 0 0 0-20z"/><path d="M2 12h20"/><path d="M12 2c3 3.2 3 16.8 0 20"/><path d="M12 2c-3 3.2-3 16.8 0 20"/>')}
        </button>
        <textarea class="chat-input" id="chat-input" placeholder="Ask anything..." rows="1"></textarea>
        <button class="composer-icon-btn" id="chat-talk-btn" type="button" aria-label="Talk mode" title="Talk mode">
          ${svgIcon('<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><path d="M12 19v3"/><path d="M8 22h8"/>')}
        </button>
        <button class="send-btn" id="chat-send-btn" disabled aria-label="Send message"></button>
      </div>
      <input type="file" id="chat-image-input" accept="image/*" hidden />
      <input type="file" id="chat-document-input" accept=".txt,.md,.json,text/plain,text/markdown,application/json" hidden />
    </div>
  `;

  // Mount the "Get Started" overlay directly inside the panel host so the
  // readiness probe's overlay visibility check works. The overlay is shown
  // whenever no model is loaded and hidden once a model enters the loaded
  // state.
  container.appendChild(buildGetStartedOverlay(
    CHAT_SHEET_OPTIONS,
    CHAT_CAPABLE_MODEL_CATEGORIES,
  ));

  const messagesEl = container.querySelector('#chat-messages') as HTMLElement;
  const inputEl = container.querySelector('#chat-input') as HTMLTextAreaElement;
  const sendBtn = container.querySelector('#chat-send-btn') as HTMLButtonElement;
  const toolsBtn = container.querySelector('#chat-tools-btn') as HTMLButtonElement;
  const toolsStatus = container.querySelector('#chat-tools-status') as HTMLElement;
  const attachBtn = container.querySelector('#chat-attach-btn') as HTMLButtonElement;
  const attachMenu = container.querySelector('#chat-attach-menu') as HTMLElement;
  const attachmentPill = container.querySelector('#chat-attachment-pill') as HTMLElement;
  const imageInput = container.querySelector('#chat-image-input') as HTMLInputElement;
  const documentInput = container.querySelector('#chat-document-input') as HTMLInputElement;
  const talkBtn = container.querySelector('#chat-talk-btn') as HTMLButtonElement;
  const listenerScope = new AbortController();
  const listenerOptions: AddEventListenerOptions = { signal: listenerScope.signal };

  const refreshToolsButton = () => {
    toolsBtn.classList.toggle('active', toolsEnabled);
    toolsStatus.classList.toggle('hidden', !toolsEnabled);
    inputEl.placeholder = toolsEnabled ? 'Ask with web and tools...' : 'Ask anything...';
    toolsBtn.setAttribute('aria-label', toolsEnabled ? 'Disable web and tools' : 'Enable web and tools');
    toolsBtn.title = toolsEnabled
      ? 'Web and tool calling enabled (weather, time, calculator)'
      : 'Enable web and tools (weather, time, calculator)';
  };

  const refreshAttachmentPill = () => {
    if (!pendingAttachment) {
      attachmentPill.classList.add('hidden');
      attachmentPill.innerHTML = '';
      return;
    }
    attachmentPill.classList.remove('hidden');
    attachmentPill.innerHTML = `
      ${svgIcon(pendingAttachment.kind === 'image'
        ? '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="10.5" r="1.5"/><path d="M21 15l-4.5-4.5L9 18"/>'
        : '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><path d="M8 13h8"/><path d="M8 17h5"/>')}
      <span><strong>${escapeHtml(pendingAttachment.name)}</strong><small>${escapeHtml(pendingAttachment.description)}</small></span>
      <button type="button" id="chat-clear-attachment" aria-label="Remove attachment">
        ${svgIcon('<path d="M18 6 6 18"/><path d="M6 6l12 12"/>')}
      </button>
    `;
    attachmentPill
      .querySelector('#chat-clear-attachment')
      ?.addEventListener('click', () => {
        pendingAttachment = null;
        refreshAttachmentPill();
        refreshSendButton();
      }, listenerOptions);
  };
  refreshToolsButton();
  refreshAttachmentPill();

  const refreshSendButton = () => {
    const hasInput = inputEl.value.trim().length > 0;
    const modelLoaded = isModelLoaded();
    const hasAttachment = pendingAttachment !== null;
    sendBtn.disabled = !isGenerating && ((!hasInput && !hasAttachment) || (!modelLoaded && !hasAttachment));
    sendBtn.innerHTML = isGenerating
      ? svgIcon('<rect x="6" y="6" width="12" height="12" rx="2"/>')
      : svgIcon('<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7z"/>');
    // Tooltip clarifies why the button is disabled. The textbox stays
    // enabled so users may compose while a model is loading.
    if (isGenerating) {
      sendBtn.title = 'Stop';
    } else if (!modelLoaded && !hasAttachment) {
      sendBtn.title = 'Load a model first';
    } else if (!hasInput && !hasAttachment) {
      sendBtn.title = 'Type a message to send';
    } else {
      sendBtn.title = 'Send';
    }
    sendBtn.setAttribute('aria-label', isGenerating ? 'Stop generation' : 'Send message');
  };

  const autoGrowInput = () => {
    inputEl.style.height = 'auto';
    inputEl.style.height = `${inputEl.scrollHeight}px`;
  };
  inputEl.addEventListener('input', () => {
    refreshSendButton();
    autoGrowInput();
  }, listenerOptions);
  // Copy action on assistant replies (delegated — the list re-renders often).
  messagesEl.addEventListener('click', (event) => {
    const button = (event.target as HTMLElement).closest<HTMLButtonElement>('[data-copy-idx]');
    if (!button) return;
    const message = messages[Number(button.dataset.copyIdx)];
    if (!message?.content) return;
    void navigator.clipboard.writeText(message.content).then(() => {
      const label = button.querySelector('span');
      if (label) {
        label.textContent = 'Copied';
        setTimeout(() => { label.textContent = 'Copy'; }, 1500);
      }
    }).catch(() => showToast('Could not copy to clipboard', 'warning', 2600));
  }, listenerOptions);
  inputEl.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      void onSend();
    }
  }, listenerOptions);
  sendBtn.addEventListener('click', () => {
    if (isGenerating) {
      cancelGeneration?.();
      return;
    }
    void onSend();
  }, listenerOptions);
  toolsBtn.addEventListener('click', () => {
    toolsEnabled = !toolsEnabled;
    saveToolsEnabled(toolsEnabled);
    refreshToolsButton();
  }, listenerOptions);
  attachBtn.addEventListener('click', (event) => {
    event.stopPropagation();
    attachMenu.classList.toggle('hidden');
  }, listenerOptions);
  attachMenu.querySelectorAll<HTMLButtonElement>('[data-action]').forEach((button) => {
    button.addEventListener('click', () => {
      attachMenu.classList.add('hidden');
      const action = button.dataset.action;
      if (action === 'document') documentInput.click();
      if (action === 'image') imageInput.click();
      if (action === 'live') navigateTo('vision');
      if (action === 'advanced') navigateTo('advanced');
    }, listenerOptions);
  });
  const closeAttachMenu = () => attachMenu.classList.add('hidden');
  document.addEventListener('click', closeAttachMenu, listenerOptions);
  imageInput.addEventListener('change', () => {
    const file = imageInput.files?.[0] ?? null;
    imageInput.value = '';
    if (!file) return;
    const error = validateChatAttachmentFile('image', file);
    if (error) {
      showToast(error, 'warning', 4200);
      return;
    }
    pendingAttachment = {
      kind: 'image',
      file,
      name: file.name || 'Selected image',
      description: 'Ask about this image',
    };
    refreshAttachmentPill();
    refreshSendButton();
  }, listenerOptions);
  documentInput.addEventListener('change', () => {
    const file = documentInput.files?.[0] ?? null;
    documentInput.value = '';
    if (!file) return;
    const error = validateChatAttachmentFile('document', file);
    if (error) {
      showToast(error, 'warning', 4200);
      return;
    }
    pendingAttachment = {
      kind: 'document',
      file,
      name: file.name || 'Selected document',
      description: 'Ask with sources from this document',
    };
    refreshAttachmentPill();
    refreshSendButton();
  }, listenerOptions);
  talkBtn.addEventListener('click', () => navigateTo('voice'), listenerOptions);
  const resetChat = () => {
    if (cancelGeneration) cancelGeneration();
    messages = [];
    pendingAttachment = null;
    clearConversation();
    renderMessages(messagesEl);
    refreshAttachmentPill();
    refreshSendButton();
  };
  window.addEventListener('runanywhere:new-chat', resetChat, listenerOptions);

  renderMessages(messagesEl);

  // Apply the initial disabled / tooltip state so the Send button reflects
  // "Load a model first" before any user interaction.
  refreshSendButton();

  // Re-render when the model state changes so disabled/enabled states stay
  // consistent with what the toolbar reports.
  const unsubscribeState = onModelStateChange(() => refreshSendButton());

  async function onSend(): Promise<void> {
    const prompt = inputEl.value.trim();
    const attachment = pendingAttachment;
    if ((!prompt && !attachment) || isGenerating) return;

    if (attachment) {
      await sendAttachment(attachment, prompt, messagesEl);
      refreshAttachmentPill();
      refreshSendButton();
      return;
    }

    if (!isLLMBackendAvailable()) {
      messages.push({
        role: 'assistant',
        content: 'No LLM backend available. Check the console for backend load errors.',
      });
      renderMessages(messagesEl);
      return;
    }

    inputEl.value = '';
    inputEl.style.height = 'auto';
    refreshSendButton();

    messages.push({ role: 'user', content: prompt });
    const assistantMsg: ChatMessage = { role: 'assistant', content: '' };
    messages.push(assistantMsg);
    saveConversation();
    renderMessages(messagesEl);

    isGenerating = true;
    refreshSendButton();

    try {
      if (toolsEnabled) {
        await generateWithToolCalling(prompt, assistantMsg, messagesEl);
      } else {
        await generateStreaming(prompt, assistantMsg, messagesEl);
      }
    } catch (error) {
      assistantMsg.content = formatChatError(error);
      renderLastMessage(messagesEl, assistantMsg);
    } finally {
      cancelGeneration = null;
      isGenerating = false;
      saveConversation();
      refreshSendButton();
      // Full re-render drops the streaming cursor and adds hover actions.
      renderMessages(messagesEl);
    }
  }

  async function sendAttachment(
    attachment: PendingAttachment,
    prompt: string,
    host: HTMLElement,
  ): Promise<void> {
    if (attachment.kind === 'image' && !canAnswerImageAttachment()) {
      openSheet(VLM_SHEET_OPTIONS);
      showToast('Load an image model first, then send the attached image.', 'info', 4200);
      return;
    }

    inputEl.value = '';
    inputEl.style.height = 'auto';
    pendingAttachment = null;
    refreshAttachmentPill();
    refreshSendButton();

    const fallbackPrompt = attachment.kind === 'image'
      ? 'Describe this image.'
      : 'What should I know from this document?';
    const question = prompt || fallbackPrompt;
    const userMessage: ChatMessage = {
      role: 'user',
      content: question,
      attachment: {
        kind: attachment.kind,
        name: attachment.name,
        detail: attachment.description,
      },
    };
    const assistantMsg: ChatMessage = { role: 'assistant', content: '' };
    messages.push(userMessage, assistantMsg);
    saveConversation();
    renderMessages(host);

    isGenerating = true;
    refreshSendButton();
    try {
      const settings = getGenerationSettings();
      const onProgress = ({ content }: { content: string }) => {
        assistantMsg.content = content;
        renderLastMessage(host, assistantMsg);
      };
      if (attachment.kind === 'image') {
        cancelGeneration = cancelActiveImageAttachmentAnswer;
        const answer = await answerImageAttachment(attachment.file, question, settings, onProgress);
        assistantMsg.content = answer.content;
        assistantMsg.thinking = answer.thinking;
        assistantMsg.sources = answer.sources;
      } else {
        cancelGeneration = cancelActiveDocumentAttachmentAnswer;
        const answer = await answerDocumentAttachment(attachment.file, question, settings, onProgress);
        assistantMsg.content = answer.content;
        assistantMsg.thinking = answer.thinking;
        assistantMsg.sources = answer.sources;
      }
      renderLastMessage(host, assistantMsg);
    } catch (error) {
      assistantMsg.content = isAbortError(error) ? 'Cancelled.' : formatChatError(error);
      renderLastMessage(host, assistantMsg);
    } finally {
      cancelGeneration = null;
      isGenerating = false;
      saveConversation();
      refreshSendButton();
      renderMessages(host);
    }
  }

  // Tear down the model-state subscription if the panel element ever
  // detaches (e.g. a full app-shell re-render). Kept minimal since the
  // tab framework does not call a dispose hook today.
  const disposeObserver = new MutationObserver(() => {
    if (!container.isConnected) {
      disposeObserver.disconnect();
      listenerScope.abort();
      unsubscribeState();
    }
  });
  const rootParent = container.parentElement;
  if (rootParent) disposeObserver.observe(rootParent, { childList: true });

  return {
    onActivate: () => {
      refreshModelSelectionState();
      refreshSendButton();
    },
    onDeactivate: () => {
      if (cancelGeneration) cancelGeneration();
    },
  };
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError';
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

/**
 * Build generation options from the Settings tab — iOS parity:
 * LLMViewModel.swift:579-619 getGenerationOptions(). `disableThinking` is the
 * same structured gate as iOS (LLMViewModel.swift:618): suppress the thinking
 * phase only when the loaded model supports thinking AND the user toggle is
 * off — commons applies the model's no-think directive; the app never injects
 * control tokens into prompts.
 */
function buildGenerationOptions(): {
  maxTokens: number;
  temperature: number;
  systemPrompt?: string;
  disableThinking: boolean;
} {
  const settings = getGenerationSettings();
  const systemPrompt = settings.systemPrompt.trim();
  return {
    maxTokens: settings.maxTokens,
    temperature: settings.temperature,
    ...(systemPrompt.length > 0 ? { systemPrompt } : {}),
    disableThinking: loadedModelSupportsThinking() && !settings.thinkingModeEnabled,
  };
}

async function generateStreaming(
  prompt: string,
  assistantMsg: ChatMessage,
  messagesEl: HTMLElement,
): Promise<void> {
  const options = buildGenerationOptions();
  const stream = await RunAnywhere.generateStream({
    prompt,
    ...options,
  });
  cancelGeneration = stream.cancel;

  let raw = '';
  for await (const token of stream.stream) {
    raw += token;
    // Thinking-capable models can stream thinking tags inline; split them
    // into the collapsible section live (iOS receives the split from
    // commons; the Web stream carries raw tokens).
    const split = splitThinking(raw);
    assistantMsg.content = split.content;
    assistantMsg.thinking = split.thinking || undefined;
    renderLastMessage(messagesEl, assistantMsg);
  }

  const result = await stream.result;
  // Prefer the structured thinkingContent from the final result when the
  // backend separates it (same field iOS reads: result.thinkingContent).
  if (result.thinkingContent) {
    assistantMsg.thinking = result.thinkingContent;
    assistantMsg.content = splitThinking(result.text || raw).content;
  }
  renderLastMessage(messagesEl, assistantMsg);
}

/**
 * Tool-calling send path — iOS parity: LLMViewModel+ToolCalling.swift:14-35.
 * The SDK (commons) orchestrates the tool call → execute → respond loop;
 * the app only renders the result.
 */
async function generateWithToolCalling(
  prompt: string,
  assistantMsg: ChatMessage,
  messagesEl: HTMLElement,
): Promise<void> {
  const options = buildGenerationOptions();
  const controller = new AbortController();
  cancelGeneration = () => controller.abort();

  const result = await RunAnywhere.generateWithTools(prompt, {}, {
    signal: controller.signal,
    llmOptions: options,
  });

  const split = splitThinking(result.text);
  assistantMsg.content = split.content;
  assistantMsg.thinking = result.thinkingContent || split.thinking || undefined;
  if (result.toolCalls.length > 0) {
    assistantMsg.toolCalls = result.toolCalls.map((call) => {
      const toolResult = result.toolResults.find(
        (r) => r.name === call.name
          && (!r.toolCallId || !call.id || r.toolCallId === call.id),
      );
      return {
        name: call.name,
        argumentsJson: call.argumentsJson,
        resultJson: toolResult?.resultJson,
        error: toolResult && !toolResult.success ? (toolResult.error || 'failed') : undefined,
      };
    });
  }
  renderLastMessage(messagesEl, assistantMsg);
}

// ---------------------------------------------------------------------------
// Demo tools — iOS parity: ToolSettingsView.swift:32-139 (weather via
// Open-Meteo, system time, safe calculator). Executors receive PARSED args
// (Record<string, ToolValue>) and return Record<string, ToolValue>.
// ---------------------------------------------------------------------------

let demoToolsRegistered = false;

function registerDemoTools(): void {
  if (demoToolsRegistered) return;
  demoToolsRegistered = true;

  RunAnywhere.toolCalling.registerTool(
    toolDefinition(
      'get_weather',
      'Gets the current weather for a given location using Open-Meteo API',
      [stringParameter('location', "City name (e.g., 'San Francisco', 'London', 'Tokyo')")],
    ),
    async (args) => fetchWeather(toolValueString(args.location) ?? 'San Francisco'),
  );

  RunAnywhere.toolCalling.registerTool(
    toolDefinition(
      'get_current_time',
      'Gets the current date, time, and timezone information',
      [],
    ),
    () => {
      const now = new Date();
      return {
        datetime: tv(now.toLocaleString(undefined, { dateStyle: 'full', timeStyle: 'medium' })),
        time: tv(now.toLocaleTimeString(undefined, { hour12: false })),
        timestamp: tv(now.toISOString()),
        timezone: tv(Intl.DateTimeFormat().resolvedOptions().timeZone),
        utc_offset: tv(`UTC${now.getTimezoneOffset() <= 0 ? '+' : '-'}${Math.abs(now.getTimezoneOffset() / 60)}`),
      };
    },
  );

  RunAnywhere.toolCalling.registerTool(
    toolDefinition(
      'calculate',
      'Performs math calculations. Supports +, -, *, /, and parentheses',
      [stringParameter('expression', "Math expression (e.g., '2 + 2 * 3', '(10 + 5) / 3')")],
    ),
    (args): Record<string, ToolValue> => {
      // iOS parity (ToolSettingsView.swift:93-137): accept the expression
      // from common alternative keys, clean unicode operators, evaluate
      // deterministically (no eval()).
      const expression = toolValueString(args.expression)
        ?? toolValueString(args.input)
        ?? toolValueString(args.expr)
        ?? '';
      if (!expression) {
        return { error: tv('Missing expression argument') };
      }
      const cleaned = expression
        .replace(/=/g, '')
        .replace(/x/gi, '*')
        .replace(/×/g, '*')
        .replace(/÷/g, '/')
        .trim();
      const value = safeMathEvaluate(cleaned);
      if (value !== null) {
        return { result: tv(value), expression: tv(expression) };
      }
      return {
        error: tv(`Could not evaluate expression: ${expression}`),
        expression: tv(expression),
      };
    },
  );
}

function toolDefinition(
  name: string,
  description: string,
  parameters: ToolDefinition['parameters'],
): ToolDefinition {
  return {
    name,
    description,
    parameters,
    category: 'Utility',
    metadata: {},
  };
}

function stringParameter(name: string, description: string): ToolDefinition['parameters'][number] {
  return {
    name,
    type: ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
    description,
    required: true,
    enumValues: [],
  };
}

function tv(value: string | number | boolean): ToolValue {
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'number') return { numberValue: value };
  return { boolValue: value };
}

function toolValueString(value: ToolValue | undefined): string | null {
  if (!value) return null;
  if (value.stringValue !== undefined) return value.stringValue;
  if (value.numberValue !== undefined) return String(value.numberValue);
  return null;
}

/**
 * Real weather lookup via Open-Meteo (free, no API key) — iOS parity:
 * WeatherService (ToolSettingsView.swift:333-443). External demo call, not
 * SDK auth/download traffic.
 */
async function fetchWeather(location: string): Promise<Record<string, ToolValue>> {
  const geoUrl = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(location)}&count=1&language=en&format=json`;
  const geoResponse = await fetch(geoUrl);
  if (!geoResponse.ok) {
    return { error: tv(`Weather location lookup failed (${geoResponse.status})`) };
  }
  const geoPayload: unknown = await geoResponse.json();
  const first = parseOpenMeteoLocation(geoPayload);
  if (!first) {
    return {
      error: tv(`Could not find location: ${location}`),
      location: tv(location),
    };
  }

  const weatherUrl = 'https://api.open-meteo.com/v1/forecast'
    + `?latitude=${first.latitude}&longitude=${first.longitude}`
    + '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m'
    + '&temperature_unit=fahrenheit&wind_speed_unit=mph';
  const weatherResponse = await fetch(weatherUrl);
  if (!weatherResponse.ok) {
    return { error: tv(`Weather forecast lookup failed (${weatherResponse.status})`) };
  }
  const weatherPayload: unknown = await weatherResponse.json();
  const current = parseOpenMeteoCurrentWeather(weatherPayload);
  if (!current) {
    return { error: tv('Could not parse weather data') };
  }

  return {
    location: tv(first.name ?? location),
    temperature: tv(current.temperature),
    unit: tv('fahrenheit'),
    humidity: tv(current.relativeHumidity),
    wind_speed_mph: tv(current.windSpeed),
    condition: tv(weatherCodeToCondition(current.weatherCode)),
  };
}

interface OpenMeteoLocation {
  latitude: number;
  longitude: number;
  name?: string;
}

interface OpenMeteoCurrentWeather {
  temperature: number;
  relativeHumidity: number;
  weatherCode: number;
  windSpeed: number;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function parseOpenMeteoLocation(payload: unknown): OpenMeteoLocation | null {
  if (!isJsonObject(payload) || !Array.isArray(payload.results)) return null;

  for (const candidate of payload.results) {
    if (
      !isJsonObject(candidate)
      || !isFiniteNumber(candidate.latitude)
      || candidate.latitude < -90
      || candidate.latitude > 90
      || !isFiniteNumber(candidate.longitude)
      || candidate.longitude < -180
      || candidate.longitude > 180
      || (candidate.name !== undefined && typeof candidate.name !== 'string')
    ) {
      continue;
    }
    return {
      latitude: candidate.latitude,
      longitude: candidate.longitude,
      ...(candidate.name !== undefined ? { name: candidate.name } : {}),
    };
  }
  return null;
}

function parseOpenMeteoCurrentWeather(payload: unknown): OpenMeteoCurrentWeather | null {
  if (!isJsonObject(payload) || !isJsonObject(payload.current)) return null;
  const current = payload.current;
  if (
    !isFiniteNumber(current.temperature_2m)
    || !isFiniteNumber(current.relative_humidity_2m)
    || current.relative_humidity_2m < 0
    || current.relative_humidity_2m > 100
    || !isFiniteNumber(current.weather_code)
    || !Number.isInteger(current.weather_code)
    || !isFiniteNumber(current.wind_speed_10m)
    || current.wind_speed_10m < 0
  ) {
    return null;
  }
  return {
    temperature: current.temperature_2m,
    relativeHumidity: current.relative_humidity_2m,
    weatherCode: current.weather_code,
    windSpeed: current.wind_speed_10m,
  };
}

/** WMO weather code → condition — iOS parity: ToolSettingsView.swift:423-442. */
function weatherCodeToCondition(code: number): string {
  if (code === 0) return 'Clear sky';
  if (code === 1) return 'Mainly clear';
  if (code === 2) return 'Partly cloudy';
  if (code === 3) return 'Overcast';
  if (code === 45 || code === 48) return 'Foggy';
  if (code >= 51 && code <= 55) return 'Drizzle';
  if (code === 56 || code === 57) return 'Freezing drizzle';
  if (code === 61 || code === 63 || code === 65) return 'Rain';
  if (code === 66 || code === 67) return 'Freezing rain';
  if (code === 71 || code === 73 || code === 75) return 'Snow';
  if (code === 77) return 'Snow grains';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code === 85 || code === 86) return 'Snow showers';
  if (code === 95) return 'Thunderstorm';
  if (code === 96 || code === 99) return 'Thunderstorm with hail';
  return 'Unknown';
}

// ---------------------------------------------------------------------------
// Safe math evaluator — iOS parity: SafeMathEvaluator
// (ToolSettingsView.swift:455-570). Deterministic recursive-descent parser;
// never uses eval(). Grammar: expr := term (("+"|"-") term)*;
// term := factor (("*"|"/") factor)*; factor := ("+"|"-") factor | primary;
// primary := number | "(" expr ")".
// ---------------------------------------------------------------------------

function safeMathEvaluate(expression: string): number | null {
  let index = 0;

  const skipWhitespace = (): void => {
    while (index < expression.length && /\s/.test(expression[index])) index += 1;
  };
  const peek = (): string | null => {
    skipWhitespace();
    return index < expression.length ? expression[index] : null;
  };
  const match = (char: string): boolean => {
    if (peek() === char) {
      index += 1;
      return true;
    }
    return false;
  };

  const parseNumber = (): number | null => {
    skipWhitespace();
    const start = index;
    let seenDot = false;
    while (index < expression.length) {
      const char = expression[index];
      if (/\d/.test(char)) {
        index += 1;
      } else if (char === '.' && !seenDot) {
        seenDot = true;
        index += 1;
      } else {
        break;
      }
    }
    if (index === start) return null;
    const value = Number(expression.slice(start, index));
    return Number.isFinite(value) ? value : null;
  };

  const parsePrimary = (): number | null => {
    if (match('(')) {
      const value = parseExpression();
      if (value === null || !match(')')) return null;
      return value;
    }
    return parseNumber();
  };

  const parseFactor = (): number | null => {
    if (match('+')) return parseFactor();
    if (match('-')) {
      const value = parseFactor();
      return value === null ? null : -value;
    }
    return parsePrimary();
  };

  const parseTerm = (): number | null => {
    let value = parseFactor();
    if (value === null) return null;
    for (let op = peek(); op === '*' || op === '/'; op = peek()) {
      index += 1;
      const rhs = parseFactor();
      if (rhs === null) return null;
      if (op === '/') {
        if (rhs === 0) return null;
        value /= rhs;
      } else {
        value *= rhs;
      }
    }
    return value;
  };

  const parseExpression = (): number | null => {
    let value = parseTerm();
    if (value === null) return null;
    for (let op = peek(); op === '+' || op === '-'; op = peek()) {
      index += 1;
      const rhs = parseTerm();
      if (rhs === null) return null;
      value = op === '+' ? value + rhs : value - rhs;
    }
    return value;
  };

  const result = parseExpression();
  skipWhitespace();
  if (result === null || index < expression.length || !Number.isFinite(result)) {
    return null;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Conversation persistence (localStorage; mirrors iOS ConversationStore at
// MVP scope — Core/Services/ConversationStore.swift)
// ---------------------------------------------------------------------------

function loadConversation(): ChatMessage[] {
  try {
    const saved = localStorage.getItem(CONVERSATION_STORAGE_KEY);
    if (!saved) return [];
    const parsed: unknown = JSON.parse(saved);
    if (!isJsonObject(parsed) || !Array.isArray(parsed.messages)) return [];
    return parsed.messages.filter(isChatMessage);
  } catch {
    return [];
  }
}

function saveConversation(): void {
  try {
    localStorage.setItem(
      CONVERSATION_STORAGE_KEY,
      JSON.stringify({ messages, updatedAt: Date.now() }),
    );
  } catch { /* storage may not be available */ }
  window.dispatchEvent(new CustomEvent('runanywhere:conversation-updated'));
}

function clearConversation(): void {
  try {
    localStorage.removeItem(CONVERSATION_STORAGE_KEY);
  } catch { /* storage may not be available */ }
  window.dispatchEvent(new CustomEvent('runanywhere:conversation-updated'));
}

function loadToolsEnabled(): boolean {
  try {
    return localStorage.getItem(TOOLS_ENABLED_STORAGE_KEY) === 'true';
  } catch {
    return false;
  }
}

function saveToolsEnabled(enabled: boolean): void {
  try {
    localStorage.setItem(TOOLS_ENABLED_STORAGE_KEY, String(enabled));
  } catch { /* storage may not be available */ }
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

function navigateTo(tab: string): void {
  window.dispatchEvent(new CustomEvent('runanywhere:navigate', { detail: { tab } }));
}

function svgIcon(paths: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${paths}</svg>`;
}

/**
 * True when the C++ lifecycle reports an LLM loaded. Used to gate the chat
 * Send button so users can't click into a silent no-op before loading a
 * model from the toolbar picker.
 */
function isModelLoaded(): boolean {
  try {
    const current = RunAnywhere.currentModel({
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      includeModelMetadata: false,
    });
    return Boolean(current?.modelId);
  } catch {
    return false;
  }
}

/**
 * Whether the loaded LLM supports a thinking phase — read from the registry
 * record, same source iOS uses (LLMViewModel `loadedModelSupportsThinking`).
 */
function loadedModelSupportsThinking(): boolean {
  try {
    const current = RunAnywhere.currentModel({
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      includeModelMetadata: false,
    });
    if (!current?.modelId) return false;
    return RunAnywhere.getModel(current.modelId)?.supportsThinking ?? false;
  } catch {
    return false;
  }
}

/**
 * Split built-in thinking sections out of raw model text. Handles an
 * unterminated tag while tokens are still streaming. iOS receives the
 * split from commons (result.thinkingContent); the Web stream carries raw
 * tokens, so the view performs the same tag split client-side.
 */
function splitThinking(raw: string): { content: string; thinking: string } {
  const thinkingParts: string[] = [];
  const content = raw.replace(
    /<(think|thinking)>([\s\S]*?)(<\/\1>|$)/gi,
    (_match, _tag: string, inner: string) => {
      if (inner.trim().length > 0) thinkingParts.push(inner.trim());
      return '';
    },
  );
  return { content: content.trim(), thinking: thinkingParts.join('\n\n') };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function greeting(): string {
  const hour = new Date().getHours();
  if (hour < 5) return 'Working late?';
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

const STARTER_PROMPTS: Array<{ label: string; prompt: string; icon: string }> = [
  {
    label: 'Draft a message',
    prompt: 'Help me draft a short, friendly message to my team about shipping our next release this Friday.',
    icon: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
  },
  {
    label: 'Explain a topic',
    prompt: 'Explain how on-device AI keeps my data private, in simple terms.',
    icon: '<circle cx="12" cy="12" r="10"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3"/><path d="M12 17h.01"/>',
  },
  {
    label: 'Compare options',
    prompt: 'Help me compare two small local models for private chat.',
    icon: '<path d="M16 3h5v5"/><path d="M8 3H3v5"/><path d="M21 3l-7 7"/><path d="M3 3l7 7"/><path d="M16 21h5v-5"/><path d="M8 21H3v-5"/><path d="M21 21l-7-7"/><path d="M3 21l7-7"/>',
  },
  {
    label: 'Make a checklist',
    prompt: 'Draft a concise checklist for testing an on-device AI app.',
    icon: '<path d="M3 17l2 2 4-4"/><path d="M3 7l2 2 4-4"/><path d="M13 6h8"/><path d="M13 12h8"/><path d="M13 18h8"/>',
  },
];

function renderMessages(host: HTMLElement): void {
  if (messages.length === 0) {
    host.innerHTML = `
      <div class="chat-empty-state">
        <div class="empty-logo">${svgIcon('<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3z"/><path d="M5 3l.8 2.2L8 6l-2.2.8L5 9l-.8-2.2L2 6l2.2-.8L5 3z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8L19 15z"/>')}</div>
        <h3>${greeting()}</h3>
        <p>Ask anything — everything runs privately on this device.</p>
        <div class="suggestion-chips">
          ${STARTER_PROMPTS.map((starter) => `
            <button type="button" class="suggestion-chip" data-prompt="${escapeHtml(starter.prompt)}">
              ${svgIcon(starter.icon)}
              <span>${starter.label}</span>
            </button>
          `).join('')}
        </div>
      </div>
    `;
    host.querySelectorAll<HTMLButtonElement>('[data-prompt]').forEach((button) => {
      button.addEventListener('click', () => {
        const input = container.querySelector<HTMLTextAreaElement>('#chat-input');
        if (!input) return;
        input.value = button.dataset.prompt ?? '';
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.focus();
      });
    });
    return;
  }

  host.innerHTML = messages.map((msg, idx) => `
    <div class="chat-message chat-message--${msg.role}" data-idx="${idx}">
      ${renderMessageBody(msg)}
      ${renderMessageActions(msg, idx)}
    </div>
  `).join('');

  host.scrollTop = host.scrollHeight;
}

function renderMessageActions(msg: ChatMessage, idx: number): string {
  if (msg.role !== 'assistant' || !msg.content) return '';
  return `
    <div class="chat-msg-actions">
      <button type="button" class="chat-action-btn" data-copy-idx="${idx}" aria-label="Copy reply">
        ${svgIcon('<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>')}
        <span>Copy</span>
      </button>
    </div>
  `;
}

function renderLastMessage(host: HTMLElement, msg: ChatMessage): void {
  const last = host.lastElementChild;
  if (last) {
    last.innerHTML = renderMessageBody(msg, isGenerating);
  }
  host.scrollTop = host.scrollHeight;
}

function renderMessageBody(msg: ChatMessage, streaming = false): string {
  // Collapsible thinking section — iOS parity:
  // ChatMessageComponents.swift:128-181 (thinkingSection).
  const thinking = msg.thinking?.trim();
  const thinkingSection = msg.role === 'assistant' && thinking
    ? `
      <details class="chat-thinking">
        <summary>Thinking</summary>
        <pre class="chat-thinking-content">${escapeHtml(thinking)}</pre>
      </details>
    `
    : '';

  const toolSection = msg.role === 'assistant' && msg.toolCalls?.length
    ? `
      <div class="chat-tool-stack">
        ${msg.toolCalls.map((call) => `
          <details class="chat-tool-call">
            <summary>
              ${svgIcon(call.error
                ? '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4"/><path d="M12 17h.01"/>'
                : '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.8-3.8a6 6 0 0 1-7.9 7.9l-6.9 6.9a2.1 2.1 0 0 1-3-3l6.9-6.9a6 6 0 0 1 7.9-7.9l-3.8 3.8z"/>')}
              <span>${escapeHtml(call.name)}</span>
              <small>${call.error ? 'failed' : 'completed'}</small>
            </summary>
            <pre>Args: ${escapeHtml(call.argumentsJson || '{}')}${call.resultJson ? `\nResult: ${escapeHtml(call.resultJson)}` : ''}${call.error ? `\nError: ${escapeHtml(call.error)}` : ''}</pre>
          </details>
        `).join('')}
      </div>
    `
    : '';

  const attachmentSection = msg.attachment
    ? `
      <div class="chat-attachment-card chat-attachment-card--${msg.attachment.kind}">
        ${svgIcon(msg.attachment.kind === 'image'
          ? '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="10.5" r="1.5"/><path d="M21 15l-4.5-4.5L9 18"/>'
          : '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><path d="M8 13h8"/><path d="M8 17h5"/>')}
        <span><strong>${escapeHtml(msg.attachment.name)}</strong><small>${escapeHtml(msg.attachment.detail ?? '')}</small></span>
      </div>
    `
    : '';

  const sourcesSection = msg.role === 'assistant' && msg.sources?.length
    ? `
      <div class="chat-source-strip">
        <span class="chat-source-strip__label">Sources</span>
        ${msg.sources.slice(0, 3).map((source, index) => `
          <div class="chat-source">
            <strong>${index + 1}. ${escapeHtml(source.document || 'Document')}</strong>
            <span>${escapeHtml(source.text.slice(0, 180))}${source.text.length > 180 ? '...' : ''}</span>
          </div>
        `).join('')}
      </div>
    `
    : '';

  const cursor = streaming && msg.role === 'assistant'
    ? '<span class="chat-cursor" aria-hidden="true"></span>'
    : '';
  const body = msg.content
    ? renderMarkdownLite(msg.content) + cursor
    : (thinking
      ? `<span class="chat-bubble-typing">Thinking&hellip;</span>${cursor}`
      : cursor || '<span class="chat-bubble-typing">&hellip;</span>');

  return `${thinkingSection}${toolSection}<div class="chat-bubble">${attachmentSection}${body}${sourcesSection}</div>`;
}

/**
 * Minimal markdown rendering on top of escapeHtml (kept dependency-free):
 * fenced code blocks, inline code, and bold. Everything passes through
 * escapeHtml first, so model output can never inject markup.
 */
function renderMarkdownLite(text: string): string {
  const codeBlocks: string[] = [];
  const escaped = escapeHtml(text);
  // Fenced code blocks (tolerates an unterminated fence while streaming).
  let html = escaped.replace(/```[^\n`]*\n?([\s\S]*?)(?:```|$)/g, (_match, code: string) => {
    codeBlocks.push(`<pre class="chat-code"><code>${code.replace(/\n$/, '')}</code></pre>`);
    return `\uE000${codeBlocks.length - 1}\uE000`;
  });
  html = html
    .replace(/`([^`\n]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\n/g, '<br>');
  return html.replace(/\uE000(\d+)\uE000/g, (_match, i: string) => codeBlocks[Number(i)]);
}

function formatChatError(error: unknown): string {
  if (isSDKException(error)) {
    return `Error: ${error.message}`;
  }
  return `Error: ${formatError(error)}`;
}
