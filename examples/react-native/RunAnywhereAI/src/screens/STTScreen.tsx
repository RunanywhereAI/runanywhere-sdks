import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Alert,
  Platform,
  Animated,
  PermissionsAndroid,
  Linking,
  ActivityIndicator,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useFocusEffect } from '@react-navigation/native';
import { check, request, PERMISSIONS, RESULTS } from 'react-native-permissions';
import { Icon, useTheme } from '../theme/system';
import { ModelRequiredOverlay } from '../components/common';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';
import { STTMode } from '../types/voice';

import {
  RunAnywhere,
  AudioCaptureManager,
  createPushableAudioStream,
  type PushableAudioStream,
} from '@runanywhere/core';
import {
  AudioFormat,
  ModelCategory,
  ModelLoadRequest,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import {
  STTLanguage,
  type STTPartialResult,
} from '@runanywhere/proto-ts/stt_options';
import { isModelLoadedForCategory } from '../utils/runAnywhereLifecycle';
import { listVisibleCatalogModels } from '../services/ModelRegistryQueries';
import { visibleNativeNpuCatalogModelOrNull } from '../services/NpuModelCatalog';

const CAPTURE_SAMPLE_RATE = 16000;
const CAPTURE_BYTES_PER_MS = (CAPTURE_SAMPLE_RATE * 2) / 1000;
const BAR_COUNT = 12;

function wrapPcm16InWav(pcmChunks: Uint8Array[]): Uint8Array {
  const dataSize = pcmChunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const wav = new Uint8Array(44 + dataSize);
  const view = new DataView(wav.buffer);

  const writeString = (offset: number, str: string) => {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  };

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, CAPTURE_SAMPLE_RATE, true);
  view.setUint32(28, CAPTURE_SAMPLE_RATE * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeString(36, 'data');
  view.setUint32(40, dataSize, true);

  let offset = 44;
  for (const chunk of pcmChunks) {
    wav.set(chunk, offset);
    offset += chunk.length;
  }
  return wav;
}

async function transcribePcmChunks(pcmChunks: Uint8Array[]) {
  return RunAnywhere.transcribe(wrapPcm16InWav(pcmChunks), {
    language: STTLanguage.STT_LANGUAGE_EN,
    audioFormat: AudioFormat.AUDIO_FORMAT_WAV,
    sampleRate: CAPTURE_SAMPLE_RATE,
  });
}

const loadModelWithRequest = RunAnywhere.loadModel;

export const STTScreen: React.FC = () => {
  const { colors, typography, dimens } = useTheme();
  const insets = useSafeAreaInsets();

  const [mode, setMode] = useState<STTMode>(STTMode.Batch);
  const [isRecording, setIsRecording] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [partialTranscript, setPartialTranscript] = useState('');
  const [confidence, setConfidence] = useState<number | null>(null);
  const [currentModel, setCurrentModel] = useState<SDKModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [recordingDuration, setRecordingDuration] = useState(0);
  const [audioLevel, setAudioLevel] = useState(0);
  const [showModelSelection, setShowModelSelection] = useState(false);

  const captureManagerRef = useRef<AudioCaptureManager | null>(null);
  const getCaptureManager = (): AudioCaptureManager => {
    if (!captureManagerRef.current) {
      captureManagerRef.current = new AudioCaptureManager();
    }
    return captureManagerRef.current;
  };

  const pcmChunksRef = useRef<Uint8Array[]>([]);
  const pcmBytesRef = useRef(0);
  const accumulatedTranscriptRef = useRef('');
  const liveAudioStreamRef = useRef<PushableAudioStream | null>(null);
  const liveTranscriptionTaskRef = useRef<Promise<void> | null>(null);
  const isLiveRecordingRef = useRef(false);

  const pulseAnim = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    if (isRecording) {
      const pulse = Animated.loop(
        Animated.sequence([
          Animated.timing(pulseAnim, { toValue: 1.3, duration: 500, useNativeDriver: true }),
          Animated.timing(pulseAnim, { toValue: 1, duration: 500, useNativeDriver: true }),
        ])
      );
      pulse.start();
      return () => pulse.stop();
    } else {
      pulseAnim.setValue(1);
    }
  }, [isRecording, pulseAnim]);

  useEffect(() => {
    return () => {
      isLiveRecordingRef.current = false;
      liveAudioStreamRef.current?.close();
      liveAudioStreamRef.current = null;
      try { captureManagerRef.current?.stopRecording(); } catch {}
      pcmChunksRef.current = [];
      pcmBytesRef.current = 0;
    };
  }, []);

  const loadModels = useCallback(async () => {
    try {
      const allModels = await listVisibleCatalogModels();
      const sttModels = allModels.filter(
        (m: SDKModelInfo) => m.category === ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
      );
      setAvailableModels(sttModels);
      const loaded = await RunAnywhere.modelInfoForCategory(
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
      );
      setCurrentModel(visibleNativeNpuCatalogModelOrNull(loaded));
    } catch (error) {
      console.warn('[STTScreen] Error loading models:', error);
    }
  }, []);

  useFocusEffect(
    useCallback(() => { loadModels(); }, [loadModels])
  );

  const handleSelectModel = useCallback(() => { setShowModelSelection(true); }, []);

  const handleModelSelected = useCallback(async (model: SDKModelInfo) => {
    setShowModelSelection(false);
    await loadModel(model);
  }, []);

  const loadModel = async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      if (!model.isDownloaded && !model.localPath) {
        Alert.alert('Error', 'Model has not been downloaded. Open the model picker to download it first.');
        return;
      }
      const result = await loadModelWithRequest(
        ModelLoadRequest.fromPartial({
          modelId: model.id,
          category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
          forceReload: false,
          validateAvailability: true,
        })
      );
      if (result.success) {
        const isLoaded = await isModelLoadedForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
        if (isLoaded) {
          const loaded = await RunAnywhere.modelInfoForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
          setCurrentModel(
            visibleNativeNpuCatalogModelOrNull(loaded) ?? model
          );
        }
      } else {
        const error = result.errorMessage || 'Native model lifecycle returned an unsuccessful load result';
        Alert.alert('Error', `Failed to load model: ${error || 'Unknown error'}`);
      }
    } catch (error) {
      Alert.alert('Error', `Failed to load model: ${error}`);
    } finally {
      setIsModelLoading(false);
    }
  };

  const formatDuration = (ms: number): string => {
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  const requestMicrophonePermission = async (): Promise<boolean> => {
    try {
      if (Platform.OS === 'ios') {
        const status = await check(PERMISSIONS.IOS.MICROPHONE);
        if (status === RESULTS.GRANTED) return true;
        if (status === RESULTS.DENIED) {
          const result = await request(PERMISSIONS.IOS.MICROPHONE);
          return result === RESULTS.GRANTED;
        }
        if (status === RESULTS.BLOCKED) {
          Alert.alert('Microphone Permission Required', 'Please enable microphone access in Settings.', [
            { text: 'Cancel', style: 'cancel' },
            { text: 'Open Settings', onPress: () => Linking.openSettings() },
          ]);
          return false;
        }
        return false;
      } else {
        const granted = await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO, {
          title: 'Microphone Permission',
          message: 'RunAnywhereAI needs access to your microphone for speech-to-text.',
          buttonNeutral: 'Ask Me Later',
          buttonNegative: 'Cancel',
          buttonPositive: 'OK',
        });
        return granted === PermissionsAndroid.RESULTS.GRANTED;
      }
    } catch (error) {
      return false;
    }
  };

  const beginCapture = async (onChunk?: (chunk: Uint8Array) => void) => {
    const capture = getCaptureManager();
    pcmChunksRef.current = [];
    pcmBytesRef.current = 0;
    await capture.startRecording((chunk: Uint8Array) => {
      if (onChunk) {
        onChunk(chunk);
      } else {
        pcmChunksRef.current.push(chunk);
      }
      pcmBytesRef.current += chunk.length;
      setAudioLevel(capture.audioLevel);
      setRecordingDuration(pcmBytesRef.current / CAPTURE_BYTES_PER_MS);
    });
  };

  const drainCapturedChunks = (): Uint8Array[] => {
    const chunks = pcmChunksRef.current;
    pcmChunksRef.current = [];
    pcmBytesRef.current = 0;
    return chunks;
  };

  const startRecording = async () => {
    try {
      const hasPermission = await requestMicrophonePermission();
      if (!hasPermission) return;
      await beginCapture();
      setIsRecording(true);
      setTranscript('');
      setConfidence(null);
    } catch (error) {
      Alert.alert('Recording Error', `Failed to start recording: ${error}`);
    }
  };

  const stopRecordingAndTranscribe = async () => {
    try {
      getCaptureManager().stopRecording();
      setIsRecording(false);
      setIsProcessing(true);

      const chunks = drainCapturedChunks();
      const totalBytes = chunks.reduce((sum, c) => sum + c.length, 0);
      if (totalBytes < 1000) throw new Error('Recording too short');

      const isLoaded = await isModelLoadedForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
      if (!isLoaded) throw new Error('STT model not loaded');

      const result = await transcribePcmChunks(chunks);
      if (result.text) {
        setTranscript(result.text);
        setConfidence(result.confidence);
      } else {
        setTranscript('(No speech detected)');
      }
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      Alert.alert('Transcription Error', errorMessage);
      setTranscript('');
    } finally {
      setIsProcessing(false);
      setRecordingDuration(0);
      setAudioLevel(0);
    }
  };

  const startLiveTranscription = async () => {
    try {
      const hasPermission = await requestMicrophonePermission();
      if (!hasPermission) return;

      const isLoaded = await isModelLoadedForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
      if (!isLoaded) { Alert.alert('Model Not Loaded', 'Please load an STT model first.'); return; }

      accumulatedTranscriptRef.current = '';
      setTranscript('');
      setPartialTranscript('Listening...');
      setConfidence(null);
      setRecordingDuration(0);
      isLiveRecordingRef.current = true;

      const audioStream = createPushableAudioStream();
      liveAudioStreamRef.current = audioStream;
      const partials = RunAnywhere.transcribeStream(audioStream.iterable, {
        language: STTLanguage.STT_LANGUAGE_EN,
        audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
        sampleRate: CAPTURE_SAMPLE_RATE,
      });
      liveTranscriptionTaskRef.current = consumeLiveTranscription(partials);
      await beginCapture((chunk) => audioStream.push(chunk));
      setIsRecording(true);
    } catch (error) {
      Alert.alert('Recording Error', `Failed to start live transcription: ${error}`);
      isLiveRecordingRef.current = false;
      liveAudioStreamRef.current?.close();
    }
  };

  const consumeLiveTranscription = async (partials: AsyncIterable<STTPartialResult>) => {
    const iterator = partials[Symbol.asyncIterator]();
    try {
      let step = await iterator.next();
      while (!step.done) {
        const partial = step.value;
        const finalText = partial.finalOutput?.text?.trim();
        const text = (finalText || partial.text || '').trim();
        if (text) {
          if (partial.isFinal || finalText) {
            accumulatedTranscriptRef.current = text;
            setTranscript(text);
            setPartialTranscript('');
            setConfidence(partial.finalOutput?.confidence ?? null);
          } else {
            setPartialTranscript(text);
          }
        }
        step = await iterator.next();
      }
    } catch (error) {
      console.error('[STTScreen] Live transcription stream error:', error);
    } finally {
      await iterator.return?.();
    }
  };

  const stopLiveTranscription = async () => {
    isLiveRecordingRef.current = false;
    try {
      setIsProcessing(true);
      setPartialTranscript('Finalizing...');
      getCaptureManager().stopRecording();
      liveAudioStreamRef.current?.close();
      await liveTranscriptionTaskRef.current;
      liveAudioStreamRef.current = null;
      liveTranscriptionTaskRef.current = null;
    } catch (error) {
      console.error('[STTScreen] Error stopping live transcription:', error);
    } finally {
      setIsRecording(false);
      setIsProcessing(false);
      setPartialTranscript('');
      setRecordingDuration(0);
      setAudioLevel(0);
    }
  };

  const handleToggleRecording = useCallback(async () => {
    if (isRecording) {
      if (mode === STTMode.Live) await stopLiveTranscription();
      else await stopRecordingAndTranscribe();
    } else {
      if (!currentModel) { Alert.alert('Model Required', 'Please select an STT model first.'); return; }
      if (mode === STTMode.Live) await startLiveTranscription();
      else await startRecording();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isRecording, currentModel, mode]);

  const handleClear = useCallback(() => {
    setTranscript('');
    setPartialTranscript('');
    setConfidence(null);
    accumulatedTranscriptRef.current = '';
  }, []);

  const busy = isRecording || isProcessing;
  const recordButtonColor = !currentModel
    ? colors.surfaceContainerHighest
    : isRecording
    ? colors.error
    : colors.primary;

  const modeDescriptionText =
    mode === STTMode.Batch
      ? 'Tap record, speak, then tap again to transcribe — all on-device.'
      : 'Live mode transcribes each phrase as you pause. Tap to start.';

  if (!currentModel && !isModelLoading) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={[styles.topBar, { paddingTop: insets.top + dimens.spacing.sm }]}>
          <Text style={[typography.titleLarge, { color: colors.onSurface, fontWeight: '700' }]}>
            Speech to Text
          </Text>
        </View>
        <ModelRequiredOverlay modality="stt" onSelectModel={handleSelectModel} />
        <ModelSelectionSheet
          visible={showModelSelection}
          context={ModelSelectionContext.STT}
          onClose={() => setShowModelSelection(false)}
          onModelSelected={handleModelSelected}
        />
      </View>
    );
  }

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={[
          styles.content,
          { paddingTop: insets.top + dimens.spacing.lg, paddingHorizontal: dimens.screenPadding },
        ]}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View style={[styles.headerSection, { gap: dimens.spacing.sm }]}>
          <View style={[styles.iconCircle, { backgroundColor: colors.primaryContainer }]}>
            <Icon name="transcribe" size={dimens.icon.lg} color={colors.onPrimaryContainer} />
          </View>
          <Text style={[typography.titleLarge, { color: colors.onSurface, fontWeight: '700' }]}>
            Speech to Text
          </Text>
          <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant, textAlign: 'center' }]}>
            {modeDescriptionText}
          </Text>
        </View>

        {/* Mode Selector */}
        <View style={[styles.modeContainer, { backgroundColor: colors.surfaceContainerHigh, marginTop: dimens.spacing.lg }]}>
          <View style={styles.modePad}>
            {([STTMode.Batch, STTMode.Live] as STTMode[]).map((option) => {
              const selected = option === mode;
              return (
                <TouchableOpacity
                  key={option}
                  style={[
                    styles.modeTab,
                    { backgroundColor: selected ? colors.primary : 'transparent' },
                  ]}
                  onPress={() => !busy && !selected && setMode(option)}
                  activeOpacity={0.8}
                  disabled={busy}
                >
                  <Text
                    style={[
                      typography.labelLarge,
                      { color: selected ? colors.onPrimary : colors.onSurfaceVariant, fontWeight: '600' },
                    ]}
                  >
                    {option === STTMode.Batch ? 'Batch' : 'Live'}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>
        </View>

        {/* Model Card */}
        <TouchableOpacity
          style={[styles.modelCard, { backgroundColor: colors.surfaceContainerHigh, marginTop: dimens.spacing.lg }]}
          onPress={handleSelectModel}
          activeOpacity={0.7}
        >
          <Icon name="transcribe" size={dimens.icon.md} color={colors.primary} />
          <View style={styles.modelCardText}>
            <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>Model</Text>
            <Text style={[typography.bodyLarge, { color: colors.onSurface }]} numberOfLines={1}>
              {isModelLoading ? 'Loading…' : (currentModel?.name ?? 'Select a model')}
            </Text>
          </View>
          <Icon name="chevronRight" size={dimens.icon.sm} color={colors.onSurfaceVariant} />
        </TouchableOpacity>

        {/* Record Button */}
        <View style={[styles.recordSection, { marginTop: dimens.spacing.xl }]}>
          <TouchableOpacity
            style={[styles.recordButton, { backgroundColor: recordButtonColor }]}
            onPress={handleToggleRecording}
            disabled={isProcessing || !currentModel}
            activeOpacity={0.85}
          >
            <Icon
              name={isRecording ? 'stop' : 'voice'}
              size={40}
              color={colors.onPrimary}
            />
          </TouchableOpacity>
        </View>

        {/* Status Line */}
        <View style={[styles.statusLine, { marginTop: dimens.spacing.md }]}>
          {isRecording ? (
            <View style={[styles.statusCenter, { gap: dimens.spacing.sm }]}>
              <LevelBars audioLevel={audioLevel} colors={colors} dimens={dimens} />
              <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}>
                {mode === STTMode.Live ? 'Listening — pause to transcribe' : 'Recording…'}
              </Text>
              <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
                {formatDuration(recordingDuration)}
              </Text>
            </View>
          ) : isProcessing ? (
            <View style={[styles.statusRow, { gap: dimens.spacing.sm }]}>
              <ActivityIndicator size="small" color={colors.primary} />
              <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}>
                Transcribing…
              </Text>
            </View>
          ) : (
            <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}>
              {currentModel ? 'Tap to record' : 'Select a model to begin'}
            </Text>
          )}
        </View>

        {/* Transcript Card */}
        {(transcript.length > 0 || partialTranscript.length > 0) && (
          <View style={[styles.labeledSection, { marginTop: dimens.spacing.lg, gap: dimens.spacing.sm }]}>
            <View style={styles.labelRow}>
              <Text style={[typography.titleSmall, { color: colors.onSurfaceVariant }]}>Transcript</Text>
              {transcript.length > 0 && (
                <TouchableOpacity onPress={handleClear} hitSlop={8}>
                  <Icon name="close" size={dimens.icon.sm} color={colors.onSurfaceVariant} />
                </TouchableOpacity>
              )}
            </View>
            <View style={[styles.card, { backgroundColor: colors.surfaceContainerHigh }]}>
              <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>
                {transcript}
                {partialTranscript ? (
                  <Text style={{ color: colors.onSurfaceVariant, fontStyle: 'italic' }}>
                    {transcript ? ' ' : ''}{partialTranscript}
                  </Text>
                ) : null}
              </Text>
            </View>
          </View>
        )}

        {/* No speech card — show after a completed transcription with empty result */}
        {transcript === '' && !isRecording && !isProcessing && confidence !== null && (
          <View style={[styles.labeledSection, { marginTop: dimens.spacing.lg, gap: dimens.spacing.sm }]}>
            <Text style={[typography.titleSmall, { color: colors.onSurfaceVariant }]}>Transcript</Text>
            <View style={[styles.card, { backgroundColor: colors.surfaceContainerHigh }]}>
              <Text style={[typography.bodyLarge, { color: colors.onSurfaceVariant }]}>No speech recognized.</Text>
            </View>
          </View>
        )}

        {/* Audio Stats */}
        {confidence !== null && !isRecording && !isProcessing && (
          <View style={[styles.labeledSection, { marginTop: dimens.spacing.lg, gap: dimens.spacing.sm }]}>
            <Text style={[typography.titleSmall, { color: colors.onSurfaceVariant }]}>Audio stats</Text>
            <View style={[styles.card, { backgroundColor: colors.surfaceContainerHigh }]}>
              <View style={styles.statRow}>
                <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}>Confidence</Text>
                <Text style={[typography.bodyMedium, { color: colors.onSurface, fontWeight: '600', fontVariant: ['tabular-nums'] }]}>
                  {Math.round(confidence * 100)}%
                </Text>
              </View>
            </View>
          </View>
        )}

        <View style={{ height: insets.bottom + dimens.spacing.xl }} />
      </ScrollView>

      <ModelSelectionSheet
        visible={showModelSelection}
        context={ModelSelectionContext.STT}
        onClose={() => setShowModelSelection(false)}
        onModelSelected={handleModelSelected}
      />
    </View>
  );
};

interface LevelBarsProps {
  audioLevel: number;
  colors: ReturnType<typeof useTheme>['colors'];
  dimens: ReturnType<typeof useTheme>['dimens'];
}

const LevelBars: React.FC<LevelBarsProps> = ({ audioLevel, colors, dimens }) => {
  const active = Math.floor(audioLevel * BAR_COUNT);
  return (
    <View style={[styles.levelBars, { gap: dimens.spacing.xs }]}>
      {Array.from({ length: BAR_COUNT }, (_, i) => (
        <View
          key={i}
          style={[
            styles.levelBar,
            {
              height: 8 + i * 2,
              borderRadius: dimens.radius.full,
              backgroundColor: i < active ? colors.success : colors.surfaceContainerHighest,
            },
          ]}
        />
      ))}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scroll: {
    flex: 1,
  },
  content: {
    alignItems: 'center',
  },
  topBar: {
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
  headerSection: {
    alignItems: 'center',
    width: '100%',
  },
  iconCircle: {
    width: 64,
    height: 64,
    borderRadius: 32,
    alignItems: 'center',
    justifyContent: 'center',
  },
  modeContainer: {
    width: '100%',
    borderRadius: 999,
  },
  modePad: {
    flexDirection: 'row',
    padding: 4,
  },
  modeTab: {
    flex: 1,
    paddingVertical: 8,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
  },
  modelCard: {
    width: '100%',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 16,
    borderRadius: 20,
  },
  modelCardText: {
    flex: 1,
    gap: 2,
  },
  recordSection: {
    alignItems: 'center',
  },
  recordButton: {
    width: 96,
    height: 96,
    borderRadius: 48,
    alignItems: 'center',
    justifyContent: 'center',
  },
  statusLine: {
    width: '100%',
    alignItems: 'center',
    minHeight: 40,
  },
  statusCenter: {
    alignItems: 'center',
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  levelBars: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  levelBar: {
    width: 5,
  },
  labeledSection: {
    width: '100%',
  },
  labelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  card: {
    borderRadius: 20,
    padding: 16,
  },
  statRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
});

export default STTScreen;
