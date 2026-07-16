// chat.js — multi-turn conversation: the second turn relies on memory from the
// first. Downloads a small instruct model by catalog id.
//   node examples/chat.js
const { RunAnywhere } = require('../dist');

async function say(chat, user) {
  console.log('\nUser: ' + user);
  process.stdout.write('Assistant: ');
  for await (const t of chat.send(user)) process.stdout.write(t);
  console.log();
}

(async () => {
  console.log('@runanywhere/electron — commons version:', RunAnywhere.version);
  RunAnywhere.initialize();

  let last = -1;
  const llm = await RunAnywhere.loadLLM('qwen2.5-0.5b', {
    onProgress: (p) => {
      if (p.percent !== last && p.percent % 25 === 0) {
        last = p.percent;
        process.stdout.write(`  downloading ${p.file}: ${p.percent}%\n`);
      }
    },
  });

  const chat = RunAnywhere.createChat(llm, {
    system: 'You are a concise, friendly assistant. Answer in one short sentence.',
  });

  await say(chat, 'My name is Aman and I love astronomy.');
  await say(chat, 'What is my name, and what do I love?'); // relies on turn 1

  console.log('\n[chat] conversation turns recorded:', chat.messages.length);

  llm.unload();
  RunAnywhere.shutdown();
  console.log('[chat] OK — multi-turn chat with memory across turns.');
})().catch((e) => {
  console.error('FAILED:', e);
  process.exit(1);
});
