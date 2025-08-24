'use client';

import { useState, useCallback, useRef, useEffect } from 'react';

interface VoiceAssistantConfig {
  apiKey: string;
  useLocalModels?: boolean;
  volume?: number;
  speed?: number;
}

export function useVoiceAssistant(config: VoiceAssistantConfig) {
  const [isListening, setIsListening] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [response, setResponse] = useState('');
  const [error, setError] = useState<string | null>(null);

  const recognitionRef = useRef<any>(null);
  const synthRef = useRef<SpeechSynthesisUtterance | null>(null);

  // Initialize Web Speech API
  useEffect(() => {
    if (!config.apiKey) return;

    try {
      // Initialize Web Speech API for recognition
      if (typeof window !== 'undefined' && 'webkitSpeechRecognition' in window) {
        const SpeechRecognition = (window as any).webkitSpeechRecognition;
        recognitionRef.current = new SpeechRecognition();
        recognitionRef.current.continuous = false;
        recognitionRef.current.interimResults = true;
        recognitionRef.current.lang = 'en-US';

        recognitionRef.current.onresult = (event: any) => {
          const current = event.resultIndex;
          const transcript = event.results[current][0].transcript;
          setTranscript(transcript);

          if (event.results[current].isFinal) {
            handleTranscriptComplete(transcript);
          }
        };

        recognitionRef.current.onerror = (event: any) => {
          console.error('Speech recognition error:', event.error);
          setError(`Speech recognition error: ${event.error}`);
          setIsListening(false);
        };

        recognitionRef.current.onend = () => {
          setIsListening(false);
        };
      } else {
        console.warn('Web Speech API not supported');
        setError('Speech recognition is not supported in your browser');
      }

      // Initialize Speech Synthesis
      if ('speechSynthesis' in window) {
        synthRef.current = new SpeechSynthesisUtterance();
        synthRef.current.volume = config.volume || 0.7;
        synthRef.current.rate = config.speed || 1.0;
      }
    } catch (err) {
      console.error('Failed to initialize voice assistant:', err);
      setError('Failed to initialize voice assistant');
    }

    return () => {
      // Cleanup
      if (recognitionRef.current) {
        try {
          recognitionRef.current.stop();
        } catch (e) {
          // Ignore errors during cleanup
        }
      }
      if (window.speechSynthesis) {
        window.speechSynthesis.cancel();
      }
    };
  }, [config.apiKey, config.volume, config.speed]);

  const handleTranscriptComplete = async (text: string) => {
    setIsProcessing(true);
    setResponse('');

    try {
      // Process with OpenAI
      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${config.apiKey}`,
        },
        body: JSON.stringify({
          model: 'gpt-4-turbo-preview',
          messages: [
            { role: 'system', content: 'You are a helpful assistant. Keep responses concise and friendly.' },
            { role: 'user', content: text }
          ],
          temperature: 0.7,
          max_tokens: 150,
          stream: true,
        }),
      });

      if (!response.ok) {
        throw new Error('Failed to get AI response');
      }

      // Handle streaming response
      const reader = response.body?.getReader();
      const decoder = new TextDecoder();
      let accumulatedResponse = '';

      if (reader) {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          const chunk = decoder.decode(value);
          const lines = chunk.split('\n');

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const data = line.slice(6);
              if (data === '[DONE]') continue;

              try {
                const parsed = JSON.parse(data);
                const content = parsed.choices?.[0]?.delta?.content;
                if (content) {
                  accumulatedResponse += content;
                  setResponse(accumulatedResponse);
                }
              } catch (e) {
                // Ignore parse errors
              }
            }
          }
        }
      }

      // Speak the response using Web Speech API
      if (synthRef.current && accumulatedResponse && window.speechSynthesis) {
        synthRef.current.text = accumulatedResponse;
        window.speechSynthesis.speak(synthRef.current);
      }
    } catch (err) {
      console.error('Error processing transcript:', err);
      setError('Failed to process your request. Please check your API key.');
    } finally {
      setIsProcessing(false);
    }
  };

  const startListening = useCallback(() => {
    if (!recognitionRef.current) {
      setError('Speech recognition not available');
      return;
    }

    setError(null);
    setTranscript('');
    setResponse('');
    setIsListening(true);

    try {
      recognitionRef.current.start();
    } catch (err) {
      console.error('Failed to start listening:', err);
      setError('Failed to start listening');
      setIsListening(false);
    }
  }, []);

  const stopListening = useCallback(() => {
    if (recognitionRef.current && isListening) {
      recognitionRef.current.stop();
      setIsListening(false);
    }
  }, [isListening]);

  const toggleListening = useCallback(() => {
    if (isListening) {
      stopListening();
    } else {
      startListening();
    }
  }, [isListening, startListening, stopListening]);

  return {
    isListening,
    isProcessing,
    transcript,
    response,
    error,
    startListening,
    stopListening,
    toggleListening,
  };
}
