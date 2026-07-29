// Usage:
//   RUNANYWHERE_NATIVE_PATH=... node scripts/test-gemma-multimodal.js <catalog-id> <media...>
const path = require('path');
const { RunAnywhere } = require('../dist');

const [model = 'gemma-4-e4b', ...media] = process.argv.slice(2);
if (!media.length) {
  console.error('Pass at least one image or WAV path.');
  process.exit(2);
}

(async () => {
  RunAnywhere.initialize();
  const vlm = await RunAnywhere.loadVLM(model);
  try {
    for (const file of media) {
      const audio = /\.(wav|mp3|flac|m4a|ogg)$/i.test(file);
      const prompt = audio
        ? 'Transcribe the speech and summarize the audio in one sentence.'
        : 'Describe this image in one concise sentence.';
      const answer = (await vlm.captionText(path.resolve(file), prompt)).trim();
      if (!answer) throw new Error(`empty multimodal answer for ${file}`);
      console.log(`[gemma-media] ${path.basename(file)}: ${answer}`);
    }
  } finally {
    vlm.unload();
    RunAnywhere.shutdown();
  }
})().catch((error) => {
  console.error('[gemma-media] failed:', error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
