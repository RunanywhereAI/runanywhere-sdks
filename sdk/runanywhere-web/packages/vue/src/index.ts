// Composables
export { useVoicePipeline } from './composables/useVoicePipeline';

// Components
export { default as VoiceChat } from './components/VoiceChat.vue';
export { default as VoicePipelineButton } from './components/VoicePipelineButton.vue';

// Types
export type {
  VoicePipelineConfig,
  ConversationEntry,
  VoicePipelineState,
  VoiceMetrics
} from './types';

// Re-export core types for convenience
export type {
  EnhancedPipelineConfig,
  EnhancedPipelineEvents
} from '@runanywhere/voice';

// Vue plugin for easy installation
import type { App } from 'vue';
import VoiceChat from './components/VoiceChat.vue';
import VoicePipelineButton from './components/VoicePipelineButton.vue';

export default {
  install(app: App) {
    app.component('VoiceChat', VoiceChat);
    app.component('VoicePipelineButton', VoicePipelineButton);
  }
};
