import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { RunAnywhere } from '@runanywhere/core';
import {
  JSONSchema,
  JSONSchemaProperty,
  JSONSchemaType,
} from '@runanywhere/proto-ts/structured_output';
import {
  ToolCall,
  ToolDefinition,
  ToolParameterType,
} from '@runanywhere/proto-ts/tool_calling';
import {
  ModelCategory,
  ModelLoadRequest,
} from '@runanywhere/proto-ts/model_types';
import { isModelLoadedForCategory } from '../utils/runAnywhereLifecycle';
import { attachLoRAFixture } from '../utils/loraFixture';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing } from '../theme/spacing';

const ACTION_LOG_PREFIX = '[RN_VALIDATION_ACTION]';
// Mirrors Voice Assistant Setup in the iOS app (VoiceAgentViewModel.swift):
// vad.synthetic_* actions invoke RunAnywhere.detectVoiceActivity, which in
// turn calls rac_vad_process_lifecycle_proto. Without a loaded VAD model the
// commons ABI returns "VAD lifecycle model is not loaded" — the harness must
// load silero-vad up-front so the synthetic_silence / synthetic_tone actions
// have a deterministic precondition (CLUSTER-03 / RN-VAD-001).
const SILERO_VAD_MODEL_ID = 'silero-vad';

type VadReadiness = 'idle' | 'loading' | 'ready' | 'failed';

type HarnessStatus = 'PASS' | 'FAIL' | 'EXPECTED_ERROR';

type HarnessActionId =
  | 'structured.extract_fixture'
  | 'structured.generate_fixture'
  | 'tools.get_device_label'
  | 'vad.synthetic_silence'
  | 'vad.synthetic_tone'
  | 'lora.list'
  | 'lora.compatibility'
  | 'lora.apply_fixture'
  | 'lora.remove_fixture'
  | 'pluginloader.snapshot'
  | 'pluginloader.load_empty_error';

interface HarnessAction {
  id: HarnessActionId;
  title: string;
  detail: string;
  run: () => Promise<unknown>;
}

interface HarnessRecord {
  id: HarnessActionId;
  status: HarnessStatus;
  startedAt: string;
  completedAt: string;
  durationMs: number;
  input?: unknown;
  output?: unknown;
  error?: string;
}

const bytesToString = (bytes: Uint8Array): string => {
  let text = '';
  for (const byte of bytes) {
    text += String.fromCharCode(byte);
  }
  return text;
};

const sanitizeForLog = (value: unknown): unknown => {
  if (value instanceof Uint8Array) {
    const text = bytesToString(value);
    return {
      byteLength: value.byteLength,
      text,
    };
  }
  if (value instanceof Float32Array) {
    return {
      frameCount: value.length,
      firstSamples: Array.from(value.slice(0, 8)),
    };
  }
  if (Array.isArray(value)) {
    return value.map(sanitizeForLog);
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, sanitizeForLog(entry)])
    );
  }
  return value;
};

const createStructuredSchema = (): JSONSchema =>
  JSONSchema.fromPartial({
    type: JSONSchemaType.JSON_SCHEMA_TYPE_OBJECT,
    title: 'React Native validation fixture',
    additionalProperties: false,
    required: ['route', 'score', 'passed'],
    properties: {
      route: JSONSchemaProperty.fromPartial({
        type: JSONSchemaType.JSON_SCHEMA_TYPE_STRING,
        enumValues: ['validation'],
      }),
      score: JSONSchemaProperty.fromPartial({
        type: JSONSchemaType.JSON_SCHEMA_TYPE_INTEGER,
        minimum: 0,
        maximum: 100,
      }),
      passed: JSONSchemaProperty.fromPartial({
        type: JSONSchemaType.JSON_SCHEMA_TYPE_BOOLEAN,
      }),
    },
  });

const createSyntheticAudio = (kind: 'silence' | 'tone'): Float32Array => {
  const sampleRate = 16000;
  const audio = new Float32Array(sampleRate);
  if (kind === 'tone') {
    for (let index = 0; index < audio.length; index += 1) {
      audio[index] = Math.sin((2 * Math.PI * 440 * index) / sampleRate) * 0.2;
    }
  }
  return audio;
};

const getErrorMessage = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

export const ValidationHarnessScreen: React.FC = () => {
  const [records, setRecords] = useState<HarnessRecord[]>([]);
  const [runningId, setRunningId] = useState<HarnessActionId | null>(null);
  const [vadReadiness, setVadReadiness] = useState<VadReadiness>('idle');
  const [vadError, setVadError] = useState<string | null>(null);

  // Ensure silero-vad is loaded before vad.synthetic_* actions can run.
  // Mirrors Voice Assistant Setup → silero-vad auto-load on iOS
  // (VoiceAgentViewModel.swift): without this precondition the underlying
  // rac_vad_process_lifecycle_proto returns RAC_ERROR_NOT_INITIALIZED with
  // "VAD lifecycle model is not loaded" — see CLUSTER-03 / RN-VAD-001.
  //
  // Commons `rac_model_lifecycle_load_proto` owns the canonical
  // download→load atom when `validateAvailability=true`: if the registered
  // ModelInfo has no local artifact and advertises a download source, the
  // SDK drives the download plan→start→poll cycle internally before
  // proceeding with the load. The example never reaches into multi-step
  // orchestration (see CLUSTER-19 / examples-react-native-002).
  useEffect(() => {
    let cancelled = false;
    const ensureVadLoaded = async () => {
      try {
        const alreadyLoaded = await isModelLoadedForCategory(
          ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
        );
        if (cancelled) return;
        if (alreadyLoaded) {
          setVadReadiness('ready');
          return;
        }

        setVadReadiness('loading');
        const result = await RunAnywhere.loadModel(
          ModelLoadRequest.fromPartial({
            modelId: SILERO_VAD_MODEL_ID,
            category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
            forceReload: false,
            validateAvailability: true,
          })
        );
        if (cancelled) return;
        if (result.success) {
          setVadReadiness('ready');
          setVadError(null);
        } else {
          setVadReadiness('failed');
          setVadError(result.errorMessage || 'Unknown VAD load error');
        }
      } catch (error) {
        if (cancelled) return;
        setVadReadiness('failed');
        setVadError(getErrorMessage(error));
      }
    };
    // void: deliberate fire-and-forget; setVadReadiness handles outcome.
    // eslint-disable-next-line no-void
    void ensureVadLoaded();
    return () => {
      cancelled = true;
    };
  }, []);

  const recordAction = useCallback(
    async (
      id: HarnessActionId,
      input: unknown,
      run: () => Promise<unknown>,
      expectedError = false
    ) => {
      const started = Date.now();
      const startedAt = new Date(started).toISOString();
      setRunningId(id);
      try {
        const output = await run();
        const completed = Date.now();
        const record: HarnessRecord = {
          id,
          status: 'PASS',
          startedAt,
          completedAt: new Date(completed).toISOString(),
          durationMs: completed - started,
          input: sanitizeForLog(input),
          output: sanitizeForLog(output),
        };
        // eslint-disable-next-line no-console -- validation actions are captured from Metro as JSONL evidence.
        console.log(`${ACTION_LOG_PREFIX} ${JSON.stringify(record)}`);
        setRecords((previous) => [record, ...previous]);
      } catch (error) {
        const completed = Date.now();
        const record: HarnessRecord = {
          id,
          status: expectedError ? 'EXPECTED_ERROR' : 'FAIL',
          startedAt,
          completedAt: new Date(completed).toISOString(),
          durationMs: completed - started,
          input: sanitizeForLog(input),
          error: getErrorMessage(error),
        };
        // eslint-disable-next-line no-console -- validation actions are captured from Metro as JSONL evidence.
        console.log(`${ACTION_LOG_PREFIX} ${JSON.stringify(record)}`);
        setRecords((previous) => [record, ...previous]);
      } finally {
        setRunningId(null);
      }
    },
    []
  );

  const actions = useMemo<HarnessAction[]>(
    () => [
      {
        id: 'structured.extract_fixture',
        title: 'Structured Parse',
        detail: 'Extract fixed JSON against a fixed schema.',
        run: async () => {
          const schema = createStructuredSchema();
          const result = await RunAnywhere.extractStructuredOutput(
            '{"route":"validation","score":100,"passed":true}',
            schema
          );
          return {
            rawText: result.rawText,
            parsedJson: result.parsedJson,
            validation: result.validation,
            errorCode: result.errorCode,
          };
        },
      },
      {
        id: 'structured.generate_fixture',
        title: 'Structured Generate',
        detail: 'Ask the loaded LLM for the same schema-shaped payload.',
        run: async () =>
          RunAnywhere.generateStructured(
            'Return JSON only: route validation, score 100, passed true.',
            createStructuredSchema()
          ),
      },
      {
        id: 'tools.get_device_label',
        title: 'Tool Call',
        detail: 'Register and execute get_device_label without network input.',
        run: async () => {
          await RunAnywhere.unregisterTool('get_device_label');
          await RunAnywhere.registerTool(
            ToolDefinition.fromPartial({
              name: 'get_device_label',
              description:
                'Returns a deterministic label for the current RN runtime.',
              parameters: [
                {
                  name: 'includeDeviceId',
                  type: ToolParameterType.TOOL_PARAMETER_TYPE_BOOLEAN,
                  description: 'Whether to include the persisted device id.',
                  required: false,
                },
              ],
              metadata: { lane: 'react-native-validation' },
            }),
            async (args) => {
              const includeDeviceId = args.includeDeviceId === true;
              const deviceId = includeDeviceId
                ? await RunAnywhere.deviceId
                : '';
              return {
                label: `${Platform.OS}-${Platform.Version}`,
                platform: Platform.OS,
                version: String(Platform.Version),
                deviceIdSuffix: deviceId ? deviceId.slice(-6) : '',
              };
            }
          );
          const result = await RunAnywhere.executeTool(
            ToolCall.fromPartial({
              id: 'rn-validation-tool-call-001',
              name: 'get_device_label',
              argumentsJson: '{"includeDeviceId":false}',
              type: 'function',
              createdAtMs: Date.now(),
            })
          );
          const registeredTools = await RunAnywhere.getRegisteredTools();
          return {
            registeredTools: registeredTools.map((tool) => tool.name),
            result,
          };
        },
      },
      {
        id: 'vad.synthetic_silence',
        title: 'VAD Silence',
        detail: 'Run standalone VAD on one second of synthetic silence.',
        run: async () =>
          RunAnywhere.detectVoiceActivity(createSyntheticAudio('silence'), {
            threshold: 0.01,
            minSpeechDurationMs: 100,
            minSilenceDurationMs: 300,
            maxSpeechDurationMs: 0,
          }),
      },
      {
        id: 'vad.synthetic_tone',
        title: 'VAD Tone',
        detail: 'Run standalone VAD on one second of deterministic tone.',
        run: async () =>
          RunAnywhere.detectVoiceActivity(createSyntheticAudio('tone'), {
            threshold: 0.01,
            minSpeechDurationMs: 100,
            minSilenceDurationMs: 300,
            maxSpeechDurationMs: 0,
          }),
      },
      {
        id: 'lora.list',
        title: 'LoRA List',
        detail: 'Capture current adapter state.',
        run: async () => RunAnywhere.lora.list(),
      },
      {
        id: 'lora.compatibility',
        title: 'LoRA Compatibility',
        detail: 'Check a deterministic fixture adapter config.',
        run: async () => {
          const { config } = await attachLoRAFixture();
          return RunAnywhere.lora.checkCompatibility(config);
        },
      },
      {
        id: 'lora.apply_fixture',
        title: 'LoRA Apply',
        detail: 'Apply the fixture path and capture success or bridge error.',
        run: async () => {
          const { config } = await attachLoRAFixture();
          return RunAnywhere.lora.apply({
            requestId: `rn-validation-lora-apply-${Date.now()}`,
            adapters: [config],
            replaceExisting: true,
          });
        },
      },
      {
        id: 'lora.remove_fixture',
        title: 'LoRA Remove',
        detail: 'Remove the fixture adapter id/path and capture state.',
        run: async () => {
          const { adapterPath } = await attachLoRAFixture();
          return RunAnywhere.lora.remove({
            requestId: `rn-validation-lora-remove-${Date.now()}`,
            adapterIds: ['rn-validation-identity'],
            adapterPaths: [adapterPath],
            clearAll: false,
          });
        },
      },
      {
        id: 'pluginloader.snapshot',
        title: 'Plugin Snapshot',
        detail: 'Read loader version, counts, registered names, loaded list.',
        run: async () => ({
          apiVersion: await RunAnywhere.pluginLoader.apiVersion,
          registeredCount: await RunAnywhere.pluginLoader.registeredCount,
          registeredNames: await RunAnywhere.pluginLoader.registeredNames(),
          loaded: await RunAnywhere.pluginLoader.listLoaded(),
        }),
      },
      {
        id: 'pluginloader.load_empty_error',
        title: 'Plugin Error',
        detail: 'Verify empty plugin load returns a typed error.',
        run: async () => RunAnywhere.pluginLoader.load(''),
      },
    ],
    []
  );

  const runHarnessAction = useCallback(
    async (action: HarnessAction) => {
      const expectedError = action.id === 'pluginloader.load_empty_error';
      let fixtureAdapterPath: string | undefined;
      if (action.id.startsWith('lora.')) {
        try {
          fixtureAdapterPath = (await attachLoRAFixture()).adapterPath;
        } catch {
          fixtureAdapterPath = undefined;
        }
      }
      await recordAction(
        action.id,
        {
          screen: 'Validation',
          action: action.title,
          fixtureAdapterPath,
        },
        action.run,
        expectedError
      );
    },
    [recordAction]
  );

  const latestRecord = records[0];

  return (
    <SafeAreaView style={styles.container} testID="validation-harness-screen">
      <View style={styles.header}>
        <Text style={styles.title}>Validation</Text>
        <Text style={styles.subtitle}>
          Capture deterministic modality evidence as JSONL in Metro logs.
        </Text>
        <Text style={styles.prefix} testID="validation-log-prefix">
          {ACTION_LOG_PREFIX}
        </Text>
      </View>

      <ScrollView
        style={styles.content}
        contentContainerStyle={styles.contentInset}
      >
        <View style={styles.statusBanner} testID="validation-vad-status">
          <Text style={styles.statusBannerText}>
            {vadReadiness === 'loading'
              ? `Loading VAD model (${SILERO_VAD_MODEL_ID})...`
              : vadReadiness === 'ready'
                ? `VAD ready: ${SILERO_VAD_MODEL_ID}`
                : vadReadiness === 'failed'
                  ? `VAD load failed: ${vadError ?? 'unknown'}`
                  : 'Checking VAD model...'}
          </Text>
        </View>

        <View style={styles.actionGrid}>
          {actions.map((action) => {
            const isVadAction = action.id.startsWith('vad.');
            const vadGate = isVadAction && vadReadiness !== 'ready';
            const disabled = runningId !== null || vadGate;
            const isRunning = runningId === action.id;
            return (
              <TouchableOpacity
                key={action.id}
                testID={`validation-action-${action.id}`}
                accessibilityRole="button"
                accessibilityLabel={action.title}
                disabled={disabled}
                // void: TouchableOpacity onPress is sync; intentional fire-and-forget.
                // eslint-disable-next-line no-void
                onPress={() => void runHarnessAction(action)}
                style={[
                  styles.actionButton,
                  disabled && styles.actionButtonDisabled,
                  isRunning && styles.actionButtonRunning,
                ]}
              >
                <Text style={styles.actionTitle}>
                  {isRunning ? 'Running...' : action.title}
                </Text>
                <Text style={styles.actionDetail}>
                  {vadGate && vadReadiness === 'loading'
                    ? 'Loading VAD model...'
                    : vadGate
                      ? 'Waiting for VAD model load.'
                      : action.detail}
                </Text>
              </TouchableOpacity>
            );
          })}
        </View>

        <View style={styles.summary} testID="validation-latest-record">
          <Text style={styles.sectionTitle}>Latest Record</Text>
          <Text style={styles.monospace}>
            {latestRecord
              ? JSON.stringify(latestRecord, null, 2)
              : 'No validation actions captured yet.'}
          </Text>
        </View>

        <View style={styles.summary} testID="validation-action-log">
          <Text style={styles.sectionTitle}>Action Log</Text>
          {records.map((record) => (
            <Text
              key={`${record.id}-${record.startedAt}`}
              style={styles.logLine}
            >
              {JSON.stringify(record)}
            </Text>
          ))}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  header: {
    paddingHorizontal: Spacing.large,
    paddingTop: Spacing.mediumLarge,
    paddingBottom: Spacing.smallMedium,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Colors.borderLight,
  },
  title: {
    ...Typography.largeTitle,
    color: Colors.textPrimary,
  },
  subtitle: {
    ...Typography.body,
    color: Colors.textSecondary,
    marginTop: Spacing.xSmall,
  },
  prefix: {
    ...Typography.caption,
    color: Colors.primaryBlue,
    marginTop: Spacing.smallMedium,
    fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace' }),
  },
  content: {
    flex: 1,
  },
  contentInset: {
    padding: Spacing.large,
    gap: Spacing.large,
  },
  actionGrid: {
    gap: Spacing.smallMedium,
  },
  statusBanner: {
    borderWidth: 1,
    borderColor: Colors.borderLight,
    borderRadius: 8,
    padding: Spacing.smallMedium,
    backgroundColor: Colors.backgroundSecondary,
  },
  statusBannerText: {
    ...Typography.caption,
    color: Colors.textPrimary,
    fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace' }),
  },
  actionButton: {
    borderWidth: 1,
    borderColor: Colors.borderLight,
    borderRadius: 8,
    padding: Spacing.mediumLarge,
    backgroundColor: Colors.backgroundSecondary,
    minHeight: 76,
  },
  actionButtonDisabled: {
    opacity: 0.58,
  },
  actionButtonRunning: {
    borderColor: Colors.primaryBlue,
  },
  actionTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
  },
  actionDetail: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginTop: Spacing.xSmall,
  },
  summary: {
    borderWidth: 1,
    borderColor: Colors.borderLight,
    borderRadius: 8,
    padding: Spacing.mediumLarge,
    backgroundColor: Colors.backgroundSecondary,
  },
  sectionTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
    marginBottom: Spacing.smallMedium,
  },
  monospace: {
    ...Typography.caption,
    color: Colors.textPrimary,
    fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace' }),
  },
  logLine: {
    ...Typography.caption2,
    color: Colors.textPrimary,
    marginBottom: Spacing.xSmall,
    fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace' }),
  },
});

export default ValidationHarnessScreen;
