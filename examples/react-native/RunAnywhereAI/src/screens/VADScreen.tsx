/**
 * VADScreen - Voice Activity Detection demo.
 *
 * Mirrors the iOS VAD demo shape: load a VAD model, stream microphone frames
 * through RunAnywhere.streamVAD, and render speech/energy/confidence.
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import {
  SafeAreaView,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius, ButtonHeight } from '../theme/spacing';
import { ModelRequiredOverlay, ModelStatusBanner } from '../components/common';
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

export const VADScreen: React.FC = () => {
  const insets = useSafeAreaInsets();
  const [currentModel, setCurrentModel] = useState<SDKModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [isListening, setIsListening] = useState(false);
  const [latestResult, setLatestResult] = useState<VADResult | null>(null);
  const [frameCount, setFrameCount] = useState(0);

  const captureRef = useRef<AudioCaptureManager | null>(null);
  const streamRef = useRef<PushableAudioStream | null>(null);
  const taskRef = useRef<Promise<void> | null>(null);
  const isListeningRef = useRef(false);

  const getCapture = () => {
    if (!captureRef.current) {
      captureRef.current = new AudioCaptureManager();
    }
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

  const speechDetected = latestResult?.isSpeech ?? false;
  const confidence = Math.round((latestResult?.confidence ?? 0) * 100);
  const energy = latestResult?.energy ?? 0;

  if (!currentModel && !isModelLoading) {
    return (
      <SafeAreaView style={styles.container}>
        <View
          style={[
            styles.header,
            { paddingTop: insets.top + Padding.padding12 },
          ]}
        >
          <Text style={styles.title}>Voice Activity</Text>
        </View>
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
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <View
        style={[styles.header, { paddingTop: insets.top + Padding.padding12 }]}
      >
        <Text style={styles.title}>Voice Activity</Text>
      </View>
      <ModelStatusBanner
        modelName={currentModel?.name}
        framework={currentModel?.preferredFramework}
        isLoading={isModelLoading}
        onSelectModel={() => setShowModelSelection(true)}
        placeholder="Select a VAD model"
      />

      <View style={styles.content}>
        <View
          style={[
            styles.statusPanel,
            speechDetected && styles.statusPanelActive,
          ]}
        >
          <Icon
            name={speechDetected ? 'mic' : 'mic-outline'}
            size={48}
            color={speechDetected ? Colors.primaryGreen : Colors.textTertiary}
          />
          <Text style={styles.statusTitle}>
            {speechDetected ? 'Speech detected' : 'Silence'}
          </Text>
          <Text style={styles.statusSubtitle}>
            {frameCount} frames analyzed
          </Text>
        </View>

        <View style={styles.metricRow}>
          <Text style={styles.metricLabel}>Confidence</Text>
          <Text style={styles.metricValue}>{confidence}%</Text>
        </View>
        <View style={styles.meterTrack}>
          <View style={[styles.meterFill, { width: `${confidence}%` }]} />
        </View>
        <View style={styles.metricRow}>
          <Text style={styles.metricLabel}>Energy</Text>
          <Text style={styles.metricValue}>{energy.toFixed(3)}</Text>
        </View>
      </View>

      <View style={styles.controls}>
        <TouchableOpacity
          style={[styles.recordButton, isListening && styles.recordButtonStop]}
          onPress={() => {
            if (isListening) {
              void stopListening();
            } else {
              void startListening();
            }
          }}
        >
          <Icon
            name={isListening ? 'stop' : 'mic'}
            size={32}
            color={Colors.textWhite}
          />
        </TouchableOpacity>
        <Text style={styles.controlLabel}>
          {isListening ? 'Tap to stop' : 'Tap to listen'}
        </Text>
      </View>

      <ModelSelectionSheet
        visible={showModelSelection}
        context={ModelSelectionContext.VAD}
        onClose={() => setShowModelSelection(false)}
        onModelSelected={async (model) => {
          setShowModelSelection(false);
          await loadModel(model);
        }}
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
    paddingHorizontal: Padding.padding16,
    paddingBottom: Padding.padding12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
  },
  content: {
    flex: 1,
    padding: Padding.padding20,
    gap: Spacing.large,
  },
  statusPanel: {
    alignItems: 'center',
    padding: Padding.padding24,
    borderRadius: BorderRadius.large,
    backgroundColor: Colors.backgroundSecondary,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    gap: Spacing.small,
  },
  statusPanelActive: {
    borderColor: Colors.primaryGreen,
    backgroundColor: Colors.badgeGreen,
  },
  statusTitle: {
    ...Typography.title3,
    color: Colors.textPrimary,
  },
  statusSubtitle: {
    ...Typography.footnote,
    color: Colors.textSecondary,
  },
  metricRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  metricLabel: {
    ...Typography.body,
    color: Colors.textSecondary,
  },
  metricValue: {
    ...Typography.body,
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  meterTrack: {
    height: 8,
    borderRadius: 4,
    overflow: 'hidden',
    backgroundColor: Colors.backgroundGray5,
  },
  meterFill: {
    height: '100%',
    backgroundColor: Colors.primaryGreen,
  },
  controls: {
    alignItems: 'center',
    paddingVertical: Padding.padding20,
    paddingBottom: Padding.padding40,
  },
  recordButton: {
    width: ButtonHeight.large,
    height: ButtonHeight.large,
    borderRadius: ButtonHeight.large / 2,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primaryBlue,
  },
  recordButtonStop: {
    backgroundColor: Colors.primaryRed,
  },
  controlLabel: {
    ...Typography.footnote,
    color: Colors.textSecondary,
    marginTop: Spacing.smallMedium,
  },
});

export default VADScreen;
