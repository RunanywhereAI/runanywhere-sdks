import { IDBFactory } from 'fake-indexeddb';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ConversationsStoreImpl } from './conversations-store';

function createStore(ids: string[]) {
  let timestamp = 1_000;
  let idIndex = 0;
  return new ConversationsStoreImpl({
    now: () => ++timestamp,
    createId: () => ids[idIndex++] ?? `chat-${idIndex}`,
  });
}

describe('ConversationsStore', () => {
  beforeEach(() => {
    vi.stubGlobal('indexedDB', new IDBFactory());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('persists, selects, and deletes real IndexedDB records', async () => {
    const first = new ConversationsStoreImpl({
      now: () => 1_234,
      createId: () => 'indexed-chat',
    });
    await first.saveCurrent([
      { role: 'user', content: 'Stored in IndexedDB' },
      { role: 'assistant', content: 'Durable reply' },
    ]);

    const reloaded = new ConversationsStoreImpl();
    expect(await reloaded.getCurrent()).toMatchObject({
      id: 'indexed-chat',
      title: 'Stored in IndexedDB',
    });
    expect((await reloaded.getCurrent())?.messages).toHaveLength(2);

    await reloaded.delete('indexed-chat');
    const afterDelete = new ConversationsStoreImpl();
    expect(await afterDelete.getCurrent()).toBeNull();
    expect(await afterDelete.getConversations()).toEqual([]);
  });

  it('keeps multiple chats and restores the selected chat from the database', async () => {
    const store = createStore(['first', 'second']);

    const first = await store.saveCurrent([
      { role: 'user', content: 'First saved question' },
      { role: 'assistant', content: 'First answer' },
    ]);
    await store.startNew();
    const second = await store.saveCurrent([
      { role: 'user', content: 'Second saved question' },
      { role: 'assistant', content: 'Second answer' },
    ]);

    expect(first?.id).toBe('first');
    expect(second?.id).toBe('second');
    expect((await store.getConversations()).map(({ title }) => title)).toEqual([
      'Second saved question',
      'First saved question',
    ]);

    await store.setCurrent('first');
    const reloaded = createStore(['unused']);
    expect(await reloaded.getCurrent()).toMatchObject({
      id: 'first',
      title: 'First saved question',
      messages: [
        { role: 'user', content: 'First saved question' },
        { role: 'assistant', content: 'First answer' },
      ],
    });
  });

  it('starts a blank chat without deleting prior database records', async () => {
    const store = createStore(['existing']);
    await store.saveCurrent([{ role: 'user', content: 'Keep this chat' }]);

    await store.startNew();

    expect(await store.getCurrent()).toBeNull();
    expect(await store.getConversations()).toHaveLength(1);

    const reloaded = createStore(['unused']);
    expect(await reloaded.getCurrent()).toBeNull();
    expect((await reloaded.getConversations())[0]?.title).toBe('Keep this chat');
  });

  it('serializes concurrent writes so the newest snapshot wins', async () => {
    const store = createStore(['only']);

    await Promise.all([
      store.saveCurrent([{ role: 'user', content: 'First snapshot' }]),
      store.saveCurrent([{ role: 'user', content: 'Second snapshot' }]),
    ]);

    expect((await store.getConversations())).toHaveLength(1);
    expect((await store.getCurrent())?.title).toBe('Second snapshot');
  });

  it('deletes only the requested database record', async () => {
    const store = createStore(['first', 'second']);
    await store.saveCurrent([{ role: 'user', content: 'First' }]);
    await store.startNew();
    await store.saveCurrent([{ role: 'user', content: 'Second' }]);

    expect(await store.delete('first')).toBe(true);
    expect((await store.getConversations()).map(({ id }) => id)).toEqual(['second']);
    expect((await store.getCurrent())?.id).toBe('second');
  });

  it('fails clearly instead of presenting ephemeral history without IndexedDB', async () => {
    vi.stubGlobal('indexedDB', undefined);
    const store = createStore(['unused']);

    await expect(store.getConversations()).rejects.toThrow(
      'IndexedDB is unavailable; saved chats cannot be persisted.',
    );
  });
});
