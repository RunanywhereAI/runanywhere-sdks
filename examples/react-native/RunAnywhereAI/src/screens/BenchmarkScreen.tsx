/**
 * BenchmarkScreen - on-device performance benchmarks.
 *
 * RN MVP mirror of iOS `BenchmarkDashboardView` + `BenchmarkRunner`:
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
import AsyncStorage from '@react-native-async-storage/async-storage';
import Icon from 'react-native-vector-icons/Ionicons';
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
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';
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

// Prompts copied verbatim from iOS LLMBenchmarkProvider.swift.
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

/** Mirrors iOS LLMBenchmarkProvider.execute. */
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
    // Warmup
    const warmupEvents = RunAnywhere.generateStream(
      'Hello',
      LLMGenerationOptions.fromPartial({ maxTokens: 5, temperature: 0 })
    );
    for await (const event of warmupEvents) {
      if (event.isFinal) break;
    }

    // Benchmark
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

/** Mirrors iOS STTBenchmarkProvider.execute. */
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

// Texts copied verbatim from iOS TTSBenchmarkProvider.swift.
const TTS_TEXTS: Record<'short' | 'medium', string> = {
  short: 'Hello, this is a test.',
  medium:
    'The quick brown fox jumps over the lazy dog. Machine learning models can ' +
    'generate speech from text with remarkable quality and natural intonation.',
};

/** Mirrors iOS TTSBenchmarkProvider.execute. */
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

/** Scenario lists mirror the iOS providers. */
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

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

export const BenchmarkScreen: React.FC = () => {
  const [selectedCategories, setSelectedCategories] = useState<
    Set<BenchmarkCategory>
  >(new Set(ALL_CATEGORIES));
  const [modelsByCategory, setModelsByCategory] = useState<
    Record<BenchmarkCategory, SDKModelInfo[]>
  >({ LLM: [], STT: [], TTS: [] });
  const [selectedModelIds, setSelectedModelIds] = useState<Set<string>>(
    new Set()
  );
  const [results, setResults] = useState<BenchmarkResultEntry[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [progressText, setProgressText] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const cancelRef = useRef(false);

  /**
   * Preflight: downloaded (on-disk) models grouped by category — mirrors
   * iOS BenchmarkRunner.preflight / downloadedModels(for:in:).
   */
  const refreshModels = useCallback(async () => {
    setError(null);
    try {
      await RunAnywhere.refreshModelRegistry();
      const listResult = await RunAnywhere.listModels();
      const allModels = listResult.models?.models ?? [];
      const grouped: Record<BenchmarkCategory, SDKModelInfo[]> = {
        LLM: [],
        STT: [],
        TTS: [],
      };
      for (const category of ALL_CATEGORIES) {
        grouped[category] = allModels.filter(
          (model) =>
            model.category === CATEGORY_MODEL_CATEGORY[category] &&
            Boolean(model.localPath && model.localPath.trim().length > 0)
        );
      }
      setModelsByCategory(grouped);
      // Default-select every downloaded model.
      setSelectedModelIds(
        new Set(
          ALL_CATEGORIES.flatMap((category) =>
            grouped[category].map((model) => model.id)
          )
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
      // History is best-effort; a corrupt entry should not break the screen.
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

  /** Expand (category x model x scenario) — mirrors iOS buildWorkItems. */
  const buildWorkItems = useCallback((): WorkItem[] => {
    const items: WorkItem[] = [];
    for (const category of ALL_CATEGORIES) {
      if (!selectedCategories.has(category)) continue;
      const models = modelsByCategory[category].filter((model) =>
        selectedModelIds.has(model.id)
      );
      for (const model of models) {
        for (const scenario of scenariosForCategory(category)) {
          items.push({
            category,
            model,
            scenario: scenario.name,
            run: scenario.run,
          });
        }
      }
    }
    return items;
  }, [selectedCategories, modelsByCategory, selectedModelIds]);

  const handleRun = useCallback(async () => {
    const workItems = buildWorkItems();
    if (workItems.length === 0) {
      setError(
        'No benchmarks to run. Download models first, then select at least one.'
      );
      return;
    }
    setIsRunning(true);
    setError(null);
    cancelRef.current = false;

    const newResults: BenchmarkResultEntry[] = [];
    for (let i = 0; i < workItems.length; i++) {
      if (cancelRef.current) break;
      const item = workItems[i];
      setProgressText(
        `${i + 1}/${workItems.length} — ${item.scenario} · ${item.model.name}`
      );
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

    setProgressText(null);
    setIsRunning(false);
    await persistResults([...newResults, ...results]);
  }, [buildWorkItems, persistResults, results]);

  const handleCancel = useCallback(() => {
    cancelRef.current = true;
    setProgressText('Cancelling after current scenario…');
  }, []);

  const handleClearResults = useCallback(async () => {
    await persistResults([]);
  }, [persistResults]);

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      {error && (
        <View style={styles.errorBox}>
          <Icon name="alert-circle" size={16} color={Colors.primaryRed} />
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}

      {/* Category chips */}
      <Text style={styles.sectionHeader}>CATEGORIES</Text>
      <View style={styles.chipRow}>
        {ALL_CATEGORIES.map((category) => {
          const selected = selectedCategories.has(category);
          return (
            <TouchableOpacity
              key={category}
              style={[styles.chip, selected && styles.chipSelected]}
              onPress={() => toggleCategory(category)}
              disabled={isRunning}
            >
              <Text
                style={[styles.chipText, selected && styles.chipTextSelected]}
              >
                {category}
              </Text>
            </TouchableOpacity>
          );
        })}
      </View>

      {/* Downloaded models per selected category */}
      {ALL_CATEGORIES.filter((category) =>
        selectedCategories.has(category)
      ).map((category) => (
        <View key={category} style={styles.modelSection}>
          <Text style={styles.sectionHeader}>{category} MODELS</Text>
          {modelsByCategory[category].length === 0 ? (
            <Text style={styles.emptyText}>
              No downloaded {category} models. Download from Settings → Model
              Catalog first.
            </Text>
          ) : (
            modelsByCategory[category].map((model) => {
              const selected = selectedModelIds.has(model.id);
              return (
                <TouchableOpacity
                  key={model.id}
                  style={styles.modelRow}
                  onPress={() => toggleModel(model.id)}
                  disabled={isRunning}
                >
                  <Icon
                    name={selected ? 'checkbox' : 'square-outline'}
                    size={20}
                    color={selected ? Colors.primaryBlue : Colors.textTertiary}
                  />
                  <Text style={styles.modelName}>{model.name}</Text>
                </TouchableOpacity>
              );
            })
          )}
        </View>
      ))}

      {/* Run / cancel */}
      {isRunning ? (
        <View style={styles.runArea}>
          <ActivityIndicator size="small" color={Colors.primaryBlue} />
          {progressText && (
            <Text style={styles.progressText}>{progressText}</Text>
          )}
          <TouchableOpacity style={styles.cancelButton} onPress={handleCancel}>
            <Text style={styles.cancelButtonText}>Cancel</Text>
          </TouchableOpacity>
        </View>
      ) : (
        <TouchableOpacity style={styles.runButton} onPress={handleRun}>
          <Icon name="speedometer-outline" size={18} color={Colors.textWhite} />
          <Text style={styles.runButtonText}>Run Benchmarks</Text>
        </TouchableOpacity>
      )}

      {/* Results */}
      {results.length > 0 && (
        <View style={styles.modelSection}>
          <View style={styles.resultsHeaderRow}>
            <Text style={styles.sectionHeader}>RESULTS</Text>
            <TouchableOpacity onPress={handleClearResults} disabled={isRunning}>
              <Text style={styles.clearText}>Clear All</Text>
            </TouchableOpacity>
          </View>
          {results.map((entry) => (
            <View key={entry.id} style={styles.resultCard}>
              <View style={styles.resultTitleRow}>
                <Text style={styles.resultScenario}>
                  {entry.category} · {entry.scenario}
                </Text>
                <Text style={styles.resultModel} numberOfLines={1}>
                  {entry.modelName}
                </Text>
              </View>
              {entry.errorMessage ? (
                <Text style={styles.resultError}>{entry.errorMessage}</Text>
              ) : (
                <Text style={styles.resultMetrics}>
                  Load {entry.loadTimeMs.toFixed(0)} ms · {entry.metricSummary}
                </Text>
              )}
            </View>
          ))}
        </View>
      )}
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  content: {
    padding: Padding.padding16,
  },
  errorBox: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    backgroundColor: Colors.badgeRed,
    borderRadius: BorderRadius.medium,
    padding: Padding.padding12,
    marginBottom: Spacing.medium,
  },
  errorText: {
    ...Typography.caption,
    color: Colors.primaryRed,
    flex: 1,
  },
  sectionHeader: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginBottom: Spacing.small,
  },
  chipRow: {
    flexDirection: 'row',
    gap: Spacing.small,
    marginBottom: Spacing.large,
  },
  chip: {
    borderWidth: 1,
    borderColor: Colors.primaryBlue,
    borderRadius: 16,
    paddingHorizontal: Padding.padding16,
    paddingVertical: 6,
  },
  chipSelected: {
    backgroundColor: Colors.primaryBlue,
  },
  chipText: {
    ...Typography.caption,
    color: Colors.primaryBlue,
  },
  chipTextSelected: {
    color: Colors.textWhite,
  },
  modelSection: {
    marginBottom: Spacing.large,
  },
  modelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    paddingVertical: Padding.padding8,
  },
  modelName: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    flex: 1,
  },
  emptyText: {
    ...Typography.caption,
    color: Colors.textTertiary,
  },
  runArea: {
    alignItems: 'center',
    gap: Spacing.small,
    marginVertical: Spacing.medium,
  },
  progressText: {
    ...Typography.caption,
    color: Colors.textSecondary,
    textAlign: 'center',
  },
  cancelButton: {
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding8,
  },
  cancelButtonText: {
    ...Typography.subheadline,
    color: Colors.primaryRed,
  },
  runButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.small,
    backgroundColor: Colors.primaryBlue,
    borderRadius: BorderRadius.medium,
    paddingVertical: Padding.padding12,
    marginVertical: Spacing.medium,
  },
  runButtonText: {
    ...Typography.headline,
    color: Colors.textWhite,
  },
  resultsHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  clearText: {
    ...Typography.caption,
    color: Colors.primaryRed,
  },
  resultCard: {
    backgroundColor: Colors.backgroundSecondary,
    borderRadius: BorderRadius.medium,
    padding: Padding.padding12,
    marginBottom: Spacing.small,
  },
  resultTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: Spacing.small,
  },
  resultScenario: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
  },
  resultModel: {
    ...Typography.caption,
    color: Colors.textSecondary,
    flexShrink: 1,
  },
  resultMetrics: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginTop: 4,
  },
  resultError: {
    ...Typography.caption,
    color: Colors.primaryRed,
    marginTop: 4,
  },
});

export default BenchmarkScreen;
