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
 *   - IndexedDB conversation history mirrors the iOS ConversationStore:
 *     save on update, restore on mount, and switch between prior chats.
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
  type ChatMessage as SDKChatMessage,
  type GenerationResult,
  type LlmOptions,
  type ToolDefinition,
} from '@runanywhere/web';
import type { ToolValue } from '@runanywhere/proto-ts/tool_calling';
import {
  buildGetStartedOverlay,
  syncMountedOverlayState,
  setOverlaySuppressed,
  findLoadedModelForCategory,
  onModelStateChange,
  openSheet,
  refreshModelSelectionState,
  type OpenSheetOptions,
} from '../components/model-selection';
import { showToast } from '../components/dialogs';
import { icon, type IconName } from '../components/icons';
import { getGenerationSettings, setThinkingModeEnabled } from './settings';
import {
  answerDocumentAttachment,
  answerImageAttachment,
  canAnswerDocumentAttachment,
  canAnswerImageAttachment,
  cancelActiveDocumentAttachmentAnswer,
  cancelActiveImageAttachmentAnswer,
  imageAttachmentThumbnail,
  kindForFile,
  validateChatAttachmentFile,
  type ChatAttachmentAnswer,
} from '../services/chat-attachments';
import { escapeHtml } from '../services/escape-html';
import { renderMarkdown } from '../services/markdown';
import { formatError } from '../services/format-error';
import {
  ConversationsStore,
  type StoredConversation,
} from '../services/conversations-store';
import { appLogger } from '../services/app-logger';

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
  /**
   * A thumbnail-sized JPEG data URL of an image attachment.
   *
   * An image turn that shows only a filename and a picture glyph asks the reader
   * to remember which photo they sent — iOS keeps the image itself on the turn
   * (LLMViewModel+Vision.swift:75-92 persists the attachment bytes). Stored at
   * 96 px so a conversation full of photos stays a few kilobytes per turn in
   * IndexedDB rather than a few megabytes.
   */
  thumbnailDataUrl?: string;
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
  /**
   * This turn is a failure report, not something the model said.
   *
   * Mirrors iOS `Message.isError`. Without it a failed turn was an ordinary assistant
   * bubble — same ink, run through the markdown renderer — and
   * `conversationHistoryForGeneration` filtered only on blank content, so the next
   * request told the model it had previously said "Error: …". Persisted with the turn
   * because the conversation is reloaded from IndexedDB, and a reload must not
   * resurrect the error into history.
   */
  isError?: boolean;
}

interface ConversationGenerationContext {
  history: SDKChatMessage[];
  conversationId?: string;
}

interface PendingAttachment {
  kind: 'image' | 'document';
  file: File;
  name: string;
  description: string;
  /** Filled in asynchronously for images; see `ChatAttachmentInfo`. */
  thumbnailDataUrl?: string;
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
    && hasOptionalString(value, 'detail')
    // Restored straight into an `<img src>`, so a stored value that is not a
    // data URL never reaches the DOM — the database is app-owned but it is still
    // persisted, origin-scoped input.
    && (value.thumbnailDataUrl === undefined
      || (typeof value.thumbnailDataUrl === 'string'
        && value.thumbnailDataUrl.startsWith('data:image/')));
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
      || (Array.isArray(value.sources) && value.sources.every(isChatSourceInfo)))
    && (value.isError === undefined || typeof value.isError === 'boolean');
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

/**
 * A grounded file answer needs both halves of the pipeline, so the picker it
 * opens shows both — the same move the image branch already made, rather than
 * failing the send with the SDK's "model is not downloaded" sentence.
 */
const DOCUMENT_SHEET_OPTIONS: OpenSheetOptions = {
  title: 'Choose Document Models',
  filterCategories: [
    ModelCategory.MODEL_CATEGORY_EMBEDDING,
    ModelCategory.MODEL_CATEGORY_LANGUAGE,
  ],
};

const CHAT_CAPABLE_MODEL_CATEGORIES: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_LANGUAGE,
  ModelCategory.MODEL_CATEGORY_MULTIMODAL,
  ModelCategory.MODEL_CATEGORY_VISION,
];

// iOS parity: ToolSettingsView.swift:23 persists "toolCallingEnabled".
const TOOLS_ENABLED_STORAGE_KEY = 'runanywhere-tool-calling-enabled';

let container: HTMLElement;
let messages: ChatMessage[] = [];
let isGenerating = false;
let cancelGeneration: (() => void) | null = null;
let toolsEnabled = false;
let pendingAttachment: PendingAttachment | null = null;
let conversationStorageWarningShown = false;

export function initChatTab(el: HTMLElement): TabLifecycle {
  container = el;

  messages = [];
  toolsEnabled = loadToolsEnabled();
  // Module state outlives a panel rebuild. Without this, remounting the tab
  // re-showed the pill for a File the previous composer had staged.
  pendingAttachment = null;

  // Register the demo tools once at chat setup — iOS parity:
  // ToolSettingsViewModel.registerDemoTools (ToolSettingsView.swift:153-159).
  registerDemoTools();

  container.classList.add('chat-panel-consumer');
  container.innerHTML = `
    <div class="scroll-area chat-scroll" id="chat-messages"></div>
    <div class="chat-composer-shell">
      <div class="composer-status-pill hidden" id="chat-attachment-pill"></div>
      <div class="composer-status-pill composer-status-pill--tools hidden" id="chat-tools-status">
        ${icon('globe')}
        <span><strong>Web & tools on</strong><small>Trace appears in replies</small></span>
      </div>
      <div class="chat-input-area">
        <div class="composer-menu-wrap">
          <button class="composer-icon-btn" id="chat-attach-btn" type="button"
            aria-label="Attach a file or open live camera" title="Attach a file or open live camera"
            aria-haspopup="menu" aria-expanded="false" aria-controls="chat-attach-menu">
            ${icon('plus')}
          </button>
          <div class="composer-menu hidden" id="chat-attach-menu" role="menu">
            <button type="button" role="menuitem" data-action="document">
              ${icon('file')}
              <span><strong>Document</strong><small>Ask questions with sources</small></span>
            </button>
            <button type="button" role="menuitem" data-action="image">
              ${icon('image')}
              <span><strong>Image</strong><small>Ask about a photo</small></span>
            </button>
            <button type="button" role="menuitem" data-action="live">
              ${icon('eye')}
              <span><strong>Live camera</strong><small>Look around with vision</small></span>
            </button>
          </div>
        </div>
        <button class="composer-icon-btn" id="chat-tools-btn" type="button" aria-label="Enable web and tools" title="Enable web and tools">
          ${icon('globe')}
        </button>
        <!-- Reasoning lives in the composer, next to web-and-tools, because it
             changes what the NEXT turn does — the same place and the same brain
             glyph Android's composer uses. It used to exist only as a switch in
             the Settings tab, so a browser reader had to leave the conversation
             to change how the reply would be produced, and had no way to see
             from here whether reasoning was on. -->
        <button class="composer-icon-btn" id="chat-thinking-btn" type="button" aria-label="Enable reasoning" title="Enable reasoning">
          ${icon('brain')}
        </button>
        <textarea class="chat-input" id="chat-input" placeholder="Ask anything..." rows="1"></textarea>
        <button class="composer-icon-btn" id="chat-talk-btn" type="button" aria-label="Talk" title="Talk">
          ${icon('mic')}
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
  const getStartedOverlay = buildGetStartedOverlay(
    CHAT_SHEET_OPTIONS,
    CHAT_CAPABLE_MODEL_CATEGORIES,
  );
  const messagesEl = container.querySelector('#chat-messages') as HTMLElement;
  // Inserted where the scroll region sits in the flex column, not appended after
  // the composer: the card takes that region's place instead of covering the
  // panel, so the composer below it stays visible rather than being hidden
  // behind an opaque layer while remaining focusable.
  container.insertBefore(getStartedOverlay, messagesEl.nextSibling);
  // Only now can the overlay set state on its parent — see
  // syncMountedOverlayState. Without this the panel's empty state is hidden a
  // frame late and the overlay doubles in height after paint.
  syncMountedOverlayState();

  const inputEl = container.querySelector('#chat-input') as HTMLTextAreaElement;
  const sendBtn = container.querySelector('#chat-send-btn') as HTMLButtonElement;
  const toolsBtn = container.querySelector('#chat-tools-btn') as HTMLButtonElement;
  const toolsStatus = container.querySelector('#chat-tools-status') as HTMLElement;
  const thinkingBtn = container.querySelector('#chat-thinking-btn') as HTMLButtonElement;
  const attachBtn = container.querySelector('#chat-attach-btn') as HTMLButtonElement;
  const attachMenu = container.querySelector('#chat-attach-menu') as HTMLElement;
  const attachmentPill = container.querySelector('#chat-attachment-pill') as HTMLElement;
  const imageInput = container.querySelector('#chat-image-input') as HTMLInputElement;
  const documentInput = container.querySelector('#chat-document-input') as HTMLInputElement;
  const talkBtn = container.querySelector('#chat-talk-btn') as HTMLButtonElement;
  const listenerScope = new AbortController();
  const listenerOptions: AddEventListenerOptions = { signal: listenerScope.signal };
  let pendingConversationAction: (() => Promise<void>) | null = null;
  let conversationActionVersion = 0;
  let conversationHydrated = false;
  let conversationHydration: Promise<void> = Promise.resolve();

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
      ${attachmentGlyph(pendingAttachment.kind, pendingAttachment.thumbnailDataUrl)}
      <span><strong>${escapeHtml(pendingAttachment.name)}</strong><small>${escapeHtml(pendingAttachment.description)}</small></span>
      <button type="button" id="chat-clear-attachment" aria-label="Remove ${escapeHtml(pendingAttachment.name)}">
        ${icon('close')}
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
  /**
   * The reasoning toggle's three honest states.
   *
   * A model with no thinking phase cannot be made to reason, so the control is
   * disabled and says why rather than offering a switch that would change nothing —
   * the same rule Android's composer applies via `thinkingSupported`.
   */
  const refreshThinkingButton = () => {
    const supported = loadedModelSupportsThinking();
    const on = supported && getGenerationSettings().thinkingModeEnabled;
    thinkingBtn.disabled = !supported;
    thinkingBtn.classList.toggle('active', on);
    const label = !supported
      ? 'Reasoning not supported by this model'
      : on ? 'Disable reasoning' : 'Enable reasoning';
    thinkingBtn.setAttribute('aria-label', label);
    thinkingBtn.setAttribute('aria-pressed', on ? 'true' : 'false');
    thinkingBtn.title = label;
  };
  refreshToolsButton();
  refreshThinkingButton();
  refreshAttachmentPill();

  const refreshSendButton = () => {
    // Reasoning availability depends on the loaded model, and this runs on every
    // model-state change (see `onModelStateChange` below), so the toggle follows.
    refreshThinkingButton();
    const hasInput = inputEl.value.trim().length > 0;
    const modelLoaded = isModelLoaded();
    const hasAttachment = pendingAttachment !== null;
    sendBtn.disabled = !conversationHydrated
      || (!isGenerating && ((!hasInput && !hasAttachment) || (!modelLoaded && !hasAttachment)));
    sendBtn.innerHTML = isGenerating
      ? icon('stop')
      : icon('send');
    // Tooltip clarifies why the button is disabled. The textbox stays
    // enabled so users may compose while a model is loading.
    if (!conversationHydrated) {
      sendBtn.title = 'Loading saved chats';
    } else if (isGenerating) {
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
  // Copy a fenced code block. Delegated for the same reason as the reply copy
  // above — every streamed token re-renders the bubble, so a listener bound to
  // the button itself would be discarded on the next token. The code rides in
  // the attribute rather than being read from the DOM so what lands on the
  // clipboard is exactly what the model wrote.
  messagesEl.addEventListener('click', (event) => {
    const button = (event.target as HTMLElement).closest<HTMLButtonElement>('[data-md-code]');
    if (!button) return;
    const code = button.dataset.mdCode;
    if (!code) return;
    void navigator.clipboard.writeText(code).then(() => {
      button.textContent = 'Copied';
      setTimeout(() => { button.textContent = 'Copy'; }, 1500);
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
  thinkingBtn.addEventListener('click', () => {
    // Writes through to the one persisted setting the Settings tab also edits, so
    // the two controls can never disagree about whether reasoning is on.
    setThinkingModeEnabled(!getGenerationSettings().thinkingModeEnabled);
    refreshThinkingButton();
  }, listenerOptions);
  // `aria-expanded` is the only thing that tells a screen-reader user the menu
  // opened at all — the visual state is a class that flips `display`, which is
  // silent. Kept in one place so the flag cannot drift from the class.
  const setAttachMenuOpen = (open: boolean) => {
    attachMenu.classList.toggle('hidden', !open);
    attachBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
  };
  const closeAttachMenu = () => setAttachMenuOpen(false);
  attachBtn.addEventListener('click', (event) => {
    event.stopPropagation();
    setAttachMenuOpen(attachMenu.classList.contains('hidden'));
  }, listenerOptions);
  attachMenu.querySelectorAll<HTMLButtonElement>('[data-action]').forEach((button) => {
    button.addEventListener('click', () => {
      closeAttachMenu();
      const action = button.dataset.action;
      if (action === 'document') documentInput.click();
      if (action === 'image') imageInput.click();
      if (action === 'live') navigateTo('vision');
      if (action === 'advanced') navigateTo('advanced');
    }, listenerOptions);
  });
  document.addEventListener('click', closeAttachMenu, listenerOptions);
  // Escape is how every other dismissible surface in this app closes; a menu
  // that only closes on an outside click strands a keyboard user inside it.
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || attachMenu.classList.contains('hidden')) return;
    closeAttachMenu();
    attachBtn.focus();
  }, listenerOptions);
  /**
   * Validate one file and stage it as the pending attachment.
   *
   * The single funnel for all four ways a file can arrive — the image picker,
   * the document picker, a drop on the composer, and a paste. Sharing it is what
   * guarantees a dropped file is checked exactly as strictly as a picked one; the
   * `accept` attribute only constrains the pickers, and drop and paste never
   * consult it.
   */
  const stageAttachment = (kind: 'image' | 'document', file: File): boolean => {
    const error = validateChatAttachmentFile(kind, file);
    if (error) {
      showToast(error, 'warning', 4200);
      return false;
    }
    const staged: PendingAttachment = kind === 'image'
      ? {
        kind: 'image',
        file,
        name: file.name || 'Selected image',
        description: 'Ask about this image',
      }
      : {
        kind: 'document',
        file,
        name: file.name || 'Selected document',
        description: 'Ask with sources from this document',
      };
    pendingAttachment = staged;
    refreshAttachmentPill();
    refreshSendButton();
    if (kind === 'image') {
      // Decoding is async, so the pill appears immediately with its glyph and
      // gains the picture a moment later rather than making the reader wait for
      // a canvas round-trip before the composer responds at all.
      void imageAttachmentThumbnail(file).then((thumbnailDataUrl) => {
        if (!thumbnailDataUrl || pendingAttachment !== staged) return;
        staged.thumbnailDataUrl = thumbnailDataUrl;
        refreshAttachmentPill();
      });
    }
    return true;
  };

  imageInput.addEventListener('change', () => {
    const file = imageInput.files?.[0] ?? null;
    imageInput.value = '';
    if (file) stageAttachment('image', file);
  }, listenerOptions);
  documentInput.addEventListener('change', () => {
    const file = documentInput.files?.[0] ?? null;
    documentInput.value = '';
    if (file) stageAttachment('document', file);
  }, listenerOptions);

  /**
   * Accept a file the user dropped or pasted, choosing the mode from the file.
   *
   * Dropping an image on a chat box and pasting a screenshot are both things a
   * user simply expects to work — Documents already accepted drops and pastes,
   * so the composer not accepting them was an inconsistency inside one app as
   * well as across the four. `kindForFile` decides the mode, and an unsupported
   * file says so rather than being silently ignored, which is indistinguishable
   * from the feature being broken.
   */
  const acceptDroppedFile = (file: File): void => {
    const kind = kindForFile(file);
    if (!kind) {
      showToast(
        `${file.name || 'That file'} is not supported. Attach an image or a .txt, .md, or .json file.`,
        'warning',
        4200,
      );
      return;
    }
    if (stageAttachment(kind, file)) inputEl.focus();
  };

  const composerShell = container.querySelector('.chat-composer-shell') as HTMLElement;
  // `dragover` must be cancelled or the browser navigates away to the dropped
  // file, discarding the conversation.
  composerShell.addEventListener('dragover', (event) => {
    if (!event.dataTransfer?.types.includes('Files')) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
    composerShell.classList.add('chat-composer-shell--dropping');
  }, listenerOptions);
  // `dragleave` fires when crossing between child elements too, so the target
  // check keeps the highlight from flickering as the pointer moves inside.
  composerShell.addEventListener('dragleave', (event) => {
    if (event.target === composerShell) {
      composerShell.classList.remove('chat-composer-shell--dropping');
    }
  }, listenerOptions);
  composerShell.addEventListener('drop', (event) => {
    if (!event.dataTransfer?.files.length) return;
    event.preventDefault();
    composerShell.classList.remove('chat-composer-shell--dropping');
    acceptDroppedFile(event.dataTransfer.files[0]);
  }, listenerOptions);
  inputEl.addEventListener('paste', (event) => {
    const items = event.clipboardData?.items;
    if (!items) return;
    for (const item of items) {
      if (item.kind !== 'file') continue;
      const file = item.getAsFile();
      if (!file) continue;
      // Only claim the paste once a file is actually found, so pasting ordinary
      // text still lands in the textarea as normal.
      event.preventDefault();
      acceptDroppedFile(file);
      return;
    }
  }, listenerOptions);
  talkBtn.addEventListener('click', () => navigateTo('voice'), listenerOptions);
  /**
   * Show a different conversation.
   *
   * `clearComposer` is false for exactly one caller: the initial restore from
   * IndexedDB. Restoring is not switching — the reader did not ask for it and
   * may already be typing or have staged a file while it was in flight, and this
   * function used to wipe both, so a message composed in the first second after
   * opening chat silently vanished.
   */
  const showConversation = (nextMessages: ChatMessage[], clearComposer = true) => {
    messages = nextMessages;
    setOverlaySuppressed(conversationSuppressesModelOverlay(nextMessages));
    if (clearComposer) {
      inputEl.value = '';
      inputEl.style.height = 'auto';
      pendingAttachment = null;
    }
    renderMessages(messagesEl);
    refreshAttachmentPill();
    refreshSendButton();
  };
  const reportConversationStorageError = (error: unknown) => {
    if (!conversationStorageWarningShown) {
      conversationStorageWarningShown = true;
      showToast('Saved chats are unavailable in this browser session.', 'warning', 4200);
    }
    appLogger.warning('[Chat] Conversation storage operation failed:', error);
  };
  const runConversationAction = (action: () => Promise<void>) => {
    conversationActionVersion += 1;
    if (isGenerating) {
      pendingConversationAction = action;
      cancelGeneration?.();
      return;
    }
    void action().catch(reportConversationStorageError);
  };
  const runPendingConversationAction = () => {
    const action = pendingConversationAction;
    pendingConversationAction = null;
    if (action) void action().catch(reportConversationStorageError);
  };
  const resetChat = () => runConversationAction(async () => {
    await ConversationsStore.startNew();
    showConversation([]);
  });
  const restoreSavedChat = (event: Event) => {
    const conversationId = (event as CustomEvent<{ conversationId?: string }>).detail?.conversationId;
    if (!conversationId) return;
    runConversationAction(async () => {
      const conversation = await ConversationsStore.setCurrent(conversationId);
      if (!conversation) {
        showToast('That saved chat is no longer available.', 'warning', 3200);
        return;
      }
      showConversation(conversation.messages.filter(isChatMessage));
    });
  };
  const deleteSavedChat = (event: Event) => {
    const conversationId = (event as CustomEvent<{ conversationId?: string }>).detail?.conversationId;
    if (!conversationId) return;
    void ConversationsStore.getCurrent().then((current) => {
      if (current?.id !== conversationId) {
        return ConversationsStore.delete(conversationId).then(() => undefined);
      }
      runConversationAction(async () => {
        await ConversationsStore.delete(conversationId);
        showConversation([]);
      });
      return undefined;
    }).catch(reportConversationStorageError);
  };
  window.addEventListener('runanywhere:new-chat', resetChat, listenerOptions);
  window.addEventListener('runanywhere:load-chat', restoreSavedChat, listenerOptions);
  window.addEventListener('runanywhere:delete-chat', deleteSavedChat, listenerOptions);

  renderMessages(messagesEl);
  const initialConversationVersion = conversationActionVersion;
  conversationHydration = loadConversation().then((savedMessages) => {
    if (conversationActionVersion === initialConversationVersion) {
      showConversation(savedMessages, false);
    }
  }).catch(reportConversationStorageError).finally(() => {
    conversationHydrated = true;
    refreshSendButton();
  });

  // Apply the initial disabled / tooltip state so the Send button reflects
  // "Load a model first" before any user interaction.
  refreshSendButton();

  // Re-render when the model state changes so disabled/enabled states stay
  // consistent with what the toolbar reports.
  const unsubscribeState = onModelStateChange(() => refreshSendButton());

  async function onSend(): Promise<void> {
    await conversationHydration;
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

    const history = conversationHistoryForGeneration(messages);
    messages.push({ role: 'user', content: prompt });
    const assistantMsg: ChatMessage = { role: 'assistant', content: '' };
    messages.push(assistantMsg);
    isGenerating = true;
    refreshSendButton();
    const conversation = await saveConversation();
    const generationContext: ConversationGenerationContext = {
      history,
      ...(conversation ? { conversationId: conversation.id } : {}),
    };
    renderMessages(messagesEl);
    if (pendingConversationAction) {
      assistantMsg.content = 'Cancelled.';
      await saveConversation();
      isGenerating = false;
      refreshSendButton();
      renderMessages(messagesEl);
      runPendingConversationAction();
      return;
    }

    try {
      if (toolsEnabled) {
        await generateWithToolCalling(prompt, assistantMsg, messagesEl);
      } else {
        await generateStreaming(prompt, assistantMsg, messagesEl, generationContext);
      }
    } catch (error) {
      if (assistantMsg.thinking === 'Starting…') assistantMsg.thinking = undefined;
      assistantMsg.content = formatChatError(error);
      assistantMsg.isError = true;
      renderLastMessage(messagesEl, assistantMsg, false);
    } finally {
      cancelGeneration = null;
      isGenerating = false;
      await saveConversation();
      refreshSendButton();
      // Full re-render drops the streaming cursor and adds hover actions.
      renderMessages(messagesEl);
      runPendingConversationAction();
    }
  }

  async function sendAttachment(
    attachment: PendingAttachment,
    prompt: string,
    host: HTMLElement,
  ): Promise<void> {
    // Both branches leave the file staged on purpose: the reader's next action
    // after picking a model is to press Send again, and re-attaching the file
    // first would be busywork the app created.
    if (attachment.kind === 'image' && !canAnswerImageAttachment()) {
      openSheet(VLM_SHEET_OPTIONS);
      showToast('Load an image model first, then send the attached image.', 'info', 4200);
      return;
    }
    if (attachment.kind === 'document' && !canAnswerDocumentAttachment()) {
      openSheet(DOCUMENT_SHEET_OPTIONS);
      showToast(
        'Answering questions about a file needs an indexing model and a chat model. Download them here, then send the file again.',
        'info',
        5200,
      );
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
        ...(attachment.thumbnailDataUrl
          ? { thumbnailDataUrl: attachment.thumbnailDataUrl }
          : {}),
      },
    };
    const assistantMsg: ChatMessage = { role: 'assistant', content: '' };
    messages.push(userMessage, assistantMsg);
    isGenerating = true;
    refreshSendButton();
    await saveConversation();
    renderMessages(host);
    if (pendingConversationAction) {
      assistantMsg.content = 'Cancelled.';
      await saveConversation();
      isGenerating = false;
      refreshSendButton();
      renderMessages(host);
      runPendingConversationAction();
      return;
    }
    try {
      const settings = getGenerationSettings();
      const onProgress = ({ content }: { content: string }) => {
        assistantMsg.content = content;
        renderLastMessage(host, assistantMsg);
      };
      let answer: ChatAttachmentAnswer;
      if (attachment.kind === 'image') {
        cancelGeneration = cancelActiveImageAttachmentAnswer;
        answer = await answerImageAttachment(attachment.file, question, settings, onProgress);
      } else {
        cancelGeneration = cancelActiveDocumentAttachmentAnswer;
        answer = await answerDocumentAttachment(attachment.file, question, settings, onProgress);
      }
      assistantMsg.thinking = answer.thinking;
      assistantMsg.sources = answer.sources;
      // A stopped turn keeps whatever had already been written — it is on screen
      // and the reader chose to stop it — and only says "Stopped." when nothing
      // arrived at all. Replacing partial text with a one-word status would
      // delete an answer the reader was in the middle of reading.
      assistantMsg.content = answer.cancelled
        ? (answer.content || 'Stopped.')
        : (answer.content || attachmentEmptyAnswer(attachment.kind));
      renderLastMessage(host, assistantMsg, false);
    } catch (error) {
      if (assistantMsg.thinking === 'Starting…') assistantMsg.thinking = undefined;
      const cancelled = isAbortError(error);
      assistantMsg.content = cancelled ? 'Stopped.' : formatChatError(error);
      // Only a real failure is flagged. A cancellation is the reader's own decision,
      // so painting it in the danger colour would report their own action back to
      // them as an error (DESIGN_GUIDELINE §9 keeps cancelled and error distinct).
      assistantMsg.isError = !cancelled;
      renderLastMessage(host, assistantMsg, false);
    } finally {
      cancelGeneration = null;
      isGenerating = false;
      await saveConversation();
      refreshSendButton();
      renderMessages(host);
      runPendingConversationAction();
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

/**
 * What an attachment turn says when the model answered nothing.
 *
 * A plain sentence rather than the "(empty response)" stand-in this used to
 * render — a parenthetical is developer shorthand, and a reader cannot tell it
 * apart from an answer the model actually gave. iOS says the same thing in the
 * same place (LLMViewModel+Vision.swift:128).
 */
function attachmentEmptyAnswer(kind: 'image' | 'document'): string {
  return kind === 'image'
    ? 'The model did not describe that image. Try another photo, or ask a more specific question.'
    : 'The model did not find an answer in that file. Try rephrasing the question.';
}

/** Saved content stays readable even when no inference model is loaded. */
export function conversationSuppressesModelOverlay(
  conversationMessages: readonly unknown[],
): boolean {
  return conversationMessages.length > 0;
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError';
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

/**
 * Build generation options from the Settings tab. Thinking is suppressed
 * structurally through `reasoning.mode` only when the loaded model supports it
 * and the user toggle is off — the app never injects control tokens.
 */
function buildGenerationOptions(): LlmOptions {
  const settings = getGenerationSettings();
  const systemPrompt = settings.systemPrompt.trim();
  const thinkingSuppressed = loadedModelSupportsThinking() && !settings.thinkingModeEnabled;
  return {
    maxOutputTokens: settings.maxTokens,
    temperature: settings.temperature,
    ...(systemPrompt.length > 0 ? { systemPrompt } : {}),
    ...(thinkingSuppressed
      ? { reasoning: { mode: 'off' as const } }
      : { reasoning: { mode: 'on' as const, includeInOutput: true } }),
  };
}

async function generateStreaming(
  prompt: string,
  assistantMsg: ChatMessage,
  messagesEl: HTMLElement,
  context: ConversationGenerationContext,
): Promise<void> {
  const options = buildGenerationOptions();
  const events = RunAnywhere.llm.generateStream(
    [...context.history, { role: 'user' as const, content: prompt }],
    { ...options, conversationId: context.conversationId },
  );
  const iterator = events[Symbol.asyncIterator]();
  cancelGeneration = () => { void iterator.return?.(); };

  const thinkingEnabled = options.reasoning?.mode === 'on';
  if (thinkingEnabled) {
    assistantMsg.thinking = 'Starting…';
    renderLastMessage(messagesEl, assistantMsg);
  }

  let answer = '';
  let thinking = '';
  let sawAnyToken = false;
  let finishReason: GenerationResult['finishReason'] = 'stop';
  const firstTokenTimeoutMs = 120_000;
  const firstTokenTimer = window.setTimeout(() => {
    if (sawAnyToken || !isGenerating) return;
    void iterator.return?.();
  }, firstTokenTimeoutMs);

  try {
    // Hermes-style manual iteration keeps the cancel handle addressable and
    // matches the shape the RN SDK requires, so the two demos read alike.
    for (let step = await iterator.next(); !step.done; step = await iterator.next()) {
      const event = step.value;
      if (event.type === 'reasoningDelta') {
        sawAnyToken = true;
        window.clearTimeout(firstTokenTimer);
        thinking += event.text;
        assistantMsg.thinking = thinking;
        renderLastMessage(messagesEl, assistantMsg);
      } else if (event.type === 'textDelta') {
        sawAnyToken = true;
        window.clearTimeout(firstTokenTimer);
        answer += event.text;
        assistantMsg.content = answer;
        renderLastMessage(messagesEl, assistantMsg);
      } else if (event.type === 'completed') {
        answer = event.result.text || answer;
        thinking = event.result.thinkingText || thinking;
        finishReason = event.result.finishReason;
      }
    }
  } finally {
    window.clearTimeout(firstTokenTimer);
  }

  if (!sawAnyToken && !answer.trim() && !thinking.trim()) {
    assistantMsg.thinking = undefined;
    assistantMsg.content = finishReason === 'cancelled'
      ? 'Cancelled — no tokens arrived before the first-token timeout or stop.'
      : 'No tokens arrived within 2 minutes. The model may still be loading '
        + 'into WebGPU, or generation stalled. Try Stop, reload the model, or switch to a smaller model.';
    renderLastMessage(messagesEl, assistantMsg, false);
    return;
  }

  const thinkingText = thinking.trim();
  assistantMsg.thinking = thinkingText || undefined;
  assistantMsg.content = answer.trim();
  if (!assistantMsg.content) {
    if (finishReason === 'cancelled') {
      assistantMsg.content = 'Cancelled.';
    } else if (finishReason === 'length') {
      assistantMsg.content = 'The response limit was reached before a final answer. '
        + 'Increase Max tokens in Settings or turn off thinking, then try again.';
    } else if (thinkingText) {
      // Reasoning models (especially heavily quantized ones) sometimes emit their
      // entire reply inside the thinking channel and never close the block, so the
      // answer channel arrives empty. Surface the reasoning as the answer rather
      // than a dead-end error — the response is right there.
      assistantMsg.content = thinkingText;
      assistantMsg.thinking = undefined;
    } else {
      assistantMsg.content = 'The model finished without producing a final answer. Try again or turn off thinking.';
    }
  }
  // Generation is terminal now, even though onSend's persistence cleanup is
  // still pending. Collapse reasoning immediately so the final answer below
  // becomes the primary surface; the native <details> remains user-expandable.
  renderLastMessage(messagesEl, assistantMsg, false);
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
  const forcedToolName = explicitlyRequestedDemoTool(prompt);
  cancelGeneration = null;

  // The SDK runs the tool loop when `options.tools` or the registry has tools;
  // `toolChoice` only pins which one the model must reach for.
  const result = await RunAnywhere.llm.generate(prompt, {
    ...options,
    toolChoice: forcedToolName
      ? { kind: 'forced', name: forcedToolName }
      : { kind: 'auto' },
  });

  // Commons already splits ToolCalling / generate results into text + thinkingText.
  assistantMsg.content = result.text.trim() || (result.toolCalls.length > 0
    ? 'The tool completed, but the model did not provide a final answer.'
    : 'The model did not produce a tool call or answer. Please try again.');
  assistantMsg.thinking = result.thinkingText?.trim() || undefined;
  if (result.toolCalls.length > 0) {
    assistantMsg.toolCalls = result.toolCalls.map((call) => ({
      name: call.name,
      argumentsJson: call.argumentsJson,
    }));
  }
  renderLastMessage(messagesEl, assistantMsg, false);
}

const DEMO_TOOL_NAMES = ['calculate', 'get_current_time', 'get_weather'] as const;
type DemoToolName = (typeof DEMO_TOOL_NAMES)[number];

/** Honor an unambiguous, explicit tool-name request through the SDK's forced
 * choice contract. Ordinary user language remains on automatic selection. */
function explicitlyRequestedDemoTool(prompt: string): DemoToolName | null {
  const requested = DEMO_TOOL_NAMES.filter((name) =>
    new RegExp(`\\b${name}\\b`, 'i').test(prompt));
  return requested.length === 1 ? requested[0]! : null;
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

  RunAnywhere.llm.tools.register(
    toolDefinition(
      'get_weather',
      'Gets the current weather for a given location using Open-Meteo API',
      [stringParameter('location', "City name (e.g., 'San Francisco', 'London', 'Tokyo')")],
    ),
    async (args) => fetchWeather(toolValueString(args.location) ?? 'San Francisco'),
  );

  RunAnywhere.llm.tools.register(
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

  RunAnywhere.llm.tools.register(
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

/** A single required string parameter, described as a JSON Schema property. */
interface DemoToolStringParameter {
  name: string;
  description: string;
}

/**
 * `ToolDefinition.parameters` is one JSON-Schema-object string now (OpenAI
 * `parameters` / Anthropic `input_schema` / MCP `inputSchema` shape), not a
 * structured `ToolParameter[]`. Build that schema string here rather than
 * hand-rolling proto types the app has no business constructing.
 */
function toolDefinition(
  name: string,
  description: string,
  parameters: DemoToolStringParameter[],
): ToolDefinition {
  const properties: Record<string, { type: 'string'; description: string }> = {};
  for (const param of parameters) {
    properties[param.name] = { type: 'string', description: param.description };
  }
  const schema = {
    type: 'object',
    properties,
    required: parameters.map((param) => param.name),
  };
  return {
    name,
    description,
    parameters: JSON.stringify(schema),
    category: 'Utility',
  };
}

function stringParameter(name: string, description: string): DemoToolStringParameter {
  return { name, description };
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
// IndexedDB conversation history.
// ---------------------------------------------------------------------------

/**
 * Convert completed UI turns into the transcript `RunAnywhere.llm.generateStream`
 * accepts. The current user prompt is deliberately not included; callers
 * snapshot history before they append that prompt to the visible conversation.
 */
export function conversationHistoryForGeneration(
  conversationMessages: readonly unknown[],
): SDKChatMessage[] {
  return conversationMessages
    .filter(isChatMessage)
    // A failed turn is the app's own report. Sending it back as a prior assistant
    // message tells the model it said "Error: Backend not available for: llm", and it
    // starts apologising for a failure it had no part in. iOS skips the same turns
    // (LLMViewModel+Generation), and Android's `ChatRequestPolicy.toProtoMessage` now
    // does too.
    .filter(({ isError }) => isError !== true)
    .filter(({ content }) => content.trim().length > 0)
    .map((message) => ({
      role: message.role === 'user' ? ('user' as const) : ('assistant' as const),
      content: message.content,
    }));
}

async function loadConversation(): Promise<ChatMessage[]> {
  const conversation = await ConversationsStore.getCurrent();
  return conversation?.messages.filter(isChatMessage) ?? [];
}

async function saveConversation(): Promise<StoredConversation | null> {
  try {
    return await ConversationsStore.saveCurrent(messages);
  } catch (error) {
    if (!conversationStorageWarningShown) {
      conversationStorageWarningShown = true;
      showToast('This chat could not be saved to the local database.', 'warning', 4200);
    }
    appLogger.warning('[Chat] Conversation database write failed:', error);
    return null;
  }
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
  return RunAnywhere.runtime.modalities.llm.status !== 'unavailable';
}

function navigateTo(tab: string): void {
  window.dispatchEvent(new CustomEvent('runanywhere:navigate', { detail: { tab } }));
}

/**
 * True when the C++ lifecycle reports an LLM loaded. Used to gate the chat
 * Send button so users can't click into a silent no-op before loading a
 * model from the toolbar picker.
 */
function isModelLoaded(): boolean {
  return findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE) !== null;
}

/**
 * Whether the loaded LLM supports a thinking phase — read from the registry
 * record, same source iOS uses (LLMViewModel `loadedModelSupportsThinking`).
 */
function loadedModelSupportsThinking(): boolean {
  return findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE)
    ?.supportsThinking ?? false;
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

/**
 * The four things a consumer opens an on-device assistant to do.
 *
 * Labels and prompt bodies are byte-identical to Android `generalSuggestions`
 * (PromptSuggestions.kt) and iOS `StarterPrompt.all` (ChatMessageListView.swift) —
 * the greeting above these chips is already shared across the three apps, so a
 * different set of chips underneath it read as an accident.
 *
 * The bodies end in a colon on purpose: each is a *prefix* the reader completes with
 * their own notes or options. The chip prefills the composer and focuses it rather
 * than sending, which is what makes the trailing colon work.
 */
const STARTER_PROMPTS: Array<{ label: string; prompt: string; icon: IconName }> = [
  {
    label: 'Plan my day',
    prompt: 'Turn this messy list into a realistic plan with the top three priorities:',
    icon: 'checklist',
  },
  {
    label: 'Rewrite clearly',
    prompt: 'Rewrite this so it is clear, warm, and concise:',
    icon: 'pencil',
  },
  {
    label: 'Compare options',
    prompt: 'Compare these options, explain the tradeoffs, and recommend one:',
    icon: 'compare',
  },
  {
    label: 'Summarize notes',
    prompt: 'Summarize these notes into decisions, action items, and open questions:',
    icon: 'condense',
  },
];

function renderMessages(host: HTMLElement): void {
  if (messages.length === 0) {
    host.innerHTML = `
      <div class="chat-empty-state">
        <div class="empty-logo">${icon('sparkles')}</div>
        <h3>${greeting()}</h3>
        <p>
          AI inference runs on this device. Setup, model downloads, and
          enabled web tools may contact the services identified by the app.
        </p>
        <div class="suggestion-chips">
          ${STARTER_PROMPTS.map((starter) => `
            <button type="button" class="suggestion-chip" data-prompt="${escapeHtml(starter.prompt)}">
              ${icon(starter.icon, { size: 20 })}
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

/**
 * The picture itself when there is one, the modality glyph otherwise.
 *
 * Sized inline because the attachment card's stylesheet rule only ever expected
 * an SVG; the thumbnail borrows that same 20px box so the pill and the bubble
 * keep their existing rhythm. The `src` is a data URL this app produced and
 * `isChatAttachmentInfo` re-checks on restore, never remote content.
 */
function attachmentGlyph(kind: 'image' | 'document', thumbnailDataUrl?: string): string {
  if (kind === 'image' && thumbnailDataUrl) {
    return `<img src="${escapeHtml(thumbnailDataUrl)}" alt=""
      style="width:28px;height:28px;object-fit:cover;border-radius:var(--radius-sm);flex:none;" />`;
  }
  return icon(kind === 'image' ? 'image' : 'file');
}

function renderMessageActions(msg: ChatMessage, idx: number): string {
  if (msg.role !== 'assistant' || !msg.content) return '';
  return `
    <div class="chat-msg-actions">
      <button type="button" class="chat-action-btn" data-copy-idx="${idx}" aria-label="Copy reply">
        ${icon('copy')}
        <span>Copy</span>
      </button>
    </div>
  `;
}

function renderLastMessage(
  host: HTMLElement,
  msg: ChatMessage,
  streaming = isGenerating,
): void {
  const last = host.lastElementChild;
  if (last) {
    last.innerHTML = renderMessageBody(msg, streaming);
  }
  host.scrollTop = host.scrollHeight;
}

function renderMessageBody(msg: ChatMessage, streaming = false): string {
  // Collapsible thinking section — iOS parity:
  // ChatMessageComponents.swift:128-181 (thinkingSection).
  const thinking = msg.thinking?.trim();
  const thinkingSection = msg.role === 'assistant' && thinking
    ? `
      <details class="chat-thinking"${streaming ? ' open' : ''}>
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
              ${icon(call.error ? 'warning' : 'tool')}
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
        ${attachmentGlyph(msg.attachment.kind, msg.attachment.thumbnailDataUrl)}
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
  // A failure report is the app speaking, not the model, so it is NOT run through the
  // markdown renderer: an error string's own punctuation would become bold or italic,
  // and it would read in the same ink as a real reply. Danger colour plus an escaped
  // paragraph, matching iOS `assistantBody` (`AppColors.dangerText`) and Android's
  // error branch. The `role="alert"` is what makes the failure reach a screen reader at
  // all — the turn used to arrive as ordinary prose.
  if (msg.isError === true && msg.content) {
    const alert = `<p class="chat-error" role="alert">${escapeHtml(msg.content)}</p>`;
    return `${thinkingSection}${toolSection}<div class="chat-bubble">${attachmentSection}${alert}</div>`;
  }

  const body = msg.content
    ? renderMarkdown(msg.content) + cursor
    : (streaming
      ? (thinking
        ? `<span class="chat-bubble-typing">Thinking&hellip;</span>${cursor}`
        : cursor || '<span class="chat-bubble-typing">&hellip;</span>')
      : '<span class="chat-bubble-typing">No final answer was generated.</span>');

  return `${thinkingSection}${toolSection}<div class="chat-bubble">${attachmentSection}${body}${sourcesSection}</div>`;
}

export function formatChatError(error: unknown): string {
  return `Error: ${formatError(error)}`;
}
