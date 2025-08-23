import {
  Component,
  Input,
  OnInit,
  OnDestroy,
  ViewChild,
  ElementRef,
  ChangeDetectionStrategy
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { Subject, Observable } from 'rxjs';
import { takeUntil, tap } from 'rxjs/operators';
import { VoicePipelineService } from '../services/voice-pipeline.service';
import type { VoicePipelineConfig, ConversationEntry, VoicePipelineState, VoiceMetrics } from '../types';

@Component({
  selector: 'ra-voice-chat',
  standalone: true,
  imports: [CommonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="ra-voice-chat" [ngClass]="chatClasses">
      <div class="ra-voice-chat__header">
        <h3 class="ra-voice-chat__title">{{ title }}</h3>
        <div class="ra-voice-chat__metrics" *ngIf="showMetrics">
          <span>VAD: {{ (metrics$ | async)?.vadLatency }}ms</span>
          <span>STT: {{ (metrics$ | async)?.sttLatency }}ms</span>
          <span>LLM: {{ (metrics$ | async)?.llmLatency }}ms</span>
          <span>TTS: {{ (metrics$ | async)?.ttsLatency }}ms</span>
        </div>
      </div>

      <div class="ra-voice-chat__conversation" #conversationContainer>
        <div
          *ngFor="let entry of conversation$ | async; trackBy: trackByEntryId"
          [class]="getMessageClass(entry)"
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

        <div *ngIf="(conversation$ | async)?.length === 0" class="ra-voice-chat__placeholder">
          {{ placeholder }}
        </div>

        <div
          *ngIf="(state$ | async)?.isProcessing && !(state$ | async)?.isPlaying"
          class="ra-voice-chat__processing"
        >
          <span class="ra-pulse"></span>
          🎤 Listening for speech...
        </div>
      </div>

      <div class="ra-voice-chat__controls">
        <button
          (click)="toggleListening()"
          [disabled]="(state$ | async)?.isProcessing && !(state$ | async)?.isListening"
          [class]="getButtonClass()"
        >
          <span *ngIf="(state$ | async)?.isListening" class="ra-pulse"></span>
          {{ buttonText$ | async }}
        </button>

        <button
          (click)="clearConversation()"
          class="ra-button ra-button--secondary"
          [disabled]="(conversation$ | async)?.length === 0"
        >
          Clear
        </button>

        <div class="ra-voice-chat__status">
          <span *ngIf="(state$ | async)?.isListening" class="ra-status ra-status--listening">
            🎤 Listening
          </span>
          <span *ngIf="(state$ | async)?.isProcessing" class="ra-status ra-status--processing">
            ⚡ Processing
          </span>
          <span *ngIf="(state$ | async)?.isPlaying" class="ra-status ra-status--playing">
            🔊 Playing
          </span>
        </div>
      </div>

      <div *ngIf="(state$ | async)?.error" class="ra-voice-chat__error">
        <span>⚠️ {{ (state$ | async)?.error?.message }}</span>
        <button (click)="clearError()" class="ra-error__close">✕</button>
      </div>
    </div>
  `,
  styles: [`
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

    .ra-voice-chat--listening .ra-voice-chat__header {
      background: #d1fae5;
    }

    .ra-voice-chat--processing .ra-voice-chat__header {
      background: #fed7aa;
    }

    .ra-voice-chat--error .ra-voice-chat__header {
      background: #fef2f2;
    }
  `]
})
export class VoiceChatComponent implements OnInit, OnDestroy {
  @Input() config: VoicePipelineConfig = {};
  @Input() title = 'Voice Assistant';
  @Input() autoStart = false;
  @Input() showMetrics = true;
  @Input() placeholder = "Click 'Start Listening' to begin voice conversation";

  @ViewChild('conversationContainer', { static: true })
  conversationContainer!: ElementRef<HTMLDivElement>;

  private destroy$ = new Subject<void>();

  // Observables from service
  state$: Observable<VoicePipelineState>;
  conversation$: Observable<ConversationEntry[]>;
  metrics$: Observable<VoiceMetrics>;
  buttonText$: Observable<string>;

  constructor(private voicePipelineService: VoicePipelineService) {
    this.state$ = this.voicePipelineService.state$;
    this.conversation$ = this.voicePipelineService.conversation$.pipe(
      tap(() => {
        // Auto-scroll conversation
        setTimeout(() => this.scrollToBottom(), 100);
      })
    );
    this.metrics$ = this.voicePipelineService.metrics$;
    this.buttonText$ = this.voicePipelineService.buttonText$;
  }

  get chatClasses(): { [key: string]: boolean } {
    const state = this.voicePipelineService.state$;
    return {
      'ra-voice-chat--listening': false, // Will be updated by async pipe in template
      'ra-voice-chat--processing': false,
      'ra-voice-chat--playing': false,
      'ra-voice-chat--error': false
    };
  }

  async ngOnInit(): Promise<void> {
    try {
      await this.voicePipelineService.initialize(this.config);
      if (this.autoStart) {
        await this.voicePipelineService.start();
      }
    } catch (error) {
      console.error('Failed to initialize voice pipeline:', error);
    }
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
    this.voicePipelineService.stop();
  }

  async toggleListening(): Promise<void> {
    try {
      const currentState = this.voicePipelineService.currentState;

      if (!currentState.isInitialized) {
        await this.voicePipelineService.initialize(this.config);
      } else if (currentState.isListening) {
        await this.voicePipelineService.stop();
      } else {
        await this.voicePipelineService.start();
      }
    } catch (error) {
      console.error('Voice pipeline error:', error);
    }
  }

  clearConversation(): void {
    this.voicePipelineService.clearConversation();
  }

  clearError(): void {
    this.voicePipelineService.clearError();
  }

  trackByEntryId(index: number, entry: ConversationEntry): string {
    return entry.id;
  }

  getMessageClass(entry: ConversationEntry): string {
    return `ra-message ra-message--${entry.type}`;
  }

  getButtonClass(): string {
    // This will be updated by template with async pipe
    return 'ra-button ra-button--primary';
  }

  formatTime(date: Date): string {
    return new Intl.DateTimeFormat('default', {
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric'
    }).format(date);
  }

  private scrollToBottom(): void {
    if (this.conversationContainer?.nativeElement) {
      const element = this.conversationContainer.nativeElement;
      element.scrollTop = element.scrollHeight;
    }
  }
}
