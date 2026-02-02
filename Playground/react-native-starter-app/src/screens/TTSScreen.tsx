/**
 * TTSScreen - Tab 2: Text-to-Speech
 *
 * Provides on-device text-to-speech synthesis with voice selection.
 * Matches iOS TextToSpeechView architecture and patterns.
 *
 * Features:
 * - Text input for synthesis
 * - Voice/model selection
 * - Audio playback controls
 * - Model status banner
 * - System TTS fallback
 *
 * Architecture:
 * - Model loading via RunAnywhere.loadTTSModel()
 * - Speech synthesis via RunAnywhere.synthesizeSpeech()
 * - Audio playback via native audio player
 * - Supports ONNX-based Piper TTS models
 *
 * Reference: iOS examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/TextToSpeechView.swift
 */

import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  SafeAreaView,
  TouchableOpacity,
  ScrollView,
  Alert,
  Platform,
  NativeModules,
} from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { useFocusEffect } from '@react-navigation/native';
import RNFS from 'react-native-fs';

// Native iOS Audio Module
const NativeAudioModule =
  Platform.OS === 'ios' ? NativeModules.NativeAudioModule : null;

// Audio playback using react-native-sound (Android only - iOS uses NativeAudioModule)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let Sound: any = null;
let soundInitialized = false;

function getSound() {
  if (Platform.OS === 'ios') {
    return null; // iOS uses NativeAudioModule instead
  }
  if (!Sound) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      Sound = require('react-native-sound').default;
      if (!soundInitialized) {
        Sound.setCategory('Playback');
        soundInitialized = true;
      }
    } catch (e) {
      console.warn('[TTSScreen] react-native-sound not available');
      return null;
    }
  }
  return Sound;
}

// Lazy load Tts for System TTS (Android only)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let Tts: any = null;
function getTts() {
  if (Platform.OS === 'ios') {
    return null; // Disabled on iOS due to bridgeless=NO requirement for Nitrogen
  }
  if (!Tts) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      Tts = require('react-native-tts').default;
    } catch (e) {
      console.warn('[TTSScreen] react-native-tts not available');
      return null;
    }
  }
  return Tts;
}
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import {
  Spacing,
  Padding,
  BorderRadius,
  ButtonHeight,
  Layout,
} from '../theme/spacing';
import { ModelStatusBanner, ModelRequiredOverlay } from '../components/common';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';
import type { ModelInfo } from '../types/model';
import { ModelModality, LLMFramework } from '../types/model';

// Import RunAnywhere SDK (Multi-Package Architecture)
import { RunAnywhere, type ModelInfo as SDKModelInfo } from '@runanywhere/core';

export const TTSScreen: React.FC = () => {
  // State
  const [text, setText] = useState('');
  const [speed, setSpeed] = useState(1.0);
  const [pitch, setPitch] = useState(1.0);
  const [volume, setVolume] = useState(1.0);
  const [isGenerating, setIsGenerating] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [audioGenerated, setAudioGenerated] = useState(false);
  const [duration, setDuration] = useState(0);
  const [currentModel, setCurrentModel] = useState<ModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [_lastGeneratedAudio, setLastGeneratedAudio] = useState<string | null>(
    null
  );
  const [currentTime, setCurrentTime] = useState(0);
  const [playbackProgress, setPlaybackProgress] = useState(0);
  const [audioFilePath, setAudioFilePath] = useState<string | null>(null);
  const [sampleRate, setSampleRate] = useState(22050);
  const [showModelSelection, setShowModelSelection] = useState(false);

  // Audio player refs - using react-native-sound directly
  const soundRef = useRef<typeof Sound | null>(null);
  const progressIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Character count
  const charCount = text.length;
  const maxChars = 1000;

  // Helper to stop progress updates
  const stopProgressUpdates = useCallback(() => {
    if (progressIntervalRef.current) {
      clearInterval(progressIntervalRef.current);
      progressIntervalRef.current = null;
    }
  }, []);

  // Helper to stop sound playback
  const stopSound = useCallback(async () => {
    stopProgressUpdates();

    // iOS: Stop NativeAudioModule
    if (Platform.OS === 'ios' && NativeAudioModule) {
      try {
        await NativeAudioModule.stopPlayback();
      } catch (e) {
        // Ignore errors
      }
    }

    // Stop react-native-sound (Android)
    if (soundRef.current) {
      soundRef.current.stop();
      soundRef.current.release();
      soundRef.current = null;
    }
  }, [stopProgressUpdates]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      stopSound();
      // Also stop System TTS
      if (Platform.OS === 'ios' && NativeAudioModule) {
        // Stop iOS native TTS
        NativeAudioModule.stopSpeaking().catch(() => {});
      } else {
        // Stop Android react-native-tts
        try {
          getTts()?.stop();
        } catch {
          // Ignore
        }
      }
      // Clean up temp audio file
      if (audioFilePath) {
        RNFS.unlink(audioFilePath).catch(() => {});
      }
    };
  }, [audioFilePath, stopSound]);

  /**
   * Load available models and check for loaded model
   * Called on mount and when screen comes into focus
   */
  const loadModels = useCallback(async () => {
    try {
      // Get available TTS models from catalog
      const allModels = await RunAnywhere.getAvailableModels();
      // Filter by category (speech-synthesis) matching SDK's ModelCategory
      const ttsModels = allModels.filter(
        (m: SDKModelInfo) => m.category === 'speech-synthesis'
      );
      setAvailableModels(ttsModels);

      // Log downloaded status for debugging
      const downloadedModels = ttsModels.filter((m) => m.isDownloaded);
      console.warn(
        '[TTSScreen] Available TTS models:',
        ttsModels.map((m) => `${m.id} (downloaded: ${m.isDownloaded})`)
      );
      console.warn(
        '[TTSScreen] Downloaded TTS models:',
        downloadedModels.map((m) => m.id)
      );

      // Check if model is already loaded
      const isLoaded = await RunAnywhere.isTTSModelLoaded();
      console.warn('[TTSScreen] isTTSModelLoaded:', isLoaded);
      if (isLoaded && !currentModel) {
        // Try to find which model is loaded from downloaded models
        const downloadedTts = ttsModels.filter((m) => m.isDownloaded);
        if (downloadedTts.length > 0) {
          // Use the first downloaded model as the likely loaded one
          const firstModel = downloadedTts[0];
          if (firstModel) {
            setCurrentModel({
              id: firstModel.id,
              name: firstModel.name,
              preferredFramework: LLMFramework.ONNX,
            } as ModelInfo);
            console.warn(
              '[TTSScreen] Set currentModel from downloaded:',
              firstModel.name
            );
          }
        } else {
          setCurrentModel({
            id: 'tts-model',
            name: 'TTS Model (Loaded)',
            preferredFramework: LLMFramework.ONNX,
          } as ModelInfo);
          console.warn('[TTSScreen] Set currentModel as generic TTS Model');
        }
      }
    } catch (error) {
      console.warn('[TTSScreen] Error loading models:', error);
    }
  }, [currentModel]);

  // Refresh models when screen comes into focus
  // This ensures we pick up any models downloaded in the Settings tab
  useFocusEffect(
    useCallback(() => {
      console.warn('[TTSScreen] Screen focused - refreshing models');
      loadModels();
    }, [loadModels])
  );

  /**
   * Handle model selection - opens model selection sheet
   */
  const handleSelectModel = useCallback(() => {
    setShowModelSelection(true);
  }, []);

  /**
   * Load a model from its info
   */
  const loadModel = useCallback(
    async (model: SDKModelInfo) => {
      try {
        setIsModelLoading(true);

        // Reset audio state when switching models
        setAudioGenerated(false);
        setAudioFilePath(null);
        stopSound();

        console.warn(
          `[TTSScreen] Loading model: ${model.id} from ${model.localPath}`
        );

        // Handle System TTS specially - it's always available, no download needed
        const isSystemTTS =
          model.id === 'system-tts' ||
          model.preferredFramework === LLMFramework.SystemTTS ||
          model.localPath?.startsWith('builtin://');

        if (isSystemTTS) {
          console.warn(
            `[TTSScreen] Using System TTS - no model loading required`
          );
          // System TTS doesn't need to load a model, just mark it as ready
          setCurrentModel({
            id: 'system-tts',
            name: 'System TTS',
            preferredFramework: LLMFramework.SystemTTS,
          } as ModelInfo);
          return;
        }

        if (!model.localPath) {
          Alert.alert(
            'Error',
            'Model path not found. Please download the model first.'
          );
          return;
        }

        // Unload any existing TTS model first
        try {
          const wasLoaded = await RunAnywhere.isTTSModelLoaded();
          if (wasLoaded) {
            console.warn('[TTSScreen] Unloading previous TTS model...');
            await RunAnywhere.unloadTTSModel();
          }
        } catch (unloadError) {
          console.warn(
            '[TTSScreen] Error unloading previous model (ignoring):',
            unloadError
          );
        }

        // Pass the path directly - C++ extractArchiveIfNeeded handles archive extraction
        // and finding the correct nested model folder
        const modelType = model.category || 'piper';
        console.warn(
          `[TTSScreen] Calling loadTTSModel with path: ${model.localPath}, type: ${modelType}`
        );

        const success = await RunAnywhere.loadTTSModel(
          model.localPath,
          modelType
        );

        if (success) {
          const isLoaded = await RunAnywhere.isTTSModelLoaded();
          if (isLoaded) {
            // Set model with framework so ModelStatusBanner shows it properly
            // Use ONNX since TTS uses Sherpa-ONNX (ONNX Runtime)
            setCurrentModel({
              id: model.id,
              name: model.name,
              preferredFramework: LLMFramework.ONNX,
            } as ModelInfo);
            console.warn(
              `[TTSScreen] Model ${model.name} loaded successfully, currentModel set`
            );
          } else {
            console.warn(
              `[TTSScreen] Model reported success but isTTSModelLoaded() returned false`
            );
            Alert.alert(
              'Warning',
              'Model may not have loaded correctly. Try generating speech to verify.'
            );
          }
        } else {
          const error = await RunAnywhere.getLastError();
          console.error(
            '[TTSScreen] loadTTSModel returned false, error:',
            error
          );
          Alert.alert(
            'Error',
            `Failed to load model: ${error || 'Unknown error'}`
          );
        }
      } catch (error) {
        console.error('[TTSScreen] Error loading model:', error);
        Alert.alert('Error', `Failed to load model: ${error}`);
      } finally {
        setIsModelLoading(false);
      }
    },
    [stopSound]
  );

  /**
   * Handle model selected from the sheet
   */
  const handleModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      // Close the modal first to prevent UI issues
      setShowModelSelection(false);
      // Then load the model
      await loadModel(model);
    },
    [loadModel]
  );

  /**
   * Generate speech using System TTS (AVSpeechSynthesizer on iOS)
   * iOS: Uses NativeAudioModule directly
   * Android: Uses react-native-tts
   */
  const handleSystemTTSGenerate = useCallback(async () => {
    console.warn('[TTSScreen] Using System TTS (native speech synthesizer)');

    try {
      // iOS: Use NativeAudioModule for System TTS
      if (Platform.OS === 'ios' && NativeAudioModule) {
        console.warn('[TTSScreen] iOS: Using NativeAudioModule.speak()');

        setIsPlaying(true);

        // Estimate duration based on text length and speed
        const estimatedDuration = (text.length * 0.06) / speed;
        setDuration(estimatedDuration);
        setSampleRate(0); // System TTS doesn't expose sample rate
        setAudioGenerated(false); // No audio file for System TTS

        try {
          const result = await NativeAudioModule.speak(text, speed, pitch);
          console.warn('[TTSScreen] iOS System TTS result:', result);
          setIsPlaying(false);
        } catch (speakError: unknown) {
          console.error('[TTSScreen] iOS System TTS error:', speakError);
          const errorMessage =
            speakError instanceof Error
              ? speakError.message
              : String(speakError);
          Alert.alert('Error', `System TTS failed: ${errorMessage}`);
          setIsPlaying(false);
        }
        return;
      }

      // Android: Use react-native-tts
      const tts = getTts();

      if (!tts) {
        Alert.alert('TTS Not Available', 'System TTS is not available.');
        return;
      }

      // Listen for finish event first
      const finishListener = tts.addListener('tts-finish', () => {
        console.warn('[TTSScreen] System TTS finished');
        setIsPlaying(false);
        finishListener.remove();
      });

      // Listen for cancel event
      const cancelListener = tts.addListener('tts-cancel', () => {
        console.warn('[TTSScreen] System TTS cancelled');
        setIsPlaying(false);
        cancelListener.remove();
      });

      // Speak the text with options
      // iOS rate: 0.0-1.0, Android rate: 0.01-0.99
      const androidRate = Math.min(0.99, Math.max(0.01, speed * 0.5));

      console.warn(
        '[TTSScreen] Android System TTS speaking with rate:',
        androidRate,
        'pitch:',
        pitch
      );

      // Just speak with default settings - avoid setDefaultRate issue
      // The speak function itself should work
      tts.speak(text, {
        rate: androidRate,
        pitch: pitch,
      });

      // Estimate duration based on text length and speed
      const estimatedDuration = (text.length * 0.06) / speed;
      setDuration(estimatedDuration);
      setSampleRate(0); // System TTS doesn't expose sample rate
      setAudioGenerated(false); // No audio file for System TTS
      setIsPlaying(true);
    } catch (error) {
      console.error('[TTSScreen] System TTS error:', error);
      Alert.alert('Error', `System TTS failed: ${error}`);
      setIsPlaying(false);
    }
  }, [text, speed, pitch]);

  /**
   * Generate speech
   */
  const handleGenerate = useCallback(async () => {
    if (!text.trim() || !currentModel) return;

    setIsGenerating(true);
    setAudioGenerated(false);

    // Stop any existing playback
    stopSound();
    // Also stop any System TTS
    if (Platform.OS === 'ios' && NativeAudioModule) {
      try {
        await NativeAudioModule.stopSpeaking();
      } catch {
        /* ignore */
      }
    } else {
      try {
        getTts()?.stop();
      } catch {
        /* ignore */
      }
    }

    // Check if using System TTS
    const isSystemTTS =
      currentModel.id === 'system-tts' ||
      currentModel.preferredFramework === LLMFramework.SystemTTS;

    try {
      // For System TTS, use native AVSpeechSynthesizer
      if (isSystemTTS) {
        console.warn('[TTSScreen] Synthesizing with System TTS (native)');
        await handleSystemTTSGenerate();
        setIsGenerating(false);
        return;
      }

      // For ONNX models, check if model is loaded
      const isLoaded = await RunAnywhere.isTTSModelLoaded();
      if (!isLoaded) {
        Alert.alert('Model Not Loaded', 'Please load a TTS model first.');
        setIsGenerating(false);
        return;
      }

      // SDK uses simple TTSConfiguration with rate/pitch/volume
      const sdkConfig = {
        voice: 'default',
        rate: speed,
        pitch: pitch,
        volume: volume,
      };

      console.warn(
        '[TTSScreen] Synthesizing text with ONNX:',
        text.substring(0, 50) + '...'
      );

      // SDK returns TTSResult with audio, sampleRate, numSamples, duration
      const result = await RunAnywhere.synthesize(text, sdkConfig);

      console.warn('[TTSScreen] Synthesis result:', {
        sampleRate: result.sampleRate,
        numSamples: result.numSamples,
        duration: result.duration,
        audioLength: result.audio?.length || 0,
      });

      // Use actual duration from result, or estimate if not available
      const audioDuration =
        result.duration ||
        result.numSamples / result.sampleRate ||
        text.length * 0.05;
      setDuration(audioDuration);
      setSampleRate(result.sampleRate || 22050);
      setLastGeneratedAudio(result.audio);

      // Convert to WAV and save to file for playback
      if (result.audio && result.audio.length > 0) {
        try {
          // Clean up previous file
          if (audioFilePath) {
            await RNFS.unlink(audioFilePath).catch(() => {});
          }

          const wavPath = await RunAnywhere.Audio.createWavFromPCMFloat32(
            result.audio,
            result.sampleRate || 22050
          );
          setAudioFilePath(wavPath);
          setAudioGenerated(true);
          setCurrentTime(0);
          setPlaybackProgress(0);
          setIsPlaying(false);

          console.warn('[TTSScreen] WAV file created:', wavPath);
        } catch (wavError) {
          console.error('[TTSScreen] Error creating WAV file:', wavError);
          Alert.alert(
            'Audio Generated',
            `Duration: ${audioDuration.toFixed(2)}s\n` +
              `Sample Rate: ${result.sampleRate} Hz\n` +
              `Samples: ${result.numSamples.toLocaleString()}\n\n` +
              'Audio file creation failed. Tap play to try again.',
            [{ text: 'OK' }]
          );
          setAudioGenerated(true);
        }
      }
    } catch (error) {
      console.error('[TTSScreen] Synthesis error:', error);
      Alert.alert('Error', `Failed to generate speech: ${error}`);
    } finally {
      setIsGenerating(false);
    }
  }, [
    text,
    speed,
    pitch,
    volume,
    currentModel,
    audioFilePath,
    handleSystemTTSGenerate,
    stopSound,
  ]);

  /**
   * Format time for display (MM:SS)
   */
  const formatTime = (seconds: number): string => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  /**
   * Toggle playback - plays or pauses audio using react-native-sound
   */
  const handleTogglePlayback = useCallback(async () => {
    console.warn('[TTSScreen] handleTogglePlayback called', {
      audioGenerated,
      audioFilePath,
      isPlaying,
      currentTime,
      playbackProgress,
    });

    if (!audioGenerated || !audioFilePath) {
      console.warn(
        '[TTSScreen] No audio to play - audioGenerated:',
        audioGenerated,
        'audioFilePath:',
        audioFilePath
      );
      Alert.alert('No Audio', 'Please generate speech first.');
      return;
    }

    // Verify file exists
    try {
      const fileExists = await RNFS.exists(audioFilePath);
      console.warn(
        '[TTSScreen] Audio file exists:',
        fileExists,
        'path:',
        audioFilePath
      );
      if (!fileExists) {
        Alert.alert(
          'File Not Found',
          'Audio file was not found. Please regenerate.'
        );
        return;
      }
      const fileStat = await RNFS.stat(audioFilePath);
      console.warn('[TTSScreen] Audio file size:', fileStat.size, 'bytes');
    } catch (statError) {
      console.error('[TTSScreen] Error checking file:', statError);
    }

    try {
      if (isPlaying) {
        // Pause playback
        console.warn('[TTSScreen] Pausing playback...');

        // iOS: Use NativeAudioModule
        if (Platform.OS === 'ios' && NativeAudioModule) {
          try {
            await NativeAudioModule.pausePlayback();
          } catch (e) {
            console.warn('[TTSScreen] iOS pause error:', e);
          }
        } else if (soundRef.current) {
          soundRef.current.pause();
        }

        stopProgressUpdates();
        setIsPlaying(false);
        console.warn('[TTSScreen] Playback paused');
      } else {
        // Check if we should resume on iOS
        if (Platform.OS === 'ios' && NativeAudioModule && currentTime > 0) {
          // Resume iOS playback
          console.warn('[TTSScreen] Resuming iOS playback from:', currentTime);
          try {
            await NativeAudioModule.resumePlayback();
            setIsPlaying(true);

            // Restart progress updates
            progressIntervalRef.current = setInterval(async () => {
              try {
                const status = await NativeAudioModule.getPlaybackStatus();
                const currentSec = status.currentTime || 0;
                const totalDuration = status.duration || duration;
                setCurrentTime(currentSec);
                if (totalDuration > 0) {
                  setPlaybackProgress(currentSec / totalDuration);
                }

                if (!status.isPlaying && currentSec >= totalDuration - 0.1) {
                  stopProgressUpdates();
                  setIsPlaying(false);
                  setCurrentTime(0);
                  setPlaybackProgress(0);
                }
              } catch (e) {
                // Ignore
              }
            }, 100);

            return;
          } catch (e) {
            console.warn('[TTSScreen] iOS resume error, starting fresh:', e);
          }
        }

        // Android: Use react-native-sound
        if (soundRef.current && currentTime > 0) {
          // Resume existing sound
          console.warn('[TTSScreen] Resuming playback from:', currentTime);
          soundRef.current.setVolume(volume);
          soundRef.current.play((success: boolean) => {
            if (success) {
              console.warn('[TTSScreen] Playback finished');
            }
            stopProgressUpdates();
            setIsPlaying(false);
            setCurrentTime(0);
            setPlaybackProgress(0);
          });

          // Start progress updates
          progressIntervalRef.current = setInterval(() => {
            soundRef.current?.getCurrentTime((seconds: number) => {
              const totalDuration = soundRef.current?.getDuration() || duration;
              setCurrentTime(seconds);
              if (totalDuration > 0) {
                setPlaybackProgress(seconds / totalDuration);
              }
            });
          }, 100);

          setIsPlaying(true);
        } else {
          // Start fresh playback
          console.warn('[TTSScreen] Starting fresh playback...');
          await stopSound(); // Clean up any existing sound

          // iOS: Use NativeAudioModule
          if (Platform.OS === 'ios' && NativeAudioModule) {
            console.warn(
              '[TTSScreen] Using NativeAudioModule for iOS playback'
            );
            try {
              const result = await NativeAudioModule.playAudio(audioFilePath);
              console.warn('[TTSScreen] iOS playback started:', result);
              setIsPlaying(true);

              // Start progress updates for iOS
              progressIntervalRef.current = setInterval(async () => {
                try {
                  const status = await NativeAudioModule.getPlaybackStatus();
                  const currentSec = status.currentTime || 0;
                  const totalDuration = status.duration || duration;
                  setCurrentTime(currentSec);
                  if (totalDuration > 0) {
                    setPlaybackProgress(currentSec / totalDuration);
                  }

                  // Check if playback finished
                  if (!status.isPlaying && currentSec >= totalDuration - 0.1) {
                    stopProgressUpdates();
                    setIsPlaying(false);
                    setCurrentTime(0);
                    setPlaybackProgress(0);
                    console.warn('[TTSScreen] iOS playback finished');
                  }
                } catch (e) {
                  // Ignore errors during polling
                }
              }, 100);

              return;
            } catch (error: unknown) {
              console.error('[TTSScreen] iOS playback error:', error);
              const errorMessage =
                error instanceof Error ? error.message : String(error);
              Alert.alert(
                'Playback Error',
                `Failed to play audio: ${errorMessage}`
              );
              return;
            }
          }

          const SoundClass = getSound();
          if (!SoundClass) {
            Alert.alert('Playback Error', 'Sound player not available');
            return;
          }
          const sound = new SoundClass(
            audioFilePath,
            '',
            (error: Error | null) => {
              if (error) {
                console.error('[TTSScreen] Failed to load sound:', error);
                Alert.alert(
                  'Playback Error',
                  `Failed to load audio: ${error.message}`
                );
                return;
              }

              console.warn(
                '[TTSScreen] Sound loaded, duration:',
                sound.getDuration(),
                'seconds'
              );
              soundRef.current = sound;
              sound.setVolume(volume);

              sound.play((success: boolean) => {
                if (success) {
                  console.warn('[TTSScreen] Playback finished successfully');
                } else {
                  console.warn('[TTSScreen] Playback interrupted');
                }
                stopProgressUpdates();
                setIsPlaying(false);
                setCurrentTime(0);
                setPlaybackProgress(0);
              });

              // Start progress updates
              progressIntervalRef.current = setInterval(() => {
                sound.getCurrentTime((seconds: number) => {
                  const totalDuration = sound.getDuration();
                  setCurrentTime(seconds);
                  if (totalDuration > 0) {
                    setPlaybackProgress(seconds / totalDuration);
                  }
                });
              }, 100);

              setIsPlaying(true);
              console.warn('[TTSScreen] Playback started successfully');
            }
          );
        }
      }
    } catch (error) {
      console.error('[TTSScreen] Playback error:', error);
      Alert.alert('Playback Error', `Failed to play audio: ${error}`);
      setIsPlaying(false);
    }
  }, [
    audioGenerated,
    audioFilePath,
    isPlaying,
    currentTime,
    playbackProgress,
    volume,
    duration,
    stopSound,
    stopProgressUpdates,
  ]);

  /**
   * Stop playback completely
   */
  const handleStop = useCallback(async () => {
    await stopSound();
    // Also stop System TTS if playing
    if (Platform.OS === 'ios' && NativeAudioModule) {
      try {
        await NativeAudioModule.stopSpeaking();
      } catch {
        /* ignore */
      }
    } else {
      const tts = getTts();
      if (tts) {
        try {
          tts.stop();
        } catch {
          /* ignore */
        }
      }
    }
    setIsPlaying(false);
    setCurrentTime(0);
    setPlaybackProgress(0);
  }, [stopSound]);

  /**
   * Clear text
   */
  const handleClear = useCallback(() => {
    setText('');
    setAudioGenerated(false);
    setIsPlaying(false);
  }, []);

  /**
   * Render slider with label
   */
  const renderSlider = (
    label: string,
    value: number,
    onValueChange: (value: number) => void,
    min: number = 0.5,
    max: number = 2.0,
    step: number = 0.1,
    formatValue: (v: number) => string = (v) => `${v.toFixed(1)}x`
  ) => (
    <View style={styles.sliderContainer}>
      <View style={styles.sliderHeader}>
        <Text style={styles.sliderLabel}>{label}</Text>
        <Text style={styles.sliderValue}>{formatValue(value)}</Text>
      </View>
      {/* TODO: Add @react-native-community/slider package */}
      <View style={styles.sliderTrack}>
        <View
          style={[
            styles.sliderFill,
            { width: `${((value - min) / (max - min)) * 100}%` },
          ]}
        />
        <TouchableOpacity
          style={[
            styles.sliderThumb,
            { left: `${((value - min) / (max - min)) * 100}%` },
          ]}
          onPress={() => {
            // Simple increment for demo
            const newValue = value + step > max ? min : value + step;
            onValueChange(Math.round(newValue * 10) / 10);
          }}
        />
      </View>
    </View>
  );

  /**
   * Render header
   */
  const renderHeader = () => (
    <View style={styles.header}>
      <Text style={styles.title}>Text to Speech</Text>
      {text && (
        <TouchableOpacity style={styles.clearButton} onPress={handleClear}>
          <Icon name="close-circle" size={22} color={Colors.textSecondary} />
        </TouchableOpacity>
      )}
    </View>
  );

  // Show model required overlay if no model
  if (!currentModel && !isModelLoading) {
    return (
      <SafeAreaView style={styles.container}>
        {renderHeader()}
        <ModelRequiredOverlay
          modality={ModelModality.TTS}
          onSelectModel={handleSelectModel}
        />
        {/* Model Selection Sheet */}
        <ModelSelectionSheet
          visible={showModelSelection}
          context={ModelSelectionContext.TTS}
          onClose={() => setShowModelSelection(false)}
          onModelSelected={handleModelSelected}
        />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      {renderHeader()}

      {/* Model Status Banner */}
      <ModelStatusBanner
        modelName={currentModel?.name}
        framework={currentModel?.preferredFramework}
        isLoading={isModelLoading}
        onSelectModel={handleSelectModel}
        placeholder="Select a voice model"
      />

      <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
        {/* Text Input */}
        <View style={styles.inputSection}>
          <Text style={styles.sectionLabel}>Text to speak</Text>
          <TextInput
            style={styles.textInput}
            value={text}
            onChangeText={setText}
            placeholder="Enter text to convert to speech..."
            placeholderTextColor={Colors.textTertiary}
            multiline
            maxLength={maxChars}
          />
          <Text style={styles.charCount}>
            {charCount}/{maxChars} characters
          </Text>
        </View>

        {/* Voice Settings */}
        <View style={styles.settingsSection}>
          <Text style={styles.sectionLabel}>Voice Settings</Text>
          {renderSlider('Speed', speed, setSpeed)}
          {renderSlider('Pitch', pitch, setPitch)}
          {renderSlider(
            'Volume',
            volume,
            setVolume,
            0,
            1,
            0.1,
            (v) => `${Math.round(v * 100)}%`
          )}
        </View>

        {/* Playback Controls */}
        {audioGenerated && (
          <View style={styles.playbackSection}>
            <Text style={styles.sectionLabel}>Generated Audio</Text>

            {/* Progress bar */}
            <View style={styles.progressContainer}>
              <Text style={styles.timeText}>{formatTime(currentTime)}</Text>
              <View style={styles.progressBar}>
                <View
                  style={[
                    styles.progressFill,
                    {
                      width: `${Math.max(0, Math.min(100, playbackProgress * 100))}%`,
                    },
                  ]}
                />
              </View>
              <Text style={styles.timeText}>{formatTime(duration)}</Text>
            </View>

            {/* Audio info */}
            <View style={styles.playbackInfo}>
              <Icon
                name="musical-notes"
                size={20}
                color={Colors.textSecondary}
              />
              <Text style={styles.durationText}>
                {duration.toFixed(1)}s @ {sampleRate} Hz
              </Text>
            </View>

            {/* Playback controls */}
            <View style={styles.playbackControls}>
              <TouchableOpacity
                style={[
                  styles.controlButton,
                  isPlaying && styles.controlButtonActive,
                ]}
                onPress={handleTogglePlayback}
              >
                <Icon
                  name={isPlaying ? 'pause' : 'play'}
                  size={24}
                  color={isPlaying ? Colors.textWhite : Colors.primaryBlue}
                />
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.controlButton}
                onPress={handleStop}
              >
                <Icon name="stop" size={24} color={Colors.primaryBlue} />
              </TouchableOpacity>
            </View>
          </View>
        )}
      </ScrollView>

      {/* Generate Button */}
      <View style={styles.footer}>
        <TouchableOpacity
          style={[
            styles.generateButton,
            (!text.trim() || isGenerating) && styles.generateButtonDisabled,
          ]}
          onPress={handleGenerate}
          disabled={!text.trim() || isGenerating}
          activeOpacity={0.8}
        >
          {isGenerating ? (
            <>
              <Icon name="hourglass" size={20} color={Colors.textWhite} />
              <Text style={styles.generateButtonText}>Generating...</Text>
            </>
          ) : (
            <>
              <Icon name="volume-high" size={20} color={Colors.textWhite} />
              <Text style={styles.generateButtonText}>Generate Speech</Text>
            </>
          )}
        </TouchableOpacity>
      </View>

      {/* Model Selection Sheet */}
      <ModelSelectionSheet
        visible={showModelSelection}
        context={ModelSelectionContext.TTS}
        onClose={() => setShowModelSelection(false)}
        onModelSelected={handleModelSelected}
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
  },
  clearButton: {
    padding: Spacing.small,
  },
  content: {
    flex: 1,
    paddingHorizontal: Padding.padding16,
  },
  inputSection: {
    marginTop: Spacing.large,
  },
  sectionLabel: {
    ...Typography.headline,
    color: Colors.textPrimary,
    marginBottom: Spacing.smallMedium,
  },
  textInput: {
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.medium,
    padding: Padding.padding14,
    minHeight: Layout.textAreaMinHeight,
    ...Typography.body,
    color: Colors.textPrimary,
    textAlignVertical: 'top',
  },
  charCount: {
    ...Typography.caption,
    color: Colors.textTertiary,
    textAlign: 'right',
    marginTop: Spacing.small,
  },
  settingsSection: {
    marginTop: Spacing.xLarge,
  },
  sliderContainer: {
    marginBottom: Spacing.large,
  },
  sliderHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.small,
  },
  sliderLabel: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
  },
  sliderValue: {
    ...Typography.subheadline,
    color: Colors.primaryBlue,
    fontWeight: '600',
  },
  sliderTrack: {
    height: 6,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 3,
    position: 'relative',
  },
  sliderFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
    borderRadius: 3,
  },
  sliderThumb: {
    position: 'absolute',
    top: -7,
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: Colors.backgroundPrimary,
    borderWidth: 2,
    borderColor: Colors.primaryBlue,
    marginLeft: -10,
  },
  playbackSection: {
    marginTop: Spacing.xLarge,
    padding: Padding.padding16,
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.medium,
  },
  progressContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    marginBottom: Spacing.medium,
    paddingVertical: Spacing.smallMedium,
  },
  timeText: {
    ...Typography.caption,
    color: Colors.textSecondary,
    minWidth: 40,
    textAlign: 'center',
  },
  progressBar: {
    flex: 1,
    height: 4,
    backgroundColor: Colors.backgroundGray5,
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: Colors.primaryBlue,
    borderRadius: 2,
  },
  playbackInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.smallMedium,
    marginBottom: Spacing.medium,
  },
  durationText: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  playbackControls: {
    flexDirection: 'row',
    gap: Spacing.medium,
  },
  controlButton: {
    width: ButtonHeight.regular,
    height: ButtonHeight.regular,
    borderRadius: ButtonHeight.regular / 2,
    backgroundColor: Colors.backgroundPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: Colors.primaryBlue,
  },
  controlButtonActive: {
    backgroundColor: Colors.primaryBlue,
    borderColor: Colors.primaryBlue,
  },
  footer: {
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding16,
    paddingBottom: Padding.padding30,
    borderTopWidth: 1,
    borderTopColor: Colors.borderLight,
  },
  generateButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.smallMedium,
    backgroundColor: Colors.primaryBlue,
    height: ButtonHeight.regular,
    borderRadius: BorderRadius.large,
  },
  generateButtonDisabled: {
    backgroundColor: Colors.backgroundGray5,
  },
  generateButtonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },
});

export default TTSScreen;
