import { describe, expect, it } from 'vitest';
import { ChatMessageStatus, MessageRole, SDKException } from '@runanywhere/web';
import {
  conversationHistoryForGeneration,
  conversationSuppressesModelOverlay,
  formatChatError,
} from './chat';

describe('chat error formatting', () => {
  it('sanitizes SDKException messages before rendering or persistence', () => {
    const error = SDKException.fromCode(
      -1,
      'Request failed at https://example.test/models?token=secret-value with Bearer access-token',
    );

    const formatted = formatChatError(error);

    expect(formatted).toBe(
      'Error: Request failed at https://example.test/models with Bearer [REDACTED]',
    );
    expect(formatted).not.toContain('secret-value');
    expect(formatted).not.toContain('access-token');
  });
});

describe('saved conversation visibility', () => {
  it('suppresses the model setup overlay only when chat history is visible', () => {
    expect(conversationSuppressesModelOverlay([])).toBe(false);
    expect(conversationSuppressesModelOverlay([
      { role: 'user', content: 'Previously saved question' },
    ])).toBe(true);
  });
});

describe('conversation generation context', () => {
  it('maps prior UI turns to the public SDK history shape', () => {
    expect(conversationHistoryForGeneration([
      { role: 'user', content: 'My name is Ada.' },
      { role: 'assistant', content: 'Nice to meet you, Ada.' },
      { role: 'assistant', content: '   ' },
      { role: 'tool', content: 'ignored' },
    ])).toEqual([
      {
        id: '',
        role: MessageRole.MESSAGE_ROLE_USER,
        content: 'My name is Ada.',
        timestampUs: 0,
        toolCalls: [],
        status: ChatMessageStatus.CHAT_MESSAGE_STATUS_COMPLETE,
        metadata: {},
        attachments: [],
      },
      {
        id: '',
        role: MessageRole.MESSAGE_ROLE_ASSISTANT,
        content: 'Nice to meet you, Ada.',
        timestampUs: 0,
        toolCalls: [],
        status: ChatMessageStatus.CHAT_MESSAGE_STATUS_COMPLETE,
        metadata: {},
        attachments: [],
      },
    ]);
  });
});
