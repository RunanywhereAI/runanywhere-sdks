// Angular Voice Pipeline Integration

// Module
export { RunAnywhereVoiceModule } from './lib/runanywhere-voice.module';

// Services
export { VoicePipelineService } from './services/voice-pipeline.service';

// Components
export { VoiceChatComponent } from './components/voice-chat.component';
export { VoicePipelineButtonComponent } from './components/voice-pipeline-button.component';

// Types
export type {
  VoicePipelineConfig,
  ConversationEntry,
  VoicePipelineState,
  VoiceMetrics
} from './types';

// Button component types
export type { CustomButtonText } from './components/voice-pipeline-button.component';

// Re-export core types for convenience
export type {
  EnhancedPipelineConfig,
  EnhancedPipelineEvents
} from '@runanywhere/voice';
