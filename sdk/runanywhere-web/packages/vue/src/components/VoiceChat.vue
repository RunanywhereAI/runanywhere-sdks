<template>
  <div class="ra-voice-chat" :class="classes">
    <div class="ra-voice-chat__header">
      <h3 class="ra-voice-chat__title">{{ title }}</h3>
      <div class="ra-voice-chat__metrics" v-if="showMetrics">
        <span>VAD: {{ metrics.vadLatency }}ms</span>
        <span>STT: {{ metrics.sttLatency }}ms</span>
        <span>LLM: {{ metrics.llmLatency }}ms</span>
        <span>TTS: {{ metrics.ttsLatency }}ms</span>
      </div>
    </div>

    <div class="ra-voice-chat__conversation" ref="conversationRef">
      <TransitionGroup name="message">
        <div
          v-for="entry in conversation"
          :key="entry.id"
          :class="getMessageClass(entry)"
        >
          <div class="ra-message__header">
            <span class="ra-message__role">
              {{ entry.type === 'user' ? '👤 You' : '🤖 Assistant' }}
            </span>
            <span class="ra-message__time">
              {{ formatTime(entry.timestamp) }}
            </span>
          </div>
          <div class="ra-message__content">
            {{ entry.text }}
          </div>
        </div>
      </TransitionGroup>

      <div v-if="conversation.length === 0" class="ra-voice-chat__placeholder">
        {{ placeholder }}
      </div>

      <Transition name="processing">
        <div v-if="state.isProcessing && !state.isPlaying" class="ra-voice-chat__processing">
          <span class="ra-pulse"></span>
          🎤 Listening for speech...
        </div>
      </Transition>
    </div>

    <div class="ra-voice-chat__controls">
      <button
        @click="toggleListening"
        :disabled="state.isProcessing && !state.isListening"
        :class="getButtonClass()"
      >
        <span v-if="state.isListening" class="ra-pulse"></span>
        {{ buttonText }}
      </button>

      <button
        @click="clearConversation"
        class="ra-button ra-button--secondary"
        :disabled="conversation.length === 0"
      >
        Clear
      </button>

      <div class="ra-voice-chat__status">
        <span v-if="state.isListening" class="ra-status ra-status--listening">
          🎤 Listening
        </span>
        <span v-if="state.isProcessing" class="ra-status ra-status--processing">
          ⚡ Processing
        </span>
        <span v-if="state.isPlaying" class="ra-status ra-status--playing">
          🔊 Playing
        </span>
      </div>
    </div>

    <Transition name="error">
      <div v-if="state.error" class="ra-voice-chat__error">
        <span>⚠️ {{ state.error.message }}</span>
        <button @click="clearError" class="ra-error__close">✕</button>
      </div>
    </Transition>
  </div>
</template>

<script setup lang="ts">
import { computed, watch, nextTick, ref } from 'vue';
import { useVoicePipeline } from '../composables/useVoicePipeline';
import type { VoicePipelineConfig } from '../types';

interface Props {
  config?: VoicePipelineConfig;
  title?: string;
  autoStart?: boolean;
  showMetrics?: boolean;
  placeholder?: string;
}

const props = withDefaults(defineProps<Props>(), {
  title: 'Voice Assistant',
  autoStart: false,
  showMetrics: true,
  placeholder: "Click 'Start Listening' to begin voice conversation"
});

const conversationRef = ref<HTMLDivElement>();

const {
  state,
  conversation,
  metrics,
  buttonText,
  initialize,
  start,
  stop,
  clearConversation,
  clearError
} = useVoicePipeline(props.config);

const classes = computed(() => ({
  'ra-voice-chat--listening': state.isListening,
  'ra-voice-chat--processing': state.isProcessing,
  'ra-voice-chat--playing': state.isPlaying,
  'ra-voice-chat--error': state.error !== null
}));

const toggleListening = async () => {
  try {
    if (!state.isInitialized) {
      await initialize();
      if (props.autoStart) {
        await start();
      }
    } else if (state.isListening) {
      await stop();
    } else {
      await start();
    }
  } catch (error) {
    console.error('Voice pipeline error:', error);
  }
};

const getMessageClass = (entry: any) => [
  'ra-message',
  `ra-message--${entry.type}`
];

const getButtonClass = () => [
  'ra-button',
  'ra-button--primary',
  {
    'ra-button--listening': state.isListening,
    'ra-button--processing': state.isProcessing
  }
];

const formatTime = (date: Date) => {
  return new Intl.DateTimeFormat('default', {
    hour: 'numeric',
    minute: 'numeric',
    second: 'numeric'
  }).format(date);
};

// Auto-scroll conversation
watch(conversation, async () => {
  await nextTick();
  if (conversationRef.value) {
    conversationRef.value.scrollTop = conversationRef.value.scrollHeight;
  }
});
</script>

<style scoped>
.ra-voice-chat {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 500px;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  background: white;
  overflow: hidden;
}

.ra-voice-chat__header {
  padding: 16px;
  border-bottom: 1px solid #e5e7eb;
  background: #f9fafb;
}

.ra-voice-chat__title {
  margin: 0 0 8px 0;
  font-size: 18px;
  font-weight: 600;
  color: #111827;
}

.ra-voice-chat__metrics {
  display: flex;
  gap: 16px;
  font-size: 12px;
  color: #6b7280;
}

.ra-voice-chat__conversation {
  flex: 1;
  padding: 16px;
  overflow-y: auto;
  background: white;
}

.ra-voice-chat__placeholder {
  text-align: center;
  color: #9ca3af;
  font-style: italic;
  margin-top: 48px;
}

.ra-message {
  margin-bottom: 16px;
  padding: 12px;
  border-radius: 8px;
  animation: slideIn 0.3s ease;
}

.ra-message--user {
  background: #f3f4f6;
  border-left: 4px solid #10b981;
}

.ra-message--assistant {
  background: #dbeafe;
  border-left: 4px solid #3b82f6;
}

.ra-message__header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 8px;
  font-size: 12px;
  color: #6b7280;
}

.ra-message__content {
  color: #111827;
  line-height: 1.5;
}

.ra-voice-chat__processing {
  padding: 12px;
  background: #fef3c7;
  border-radius: 8px;
  font-style: italic;
  color: #92400e;
  display: flex;
  align-items: center;
  gap: 8px;
}

.ra-voice-chat__controls {
  padding: 16px;
  border-top: 1px solid #e5e7eb;
  background: #f9fafb;
  display: flex;
  gap: 12px;
  align-items: center;
}

.ra-button {
  padding: 10px 20px;
  border: none;
  border-radius: 6px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s;
  display: inline-flex;
  align-items: center;
  gap: 8px;
}

.ra-button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.ra-button--primary {
  background: #10b981;
  color: white;
}

.ra-button--primary:hover:not(:disabled) {
  background: #059669;
}

.ra-button--listening {
  background: #ef4444;
}

.ra-button--listening:hover:not(:disabled) {
  background: #dc2626;
}

.ra-button--processing {
  background: #f59e0b;
}

.ra-button--secondary {
  background: #6b7280;
  color: white;
}

.ra-button--secondary:hover:not(:disabled) {
  background: #4b5563;
}

.ra-voice-chat__status {
  display: flex;
  gap: 12px;
  margin-left: auto;
  align-items: center;
}

.ra-status {
  padding: 4px 12px;
  border-radius: 12px;
  font-size: 12px;
  font-weight: 500;
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.ra-status--listening {
  background: #d1fae5;
  color: #065f46;
}

.ra-status--processing {
  background: #fed7aa;
  color: #92400e;
}

.ra-status--playing {
  background: #dbeafe;
  color: #1e40af;
}

.ra-voice-chat__error {
  position: absolute;
  bottom: 80px;
  left: 16px;
  right: 16px;
  padding: 12px;
  background: #fef2f2;
  border: 1px solid #fecaca;
  border-radius: 6px;
  color: #dc2626;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.ra-error__close {
  background: none;
  border: none;
  color: #dc2626;
  cursor: pointer;
  font-size: 18px;
  padding: 0;
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.ra-pulse {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: currentColor;
  animation: pulse 1.5s infinite;
}

@keyframes pulse {
  0%, 100% {
    opacity: 1;
  }
  50% {
    opacity: 0.5;
  }
}

@keyframes slideIn {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.message-enter-active,
.message-leave-active {
  transition: all 0.3s ease;
}

.message-enter-from {
  opacity: 0;
  transform: translateX(-30px);
}

.message-leave-to {
  opacity: 0;
  transform: translateX(30px);
}

.processing-enter-active,
.processing-leave-active {
  transition: all 0.3s ease;
}

.processing-enter-from,
.processing-leave-to {
  opacity: 0;
  transform: translateY(10px);
}

.error-enter-active,
.error-leave-active {
  transition: all 0.3s ease;
}

.error-enter-from,
.error-leave-to {
  opacity: 0;
  transform: translateY(20px);
}
</style>
