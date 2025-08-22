import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    lib: {
      entry: 'src/index.ts',
      name: 'RunAnywhereReact',
      fileName: (format) => `index.${format === 'es' ? 'js' : format}`,
      formats: ['es']
    },
    rollupOptions: {
      external: [
        'react',
        'react-dom',
        '@runanywhere/core',
        '@runanywhere/voice',
        '@runanywhere/transcription',
        '@runanywhere/llm',
        '@runanywhere/tts'
      ],
      output: {
        globals: {
          'react': 'React',
          'react-dom': 'ReactDOM',
          '@runanywhere/core': 'RunAnywhereCore',
          '@runanywhere/voice': 'RunAnywhereVoice',
          '@runanywhere/transcription': 'RunAnywhereTranscription',
          '@runanywhere/llm': 'RunAnywhereLLM',
          '@runanywhere/tts': 'RunAnywhereTTS'
        }
      }
    },
    target: 'es2020',
    minify: false,
    sourcemap: true
  }
});
