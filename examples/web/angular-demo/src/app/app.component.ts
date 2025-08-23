import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Observable } from 'rxjs';
import {
  VoicePipelineService,
  VoiceChatComponent,
  VoicePipelineButtonComponent,
  type VoicePipelineConfig,
  type ConversationEntry,
  type VoiceMetrics,
  type VoicePipelineState
} from '@runanywhere/angular';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, VoiceChatComponent, VoicePipelineButtonComponent],
  template: `
    <div class="container">
      <header>
        <h1>🎤 RunAnywhere Voice AI - Angular Example</h1>
        <p>Powered by Angular + RunAnywhere Web SDK</p>
      </header>

      <main>
        <section class="controls">
          <h2>Voice Pipeline Controls</h2>
          <div class="status">
            <div class="status-item">
              <span class="label">Status:</span>
              <span [class]="'value ' + getStatusClass()">{{ getStatusText() }}</span>
            </div>
            <div class="status-item" *ngIf="currentState.error">
              <span class="label">Error:</span>
              <span class="value error">{{ currentState.error.message }}</span>
            </div>
          </div>

          <div class="button-group">
            <button
              (click)="initializePipeline()"
              [disabled]="currentState.isInitialized"
              class="btn btn-primary">
              Initialize Pipeline
            </button>
            <runanywhere-voice-pipeline-button
              [config]="pipelineConfig"
              [customButtonText]="buttonText"
              (transcription)="handleTranscription($event)"
              (llmResponse)="handleLLMResponse($event)"
              (error)="handleError($event)"
              class="btn btn-voice">
            </runanywhere-voice-pipeline-button>
          </div>
        </section>

        <section class="conversation">
          <h2>Conversation History</h2>
          <div class="conversation-container">
            <div
              *ngFor="let entry of currentConversation"
              [class]="'message ' + entry.type">
              <div class="message-header">
                <span class="speaker">{{ entry.type === 'user' ? '🗣️ You' : '🤖 AI Assistant' }}</span>
                <span class="timestamp">{{ formatTime(entry.timestamp) }}</span>
              </div>
              <div class="message-content">{{ entry.text }}</div>
            </div>
            <div *ngIf="currentConversation.length === 0" class="no-messages">
              No conversation yet. Click the voice button to start!
            </div>
          </div>
        </section>

        <section class="metrics">
          <h2>Performance Metrics</h2>
          <div class="metrics-grid">
            <div class="metric">
              <span class="metric-label">VAD Latency</span>
              <span class="metric-value">{{ currentMetrics.vadLatency.toFixed(2) }}ms</span>
            </div>
            <div class="metric">
              <span class="metric-label">STT Latency</span>
              <span class="metric-value">{{ currentMetrics.sttLatency.toFixed(2) }}ms</span>
            </div>
            <div class="metric">
              <span class="metric-label">LLM Latency</span>
              <span class="metric-value">{{ currentMetrics.llmLatency.toFixed(2) }}ms</span>
            </div>
            <div class="metric">
              <span class="metric-label">TTS Latency</span>
              <span class="metric-value">{{ currentMetrics.ttsLatency.toFixed(2) }}ms</span>
            </div>
            <div class="metric">
              <span class="metric-label">Total Latency</span>
              <span class="metric-value">{{ currentMetrics.totalLatency.toFixed(2) }}ms</span>
            </div>
          </div>
        </section>

        <runanywhere-voice-chat
          [config]="pipelineConfig"
          class="voice-chat-component">
        </runanywhere-voice-chat>
      </main>
    </div>
  `,
  styleUrls: ['./app.component.css']
})
export class AppComponent implements OnInit, OnDestroy {
  pipelineConfig: VoicePipelineConfig = {
    enableTranscription: true,
    enableLLM: true,
    enableTTS: true,
    autoPlayTTS: true,
    maxHistorySize: 50
  };

  buttonText = {
    initialize: 'Initialize Voice',
    ready: 'Start Voice Chat',
    listening: 'Listening... (Click to Stop)',
    processing: 'Processing...'
  };

  currentState: VoicePipelineState = {
    isInitialized: false,
    isListening: false,
    isProcessing: false,
    isPlaying: false,
    error: null
  };

  currentConversation: ConversationEntry[] = [];

  currentMetrics: VoiceMetrics = {
    vadLatency: 0,
    sttLatency: 0,
    llmLatency: 0,
    ttsLatency: 0,
    totalLatency: 0
  };

  constructor(private voicePipelineService: VoicePipelineService) {}

  ngOnInit() {
    // Subscribe to state changes
    this.voicePipelineService.state$.subscribe(state => {
      this.currentState = state;
    });

    // Subscribe to conversation changes
    this.voicePipelineService.conversation$.subscribe(conversation => {
      this.currentConversation = conversation;
    });

    // Subscribe to metrics changes
    this.voicePipelineService.metrics$.subscribe(metrics => {
      this.currentMetrics = metrics;
    });
  }

  ngOnDestroy() {
    this.voicePipelineService.destroy();
  }

  async initializePipeline() {
    try {
      await this.voicePipelineService.initialize(this.pipelineConfig);
    } catch (error) {
      console.error('Failed to initialize pipeline:', error);
    }
  }

  handleTranscription(result: any) {
    console.log('🎤 Transcription:', result.text);
  }

  handleLLMResponse(result: any) {
    console.log('🤖 LLM Response:', result.text);
  }

  handleError(error: Error) {
    console.error('❌ Voice Pipeline Error:', error);
  }

  getStatusClass(): string {
    if (this.currentState.error) return 'error';
    if (this.currentState.isPlaying) return 'playing';
    if (this.currentState.isProcessing) return 'processing';
    if (this.currentState.isListening) return 'listening';
    if (this.currentState.isInitialized) return 'ready';
    return 'idle';
  }

  getStatusText(): string {
    if (this.currentState.error) return 'Error';
    if (this.currentState.isPlaying) return 'Playing TTS';
    if (this.currentState.isProcessing) return 'Processing';
    if (this.currentState.isListening) return 'Listening';
    if (this.currentState.isInitialized) return 'Ready';
    return 'Not Initialized';
  }

  formatTime(timestamp: Date): string {
    return timestamp.toLocaleTimeString();
  }
}
