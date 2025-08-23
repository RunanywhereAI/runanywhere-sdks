import { ref, reactive, computed, onUnmounted, readonly } from 'vue';
import { DIContainer, Result } from '@runanywhere/core';
import { EnhancedVoicePipelineManager } from '@runanywhere/voice';
import type { VoicePipelineConfig, ConversationEntry, VoicePipelineState, VoiceMetrics } from '../types';

export function useVoicePipeline(config: VoicePipelineConfig = {}) {
  const pipeline = ref<EnhancedVoicePipelineManager | null>(null);
  const container = ref<DIContainer | null>(null);

  const state = reactive<VoicePipelineState>({
    isInitialized: false,
    isListening: false,
    isProcessing: false,
    isPlaying: false,
    error: null
  });

  const conversation = ref<ConversationEntry[]>([]);
  const metrics = reactive<VoiceMetrics>({
    vadLatency: 0,
    sttLatency: 0,
    llmLatency: 0,
    ttsLatency: 0,
    totalLatency: 0
  });

  const buttonText = computed(() => {
    if (!state.isInitialized) return 'Initialize Voice';
    if (state.isProcessing) return 'Processing...';
    if (state.isListening) return 'Stop Listening';
    return 'Start Listening';
  });

  const isReady = computed(() => state.isInitialized && !state.error);

  const initialize = async () => {
    try {
      container.value = new DIContainer();
      pipeline.value = new EnhancedVoicePipelineManager(
        container.value as DIContainer,
        config
      );

      setupEventHandlers();

      const result = await pipeline.value.initialize();
      if (Result.isErr(result)) {
        throw result.error;
      }

      state.isInitialized = true;
      state.error = null;
    } catch (error) {
      state.error = error instanceof Error ? error : new Error(String(error));
      throw state.error;
    }
  };

  const setupEventHandlers = () => {
    if (!pipeline.value) return;

    pipeline.value.on('started', () => {
      state.isListening = true;
    });

    pipeline.value.on('stopped', () => {
      state.isListening = false;
      state.isProcessing = false;
    });

    pipeline.value.on('vadSpeechStart', () => {
      state.isProcessing = true;
    });

    pipeline.value.on('vadSpeechEnd', () => {
      // Keep processing true until transcription completes
    });

    pipeline.value.on('transcription', (result) => {
      conversation.value.push({
        id: `user-${Date.now()}`,
        type: 'user',
        text: result.text,
        timestamp: new Date()
      });
      metrics.sttLatency = result.latency || 0;
      updateTotalLatency();
    });

    pipeline.value.on('llmResponse', (result) => {
      conversation.value.push({
        id: `assistant-${Date.now()}`,
        type: 'assistant',
        text: result.text,
        timestamp: new Date()
      });
      metrics.llmLatency = result.latency || 0;
      updateTotalLatency();
      state.isProcessing = false;
    });

    pipeline.value.on('ttsPlaybackStart', () => {
      state.isPlaying = true;
    });

    pipeline.value.on('ttsPlaybackEnd', () => {
      state.isPlaying = false;
    });

    pipeline.value.on('error', (error) => {
      state.error = error;
      state.isProcessing = false;
      state.isPlaying = false;
    });
  };

  const updateTotalLatency = () => {
    metrics.totalLatency =
      metrics.vadLatency +
      metrics.sttLatency +
      metrics.llmLatency +
      metrics.ttsLatency;
  };

  const start = async () => {
    if (!pipeline.value) {
      throw new Error('Pipeline not initialized. Call initialize() first.');
    }
    try {
      state.error = null;
      await pipeline.value.start();
    } catch (error) {
      state.error = error instanceof Error ? error : new Error(String(error));
      throw state.error;
    }
  };

  const stop = async () => {
    if (!pipeline.value) return;
    try {
      await pipeline.value.stop();
    } catch (error) {
      state.error = error instanceof Error ? error : new Error(String(error));
      throw state.error;
    }
  };

  const clearConversation = () => {
    conversation.value = [];
  };

  const clearError = () => {
    state.error = null;
  };

  const destroy = () => {
    if (pipeline.value) {
      pipeline.value.destroy();
      pipeline.value = null;
    }
    if (container.value) {
      container.value = null;
    }
    state.isInitialized = false;
    state.isListening = false;
    state.isProcessing = false;
    state.isPlaying = false;
  };

  // Auto-cleanup on unmount
  onUnmounted(() => {
    destroy();
  });

  // Auto-initialize if requested
  if (config.autoInitialize) {
    initialize().then(() => {
      if (config.autoStart) {
        start();
      }
    }).catch(console.error);
  }

  return {
    // State (readonly to prevent direct mutation)
    state: readonly(state),
    conversation: readonly(conversation),
    metrics: readonly(metrics),

    // Computed properties
    buttonText,
    isReady,

    // Methods
    initialize,
    start,
    stop,
    clearConversation,
    clearError,
    destroy
  };
}
