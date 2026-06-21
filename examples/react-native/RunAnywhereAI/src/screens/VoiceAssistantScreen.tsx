import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Alert,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useFocusEffect } from '@react-navigation/native';
import { Icon, useTheme } from '../theme/system';
import type { IconName } from '../theme/system/icons';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model';
import type { VoiceConversationEntry } from '../types/voice';
import { VoicePipelineStatus } from '../types/voice';
import { RunAnywhere } from '@runanywhere/core';
import {
  ModelCategory,
  ModelLoadRequest,
  type ModelInfo as SDKModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { PipelineState as VoiceEventPipelineState } from '@runanywhere/proto-ts/voice_events';
import { VADStreamEventKind } from '@runanywhere/proto-ts/vad_options';
import type { VoiceEvent } from '@runanywhere/proto-ts/voice_events';
import { requestMicrophonePermission } from '../utils/micPermission';

const listModels = async (): Promise<SDKModelInfo[]> =>
  (await RunAnywhere.listModels()).models?.models ?? [];
const loadModelWithRequest = RunAnywhere.loadModel;

const generateId = () => Math.random().toString(36).substring(2, 15);

export const VoiceAssistantScreen: React.FC = () => {
  const { colors, typography, dimens } = useTheme();
  const insets = useSafeAreaInsets();

  const [sttModel, setSTTModel] = useState<SDKModelInfo | null>(null);
  const [llmModel, setLLMModel] = useState<SDKModelInfo | null>(null);
  const [ttsModel, setTTSModel] = useState<SDKModelInfo | null>(null);
  const [_availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);

  const [status, setStatus] = useState<VoicePipelineStatus>(VoicePipelineStatus.Idle);
  const [conversation, setConversation] = useState<VoiceConversationEntry[]>([]);
  const [isSessionActive, setIsSessionActive] = useState(false);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [activeSelectionContext, setActiveSelectionContext] =
    useState<ModelSelectionContext>(ModelSelectionContext.STT);

  const unsubscribeRef = useRef<(() => void) | null>(null);
  const scrollRef = useRef<ScrollView>(null);

  const allModelsLoaded = sttModel && llmModel && ttsModel;

  const cleanupVoiceSession = useCallback(async () => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
      unsubscribeRef.current = null;
    }
    try {
      await RunAnywhere.cleanupVoiceAgent();
    } catch (error) {
      console.warn('[VoiceAssistant] cleanupVoiceAgent failed:', error);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      checkModelStatus();
      loadAvailableModels();
    }, [])
  );

  useEffect(() => {
    return () => {
      void cleanupVoiceSession();
    };
  }, [cleanupVoiceSession]);

  useEffect(() => {
    if (conversation.length > 0) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 50);
    }
  }, [conversation.length]);

  const loadAvailableModels = async () => {
    try {
      const models = await listModels();
      setAvailableModels(models);
    } catch (error) {
      console.warn('[VoiceAssistant] Error loading models:', error);
    }
  };

  const checkModelStatus = async () => {
    try {
      const [loadedSTT, loadedLLM, loadedTTS] = await Promise.all([
        RunAnywhere.modelInfoForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION),
        RunAnywhere.modelInfoForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE),
        RunAnywhere.modelInfoForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS),
      ]);
      if (loadedSTT) setSTTModel(loadedSTT);
      if (loadedLLM) setLLMModel(loadedLLM);
      if (loadedTTS) setTTSModel(loadedTTS);
    } catch (error) {
      console.warn('[VoiceAssistant] Error checking model status:', error);
    }
  };

  const handleProtoEvent = useCallback(
    (event: VoiceEvent) => {
      if (event.state) {
        switch (event.state.current) {
          case VoiceEventPipelineState.PIPELINE_STATE_LISTENING:
            setStatus(VoicePipelineStatus.Listening);
            break;
          case VoiceEventPipelineState.PIPELINE_STATE_THINKING:
            setStatus(VoicePipelineStatus.Thinking);
            break;
          case VoiceEventPipelineState.PIPELINE_STATE_SPEAKING:
            setStatus(VoicePipelineStatus.Speaking);
            break;
          case VoiceEventPipelineState.PIPELINE_STATE_STOPPED:
            setStatus(VoicePipelineStatus.Idle);
            setIsSessionActive(false);
            void cleanupVoiceSession();
            break;
          default:
            break;
        }
        return;
      }

      if (event.vad) {
        if (event.vad.type === VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY) {
          if (event.vad.isSpeech) {
            console.warn('[VoiceAssistant] Speech started');
          } else {
            console.warn('[VoiceAssistant] Speech ended — processing');
            setStatus(VoicePipelineStatus.Processing);
          }
        }
        return;
      }

      if (event.userSaid?.text) {
        const text = event.userSaid.text;
        const userEntry: VoiceConversationEntry = {
          id: generateId(),
          speaker: 'user',
          text,
          timestamp: new Date(),
        };
        setConversation((prev) => [...prev, userEntry]);
        setStatus(VoicePipelineStatus.Thinking);
        return;
      }

      if (event.assistantToken?.text) {
        const token = event.assistantToken.text;
        setConversation((prev) => {
          const last = prev[prev.length - 1];
          if (last && last.speaker === 'assistant') {
            const updated = [...prev];
            updated[updated.length - 1] = { ...last, text: last.text + token };
            return updated;
          }
          return [
            ...prev,
            { id: generateId(), speaker: 'assistant', text: token, timestamp: new Date() },
          ];
        });
        return;
      }

      if (event.audio) {
        setStatus(VoicePipelineStatus.Speaking);
        return;
      }

      if (event.error) {
        console.error('[VoiceAssistant] Error:', event.error.message);
        setStatus(VoicePipelineStatus.Error);
        Alert.alert('Error', event.error.message || 'An error occurred');
        setTimeout(() => setStatus(VoicePipelineStatus.Idle), 2000);
        setIsSessionActive(false);
        void cleanupVoiceSession();
      }
    },
    [cleanupVoiceSession]
  );

  const handleToggleSession = useCallback(async () => {
    if (status === VoicePipelineStatus.Processing || status === VoicePipelineStatus.Thinking) {
      return;
    }
    if (isSessionActive) {
      await cleanupVoiceSession();
      setIsSessionActive(false);
      setStatus(VoicePipelineStatus.Idle);
      return;
    }
    if (!allModelsLoaded) {
      Alert.alert(
        'Models Required',
        'Please load all required models (STT, LLM, TTS) to use the voice assistant.'
      );
      return;
    }
    const hasMicPermission = await requestMicrophonePermission();
    if (!hasMicPermission) return;
    try {
      await RunAnywhere.initializeVoiceAgentWithLoadedModels();
      const eventStream = await RunAnywhere.streamVoiceAgent();
      const eventIterator = eventStream[Symbol.asyncIterator]();
      (async () => {
        try {
          while (true) {
            const { done, value } = await eventIterator.next();
            if (done) break;
            handleProtoEvent(value);
          }
        } catch (err) {
          if ((err as Error).name !== 'AbortError') {
            console.error('[VoiceAssistant] Stream error:', err);
          }
        }
      })();
      unsubscribeRef.current = () => {
        void eventIterator.return?.();
      };
      setIsSessionActive(true);
      setStatus(VoicePipelineStatus.Listening);
    } catch (error) {
      console.error('[VoiceAssistant] Failed to start voice agent:', error);
      await cleanupVoiceSession();
      Alert.alert('Error', `Failed to start voice agent: ${error}`);
    }
  }, [isSessionActive, allModelsLoaded, status, handleProtoEvent, cleanupVoiceSession]);

  const getSelectionContext = (type: 'stt' | 'llm' | 'tts'): ModelSelectionContext => {
    switch (type) {
      case 'stt': return ModelSelectionContext.STT;
      case 'llm': return ModelSelectionContext.LLM;
      case 'tts': return ModelSelectionContext.TTS;
    }
  };

  const handleSelectModel = useCallback((type: 'stt' | 'llm' | 'tts') => {
    setActiveSelectionContext(getSelectionContext(type));
    setShowModelSelection(true);
  }, []);

  const handleModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      setShowModelSelection(false);
      if (!model.isDownloaded && !model.localPath) {
        Alert.alert('Error', 'Model has not been downloaded. Open the model picker to download it first.');
        return;
      }
      try {
        switch (activeSelectionContext) {
          case ModelSelectionContext.STT: {
            const result = await loadModelWithRequest(
              ModelLoadRequest.fromPartial({
                modelId: model.id,
                category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
                forceReload: false,
                validateAvailability: true,
              })
            );
            if (result.success) {
              const loaded = await RunAnywhere.modelInfoForCategory(
                ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
              ).catch(() => null);
              setSTTModel(loaded ?? model);
            } else {
              Alert.alert('Error', `Failed to load model: ${result.errorMessage || 'Unknown error'}`);
            }
            break;
          }
          case ModelSelectionContext.LLM: {
            const result = await loadModelWithRequest(
              ModelLoadRequest.fromPartial({
                modelId: model.id,
                category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
                forceReload: false,
                validateAvailability: true,
              })
            );
            if (result.success) {
              const loaded = await RunAnywhere.modelInfoForCategory(
                ModelCategory.MODEL_CATEGORY_LANGUAGE
              ).catch(() => null);
              setLLMModel(loaded ?? model);
            } else {
              Alert.alert('Error', `Failed to load model: ${result.errorMessage || 'Unknown error'}`);
            }
            break;
          }
          case ModelSelectionContext.TTS: {
            const result = await loadModelWithRequest(
              ModelLoadRequest.fromPartial({
                modelId: model.id,
                category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                forceReload: false,
                validateAvailability: true,
              })
            );
            if (result.success) {
              const loaded = await RunAnywhere.modelInfoForCategory(
                ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
              ).catch(() => null);
              setTTSModel(loaded ?? model);
            } else {
              Alert.alert('Error', `Failed to load model: ${result.errorMessage || 'Unknown error'}`);
            }
            break;
          }
        }
      } catch (error) {
        Alert.alert('Error', `Failed to load model: ${error}`);
      }
    },
    [activeSelectionContext]
  );

  const handleClear = useCallback(() => {
    setConversation([]);
  }, []);

  const statusText = (): string => {
    if (!isSessionActive) return allModelsLoaded ? 'Tap to talk' : 'Setup required';
    switch (status) {
      case VoicePipelineStatus.Listening: return 'Listening… speak, then pause — tap to stop';
      case VoicePipelineStatus.Processing: return 'Transcribing…';
      case VoicePipelineStatus.Thinking: return 'Thinking…';
      case VoicePipelineStatus.Speaking: return 'Speaking…';
      default: return 'Tap to talk';
    }
  };

  const micButtonColor = (): string => {
    const starting = status === VoicePipelineStatus.Processing || status === VoicePipelineStatus.Thinking;
    if (!allModelsLoaded && !isSessionActive) return colors.surfaceContainerHighest;
    if (starting) return colors.secondary;
    if (status === VoicePipelineStatus.Listening) return colors.error;
    if (isSessionActive) return colors.secondary;
    return colors.primary;
  };

  const micButtonEnabled =
    !(status === VoicePipelineStatus.Processing || status === VoicePipelineStatus.Thinking);

  return (
    <View style={[styles.root, { backgroundColor: colors.background, paddingTop: insets.top }]}>
      {/* Setup card: LLM / STT / TTS rows */}
      <View style={[styles.setupCard, { backgroundColor: colors.surfaceContainerHigh, borderRadius: dimens.radius.lg }]}>
        <SetupRow
          iconName="chat"
          label="Language model"
          value={llmModel?.name ?? null}
          colors={colors}
          typography={typography}
          onPress={() => handleSelectModel('llm')}
        />
        <View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} />
        <SetupRow
          iconName="transcribe"
          label="Speech to text"
          value={sttModel?.name ?? null}
          colors={colors}
          typography={typography}
          onPress={() => handleSelectModel('stt')}
        />
        <View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} />
        <SetupRow
          iconName="speak"
          label="Voice"
          value={ttsModel?.name ?? null}
          colors={colors}
          typography={typography}
          onPress={() => handleSelectModel('tts')}
        />
      </View>

      {/* Conversation area / empty state */}
      <View style={styles.conversationArea}>
        {conversation.length === 0 ? (
          <View style={styles.emptyState}>
            <Text style={[typography.bodyLarge, { color: colors.onSurfaceVariant, textAlign: 'center' }]}>
              {allModelsLoaded
                ? 'Tap the mic and start talking'
                : 'Pick a model for each step to begin'}
            </Text>
          </View>
        ) : (
          <ScrollView
            ref={scrollRef}
            style={styles.scrollView}
            contentContainerStyle={[styles.scrollContent, { gap: dimens.spacing.sm }]}
            showsVerticalScrollIndicator={false}
          >
            {conversation.map((entry) => (
              <TurnBubble key={entry.id} entry={entry} colors={colors} typography={typography} dimens={dimens} />
            ))}
          </ScrollView>
        )}
      </View>

      {/* Error row (status === Error) */}
      {status === VoicePipelineStatus.Error && (
        <Text style={[typography.bodySmall, { color: colors.error, textAlign: 'center', paddingHorizontal: dimens.screenPadding }]}>
          An error occurred. Please try again.
        </Text>
      )}

      {/* Controls: status label + mic button + clear */}
      <View style={[styles.controls, { paddingBottom: insets.bottom + dimens.spacing.lg, gap: dimens.spacing.sm }]}>
        <Text style={[typography.bodyMedium, { color: colors.onSurfaceVariant }]}>
          {statusText()}
        </Text>

        <TouchableOpacity
          style={[styles.micButton, { backgroundColor: micButtonColor() }]}
          onPress={handleToggleSession}
          disabled={!micButtonEnabled}
          activeOpacity={0.8}
        >
          <Icon
            name={isSessionActive ? 'stop' : 'voice'}
            size={36}
            color={colors.onPrimary}
          />
        </TouchableOpacity>

        {conversation.length > 0 && (
          <TouchableOpacity onPress={handleClear} hitSlop={8} style={styles.clearBtn}>
            <Icon name="trash" size={dimens.icon.sm} color={colors.onSurfaceVariant} />
          </TouchableOpacity>
        )}
      </View>

      <ModelSelectionSheet
        visible={showModelSelection}
        context={activeSelectionContext}
        onClose={() => setShowModelSelection(false)}
        onModelSelected={handleModelSelected}
      />
    </View>
  );
};

interface SetupRowProps {
  iconName: IconName;
  label: string;
  value: string | null;
  colors: ReturnType<typeof useTheme>['colors'];
  typography: ReturnType<typeof useTheme>['typography'];
  onPress: () => void;
}

const SetupRow: React.FC<SetupRowProps> = ({ iconName, label, value, colors, typography, onPress }) => {
  const ready = value !== null;
  return (
    <TouchableOpacity style={styles.setupRow} onPress={onPress} activeOpacity={0.7}>
      <Icon
        name={iconName}
        size={22}
        color={ready ? colors.primary : colors.onSurfaceVariant}
      />
      <View style={styles.setupRowText}>
        <Text style={[typography.bodySmall, { color: colors.onSurfaceVariant }]}>{label}</Text>
        <Text style={[typography.bodyLarge, { color: colors.onSurface }]} numberOfLines={1}>
          {value ?? 'Tap to select'}
        </Text>
      </View>
      {ready && <View style={[styles.readyDot, { backgroundColor: colors.success }]} />}
      <Icon name="chevronRight" size={18} color={colors.onSurfaceVariant} />
    </TouchableOpacity>
  );
};

interface TurnBubbleProps {
  entry: VoiceConversationEntry;
  colors: ReturnType<typeof useTheme>['colors'];
  typography: ReturnType<typeof useTheme>['typography'];
  dimens: ReturnType<typeof useTheme>['dimens'];
}

const TurnBubble: React.FC<TurnBubbleProps> = ({ entry, colors, typography, dimens }) => {
  const isUser = entry.speaker === 'user';
  return (
    <View style={[styles.bubbleRow, { justifyContent: isUser ? 'flex-end' : 'flex-start' }]}>
      <View
        style={[
          styles.bubble,
          {
            backgroundColor: isUser ? colors.primary : colors.surfaceContainerHigh,
            borderRadius: dimens.radius.lg,
            maxWidth: '80%',
            paddingHorizontal: dimens.spacing.lg,
            paddingVertical: dimens.spacing.md,
          },
        ]}
      >
        <Text
          style={[
            typography.bodyLarge,
            { color: isUser ? colors.onPrimary : colors.onSurface },
          ]}
        >
          {entry.text.length === 0 ? '…' : entry.text}
        </Text>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  root: {
    flex: 1,
    paddingHorizontal: 16,
    gap: 12,
  },
  setupCard: {
    overflow: 'hidden',
  },
  setupRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  setupRowText: {
    flex: 1,
    gap: 2,
  },
  readyDot: {
    width: 8,
    height: 8,
    borderRadius: 999,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    opacity: 0.4,
  },
  conversationArea: {
    flex: 1,
  },
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 24,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingVertical: 4,
  },
  bubbleRow: {
    flexDirection: 'row',
  },
  bubble: {
    flexShrink: 1,
  },
  controls: {
    alignItems: 'center',
  },
  micButton: {
    width: 88,
    height: 88,
    borderRadius: 44,
    justifyContent: 'center',
    alignItems: 'center',
  },
  clearBtn: {
    padding: 6,
  },
});

export default VoiceAssistantScreen;
