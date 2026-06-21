import React, { useState, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Alert,
} from 'react-native';
import Slider from '@react-native-community/slider';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useFocusEffect } from '@react-navigation/native';
import { Icon, useTheme } from '../theme/system';
import { ModelRequiredOverlay } from '../components/common';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';

import { RunAnywhere } from '@runanywhere/core';
import {
  AudioFormat,
  ModelCategory,
  ModelLoadRequest,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import {
  isModelLoadedForCategory,
  unloadModelsForCategory,
} from '../utils/runAnywhereLifecycle';

const SURPRISE_PHRASES = [
  'The quick brown fox jumps over the lazy dog.',
  'To be or not to be, that is the question.',
  'All that glitters is not gold.',
  'Elementary, my dear Watson.',
  'May the force be with you.',
];

const listModels = async (): Promise<SDKModelInfo[]> =>
  (await RunAnywhere.listModels()).models?.models ?? [];
const loadModelWithRequest = RunAnywhere.loadModel;

// ─── Voice card ────────────────────────────────────────────────────────────

interface VoiceCardProps {
  voiceName: string | undefined;
  onPress: () => void;
}

const VoiceCard: React.FC<VoiceCardProps> = ({ voiceName, onPress }) => {
  const { colors, typography, dimens } = useTheme();
  return (
    <TouchableOpacity
      style={[styles.voiceCard, { backgroundColor: colors.surfaceContainerHigh, borderRadius: dimens.radius.lg }]}
      onPress={onPress}
      activeOpacity={0.7}
    >
      <View style={[styles.voiceIconTile, { backgroundColor: colors.surfaceVariant, borderRadius: dimens.radius.md }]}>
        <Icon name="speak" size={dimens.icon.md} color={colors.primary} />
      </View>
      <View style={styles.voiceCardText}>
        <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>Voice</Text>
        <Text style={[typography.bodyLarge, { color: colors.onSurface, fontWeight: '600' }]} numberOfLines={1}>
          {voiceName ?? 'Select a voice'}
        </Text>
      </View>
      <Icon name="chevronRight" size={dimens.icon.sm} color={colors.onSurfaceVariant} />
    </TouchableOpacity>
  );
};

// ─── Speed slider row ───────────────────────────────────────────────────────

interface SliderRowProps {
  label: string;
  valueText: string;
  value: number;
  onValueChange: (v: number) => void;
}

const SliderRow: React.FC<SliderRowProps> = ({ label, valueText, value, onValueChange }) => {
  const { colors, typography } = useTheme();
  return (
    <View style={styles.sliderRow}>
      <View style={styles.sliderHeader}>
        <Text style={[typography.bodyLarge, { color: colors.onSurface }]}>{label}</Text>
        <Text style={[typography.labelLarge, { color: colors.onSurfaceVariant, fontVariant: ['tabular-nums'] }]}>
          {valueText}
        </Text>
      </View>
      <Slider
        style={styles.slider}
        value={value}
        onValueChange={(v) => onValueChange(Math.round(v * 10) / 10)}
        minimumValue={0.5}
        maximumValue={2.0}
        step={0.1}
        minimumTrackTintColor={colors.primary}
        maximumTrackTintColor={colors.outlineVariant}
        thumbTintColor={colors.primary}
      />
    </View>
  );
};

// ─── Metrics card ───────────────────────────────────────────────────────────

interface TtsMetrics {
  durationMs?: number;
  sampleRate?: number;
  audioSizeBytes?: number;
}

interface MetricsCardProps {
  metrics: TtsMetrics;
}

const formatBytes = (bytes: number): string => {
  if (bytes >= 1_000_000) return `${(bytes / 1_000_000).toFixed(1)} MB`;
  if (bytes >= 1_000) return `${Math.round(bytes / 1_000)} KB`;
  return `${bytes} B`;
};

const MetricsCard: React.FC<MetricsCardProps> = ({ metrics }) => {
  const { colors, typography, dimens } = useTheme();
  const rows: [string, string][] = [];
  if (metrics.durationMs != null)
    rows.push(['Duration', `${(metrics.durationMs / 1000).toFixed(1)}s`]);
  if (metrics.audioSizeBytes != null)
    rows.push(['Audio size', formatBytes(metrics.audioSizeBytes)]);
  if (metrics.sampleRate != null)
    rows.push(['Sample rate', `${metrics.sampleRate} Hz`]);
  if (rows.length === 0) return null;
  return (
    <View style={[styles.metricsCard, { backgroundColor: colors.surfaceContainerHigh, borderRadius: dimens.radius.lg }]}>
      {rows.map(([label, value]) => (
        <View key={label} style={styles.metricRow}>
          <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}>{label}</Text>
          <Text style={[typography.labelLarge, { color: colors.onSurface, fontVariant: ['tabular-nums'] }]}>{value}</Text>
        </View>
      ))}
    </View>
  );
};

// ─── Main screen ────────────────────────────────────────────────────────────

export const TTSScreen: React.FC = () => {
  const { colors, typography, dimens } = useTheme();
  const insets = useSafeAreaInsets();

  const [text, setText] = useState('');
  const [speed, setSpeed] = useState(1.0);
  const [pitch, _setPitch] = useState(1.0);
  const [volume, setVolume] = useState(1.0);
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [isGenerating, setIsGenerating] = useState(false);
  const [currentModel, setCurrentModel] = useState<SDKModelInfo | null>(null);
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [lastMetrics, setLastMetrics] = useState<TtsMetrics | null>(null);
  const [error, setError] = useState<string | null>(null);

  const busy = isGenerating || isSpeaking;
  const hasText = text.trim().length > 0 && currentModel != null;
  const canSpeak = hasText && !busy;

  useEffect(() => {
    return () => {
      RunAnywhere.stopSpeaking().catch(() => {});
    };
  }, []);

  const loadModels = useCallback(async () => {
    try {
      const allModels = await listModels();
      const ttsModels = allModels.filter(
        (m: SDKModelInfo) => m.category === ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
      );
      setAvailableModels(ttsModels);
      if (!currentModel) {
        const loaded = await RunAnywhere.modelInfoForCategory(
          ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
        );
        if (loaded) setCurrentModel(loaded);
      }
    } catch (err) {
      console.warn('[TTSScreen] Error loading models:', err);
    }
  }, [currentModel]);

  useFocusEffect(
    useCallback(() => {
      loadModels();
    }, [loadModels])
  );

  const handleSelectModel = useCallback(() => {
    setShowModelSelection(true);
  }, []);

  const loadModel = useCallback(async (model: SDKModelInfo) => {
    try {
      setIsModelLoading(true);
      setError(null);
      if (!model.isDownloaded && !model.localPath) {
        Alert.alert('Error', 'Model has not been downloaded. Open the model picker to download it first.');
        return;
      }
      try {
        const wasLoaded = await isModelLoadedForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);
        if (wasLoaded) await unloadModelsForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);
      } catch (unloadErr) {
        console.warn('[TTSScreen] Error unloading previous model (ignoring):', unloadErr);
      }
      const result = await loadModelWithRequest(
        ModelLoadRequest.fromPartial({
          modelId: model.id,
          category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
          forceReload: false,
          validateAvailability: true,
        })
      );
      if (result.success) {
        const loaded = await RunAnywhere.modelInfoForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);
        setCurrentModel(loaded ?? model);
      } else {
        const msg = result.errorMessage || 'Native model lifecycle returned an unsuccessful load result';
        Alert.alert('Error', `Failed to load model: ${msg}`);
      }
    } catch (err) {
      console.error('[TTSScreen] Error loading model:', err);
      Alert.alert('Error', `Failed to load model: ${err}`);
    } finally {
      setIsModelLoading(false);
    }
  }, []);

  const handleModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      setShowModelSelection(false);
      await loadModel(model);
    },
    [loadModel]
  );

  const surpriseMe = useCallback(() => {
    const phrase = SURPRISE_PHRASES[Math.floor(Math.random() * SURPRISE_PHRASES.length)];
    setText(phrase);
  }, []);

  const handleSpeak = useCallback(async () => {
    if (!text.trim() || !currentModel) return;
    await RunAnywhere.stopSpeaking().catch(() => {});
    const isLoaded = await isModelLoadedForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);
    if (!isLoaded) {
      Alert.alert('Model Not Loaded', 'Please load a TTS model first.');
      return;
    }
    setIsSpeaking(true);
    setError(null);
    try {
      const sdkConfig = {
        voice: 'default',
        languageCode: '',
        speakingRate: speed,
        pitch,
        volume,
        enableSsml: false,
        audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
      };
      const result = await RunAnywhere.speak(text, sdkConfig);
      setLastMetrics({
        durationMs: result.durationMs,
        sampleRate: result.sampleRate,
        audioSizeBytes: result.audioSizeBytes,
      });
    } catch (err) {
      console.error('[TTSScreen] Speech error:', err);
      setError(`Failed to speak: ${err}`);
    } finally {
      setIsSpeaking(false);
    }
  }, [text, speed, pitch, volume, currentModel]);

  const handleStop = useCallback(async () => {
    await RunAnywhere.stopSpeaking().catch(() => {});
    setIsSpeaking(false);
    setIsGenerating(false);
  }, []);

  if (!currentModel && !isModelLoading) {
    return (
      <View style={[styles.root, { backgroundColor: colors.background }]}>
        <View style={[styles.headerBar, { paddingTop: insets.top + 8, borderBottomColor: colors.outlineVariant }]}>
          <Text style={[typography.titleLarge, { color: colors.onSurface, fontWeight: '700' }]}>
            Text to Speech
          </Text>
        </View>
        <ModelRequiredOverlay modality="tts" onSelectModel={handleSelectModel} />
        <ModelSelectionSheet
          visible={showModelSelection}
          context={ModelSelectionContext.TTS}
          onClose={() => setShowModelSelection(false)}
          onModelSelected={handleModelSelected}
        />
      </View>
    );
  }

  return (
    <SafeAreaView style={[styles.root, { backgroundColor: colors.background }]} edges={['bottom']}>
      {/* Header */}
      <View style={[styles.headerBar, { paddingTop: insets.top + 8, borderBottomColor: colors.outlineVariant }]}>
        <Text style={[typography.titleLarge, { color: colors.onSurface, fontWeight: '700' }]}>
          Text to Speech
        </Text>
      </View>

      <ScrollView
        style={styles.scroll}
        contentContainerStyle={[styles.scrollContent, { paddingHorizontal: dimens.screenPadding, paddingBottom: 120 }]}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
      >
        {/* Voice card */}
        <VoiceCard voiceName={currentModel?.name} onPress={handleSelectModel} />

        {/* Text input */}
        <TextInput
          style={[
            styles.textInput,
            {
              backgroundColor: colors.surfaceContainerHigh,
              borderColor: colors.outlineVariant,
              borderRadius: dimens.radius.lg,
              color: colors.onSurface,
            },
            typography.bodyLarge,
          ]}
          value={text}
          onChangeText={setText}
          placeholder="Text to speak"
          placeholderTextColor={colors.onSurfaceVariant}
          multiline
          textAlignVertical="top"
        />

        {/* Surprise me */}
        <TouchableOpacity style={styles.surpriseRow} onPress={surpriseMe} activeOpacity={0.7}>
          <Icon name="sparkles" size={dimens.icon.sm} color={colors.primary} />
          <Text style={[typography.labelLarge, { color: colors.primary, fontWeight: '600' }]}>
            Surprise me
          </Text>
        </TouchableOpacity>

        {/* Speed slider */}
        <SliderRow
          label="Speed"
          valueText={`${speed.toFixed(1)}×`}
          value={speed}
          onValueChange={setSpeed}
        />

        {/* Action row: Generate + Speak/Stop */}
        <View style={styles.actionRow}>
          {/* Generate (outlined style) */}
          <TouchableOpacity
            style={[
              styles.outlinedBtn,
              {
                borderColor: busy || !hasText ? colors.outlineVariant : colors.primary,
                borderRadius: dimens.radius.full,
                opacity: busy || !hasText ? 0.45 : 1,
              },
            ]}
            onPress={async () => {
              if (!currentModel || busy) return;
              setIsGenerating(true);
              try {
                await handleSpeak();
              } finally {
                setIsGenerating(false);
              }
            }}
            disabled={busy || !hasText}
            activeOpacity={0.7}
          >
            <Icon
              name="sparkles"
              size={dimens.icon.sm}
              color={busy || !hasText ? colors.onSurfaceVariant : colors.primary}
            />
            <Text
              style={[
                typography.labelLarge,
                { color: busy || !hasText ? colors.onSurfaceVariant : colors.primary, fontWeight: '700' },
              ]}
            >
              {isGenerating ? 'Generating…' : 'Generate'}
            </Text>
          </TouchableOpacity>

          {/* Speak / Stop (filled style) */}
          <TouchableOpacity
            style={[
              styles.filledBtn,
              {
                backgroundColor: isSpeaking || canSpeak ? colors.primary : colors.surfaceContainerHigh,
                borderRadius: dimens.radius.full,
              },
            ]}
            onPress={isSpeaking ? handleStop : handleSpeak}
            disabled={!isSpeaking && !canSpeak}
            activeOpacity={0.8}
          >
            <Icon
              name={isSpeaking ? 'close' : 'speak'}
              size={dimens.icon.sm}
              color={isSpeaking || canSpeak ? colors.onPrimary : colors.onSurfaceVariant}
            />
            <Text
              style={[
                typography.labelLarge,
                {
                  color: isSpeaking || canSpeak ? colors.onPrimary : colors.onSurfaceVariant,
                  fontWeight: '700',
                },
              ]}
            >
              {isSpeaking ? 'Stop' : 'Speak'}
            </Text>
          </TouchableOpacity>
        </View>

        {/* Metrics card */}
        {lastMetrics && <MetricsCard metrics={lastMetrics} />}

        {/* Error text */}
        {error && (
          <Text style={[typography.bodySmall, { color: colors.error, marginTop: 4 }]}>{error}</Text>
        )}
      </ScrollView>

      {/* Model selection sheet */}
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
  root: {
    flex: 1,
  },
  headerBar: {
    paddingHorizontal: 20,
    paddingBottom: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    gap: 16,
    paddingTop: 16,
  },
  voiceCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 16,
  },
  voiceIconTile: {
    width: 44,
    height: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
  voiceCardText: {
    flex: 1,
    gap: 2,
  },
  textInput: {
    minHeight: 120,
    padding: 14,
    borderWidth: 1,
  },
  surpriseRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    alignSelf: 'flex-start',
  },
  sliderRow: {
    gap: 4,
  },
  sliderHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  slider: {
    width: '100%',
    height: 36,
  },
  actionRow: {
    flexDirection: 'row',
    gap: 12,
  },
  outlinedBtn: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    height: 48,
    borderWidth: 1.5,
  },
  filledBtn: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    height: 48,
  },
  metricsCard: {
    padding: 16,
    gap: 10,
  },
  metricRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
});

export default TTSScreen;
