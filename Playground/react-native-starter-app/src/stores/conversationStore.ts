/**
 * ConversationStore - Zustand store for conversation management
 *
 * Reference: iOS Core/Services/ConversationStore.swift
 *
 * Uses file-based JSON persistence matching iOS implementation.
 * Conversations are stored in Documents/Conversations/{id}.json
 */

import { create } from 'zustand';
import RNFS from 'react-native-fs';
import type { Conversation, Message } from '../types/chat';
import { MessageRole } from '../types/chat';

// Generate unique ID matching iOS UUID approach
/* eslint-disable no-bitwise */
const generateId = (): string =>
  'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
/* eslint-enable no-bitwise */

// Directory for storing conversations
const CONVERSATIONS_DIR = `${RNFS.DocumentDirectoryPath}/Conversations`;

/**
 * Serialize a conversation for JSON storage
 */
const serializeConversation = (conversation: Conversation): string => {
  return JSON.stringify(
    conversation,
    (key, value) => {
      // Convert Date objects to ISO strings
      if (value instanceof Date) {
        return value.toISOString();
      }
      return value;
    },
    2
  );
};

/**
 * Deserialize a conversation from JSON storage
 */
const deserializeConversation = (json: string): Conversation => {
  const parsed = JSON.parse(json);
  return {
    ...parsed,
    createdAt: new Date(parsed.createdAt),
    updatedAt: new Date(parsed.updatedAt),
    messages: parsed.messages.map((msg: Message & { timestamp: string }) => ({
      ...msg,
      timestamp: new Date(msg.timestamp),
    })),
  };
};

interface ConversationState {
  // State
  conversations: Conversation[];
  currentConversation: Conversation | null;
  isLoading: boolean;

  // Actions
  initialize: () => Promise<void>;
  createConversation: (title?: string) => Promise<Conversation>;
  updateConversation: (conversation: Conversation) => Promise<void>;
  deleteConversation: (conversationId: string) => Promise<void>;
  loadConversation: (conversationId: string) => Promise<Conversation | null>;
  setCurrentConversation: (conversation: Conversation | null) => void;
  addMessage: (message: Message, conversationId?: string) => Promise<void>;
  updateMessage: (message: Message, conversationId?: string) => void;
  searchConversations: (query: string) => Conversation[];
  clearAllConversations: () => Promise<void>;
}

export const useConversationStore = create<ConversationState>((set, get) => ({
  conversations: [],
  currentConversation: null,
  isLoading: false,

  /**
   * Initialize the store - load conversations from disk
   * Matches iOS loadConversations() behavior
   */
  initialize: async () => {
    set({ isLoading: true });
    try {
      // Ensure directory exists
      const dirExists = await RNFS.exists(CONVERSATIONS_DIR);
      if (!dirExists) {
        await RNFS.mkdir(CONVERSATIONS_DIR);
        console.warn('[ConversationStore] Created conversations directory');
      }

      // Load all conversation files
      const files = await RNFS.readDir(CONVERSATIONS_DIR);
      const jsonFiles = files.filter((f: { name: string; path: string }) =>
        f.name.endsWith('.json')
      );

      const loadedConversations: Conversation[] = [];

      for (const file of jsonFiles) {
        try {
          const content = await RNFS.readFile(file.path, 'utf8');
          const conversation = deserializeConversation(content);
          loadedConversations.push(conversation);
        } catch (error) {
          console.warn(
            `[ConversationStore] Failed to load ${file.name}:`,
            error
          );
        }
      }

      // Sort by updatedAt descending (newest first) - matches iOS
      loadedConversations.sort(
        (a, b) => b.updatedAt.getTime() - a.updatedAt.getTime()
      );

      console.warn(
        `[ConversationStore] Loaded ${loadedConversations.length} conversations`
      );
      set({ conversations: loadedConversations, isLoading: false });
    } catch (error) {
      console.error('[ConversationStore] Failed to initialize:', error);
      set({ isLoading: false });
    }
  },

  /**
   * Create a new conversation
   * Matches iOS createConversation(title:) behavior
   */
  createConversation: async (title?: string) => {
    const now = new Date();
    const conversation: Conversation = {
      id: generateId(),
      title: title || 'New Chat',
      createdAt: now,
      updatedAt: now,
      messages: [],
    };

    // Save to disk
    const filePath = `${CONVERSATIONS_DIR}/${conversation.id}.json`;
    await RNFS.writeFile(filePath, serializeConversation(conversation), 'utf8');

    // Insert at beginning (newest first) - matches iOS
    set((state) => ({
      conversations: [conversation, ...state.conversations],
      currentConversation: conversation,
    }));

    console.warn(
      `[ConversationStore] Created conversation: ${conversation.id}`
    );
    return conversation;
  },

  /**
   * Update an existing conversation
   * Matches iOS updateConversation(_:) behavior
   */
  updateConversation: async (conversation: Conversation) => {
    const updatedConversation = {
      ...conversation,
      updatedAt: new Date(),
    };

    // Save to disk
    const filePath = `${CONVERSATIONS_DIR}/${conversation.id}.json`;
    await RNFS.writeFile(
      filePath,
      serializeConversation(updatedConversation),
      'utf8'
    );

    // Update in state
    set((state) => ({
      conversations: state.conversations.map((c) =>
        c.id === conversation.id ? updatedConversation : c
      ),
      currentConversation:
        state.currentConversation?.id === conversation.id
          ? updatedConversation
          : state.currentConversation,
    }));

    console.warn(
      `[ConversationStore] Updated conversation: ${conversation.id}`
    );
  },

  /**
   * Delete a conversation
   * Matches iOS deleteConversation(_:) behavior
   */
  deleteConversation: async (conversationId: string) => {
    // Delete from disk
    const filePath = `${CONVERSATIONS_DIR}/${conversationId}.json`;
    try {
      await RNFS.unlink(filePath);
    } catch {
      console.warn(
        `[ConversationStore] File not found for deletion: ${conversationId}`
      );
    }

    // Remove from state and handle current conversation
    set((state) => {
      const filtered = state.conversations.filter(
        (c) => c.id !== conversationId
      );
      const newCurrent =
        state.currentConversation?.id === conversationId
          ? filtered[0] || null
          : state.currentConversation;
      return {
        conversations: filtered,
        currentConversation: newCurrent,
      };
    });

    console.warn(`[ConversationStore] Deleted conversation: ${conversationId}`);
  },

  /**
   * Load a specific conversation
   * Matches iOS loadConversation(_:) behavior
   */
  loadConversation: async (conversationId: string) => {
    // First check memory
    const { conversations } = get();
    let conversation = conversations.find((c) => c.id === conversationId);

    if (!conversation) {
      // Try loading from disk
      const filePath = `${CONVERSATIONS_DIR}/${conversationId}.json`;
      try {
        const exists = await RNFS.exists(filePath);
        if (exists) {
          const content = await RNFS.readFile(filePath, 'utf8');
          conversation = deserializeConversation(content);
        }
      } catch (error) {
        console.warn(
          `[ConversationStore] Failed to load conversation ${conversationId}:`,
          error
        );
        return null;
      }
    }

    if (conversation) {
      set({ currentConversation: conversation });
    }

    return conversation || null;
  },

  /**
   * Set the current conversation (without loading from disk)
   */
  setCurrentConversation: (conversation: Conversation | null) => {
    set({ currentConversation: conversation });
  },

  /**
   * Add a message to a conversation
   * Matches iOS addMessage(_:to:) behavior with auto-title generation
   */
  addMessage: async (message: Message, conversationId?: string) => {
    const { currentConversation, conversations } = get();
    const targetId = conversationId || currentConversation?.id;

    if (!targetId) {
      console.warn('[ConversationStore] No conversation to add message to');
      return;
    }

    const conversation = conversations.find((c) => c.id === targetId);
    if (!conversation) {
      console.warn(`[ConversationStore] Conversation not found: ${targetId}`);
      return;
    }

    // Auto-generate title from first user message (matches iOS)
    let newTitle = conversation.title;
    if (
      conversation.title === 'New Chat' &&
      message.role === MessageRole.User &&
      conversation.messages.length === 0
    ) {
      // Take first 50 characters of the message as title
      newTitle =
        message.content.length > 50
          ? message.content.substring(0, 50) + '...'
          : message.content;
    }

    const updatedConversation: Conversation = {
      ...conversation,
      title: newTitle,
      messages: [...conversation.messages, message],
      updatedAt: new Date(),
      modelName: message.modelInfo?.modelName || conversation.modelName,
      frameworkName:
        message.modelInfo?.frameworkDisplayName || conversation.frameworkName,
    };

    // Save to disk
    const filePath = `${CONVERSATIONS_DIR}/${targetId}.json`;
    await RNFS.writeFile(
      filePath,
      serializeConversation(updatedConversation),
      'utf8'
    );

    // Update state - move updated conversation to top
    set((state) => {
      const filtered = state.conversations.filter((c) => c.id !== targetId);
      return {
        conversations: [updatedConversation, ...filtered],
        currentConversation:
          state.currentConversation?.id === targetId
            ? updatedConversation
            : state.currentConversation,
      };
    });
  },

  /**
   * Update an existing message in a conversation (for streaming updates)
   * Matches iOS updateMessage(at:with:) behavior
   */
  updateMessage: (message: Message, conversationId?: string) => {
    const { currentConversation, conversations } = get();
    const targetId = conversationId || currentConversation?.id;

    if (!targetId) {
      return;
    }

    const conversation = conversations.find((c) => c.id === targetId);
    if (!conversation) {
      return;
    }

    // Find and update the message by ID
    const updatedMessages = conversation.messages.map((m) =>
      m.id === message.id ? message : m
    );

    const updatedConversation: Conversation = {
      ...conversation,
      messages: updatedMessages,
      updatedAt: new Date(),
      modelName: message.modelInfo?.modelName || conversation.modelName,
      frameworkName:
        message.modelInfo?.frameworkDisplayName || conversation.frameworkName,
    };

    // Update state (don't persist to disk during streaming - final update will persist)
    set((state) => ({
      conversations: state.conversations.map((c) =>
        c.id === targetId ? updatedConversation : c
      ),
      currentConversation:
        state.currentConversation?.id === targetId
          ? updatedConversation
          : state.currentConversation,
    }));
  },

  /**
   * Search conversations by title and message content
   * Matches iOS searchConversations(query:) behavior
   */
  searchConversations: (query: string) => {
    const { conversations } = get();
    const lowerQuery = query.toLowerCase();

    return conversations.filter((conversation) => {
      // Match title
      if (conversation.title.toLowerCase().includes(lowerQuery)) {
        return true;
      }
      // Match message content
      return conversation.messages.some((message) =>
        message.content.toLowerCase().includes(lowerQuery)
      );
    });
  },

  /**
   * Clear all conversations (for Settings)
   */
  clearAllConversations: async () => {
    try {
      // Delete directory and recreate
      await RNFS.unlink(CONVERSATIONS_DIR);
      await RNFS.mkdir(CONVERSATIONS_DIR);
      set({ conversations: [], currentConversation: null });
      console.warn('[ConversationStore] Cleared all conversations');
    } catch (error) {
      console.error(
        '[ConversationStore] Failed to clear conversations:',
        error
      );
    }
  },
}));

/**
 * Helper hooks for common operations
 */

/**
 * Get summary text for a conversation (matches iOS Conversation.summary computed property)
 */
export const getConversationSummary = (conversation: Conversation): string => {
  const userMessages = conversation.messages.filter(
    (m) => m.role === MessageRole.User
  ).length;
  const assistantMessages = conversation.messages.filter(
    (m) => m.role === MessageRole.Assistant
  ).length;
  return `${conversation.messages.length} messages • ${userMessages} from you, ${assistantMessages} from AI`;
};

/**
 * Get last message preview (matches iOS Conversation.lastMessagePreview computed property)
 */
export const getLastMessagePreview = (conversation: Conversation): string => {
  if (conversation.messages.length === 0) {
    return 'No messages yet';
  }
  const lastMessage = conversation.messages[conversation.messages.length - 1];
  if (!lastMessage) {
    return 'No messages yet';
  }
  return lastMessage.content.length > 100
    ? lastMessage.content.substring(0, 100) + '...'
    : lastMessage.content;
};

/**
 * Format relative date (matches iOS relativeDate helper)
 */
export const formatRelativeDate = (date: Date): string => {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffSecs = Math.floor(diffMs / 1000);
  const diffMins = Math.floor(diffSecs / 60);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffSecs < 60) {
    return 'Just now';
  } else if (diffMins < 60) {
    return `${diffMins} minute${diffMins === 1 ? '' : 's'} ago`;
  } else if (diffHours < 24) {
    return `${diffHours} hour${diffHours === 1 ? '' : 's'} ago`;
  } else if (diffDays < 7) {
    return `${diffDays} day${diffDays === 1 ? '' : 's'} ago`;
  } else {
    return date.toLocaleDateString();
  }
};
