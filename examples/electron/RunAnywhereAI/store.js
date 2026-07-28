// store.js — the app's small JSON store (conversations / settings / custom
// models), split out of main.js so it can be unit-tested without Electron.
//
// Two properties matter here, because losing this data is silent and total:
//   * writes are ATOMIC — temp file + fsync + rename, so an interrupted write
//     can never leave truncated JSON that parses as "no conversations".
//   * an unreadable file is BACKED UP rather than discarded, so a user can get
//     their history back instead of finding an empty app.
const fs = require('fs');
const path = require('path');

/** Create a store rooted at `dir` (created on demand). */
function createStore(dir) {
  const target = (name) => path.join(dir, name);

  function readJson(name, fallback) {
    const file = target(name);
    let text;
    try {
      text = fs.readFileSync(file, 'utf8');
    } catch {
      return fallback; // missing file is the normal first-run case
    }
    try {
      return JSON.parse(text);
    } catch {
      // Keep the bytes: a parse failure is recoverable by hand, a delete is not.
      try {
        fs.copyFileSync(file, `${file}.corrupt-${Date.now()}`);
      } catch { /* best effort */ }
      return fallback;
    }
  }

  function writeJson(name, data) {
    const file = target(name);
    const tmp = `${file}.${process.pid}.tmp`;
    try {
      fs.mkdirSync(dir, { recursive: true });
      const json = JSON.stringify(data);
      const fd = fs.openSync(tmp, 'w');
      try {
        fs.writeFileSync(fd, json);
        fs.fsyncSync(fd); // durable on disk before it becomes the live file
      } finally {
        fs.closeSync(fd);
      }
      // Rename within one directory is atomic: a reader sees the old file or the
      // new one, never a half-written one.
      fs.renameSync(tmp, file);
      return true;
    } catch {
      try { fs.rmSync(tmp, { force: true }); } catch { /* ignore */ }
      return false;
    }
  }

  return { readJson, writeJson, path: target };
}

/**
 * Keep the newest `max` conversations. The store is rewritten in full on every
 * message, so an unbounded list turns into an ever-growing synchronous write.
 */
function capConversations(conversations, max = 200) {
  if (!Array.isArray(conversations)) return [];
  return conversations.length > max ? conversations.slice(0, max) : conversations;
}

// System prompts shipped by earlier builds. A user who pressed "Save settings"
// on one of those has it persisted, and persisted values override the defaults —
// so they would keep the old behaviour (a model answering "my name is Qwen" when
// asked "what is my name") forever, with no way to know why. Upgrade them.
const SUPERSEDED_SYSTEM_PROMPTS = [
  'You are a concise, helpful assistant.',
];

/**
 * Migrate persisted settings to current defaults where the stored value is a
 * known-superseded default the user never actually customised.
 */
function migrateSettings(saved, defaults) {
  if (!saved || typeof saved !== 'object') return { ...defaults };
  const out = { ...defaults, ...saved };
  if (SUPERSEDED_SYSTEM_PROMPTS.includes((saved.systemPrompt || '').trim())) {
    out.systemPrompt = defaults.systemPrompt;
    // That prompt shipped alongside a temperature tuned for it.
    if (saved.temperature === 0.7) out.temperature = defaults.temperature;
  }
  return out;
}

module.exports = { createStore, capConversations, migrateSettings, SUPERSEDED_SYSTEM_PROMPTS };
