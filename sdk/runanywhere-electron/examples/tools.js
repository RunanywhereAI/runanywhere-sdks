// tools.js — tool calling. The model is given a set of tools and forced (via a
// grammar) to emit exactly one well-formed { name, arguments } call. The grammar
// guarantees the FORMAT and valid tool NAME; the prompt drives which tool + args.
//   node examples/tools.js
const { RunAnywhere } = require('../dist');

const TOOLS = [
  {
    name: 'get_weather',
    description: 'Get the current weather for a city',
    parameters: {
      type: 'object',
      properties: { city: { type: 'string' }, unit: { type: 'string', enum: ['celsius', 'fahrenheit'] } },
      required: ['city', 'unit'],
    },
  },
  {
    name: 'set_timer',
    description: 'Start a countdown timer',
    parameters: {
      type: 'object',
      properties: { seconds: { type: 'integer' }, label: { type: 'string' } },
      required: ['seconds', 'label'],
    },
  },
];

async function ask(llm, prompt) {
  const call = await llm.generateToolCall(prompt, TOOLS, { maxTokens: 128 });
  console.log(`\nUser: ${prompt}\n  -> ${call.name}(${JSON.stringify(call.arguments)})`);
  if (!TOOLS.some((t) => t.name === call.name)) throw new Error('picked an unknown tool: ' + call.name);
  return call;
}

(async () => {
  console.log('@runanywhere/electron — commons version:', RunAnywhere.version);
  RunAnywhere.initialize();
  const llm = await RunAnywhere.loadLLM('qwen2.5-0.5b');

  const w = await ask(llm, 'What is the weather like in Tokyo in celsius?');
  if (w.name !== 'get_weather') throw new Error('expected get_weather');

  const t = await ask(llm, 'Set a 5 minute timer for my tea.');
  if (t.name !== 'set_timer') throw new Error('expected set_timer');

  llm.unload();
  RunAnywhere.shutdown();
  console.log('\n[tools] OK — grammar-guaranteed tool calls, correct tool selected.');
})().catch((e) => {
  console.error('FAILED:', e);
  process.exit(1);
});
