/**
 * BenchmarkScreen - on-device performance benchmarks.
 *
 * RN mirror of Android BenchmarkDashboardScreen + BenchmarkDetailScreen:
 * runs (category x model x scenario) work items sequentially over downloaded
 * models and reports load time plus per-category key metrics. Scenario specs
 * mirror the iOS providers (LLMBenchmarkProvider / STTBenchmarkProvider /
 * TTSBenchmarkProvider).
 *
 * MVP scope: the VLM category is omitted — iOS's synthetic gradient-image
 * input has no RN analog (no native image generation in this app).
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { RunAnywhere } from '@runanywhere/core';
import { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';
import {
  AudioFormat,
  ModelCategory,
  ModelLoadRequest,
  ModelUnloadRequest,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { STTLanguage } from '@runanywhere/proto-ts/stt_options';
import { Icon, useTheme } from '../theme/system';
import {
  silentAudioWav,
  sineWaveAudioWav,
  SYNTHETIC_AUDIO_SAMPLE_RATE,
} from '../utils/syntheticAudio';

const HISTORY_STORAGE_KEY = 'benchmark.runs';

type BenchmarkCategory = 'LLM' | 'STT' | 'TTS';

const ALL_CATEGORIES: BenchmarkCategory[] = ['LLM', 'STT', 'TTS'];

const CATEGORY_MODEL_CATEGORY: Record<BenchmarkCategory, ModelCategory> = {
  LLM: ModelCategory.MODEL_CATEGORY_LANGUAGE,
  STT: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  TTS: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
};

interface BenchmarkResultEntry {
  id: string;
  category: BenchmarkCategory;
  scenario: string;
  modelName: string;
  loadTimeMs: number;
  /** Pre-formatted key metric line, e.g. "32.1 tok/s · TTFT 180 ms". */
  metricSummary: string;
  errorMessage?: string;
  timestampMs: number;
}

interface WorkItem {
  category: BenchmarkCategory;
  model: SDKModelInfo;
  scenario: string;
  run: (model: SDKModelInfo) => Promise<{
    loadTimeMs: number;
    metricSummary: string;
  }>;
}

// ---------------------------------------------------------------------------
// Scenario execution — mirrors the iOS benchmark providers.
// ---------------------------------------------------------------------------

const LLM_SYSTEM_PROMPT =
  'You are a helpful assistant. Always give extremely detailed, ' +
  'thorough responses. Never stop early. Use the full response length available ' +
  'to you. Elaborate on every point with examples and explanations.';
const LLM_PROMPT =
  'Write a very long and detailed explanation of how neural networks work, ' +
  'covering perceptrons, activation functions, backpropagation, gradient descent, ' +
  'loss functions, convolutional layers, recurrent layers, transformers, attention ' +
  'mechanisms, and training procedures. Be as thorough as possible.';

async function unloadCategory(category: ModelCategory): Promise<void> {
  await RunAnywhere.unloadModel(ModelUnloadRequest.fromPartial({ category }));
}

async function loadBenchmarkModel(
  model: SDKModelInfo,
  category: ModelCategory
): Promise<number> {
  const loadStart = Date.now();
  const result = await RunAnywhere.loadModel(
    ModelLoadRequest.fromPartial({ modelId: model.id, category })
  );
  if (!result.success) {
    throw new Error(result.errorMessage || `Failed to load ${model.id}`);
  }
  return Date.now() - loadStart;
}

async function runLLMScenario(
  model: SDKModelInfo,
  maxTokens: number
): Promise<{ loadTimeMs: number; metricSummary: string }> {
  await unloadCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
  const loadTimeMs = await loadBenchmarkModel(
    model,
    ModelCategory.MODEL_CATEGORY_LANGUAGE
  );
  try {
    const warmupEvents = RunAnywhere.generateStream(
      'Hello',
      LLMGenerationOptions.fromPartial({ maxTokens: 5, temperature: 0 })
    );
    for await (const event of warmupEvents) {
      if (event.isFinal) break;
    }

    const benchStart = Date.now();
    const events = RunAnywhere.generateStream(
      LLM_PROMPT,
      LLMGenerationOptions.fromPartial({
        maxTokens,
        temperature: 0,
        systemPrompt: LLM_SYSTEM_PROMPT,
        streamingEnabled: true,
      })
    );
    const result = await RunAnywhere.aggregateStream(LLM_PROMPT, events);
    const wallMs = Date.now() - benchStart;
    const generationMs =
      result.generationTimeMs > 0 ? result.generationTimeMs : wallMs;

    const parts = [`${generationMs.toFixed(0)} ms total`];
    if (result.ttftMs !== undefined && result.ttftMs > 0) {
      parts.push(`TTFT ${result.ttftMs.toFixed(0)} ms`);
    }
    if (result.tokensPerSecond > 0) {
      parts.push(`${result.tokensPerSecond.toFixed(1)} tok/s`);
    }
    if (result.tokensGenerated > 0) {
      parts.push(`${result.tokensGenerated} tokens`);
    }
    return { loadTimeMs, metricSummary: parts.join(' · ') };
  } finally {
    await unloadCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
  }
}

async function runSTTScenario(
  model: SDKModelInfo,
  type: 'silent' | 'sine'
): Promise<{ loadTimeMs: number; metricSummary: string }> {
  const loadTimeMs = await loadBenchmarkModel(
    model,
    ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
  );
  try {
    const durationSeconds = type === 'silent' ? 2 : 3;
    const wav =
      type === 'silent'
        ? silentAudioWav(durationSeconds)
        : sineWaveAudioWav(durationSeconds);

    const benchStart = Date.now();
    const result = await RunAnywhere.transcribe(wav, {
      language: STTLanguage.STT_LANGUAGE_EN,
      audioFormat: AudioFormat.AUDIO_FORMAT_WAV,
      sampleRate: SYNTHETIC_AUDIO_SAMPLE_RATE,
    });
    const latencyMs = Date.now() - benchStart;

    const parts = [`${latencyMs.toFixed(0)} ms`, `${durationSeconds}s audio`];
    const rtf = result.metadata?.realTimeFactor ?? 0;
    if (rtf > 0) {
      parts.push(`RTF ${rtf.toFixed(2)}`);
    }
    return { loadTimeMs, metricSummary: parts.join(' · ') };
  } finally {
    await unloadCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
  }
}

const TTS_TEXTS: Record<'short' | 'medium', string> = {
  short: 'Hello, this is a test.',
  medium:
    'The quick brown fox jumps over the lazy dog. Machine learning models can ' +
    'generate speech from text with remarkable quality and natural intonation.',
};

async function runTTSScenario(
  model: SDKModelInfo,
  length: 'short' | 'medium'
): Promise<{ loadTimeMs: number; metricSummary: string }> {
  const loadTimeMs = await loadBenchmarkModel(
    model,
    ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
  );
  try {
    const text = TTS_TEXTS[length];
    const benchStart = Date.now();
    const result = await RunAnywhere.synthesize(text);
    const latencyMs = Date.now() - benchStart;

    const parts = [`${latencyMs.toFixed(0)} ms`];
    if (result.durationMs > 0) {
      parts.push(`${(result.durationMs / 1000).toFixed(1)}s audio`);
    }
    const charCount = result.metadata?.characterCount ?? text.length;
    parts.push(`${charCount} chars`);
    return { loadTimeMs, metricSummary: parts.join(' · ') };
  } finally {
    await unloadCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);
  }
}

function scenariosForCategory(category: BenchmarkCategory): Array<{
  name: string;
  run: (model: SDKModelInfo) => Promise<{
    loadTimeMs: number;
    metricSummary: string;
  }>;
}> {
  switch (category) {
    case 'LLM':
      return [
        { name: 'Short (50 tokens)', run: (m) => runLLMScenario(m, 50) },
        { name: 'Medium (256 tokens)', run: (m) => runLLMScenario(m, 256) },
        { name: 'Long (512 tokens)', run: (m) => runLLMScenario(m, 512) },
      ];
    case 'STT':
      return [
        { name: 'Silent 2s', run: (m) => runSTTScenario(m, 'silent') },
        { name: 'Sine Tone 3s', run: (m) => runSTTScenario(m, 'sine') },
      ];
    case 'TTS':
      return [
        { name: 'Short Text', run: (m) => runTTSScenario(m, 'short') },
        { name: 'Medium Text', run: (m) => runTTSScenario(m, 'medium') },
      ];
  }
}

function formatTimestamp(ms: number): string {
  const d = new Date(ms);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) +
    ', ' +
    d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false });
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

export const BenchmarkScreen: React.FC = () => {
  const { colors, typography, dimens } = useTheme();
  const insets = useSafeAreaInsets();

  const [selectedCategories, setSelectedCategories] = useState<Set<BenchmarkCategory>>(
    new Set(ALL_CATEGORIES)
  );
  const [modelsByCategory, setModelsByCategory] = useState<Record<BenchmarkCategory, SDKModelInfo[]>>(
    { LLM: [], STT: [], TTS: [] }
  );
  const [selectedModelIds, setSelectedModelIds] = useState<Set<string>>(new Set());
  const [results, setResults] = useState<BenchmarkResultEntry[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [progressCurrent, setProgressCurrent] = useState(0);
  const [progressTotal, setProgressTotal] = useState(0);
  const [progressLabel, setProgressLabel] = useState('');
  const [error, setError] = useState<string | null>(null);
  const cancelRef = useRef(false);

  const refreshModels = useCallback(async () => {
    setError(null);
    try {
      await RunAnywhere.refreshModelRegistry();
      const listResult = await RunAnywhere.listModels();
      const allModels = listResult.models?.models ?? [];
      const grouped: Record<BenchmarkCategory, SDKModelInfo[]> = { LLM: [], STT: [], TTS: [] };
      for (const category of ALL_CATEGORIES) {
        grouped[category] = allModels.filter(
          (model) =>
            model.category === CATEGORY_MODEL_CATEGORY[category] &&
            Boolean(model.localPath && model.localPath.trim().length > 0)
        );
      }
      setModelsByCategory(grouped);
      setSelectedModelIds(
        new Set(
          ALL_CATEGORIES.flatMap((category) => grouped[category].map((model) => model.id))
        )
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }, []);

  const loadHistory = useCallback(async () => {
    try {
      const raw = await AsyncStorage.getItem(HISTORY_STORAGE_KEY);
      if (raw) {
        setResults(JSON.parse(raw) as BenchmarkResultEntry[]);
      }
    } catch {
      // History is best-effort.
    }
  }, []);

  useEffect(() => {
    loadHistory();
    refreshModels();
  }, [loadHistory, refreshModels]);

  const persistResults = useCallback(async (next: BenchmarkResultEntry[]) => {
    setResults(next);
    try {
      await AsyncStorage.setItem(HISTORY_STORAGE_KEY, JSON.stringify(next));
    } catch {
      // Best-effort persistence.
    }
  }, []);

  const toggleCategory = useCallback((category: BenchmarkCategory) => {
    setSelectedCategories((prev) => {
      const next = new Set(prev);
      if (next.has(category)) {
        next.delete(category);
      } else {
        next.add(category);
      }
      return next;
    });
  }, []);

  const toggleModel = useCallback((modelId: string) => {
    setSelectedModelIds((prev) => {
      const next = new Set(prev);
      if (next.has(modelId)) {
        next.delete(modelId);
      } else {
        next.add(modelId);
      }
      return next;
    });
  }, []);

  const buildWorkItems = useCallback((): WorkItem[] => {
    const items: WorkItem[] = [];
    for (const category of ALL_CATEGORIES) {
      if (!selectedCategories.has(category)) continue;
      const models = modelsByCategory[category].filter((model) =>
        selectedModelIds.has(model.id)
      );
      for (const model of models) {
        for (const scenario of scenariosForCategory(category)) {
          items.push({ category, model, scenario: scenario.name, run: scenario.run });
        }
      }
    }
    return items;
  }, [selectedCategories, modelsByCategory, selectedModelIds]);

  const handleRun = useCallback(async () => {
    const workItems = buildWorkItems();
    if (workItems.length === 0) {
      setError('No benchmarks to run. Download models first, then select at least one.');
      return;
    }
    setIsRunning(true);
    setError(null);
    cancelRef.current = false;
    setProgressTotal(workItems.length);

    const newResults: BenchmarkResultEntry[] = [];
    for (let i = 0; i < workItems.length; i++) {
      if (cancelRef.current) break;
      const item = workItems[i];
      setProgressCurrent(i + 1);
      setProgressLabel(`${item.category} · ${item.scenario} · ${item.model.name}`);
      const base = {
        id: `${Date.now()}-${i}`,
        category: item.category,
        scenario: item.scenario,
        modelName: item.model.name,
        timestampMs: Date.now(),
      };
      try {
        const metrics = await item.run(item.model);
        newResults.push({ ...base, ...metrics });
      } catch (err) {
        newResults.push({
          ...base,
          loadTimeMs: 0,
          metricSummary: '',
          errorMessage: err instanceof Error ? err.message : String(err),
        });
      }
    }

    setIsRunning(false);
    setProgressCurrent(0);
    setProgressTotal(0);
    setProgressLabel('');
    await persistResults([...newResults, ...results]);
  }, [buildWorkItems, persistResults, results]);

  const handleCancel = useCallback(() => {
    cancelRef.current = true;
    setProgressLabel('Cancelling after current scenario…');
  }, []);

  const handleClearResults = useCallback(async () => {
    await persistResults([]);
  }, [persistResults]);

  const selectedCount = selectedCategories.size;
  const progressFraction = progressTotal > 0 ? progressCurrent / progressTotal : 0;

  // Group results by category for display (mirrors KT detail screen).
  const resultsByCategory = ALL_CATEGORIES.reduce<Record<BenchmarkCategory, BenchmarkResultEntry[]>>(
    (acc, cat) => {
      acc[cat] = results.filter((r) => r.category === cat);
      return acc;
    },
    { LLM: [], STT: [], TTS: [] }
  );

  return (
    <ScrollView
      style={[styles.container, { backgroundColor: colors.background }]}
      contentContainerStyle={[
        styles.content,
        { paddingTop: insets.top + dimens.spacing.md, paddingBottom: insets.bottom + 24 },
      ]}
      showsVerticalScrollIndicator={false}
    >
      {/* Error banner */}
      {error && (
        <View style={[styles.errorBanner, { backgroundColor: colors.errorContainer }]}>
          <Icon name="info" size={dimens.icon.sm} color={colors.onErrorContainer} />
          <Text style={[typography.bodySmall, { color: colors.onErrorContainer, flex: 1 }]}>
            {error}
          </Text>
        </View>
      )}

      {/* Device card */}
      <View style={[styles.card, { backgroundColor: colors.surfaceContainerHigh }]}>
        <View style={[styles.iconTile, { backgroundColor: colors.surfaceVariant }]}>
          <Icon name="cpu" size={dimens.icon.md} color={colors.primary} />
        </View>
        <View style={styles.cardText}>
          <Text style={[typography.bodyLarge, styles.bold, { color: colors.onSurface }]} numberOfLines={1}>
            On-Device Benchmark
          </Text>
          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
            {ALL_CATEGORIES.flatMap((c) => modelsByCategory[c]).length} model{ALL_CATEGORIES.flatMap((c) => modelsByCategory[c]).length !== 1 ? 's' : ''} available
          </Text>
        </View>
      </View>

      {/* Categories section */}
      <Text style={[typography.titleSmall, styles.sectionLabel, { color: colors.onSurfaceVariant }]}>
        Categories
      </Text>
      <View style={styles.chipRow}>
        {ALL_CATEGORIES.map((category) => {
          const selected = selectedCategories.has(category);
          return (
            <TouchableOpacity
              key={category}
              style={[
                styles.filterChip,
                {
                  backgroundColor: selected ? colors.secondaryContainer : colors.surfaceContainerHigh,
                  borderColor: selected ? colors.secondary : colors.outline,
                },
              ]}
              onPress={() => toggleCategory(category)}
              disabled={isRunning}
              activeOpacity={0.7}
            >
              {selected && (
                <Icon name="check" size={14} color={colors.onSecondaryContainer} />
              )}
              <Text
                style={[
                  typography.labelLarge,
                  styles.bold,
                  { color: selected ? colors.onSecondaryContainer : colors.onSurfaceVariant },
                ]}
              >
                {category}
              </Text>
            </TouchableOpacity>
          );
        })}
      </View>

      {/* Models per selected category */}
      {ALL_CATEGORIES.filter((cat) => selectedCategories.has(cat)).map((category) => (
        <View key={category} style={styles.section}>
          <Text style={[typography.titleSmall, styles.sectionLabel, { color: colors.onSurfaceVariant }]}>
            {category} Models
          </Text>
          {modelsByCategory[category].length === 0 ? (
            <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}>
              No downloaded {category} models. Download from Settings → Model Catalog first.
            </Text>
          ) : (
            <View style={[styles.listCard, { backgroundColor: colors.surfaceContainerHigh }]}>
              {modelsByCategory[category].map((model, i) => {
                const selected = selectedModelIds.has(model.id);
                return (
                  <View key={model.id}>
                    {i > 0 && (
                      <View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} />
                    )}
                    <TouchableOpacity
                      style={styles.modelRow}
                      onPress={() => toggleModel(model.id)}
                      disabled={isRunning}
                      activeOpacity={0.7}
                    >
                      <View
                        style={[
                          styles.checkbox,
                          {
                            backgroundColor: selected ? colors.primary : 'transparent',
                            borderColor: selected ? colors.primary : colors.outline,
                          },
                        ]}
                      >
                        {selected && (
                          <Icon name="check" size={12} color={colors.onPrimary} />
                        )}
                      </View>
                      <Text
                        style={[typography.bodyLarge, { color: colors.onSurface, flex: 1 }]}
                        numberOfLines={1}
                      >
                        {model.name}
                      </Text>
                    </TouchableOpacity>
                  </View>
                );
              })}
            </View>
          )}
        </View>
      ))}

      {/* Run / Running card */}
      {isRunning ? (
        <View style={[styles.runningCard, { backgroundColor: colors.surfaceContainerHigh }]}>
          <View style={styles.runningHeader}>
            <ActivityIndicator size="small" color={colors.primary} />
            <Text style={[typography.bodyLarge, { color: colors.onSurface, flex: 1 }]}>
              {progressTotal > 0 ? `Running ${progressCurrent} / ${progressTotal}` : 'Running…'}
            </Text>
            <TouchableOpacity
              style={[styles.cancelPill, { borderColor: colors.outline }]}
              onPress={handleCancel}
              activeOpacity={0.7}
            >
              <Icon name="stop" size={14} color={colors.onSurface} />
              <Text style={[typography.labelLarge, styles.bold, { color: colors.onSurface }]}>
                Cancel
              </Text>
            </TouchableOpacity>
          </View>
          {progressTotal > 0 && (
            <View style={[styles.progressTrack, { backgroundColor: colors.surfaceContainerLowest }]}>
              <View
                style={[
                  styles.progressFill,
                  { backgroundColor: colors.primary, width: `${Math.round(progressFraction * 100)}%` },
                ]}
              />
            </View>
          )}
          {progressLabel.length > 0 && (
            <Text
              style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}
              numberOfLines={1}
            >
              {progressLabel}
            </Text>
          )}
        </View>
      ) : (
        <TouchableOpacity
          style={[
            styles.runButton,
            { backgroundColor: selectedCount > 0 ? colors.primary : colors.surfaceContainerHigh },
          ]}
          onPress={handleRun}
          activeOpacity={0.8}
          disabled={selectedCount === 0}
        >
          <Icon
            name="benchmarks"
            size={dimens.icon.sm}
            color={selectedCount > 0 ? colors.onPrimary : colors.onSurfaceVariant}
          />
          <Text
            style={[
              typography.titleSmall,
              styles.bold,
              { color: selectedCount > 0 ? colors.onPrimary : colors.onSurfaceVariant },
            ]}
          >
            Run selected ({selectedCount})
          </Text>
        </TouchableOpacity>
      )}

      {/* History */}
      {results.length > 0 ? (
        <View style={styles.section}>
          <View style={styles.sectionHeaderRow}>
            <Text style={[typography.titleSmall, styles.sectionLabel, { color: colors.onSurfaceVariant }]}>
              History
            </Text>
            <TouchableOpacity onPress={handleClearResults} disabled={isRunning} hitSlop={8}>
              <Text style={[typography.labelLarge, styles.bold, { color: colors.error }]}>
                Clear all
              </Text>
            </TouchableOpacity>
          </View>

          {ALL_CATEGORIES.map((cat) => {
            const catResults = resultsByCategory[cat];
            if (catResults.length === 0) return null;
            return (
              <View key={cat} style={styles.section}>
                <Text style={[typography.titleSmall, styles.sectionLabel, { color: colors.onSurfaceVariant }]}>
                  {cat}
                </Text>
                {catResults.map((entry) => (
                  <View
                    key={entry.id}
                    style={[styles.resultCard, { backgroundColor: colors.surfaceContainerHigh }]}
                  >
                    {/* Header row: success/fail icon + scenario + model */}
                    <View style={styles.resultHeaderRow}>
                      <Icon
                        name={entry.errorMessage ? 'close' : 'check'}
                        size={dimens.icon.sm}
                        color={entry.errorMessage ? colors.error : colors.success}
                      />
                      <View style={styles.resultTitleBlock}>
                        <Text
                          style={[typography.bodyLarge, { color: colors.onSurface }]}
                          numberOfLines={1}
                        >
                          {entry.scenario}
                        </Text>
                        <Text
                          style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}
                          numberOfLines={1}
                        >
                          {entry.modelName} · {formatTimestamp(entry.timestampMs)}
                        </Text>
                      </View>
                    </View>

                    {/* Metric rows */}
                    {entry.errorMessage ? (
                      <Text style={[typography.bodySmall, { color: colors.error, marginTop: 6 }]}>
                        {entry.errorMessage}
                      </Text>
                    ) : (
                      <View style={styles.metricGrid}>
                        <View style={styles.metricCell}>
                          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
                            Load time
                          </Text>
                          <Text style={[typography.metric, styles.bold, { color: colors.onSurface }]}>
                            {entry.loadTimeMs.toFixed(0)} ms
                          </Text>
                        </View>
                        <View style={[styles.metricCellDivider, { backgroundColor: colors.outlineVariant }]} />
                        <View style={styles.metricCell}>
                          <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>
                            Result
                          </Text>
                          <Text
                            style={[typography.bodySmall, styles.bold, { color: colors.onSurface }]}
                            numberOfLines={2}
                          >
                            {entry.metricSummary}
                          </Text>
                        </View>
                      </View>
                    )}
                  </View>
                ))}
              </View>
            );
          })}
        </View>
      ) : (
        !isRunning && (
          <Text style={[typography.bodyMedium, styles.emptyHistory, { color: colors.onSurfaceVariant }]}>
            No runs yet. Pick categories and run a benchmark across your downloaded models.
          </Text>
        )
      )}
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    paddingHorizontal: 16,
    gap: 12,
  },
  bold: {
    fontWeight: '700',
  },
  errorBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    borderRadius: 12,
    padding: 12,
  },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    borderRadius: 20,
    padding: 16,
  },
  iconTile: {
    width: 44,
    height: 44,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  cardText: {
    flex: 1,
    gap: 2,
  },
  sectionLabel: {
    marginBottom: 4,
  },
  sectionHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  section: {
    gap: 8,
  },
  chipRow: {
    flexDirection: 'row',
    gap: 8,
    flexWrap: 'wrap',
  },
  filterChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderWidth: 1,
    borderRadius: 999,
    paddingHorizontal: 14,
    paddingVertical: 7,
  },
  listCard: {
    borderRadius: 16,
    overflow: 'hidden',
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    marginLeft: 48,
  },
  modelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 14,
    paddingVertical: 13,
  },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: 6,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  runningCard: {
    borderRadius: 20,
    padding: 16,
    gap: 10,
  },
  runningHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  cancelPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    borderWidth: 1,
    borderRadius: 999,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  progressTrack: {
    height: 4,
    borderRadius: 999,
    overflow: 'hidden',
  },
  progressFill: {
    height: 4,
    borderRadius: 999,
  },
  runButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    borderRadius: 999,
    paddingVertical: 14,
  },
  resultCard: {
    borderRadius: 16,
    padding: 14,
    gap: 10,
  },
  resultHeaderRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 10,
  },
  resultTitleBlock: {
    flex: 1,
    gap: 2,
  },
  metricGrid: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'stretch',
  },
  metricCell: {
    flex: 1,
    gap: 2,
  },
  metricCellDivider: {
    width: StyleSheet.hairlineWidth,
  },
  emptyHistory: {
    textAlign: 'center',
    paddingVertical: 32,
    paddingHorizontal: 24,
  },
});

export default BenchmarkScreen;
