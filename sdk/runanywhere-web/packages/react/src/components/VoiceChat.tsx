import React, { useState } from 'react';
import { useVoicePipeline, UseVoicePipelineOptions } from '../hooks/useVoicePipeline';

export interface VoiceChatProps extends UseVoicePipelineOptions {
  className?: string;
  style?: React.CSSProperties;
  placeholder?: string;
  showTranscription?: boolean;
  showLLMResponse?: boolean;
  onConversationUpdate?: (conversation: ConversationEntry[]) => void;
}

export interface ConversationEntry {
  id: string;
  type: 'user' | 'assistant';
  text: string;
  timestamp: Date;
}

export function VoiceChat({
  className,
  style,
  placeholder = "Click 'Start Listening' to begin voice conversation",
  showTranscription = true,
  showLLMResponse = true,
  onConversationUpdate,
  ...pipelineOptions
}: VoiceChatProps) {
  const [state, actions] = useVoicePipeline(pipelineOptions);
  const [conversation, setConversation] = useState<ConversationEntry[]>([]);

  // Add transcription to conversation
  React.useEffect(() => {
    if (state.transcription) {
      const entry: ConversationEntry = {
        id: `user-${Date.now()}`,
        type: 'user',
        text: state.transcription,
        timestamp: new Date()
      };

      setConversation(prev => {
        const updated = [...prev, entry];
        onConversationUpdate?.(updated);
        return updated;
      });
    }
  }, [state.transcription, onConversationUpdate]);

  // Add LLM response to conversation
  React.useEffect(() => {
    if (state.llmResponse) {
      const entry: ConversationEntry = {
        id: `assistant-${Date.now()}`,
        type: 'assistant',
        text: state.llmResponse,
        timestamp: new Date()
      };

      setConversation(prev => {
        const updated = [...prev, entry];
        onConversationUpdate?.(updated);
        return updated;
      });
    }
  }, [state.llmResponse, onConversationUpdate]);

  const handleStartStop = async () => {
    try {
      if (!state.isInitialized) {
        await actions.initialize();
      } else if (state.isListening) {
        await actions.stop();
      } else {
        await actions.start();
      }
    } catch (error) {
      console.error('Voice pipeline error:', error);
    }
  };

  const clearConversation = () => {
    setConversation([]);
    onConversationUpdate?.([]);
  };

  return (
    <div className={className} style={style}>
      {/* Controls */}
      <div style={{ marginBottom: '16px', display: 'flex', gap: '8px', alignItems: 'center' }}>
        <button
          onClick={handleStartStop}
          disabled={state.isProcessing}
          style={{
            padding: '8px 16px',
            backgroundColor: state.isListening ? '#ef4444' : '#10b981',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: state.isProcessing ? 'not-allowed' : 'pointer'
          }}
        >
          {!state.isInitialized && 'Initialize Voice'}
          {state.isInitialized && state.isProcessing && 'Processing...'}
          {state.isInitialized && !state.isProcessing && state.isListening && 'Stop Listening'}
          {state.isInitialized && !state.isProcessing && !state.isListening && 'Start Listening'}
        </button>

        <button
          onClick={clearConversation}
          style={{
            padding: '8px 16px',
            backgroundColor: '#6b7280',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer'
          }}
        >
          Clear
        </button>

        {/* Status indicators */}
        <div style={{ marginLeft: 'auto', display: 'flex', gap: '8px', alignItems: 'center' }}>
          {state.isListening && (
            <span style={{ color: '#10b981' }}>🎤 Listening</span>
          )}
          {state.isProcessing && (
            <span style={{ color: '#f59e0b' }}>⚡ Processing</span>
          )}
          {state.isPlaying && (
            <span style={{ color: '#3b82f6' }}>🔊 Playing</span>
          )}
        </div>
      </div>

      {/* Error display */}
      {state.error && (
        <div style={{
          padding: '12px',
          backgroundColor: '#fef2f2',
          border: '1px solid #fecaca',
          borderRadius: '4px',
          color: '#dc2626',
          marginBottom: '16px'
        }}>
          Error: {state.error.message}
        </div>
      )}

      {/* Conversation */}
      <div style={{
        border: '1px solid #e5e7eb',
        borderRadius: '8px',
        height: '400px',
        overflowY: 'auto',
        padding: '16px',
        backgroundColor: '#ffffff'
      }}>
        {conversation.length === 0 ? (
          <div style={{
            color: '#6b7280',
            fontStyle: 'italic',
            textAlign: 'center',
            marginTop: '50px'
          }}>
            {placeholder}
          </div>
        ) : (
          conversation.map((entry) => (
            <div
              key={entry.id}
              style={{
                marginBottom: '16px',
                padding: '12px',
                borderRadius: '8px',
                backgroundColor: entry.type === 'user' ? '#f3f4f6' : '#dbeafe',
                borderLeft: `4px solid ${entry.type === 'user' ? '#10b981' : '#3b82f6'}`
              }}
            >
              <div style={{
                fontSize: '12px',
                color: '#6b7280',
                marginBottom: '4px'
              }}>
                {entry.type === 'user' ? '👤 You' : '🤖 Assistant'} • {entry.timestamp.toLocaleTimeString()}
              </div>
              <div>{entry.text}</div>
            </div>
          ))
        )}

        {/* Live transcription preview */}
        {showTranscription && state.isProcessing && (
          <div style={{
            padding: '12px',
            backgroundColor: '#fef3c7',
            borderRadius: '8px',
            fontStyle: 'italic',
            color: '#92400e'
          }}>
            🎤 Listening for speech...
          </div>
        )}
      </div>
    </div>
  );
}
