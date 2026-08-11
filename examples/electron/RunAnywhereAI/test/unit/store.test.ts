/**
 * Unit tests for the app's JSON store (`src/main/store.ts`) and conversation
 * capping (`src/shared/conversation.ts`). Losing this data is silent and total,
 * so these pin atomic writes, corrupt-file backup, and the 200-conversation cap.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { afterEach, describe, expect, it } from 'vitest';

import { createStore } from '../../src/main/store';
import { capConversations, type ConversationRecord } from '../../src/shared/conversation';

const dirs: string[] = [];

function fresh(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ra-store-'));
  dirs.push(dir);
  return dir;
}

afterEach(() => {
  while (dirs.length > 0) {
    const dir = dirs.pop();
    if (dir !== undefined) fs.rmSync(dir, { recursive: true, force: true });
  }
});

describe('createStore', () => {
  it('readJson returns the fallback when the file does not exist', () => {
    const s = createStore(fresh());
    expect(s.readJson('conversations.json', [])).toEqual([]);
    expect(s.readJson('settings.json', { a: 1 })).toEqual({ a: 1 });
  });

  it('writeJson then readJson round-trips', () => {
    const s = createStore(fresh());
    const data = { nextConvId: 3, conversations: [{ id: 1, title: 'hi' }] };
    expect(s.writeJson('conversations.json', data)).toBe(true);
    expect(s.readJson('conversations.json', null)).toEqual(data);
  });

  it('writeJson creates the directory if it is missing', () => {
    const dir = path.join(fresh(), 'not', 'there', 'yet');
    const s = createStore(dir);
    expect(s.writeJson('settings.json', { x: 1 })).toBe(true);
    expect(fs.existsSync(path.join(dir, 'settings.json'))).toBe(true);
  });

  it('writeJson leaves NO temp file behind', () => {
    const dir = fresh();
    const s = createStore(dir);
    s.writeJson('settings.json', { x: 1 });
    const strays = fs.readdirSync(dir).filter((f) => f.includes('.tmp'));
    expect(strays).toEqual([]);
  });

  it('a write never leaves a truncated file: the old value survives a failed write', () => {
    const dir = fresh();
    const s = createStore(dir);
    s.writeJson('settings.json', { good: true });
    // Data that cannot be serialized (a BigInt) makes JSON.stringify throw AFTER
    // the store has decided to write — the live file must be untouched.
    expect(s.writeJson('settings.json', { bad: 1n })).toBe(false);
    expect(s.readJson('settings.json', null)).toEqual({ good: true });
    const strays = fs.readdirSync(dir).filter((f) => f.includes('.tmp'));
    expect(strays).toEqual([]);
  });

  it('a corrupt store is backed up, not silently discarded', () => {
    const dir = fresh();
    const s = createStore(dir);
    fs.writeFileSync(path.join(dir, 'conversations.json'), '{"conversations": [tr');
    expect(s.readJson('conversations.json', [])).toEqual([]);
    const backups = fs.readdirSync(dir).filter((f) => f.includes('.corrupt-'));
    expect(backups).toHaveLength(1);
    assert.match(fs.readFileSync(path.join(dir, backups[0] as string), 'utf8'), /conversations/);
  });

  it('a rewritten store replaces the previous contents completely', () => {
    const s = createStore(fresh());
    s.writeJson('settings.json', { a: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' });
    s.writeJson('settings.json', { b: 1 });
    expect(s.readJson('settings.json', null)).toEqual({ b: 1 });
  });
});

describe('capConversations', () => {
  it('keeps the newest entries and bounds the list at 200', () => {
    const many = Array.from({ length: 250 }, (_, i) => ({
      id: String(i),
      title: `c${i}`,
      messages: [],
      createdAtUnixMs: i,
      updatedAtUnixMs: i,
    }));
    const capped = capConversations(many, 200);
    expect(capped).toHaveLength(200);
    expect(capped[0]?.id).toBe('0');
    expect(capped[199]?.id).toBe('199');
  });

  it('leaves a short list untouched and tolerates junk', () => {
    const few: ConversationRecord[] = [
      {
        id: '1',
        title: 'a',
        messages: [],
        createdAtUnixMs: 1,
        updatedAtUnixMs: 1,
      },
      {
        id: '2',
        title: 'b',
        messages: [],
        createdAtUnixMs: 2,
        updatedAtUnixMs: 2,
      },
    ];
    expect(capConversations(few, 200)).toBe(few);
    expect(capConversations(null)).toEqual([]);
    expect(capConversations(undefined)).toEqual([]);
  });
});
