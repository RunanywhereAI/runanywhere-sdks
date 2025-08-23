import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';

// Components
import { VoiceChatComponent } from '../components/voice-chat.component';
import { VoicePipelineButtonComponent } from '../components/voice-pipeline-button.component';

// Services
import { VoicePipelineService } from '../services/voice-pipeline.service';

@NgModule({
  imports: [
    CommonModule,
    // Import standalone components
    VoiceChatComponent,
    VoicePipelineButtonComponent
  ],
  exports: [
    // Export components for use in applications
    VoiceChatComponent,
    VoicePipelineButtonComponent
  ],
  providers: [
    // Service is provided at root level via @Injectable({ providedIn: 'root' })
    // but can be explicitly provided here if needed for specific use cases
  ]
})
export class RunAnywhereVoiceModule { }
