import React from 'react';
import { useVoicePipeline, UseVoicePipelineOptions } from '../hooks/useVoicePipeline';

export interface VoicePipelineButtonProps extends UseVoicePipelineOptions {
  children?: React.ReactNode;
  className?: string;
  style?: React.CSSProperties;
  onTranscription?: (text: string) => void;
  onLLMResponse?: (text: string) => void;
  onError?: (error: Error) => void;
}

export function VoicePipelineButton({
  children,
  className,
  style,
  onTranscription,
  onLLMResponse,
  onError,
  ...pipelineOptions
}: VoicePipelineButtonProps) {
  const [state, actions] = useVoicePipeline(pipelineOptions);

  // Handle callbacks
  React.useEffect(() => {
    if (state.transcription && onTranscription) {
      onTranscription(state.transcription);
    }
  }, [state.transcription, onTranscription]);

  React.useEffect(() => {
    if (state.llmResponse && onLLMResponse) {
      onLLMResponse(state.llmResponse);
    }
  }, [state.llmResponse, onLLMResponse]);

  React.useEffect(() => {
    if (state.error && onError) {
      onError(state.error);
    }
  }, [state.error, onError]);

  const handleClick = async () => {
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

  const getButtonText = () => {
    if (!state.isInitialized) {
      return 'Initialize Voice';
    }
    if (state.isProcessing) {
      return 'Processing...';
    }
    if (state.isListening) {
      return 'Stop Listening';
    }
    return 'Start Listening';
  };

  const getButtonState = () => {
    if (state.error) return 'error';
    if (state.isProcessing) return 'processing';
    if (state.isListening) return 'listening';
    if (state.isInitialized) return 'ready';
    return 'init';
  };

  return (
    <button
      onClick={handleClick}
      className={className}
      style={style}
      disabled={state.isProcessing}
      data-state={getButtonState()}
    >
      {children || getButtonText()}
    </button>
  );
}
