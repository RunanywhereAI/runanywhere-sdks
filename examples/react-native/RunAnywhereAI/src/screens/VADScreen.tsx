import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  Alert,
  Animated,
  Easing,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Icon, useTheme } from '../theme/system';
import { ModelRequiredOverlay } from '../components/common';
import {
  ModelSelectionContext,
  ModelSelectionSheet,
} from '../components/model';
import {
  RunAnywhere,
  AudioCaptureManager,
  createPushableAudioStream,
  type PushableAudioStream,
} from '@runanywhere/core';
import {
  ModelCategory,
  ModelLoadRequest,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import type { VADResult } from '@runanywhere/proto-ts/vad_options';

function chunkToArrayBuffer(chunk: Uint8Array): ArrayBuffer {
  return chunk.buffer.slice(
    chunk.byteOffset,
    chunk.byteOffset + chunk.byteLength
  ) as ArrayBuffer;
}

function pcm16ChunkToFloat32Bytes(chunk: Uint8Array): Uint8Array {
  const samples = RunAnywhere.pcm16ToFloat32(chunkToArrayBuffer(chunk));
  return new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength);
}

const BAR_COUNT = 12;

interface LogEntry {
  type: 'started' | 'ended';
  timestampMs: number;
}

export const VADScreen: React.FC = () => {
  const insets = useSafeAreaInsets();
  const { colors, dimens, typography } = useTheme();

  const [currentModel, setCurrentModel] = useState<SDKModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [isListening, setIsListening] = useState(false);
  const [latestResult, setLatestResult] = useState<VADResult | null>(null);
  const [frameCount, setFrameCount] = useState(0);
  const [activityLog, setActivityLog] = useState<LogEntry[]>([]);

  const captureRef = useRef<AudioCaptureManager | null>(null);
  const streamRef = useRef<PushableAudioStream | null>(null);
  const taskRef = useRef<Promise<void> | null>(null);
  const isListeningRef = useRef(false);
  const prevSpeechRef = useRef<boolean>(false);

  const pulseAnim = useRef(new Animated.Value(0)).current;
  const pulseLoopRef = useRef<Animated.CompositeAnimation | null>(null);

  const getCapture = () => {
    if (!captureRef.current) captureRef.current = new AudioCaptureManager();
    return captureRef.current;
  };

  const refreshLoadedModel = useCallback(async () => {
    const loaded = await RunAnywhere.modelInfoForCategory(
      ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
    ).catch(() => null);
    if (loaded) setCurrentModel(loaded);
  }, []);

  useEffect(() => {
    void refreshLoadedModel();
    return () => {
      isListeningRef.current = false;
      streamRef.current?.close();
      captureRef.current?.stopRecording();
    };
  }, [refreshLoadedModel]);

  const speechDetected = latestResult?.isSpeech ?? false;
  const audioLevel = Math.min(1, (latestResult?.energy ?? 0) * 5);

  useEffect(() => {
    if (speechDetected && !prevSpeechRef.current) {
      setActivityLog((prev) => [
        { type: 'started', timestampMs: Date.now() },
        ...prev,
      ]);
    } else if (!speechDetected && prevSpeechRef.current) {
      setActivityLog((prev) => [
        { type: 'ended', timestampMs: Date.now() },
        ...prev,
      ]);
    }
    prevSpeechRef.current = speechDetected;
  }, [speechDetected]);

  useEffect(() => {
    if (speechDetected) {
      pulseAnim.setValue(0);
      const loop = Animated.loop(
        Animated.timing(pulseAnim, {
          toValue: 1,
          duration: 1000,
          easing: Easing.linear,
          useNativeDriver: true,
        })
      );
      pulseLoopRef.current = loop;
      loop.start();
    } else {
      pulseLoopRef.current?.stop();
      pulseAnim.setValue(0);
    }
  }, [speechDetected, pulseAnim]);

  const loadModel = async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      if (!model.isDownloaded && !model.localPath) {
        Alert.alert('Model Required', 'Download the VAD model first.');
        return;
      }
      const result = await RunAnywhere.loadModel(
        ModelLoadRequest.fromPartial({
          modelId: model.id,
          category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
          forceReload: false,
          validateAvailability: true,
        })
      );
      if (result.success) {
        setCurrentModel(model);
      } else {
        Alert.alert(
          'Load Failed',
          result.errorMessage || 'Failed to load VAD model.'
        );
      }
    } finally {
      setIsModelLoading(false);
    }
  };

  const consumeVAD = async (results: AsyncIterable<VADResult>) => {
    const iterator = results[Symbol.asyncIterator]();
    try {
      let step = await iterator.next();
      while (!step.done && isListeningRef.current) {
        setLatestResult(step.value);
        setFrameCount((count) => count + 1);
        step = await iterator.next();
      }
    } finally {
      await iterator.return?.();
    }
  };

  const startListening = async () => {
    if (!currentModel) {
      Alert.alert('Model Required', 'Please select a VAD model first.');
      return;
    }
    const capture = getCapture();
    const granted = await capture.requestPermission();
    if (!granted) {
      Alert.alert('Microphone Required', 'Microphone permission is required.');
      return;
    }
    const stream = createPushableAudioStream();
    streamRef.current = stream;
    isListeningRef.current = true;
    setLatestResult(null);
    setFrameCount(0);
    taskRef.current = consumeVAD(RunAnywhere.streamVAD(stream.iterable));
    await capture.startRecording((chunk) => {
      stream.push(pcm16ChunkToFloat32Bytes(chunk));
    });
    setIsListening(true);
  };

  const stopListening = async () => {
    isListeningRef.current = false;
    getCapture().stopRecording();
    streamRef.current?.close();
    await taskRef.current;
    streamRef.current = null;
    taskRef.current = null;
    setIsListening(false);
  };

  const onToggle = () => {
    if (!currentModel) return;
    if (isListening) void stopListening();
    else void startListening();
  };

  const pulseScale = pulseAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [1, 1.3],
  });
  const pulseOpacity = pulseAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [1, 0],
  });

  const activeBarCount = Math.round(audioLevel * BAR_COUNT);

  if (!currentModel && !isModelLoading) {
    return (
      <View style={[styles.root, { backgroundColor: colors.background, paddingTop: insets.top }]}>
        <ModelRequiredOverlay
          modality="vad"
          onSelectModel={() => setShowModelSelection(true)}
        />
        <ModelSelectionSheet
          visible={showModelSelection}
          context={ModelSelectionContext.VAD}
          onClose={() => setShowModelSelection(false)}
          onModelSelected={async (model) => {
            setShowModelSelection(false);
            await loadModel(model);
          }}
        />
      </View>
    );
  }

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      <ScrollView
        contentContainerStyle={[
          styles.scroll,
          { paddingTop: insets.top + dimens.screenPadding, paddingHorizontal: dimens.screenPadding },
        ]}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View style={styles.header}>
          <View style={[styles.headerIcon, { backgroundColor: colors.primaryContainer }]}>
            <Icon name="vad" size={dimens.icon.lg} color={colors.onPrimaryContainer} />
          </View>
          <Text style={[typography.titleLarge, { color: colors.onSurface, marginTop: dimens.spacing.sm }]}>
            Voice Activity Detection
          </Text>
          <Text
            style={[
              typography.bodyMedium,
              styles.headerSubtitle,
              { color: colors.onSurfaceVariant, marginTop: dimens.spacing.xs },
            ]}
          >
            Detect speech activity in real-time, all on-device.
          </Text>
        </View>

        {/* Model card */}
        <TouchableOpacity
          style={[styles.modelCard, { backgroundColor: colors.surfaceContainerHigh }]}
          onPress={() => setShowModelSelection(true)}
          activeOpacity={0.7}
        >
          <Icon name="sparkles" size={dimens.icon.md} color={colors.primary} />
          <View style={styles.modelCardText}>
            <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>Model</Text>
            <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>
              {currentModel?.name ?? 'Select a model'}
            </Text>
          </View>
          <Icon name="chevronRight" size={dimens.icon.sm} color={colors.onSurfaceVariant} />
        </TouchableOpacity>

        {/* Speech indicator */}
        <View style={styles.indicatorSection}>
          <View style={styles.indicatorRing}>
            {speechDetected && (
              <Animated.View
                style={[
                  styles.pulseRing,
                  {
                    backgroundColor: colors.success + '40',
                    transform: [{ scale: pulseScale }],
                    opacity: pulseOpacity,
                  },
                ]}
              />
            )}
            <View
              style={[
                styles.outerCircle,
                {
                  backgroundColor: speechDetected
                    ? colors.success + '33'
                    : colors.surfaceContainerHigh,
                },
              ]}
            />
            <View
              style={[
                styles.innerCircle,
                {
                  backgroundColor: speechDetected
                    ? colors.success
                    : colors.surfaceContainerHighest,
                },
              ]}
            >
              <Icon
                name={speechDetected ? 'voice' : 'micOff'}
                size={dimens.icon.md}
                color={speechDetected ? colors.onPrimary : colors.onSurfaceVariant}
              />
            </View>
          </View>

          <Text
            style={[
              typography.titleMedium,
              {
                color: speechDetected ? colors.success : colors.onSurfaceVariant,
                marginTop: dimens.spacing.md,
              },
            ]}
          >
            {speechDetected ? 'Speech Detected' : 'Silence'}
          </Text>

          {isListening && (
            <View style={[styles.levelBars, { marginTop: dimens.spacing.md }]}>
              {Array.from({ length: BAR_COUNT }, (_, i) => (
                <View
                  key={i}
                  style={[
                    styles.levelBar,
                    {
                      height: 8 + i * 2,
                      backgroundColor:
                        i < activeBarCount ? colors.success : colors.surfaceContainerHighest,
                    },
                  ]}
                />
              ))}
            </View>
          )}
        </View>

        {/* Listen button */}
        <TouchableOpacity
          style={[
            styles.listenButton,
            {
              backgroundColor: !currentModel
                ? colors.surfaceContainerHighest
                : isListening
                ? colors.error
                : colors.primary,
              marginTop: dimens.spacing.sm,
            },
          ]}
          onPress={onToggle}
          disabled={!currentModel}
          activeOpacity={0.8}
        >
          <Icon
            name={isListening ? 'stop' : 'voice'}
            size={40}
            color={colors.onPrimary}
          />
        </TouchableOpacity>

        <Text
          style={[
            typography.bodyMedium,
            { color: colors.onSurfaceVariant, marginTop: dimens.spacing.md, textAlign: 'center' },
          ]}
        >
          {isListening
            ? 'Listening for speech…'
            : currentModel
            ? 'Tap to start detection'
            : 'Select a model to begin'}
        </Text>

        {/* Activity log */}
        {activityLog.length > 0 && (
          <View style={[styles.logSection, { marginTop: dimens.spacing.lg }]}>
            <View style={styles.logHeader}>
              <Text style={[typography.titleSmall, { color: colors.onSurfaceVariant, flex: 1 }]}>
                Activity Log
              </Text>
              <TouchableOpacity onPress={() => setActivityLog([])} hitSlop={8}>
                <Text style={[typography.labelLarge, { color: colors.primary }]}>Clear</Text>
              </TouchableOpacity>
            </View>
            <View style={[styles.logCard, { backgroundColor: colors.surfaceContainerHigh }]}>
              {activityLog.slice(0, 20).map((entry, i) => {
                const started = entry.type === 'started';
                const time = new Date(entry.timestampMs).toLocaleTimeString();
                return (
                  <View
                    key={i}
                    style={[
                      styles.logRow,
                      i > 0 && { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.outlineVariant },
                    ]}
                  >
                    <Icon
                      name="voice"
                      size={dimens.icon.sm}
                      color={started ? colors.success : colors.onSurfaceVariant}
                    />
                    <Text
                      style={[
                        typography.bodyMedium,
                        {
                          flex: 1,
                          color: started ? colors.onSurface : colors.onSurfaceVariant,
                          marginLeft: dimens.spacing.md,
                        },
                      ]}
                    >
                      {started ? 'Speech Started' : 'Speech Ended'}
                    </Text>
                    <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
                      {time}
                    </Text>
                  </View>
                );
              })}
            </View>
          </View>
        )}

        <View style={{ height: dimens.spacing.xl }} />
      </ScrollView>

      <ModelSelectionSheet
        visible={showModelSelection}
        context={ModelSelectionContext.VAD}
        onClose={() => setShowModelSelection(false)}
        onModelSelected={async (model) => {
          setShowModelSelection(false);
          await loadModel(model);
        }}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  scroll: {
    alignItems: 'center',
    gap: 16,
  },
  header: {
    alignItems: 'center',
    gap: 0,
    paddingVertical: 8,
  },
  headerIcon: {
    width: 64,
    height: 64,
    borderRadius: 32,
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerSubtitle: {
    textAlign: 'center',
    maxWidth: 280,
  },
  modelCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    alignSelf: 'stretch',
    borderRadius: 20,
    padding: 16,
  },
  modelCardText: {
    flex: 1,
    gap: 2,
  },
  indicatorSection: {
    alignItems: 'center',
    marginVertical: 8,
  },
  indicatorRing: {
    width: 140,
    height: 140,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pulseRing: {
    position: 'absolute',
    width: 120,
    height: 120,
    borderRadius: 60,
  },
  outerCircle: {
    position: 'absolute',
    width: 100,
    height: 100,
    borderRadius: 50,
  },
  innerCircle: {
    width: 60,
    height: 60,
    borderRadius: 30,
    alignItems: 'center',
    justifyContent: 'center',
  },
  levelBars: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  levelBar: {
    width: 5,
    borderRadius: 999,
  },
  listenButton: {
    width: 96,
    height: 96,
    borderRadius: 48,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 8,
  },
  logSection: {
    alignSelf: 'stretch',
    gap: 8,
  },
  logHeader: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  logCard: {
    borderRadius: 20,
    overflow: 'hidden',
  },
  logRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
});

export default VADScreen;
