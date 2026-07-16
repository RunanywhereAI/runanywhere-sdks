// structured.js — grammar-constrained structured output. The model is forced to
// emit JSON matching the schema (via a GBNF grammar compiled from the schema),
// so the result always parses — no prompt-and-hope, no regex repair.
//   node examples/structured.js
const { RunAnywhere } = require('../dist');

(async () => {
  console.log('@runanywhere/electron — commons version:', RunAnywhere.version);
  RunAnywhere.initialize();

  const llm = await RunAnywhere.loadLLM('qwen2.5-0.5b');

  // 1) Object extraction: pull a typed record out of free text.
  const person = await llm.generateObject(
    'Extract the person as JSON. Text: "Ada Lovelace was a 36 year old English mathematician who loved poetry and analytical engines."',
    {
      maxTokens: 128,
      schema: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          age: { type: 'integer' },
          nationality: { type: 'string' },
          interests: { type: 'array', items: { type: 'string' } },
        },
        required: ['name', 'age', 'nationality', 'interests'],
      },
    }
  );
  console.log('\n[object] ', person);
  if (typeof person.name !== 'string' || typeof person.age !== 'number')
    throw new Error('schema not honored');

  // 2) Classification via enum: output is constrained to one of the labels.
  const sentiment = await llm.generateObject(
    'Classify the sentiment of this review: "Absolutely loved it, best purchase this year!"',
    {
      maxTokens: 32,
      schema: {
        type: 'object',
        properties: {
          sentiment: { type: 'string', enum: ['positive', 'negative', 'neutral'] },
          confidence: { type: 'number' },
        },
        required: ['sentiment', 'confidence'],
      },
    }
  );
  console.log('[enum]   ', sentiment);
  if (!['positive', 'negative', 'neutral'].includes(sentiment.sentiment))
    throw new Error('enum not honored');

  llm.unload();
  RunAnywhere.shutdown();
  console.log('\n[structured] OK — schema-constrained JSON, guaranteed parseable.');
})().catch((e) => {
  console.error('FAILED:', e);
  process.exit(1);
});
