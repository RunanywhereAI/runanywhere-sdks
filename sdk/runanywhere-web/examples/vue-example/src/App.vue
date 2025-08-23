<template>
  <div id="app" class="container">
    <header>
      <h1>🎤 RunAnywhere Voice AI - Vue Example</h1>
      <p>Powered by Vue 3 + RunAnywhere Web SDK</p>
    </header>

    <main>
      <section class="controls">
        <h2>Voice Pipeline Controls</h2>
        <div class="status">
          <div class="status-item">
            <span class="label">Status:</span>
            <span :class="['value', statusClass]">{{ statusText }}</span>
          </div>
          <div class="status-item" v-if="state.error">
            <span class="label">Error:</span>
            <span class="value error">{{ state.error.message }}</span>
          </div>
        </div>

        <div class="button-group">
          <button @click="initialize" :disabled="state.isInitialized" class="btn btn-primary">
            Initialize Pipeline
          </button>
          <VoicePipelineButton
            :config="pipelineConfig"
            :customButtonText="buttonText"
            @transcription="handleTranscription"
            @llm-response="handleLLMResponse"
            @error="handleError"
            class="btn btn-voice"
          />
        </div>
      </section>

      <section class="conversation">
        <h2>Conversation History</h2>
        <div class="conversation-container">
          <div
            v-for="entry in conversation"
            :key="entry.id"
            :class="['message', entry.type]"
          >
            <div class="message-header">
              <span class="speaker">{{ entry.type === 'user' ? '🗣️ You' : '🤖 AI Assistant' }}</span>
              <span class="timestamp">{{ formatTime(entry.timestamp) }}</span>
            </div>
            <div class="message-content">{{ entry.text }}</div>
          </div>
          <div v-if="conversation.length === 0" class="no-messages">
            No conversation yet. Click the voice button to start!
          </div>
        </div>
      </section>

      <section class="metrics">
        <h2>Performance Metrics</h2>
        <div class="metrics-grid">
          <div class="metric">
            <span class="metric-label">VAD Latency</span>
            <span class="metric-value">{{ metrics.vadLatency.toFixed(2) }}ms</span>
          </div>
          <div class="metric">
            <span class="metric-label">STT Latency</span>
            <span class="metric-value">{{ metrics.sttLatency.toFixed(2) }}ms</span>
          </div>
          <div class="metric">
            <span class="metric-label">LLM Latency</span>
            <span class="metric-value">{{ metrics.llmLatency.toFixed(2) }}ms</span>
          </div>
          <div class="metric">
            <span class="metric-label">TTS Latency</span>
            <span class="metric-value">{{ metrics.ttsLatency.toFixed(2) }}ms</span>
          </div>
          <div class="metric">
            <span class="metric-label">Total Latency</span>
            <span class="metric-value">{{ metrics.totalLatency.toFixed(2) }}ms</span>
          </div>
        </div>
      </section>

      <VoiceChat
        :config="pipelineConfig"
        class="voice-chat-component"
      />
    </main>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useVoicePipeline, VoiceChat, VoicePipelineButton } from '@runanywhere/vue';
import type { VoicePipelineConfig, ConversationEntry, TranscriptionResult, CompletionResult } from '@runanywhere/vue';

// Pipeline configuration
const pipelineConfig: VoicePipelineConfig = {
  enableTranscription: true,
  enableLLM: true,
  enableTTS: true,
  autoPlayTTS: true,
  maxHistorySize: 50
};

// Custom button text configuration
const buttonText = {
  initialize: 'Initialize Voice',
  ready: 'Start Voice Chat',
  listening: 'Listening... (Click to Stop)',
  processing: 'Processing...'
};

// Initialize voice pipeline
const {
  state,
  conversation,
  metrics,
  isReady,
  buttonText: defaultButtonText,
  initialize
} = useVoicePipeline(pipelineConfig);

// Computed properties
const statusClass = computed(() => {
  if (state.error) return 'error';
  if (state.isPlaying) return 'playing';
  if (state.isProcessing) return 'processing';
  if (state.isListening) return 'listening';
  if (state.isInitialized) return 'ready';
  return 'idle';
});

const statusText = computed(() => {
  if (state.error) return 'Error';
  if (state.isPlaying) return 'Playing TTS';
  if (state.isProcessing) return 'Processing';
  if (state.isListening) return 'Listening';
  if (state.isInitialized) return 'Ready';
  return 'Not Initialized';
});

// Event handlers
const handleTranscription = (result: TranscriptionResult) => {
  console.log('🎤 Transcription:', result.text);
};

const handleLLMResponse = (result: CompletionResult) => {
  console.log('🤖 LLM Response:', result.text);
};

const handleError = (error: Error) => {
  console.error('❌ Voice Pipeline Error:', error);
};

// Utility functions
const formatTime = (timestamp: Date) => {
  return timestamp.toLocaleTimeString();
};
</script>

<style scoped>
.container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 20px;
  font-family: 'Inter', system-ui, -apple-system, sans-serif;
}

header {
  text-align: center;
  margin-bottom: 2rem;
}

header h1 {
  color: #2d3748;
  font-size: 2.5rem;
  margin-bottom: 0.5rem;
}

header p {
  color: #718096;
  font-size: 1.1rem;
}

main {
  display: grid;
  gap: 2rem;
  grid-template-columns: 1fr 1fr;
  grid-template-areas:
    "controls conversation"
    "metrics conversation"
    "voice-chat voice-chat";
}

.controls {
  grid-area: controls;
  background: white;
  border-radius: 12px;
  padding: 1.5rem;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.conversation {
  grid-area: conversation;
  background: white;
  border-radius: 12px;
  padding: 1.5rem;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.metrics {
  grid-area: metrics;
  background: white;
  border-radius: 12px;
  padding: 1.5rem;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.voice-chat-component {
  grid-area: voice-chat;
}

h2 {
  color: #2d3748;
  font-size: 1.3rem;
  margin-bottom: 1rem;
  border-bottom: 2px solid #e2e8f0;
  padding-bottom: 0.5rem;
}

.status {
  margin-bottom: 1.5rem;
}

.status-item {
  display: flex;
  justify-content: space-between;
  margin-bottom: 0.5rem;
}

.label {
  font-weight: 600;
  color: #4a5568;
}

.value {
  font-weight: 500;
  padding: 0.25rem 0.5rem;
  border-radius: 6px;
  font-size: 0.9rem;
}

.value.idle { background: #f7fafc; color: #718096; }
.value.ready { background: #c6f6d5; color: #276749; }
.value.listening { background: #bee3f8; color: #2c5282; }
.value.processing { background: #feebc8; color: #c05621; }
.value.playing { background: #e6fffa; color: #285e61; }
.value.error { background: #fed7d7; color: #c53030; }

.button-group {
  display: flex;
  gap: 1rem;
}

.btn {
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 8px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-primary {
  background: #3182ce;
  color: white;
}

.btn-primary:hover:not(:disabled) {
  background: #2c5282;
}

.btn-voice {
  background: #38a169;
  color: white;
}

.btn-voice:hover:not(:disabled) {
  background: #2f855a;
}

.conversation-container {
  max-height: 400px;
  overflow-y: auto;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  padding: 1rem;
}

.message {
  margin-bottom: 1rem;
  padding: 1rem;
  border-radius: 8px;
}

.message.user {
  background: #ebf8ff;
  border-left: 4px solid #3182ce;
}

.message.assistant {
  background: #f0fff4;
  border-left: 4px solid #38a169;
}

.message-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 0.5rem;
  font-size: 0.9rem;
}

.speaker {
  font-weight: 600;
}

.timestamp {
  color: #718096;
}

.message-content {
  line-height: 1.6;
}

.no-messages {
  text-align: center;
  color: #a0aec0;
  font-style: italic;
  padding: 2rem;
}

.metrics-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
  gap: 1rem;
}

.metric {
  text-align: center;
  padding: 1rem;
  background: #f7fafc;
  border-radius: 8px;
}

.metric-label {
  display: block;
  font-size: 0.8rem;
  color: #718096;
  margin-bottom: 0.5rem;
}

.metric-value {
  display: block;
  font-size: 1.2rem;
  font-weight: 700;
  color: #2d3748;
}

@media (max-width: 768px) {
  main {
    grid-template-columns: 1fr;
    grid-template-areas:
      "controls"
      "conversation"
      "metrics"
      "voice-chat";
  }

  .button-group {
    flex-direction: column;
  }
}
</style>
