import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  NativeModules,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { AppIcon } from '../components/common/AppIcon';
import { pick as documentPick } from '@react-native-documents/picker';
import { useTheme } from '../theme';
import { Typography, FontWeight } from '../theme/typography';
import { BorderRadius, Padding, Spacing } from '../theme/spacing';
import type { ThemeColors } from '../theme/colors';
import {
  ModelSelectionContext,
  ModelSelectionSheet,
} from '../components/model/ModelSelectionSheet';
import {
  type ModelInfo as SDKModelInfo,
  initializeNitroModulesGlobally,
  ragCreatePipeline,
  ragDestroyPipeline,
  ragIngest,
  ragQuery,
} from '@runanywhere/core';

interface ChatMessage {
  role: 'user' | 'assistant';
  text: string;
}

function resolveEmbeddingFilePath(localPath: string): string {
  if (!localPath.endsWith('.onnx')) return `${localPath}/model.onnx`;
  return localPath;
}

function resolveLLMFilePath(localPath: string): string {
  if (localPath.endsWith('.gguf') || localPath.endsWith('.bin')) return localPath;
  return localPath;
}

const { DocumentService: NativeDocumentService } = NativeModules;

async function extractTextFromFile(filePath: string): Promise<string> {
  if (NativeDocumentService?.extractText) {
    return NativeDocumentService.extractText(filePath);
  }
  throw new Error('DocumentService native module not available');
}

type SetupSlotProps = {
  iconName: Parameters<typeof AppIcon>[0]['name'];
  label: string;
  value: string | null;
  placeholder: string;
  ready: boolean;
  onPress: () => void;
  disabled?: boolean;
};

const SetupSlot: React.FC<SetupSlotProps> = ({
  iconName,
  label,
  value,
  placeholder,
  ready,
  onPress,
  disabled,
}) => {
  const { colors } = useTheme();
  return (
    <TouchableOpacity
      onPress={onPress}
      disabled={disabled}
      activeOpacity={0.7}
      style={[
        slotStyles.row,
        {
          backgroundColor: colors.surface,
          borderColor: ready ? colors.primary : colors.border,
          opacity: disabled ? 0.5 : 1,
        },
      ]}
    >
      <View
        style={[
          slotStyles.iconWrap,
          { backgroundColor: ready ? colors.primarySoft : colors.surfaceAlt },
        ]}
      >
        <AppIcon
          name={iconName}
          size={18}
          color={ready ? colors.primary : colors.textSecondary}
        />
      </View>
      <View style={slotStyles.textWrap}>
        <Text
          style={[Typography.caption2, { color: colors.textSecondary }]}
        >
          {label.toUpperCase()}
        </Text>
        <Text
          style={[
            Typography.subheadline,
            {
              color: value ? colors.text : colors.textTertiary,
              fontWeight: value ? FontWeight.medium : FontWeight.regular,
            },
          ]}
          numberOfLines={1}
        >
          {value ?? placeholder}
        </Text>
      </View>
      {ready ? (
        <AppIcon name="checkmark-circle" size={18} color={colors.primary} />
      ) : (
        <AppIcon name="chevron-forward" size={18} color={colors.textTertiary} />
      )}
    </TouchableOpacity>
  );
};

export const RAGScreen: React.FC = () => {
  const { colors } = useTheme();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [isNitroReady, setIsNitroReady] = useState(false);
  const [nitroError, setNitroError] = useState<string | null>(null);

  const [selectedEmbeddingModel, setSelectedEmbeddingModel] =
    useState<SDKModelInfo | null>(null);
  const [selectedLLMModel, setSelectedLLMModel] = useState<SDKModelInfo | null>(null);
  const [showingEmbeddingPicker, setShowingEmbeddingPicker] = useState(false);
  const [showingLLMPicker, setShowingLLMPicker] = useState(false);

  const [documentName, setDocumentName] = useState<string | null>(null);
  const [isDocumentLoaded, setIsDocumentLoaded] = useState(false);
  const [isLoadingDocument, setIsLoadingDocument] = useState(false);

  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [currentQuestion, setCurrentQuestion] = useState('');
  const [isQuerying, setIsQuerying] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const scrollViewRef = useRef<ScrollView>(null);

  const areModelsReady =
    selectedEmbeddingModel?.localPath != null &&
    selectedLLMModel?.localPath != null;

  const canAskQuestion =
    isDocumentLoaded && !isQuerying && currentQuestion.trim().length > 0;

  useEffect(() => {
    let mounted = true;
    const timer = setTimeout(async () => {
      try {
        await initializeNitroModulesGlobally();
        if (mounted) {
          setIsNitroReady(true);
          setNitroError(null);
        }
      } catch (err) {
        if (mounted) {
          setNitroError(
            err instanceof Error ? err.message : 'Failed to initialize NitroModules'
          );
        }
      }
    }, 500);
    return () => {
      mounted = false;
      clearTimeout(timer);
    };
  }, []);

  useEffect(() => {
    return () => {
      if (isDocumentLoaded) {
        ragDestroyPipeline().catch(console.error);
      }
    };
  }, [isDocumentLoaded]);

  const handleSelectDocument = useCallback(async () => {
    if (!areModelsReady || !isNitroReady) return;
    try {
      const [result] = await documentPick({
        type: ['application/pdf', 'text/plain', 'application/json'],
      });
      const fileUri = result.uri;
      if (!fileUri) return;
      setIsLoadingDocument(true);
      setError(null);
      const text = await extractTextFromFile(fileUri);
      const embeddingPath = resolveEmbeddingFilePath(
        selectedEmbeddingModel!.localPath!
      );
      const llmPath = resolveLLMFilePath(selectedLLMModel!.localPath!);
      await ragCreatePipeline({
        embeddingModelPath: embeddingPath,
        llmModelPath: llmPath,
        topK: 3,
        similarityThreshold: 0.12,
        maxContextTokens: 2048,
        chunkSize: 180,
        chunkOverlap: 30,
      });
      await ragIngest(text);
      setDocumentName(result.name || 'Document');
      setIsDocumentLoaded(true);
    } catch (err) {
      const cancelErr = err as { code?: string };
      if (cancelErr?.code === 'OPERATION_CANCELED') return;
      const msg = err instanceof Error ? err.message : 'Failed to load document';
      setError(msg);
      console.error('[RAGScreen] Document load error:', err);
    } finally {
      setIsLoadingDocument(false);
    }
  }, [areModelsReady, isNitroReady, selectedEmbeddingModel, selectedLLMModel]);

  const handleChangeDocument = useCallback(async () => {
    await ragDestroyPipeline();
    setDocumentName(null);
    setIsDocumentLoaded(false);
    setMessages([]);
    setError(null);
    setCurrentQuestion('');
    handleSelectDocument();
  }, [handleSelectDocument]);

  const handleAskQuestion = useCallback(async () => {
    const question = currentQuestion.trim();
    if (!question || !isDocumentLoaded) return;
    setMessages((prev) => [...prev, { role: 'user', text: question }]);
    setCurrentQuestion('');
    setIsQuerying(true);
    setError(null);
    try {
      const result = await ragQuery(question, {
        maxTokens: 256,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
      });
      setMessages((prev) => [...prev, { role: 'assistant', text: result.answer }]);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Query failed';
      setError(msg);
      setMessages((prev) => [...prev, { role: 'assistant', text: `Error: ${msg}` }]);
    } finally {
      setIsQuerying(false);
    }
    setTimeout(() => scrollViewRef.current?.scrollToEnd({ animated: true }), 100);
  }, [currentQuestion, isDocumentLoaded]);

  const handleEmbeddingModelSelected = useCallback(async (model: SDKModelInfo) => {
    setSelectedEmbeddingModel(model);
    setShowingEmbeddingPicker(false);
  }, []);

  const handleLLMModelSelected = useCallback(async (model: SDKModelInfo) => {
    setSelectedLLMModel(model);
    setShowingLLMPicker(false);
  }, []);

  if (nitroError) {
    return (
      <SafeAreaView edges={['top']} style={styles.container}>
        <View style={styles.centered}>
          <AppIcon name="alert-circle-outline" size={64} color={colors.error} />
          <Text style={[Typography.headline, styles.errorTitle, { color: colors.error }]}>
            NitroModules Error
          </Text>
          <Text
            style={[
              Typography.body,
              styles.errorHint,
              { color: colors.textSecondary },
            ]}
          >
            {nitroError}
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  if (!isNitroReady) {
    return (
      <SafeAreaView edges={['top']} style={styles.container}>
        <View style={styles.centered}>
          <ActivityIndicator size="large" color={colors.primary} />
          <Text style={[Typography.body, styles.loadingText, { color: colors.textSecondary }]}>
            Initializing…
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  const showDocumentPlaceholder = !isDocumentLoaded && !isLoadingDocument;

  return (
    <SafeAreaView edges={['top']} style={styles.container}>
      <KeyboardAvoidingView
        style={styles.flex1}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          ref={scrollViewRef}
          style={styles.scrollArea}
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
        >
          <View style={styles.setupGroup}>
            <Text
              style={[
                Typography.caption2,
                styles.sectionLabel,
                { color: colors.textSecondary },
              ]}
            >
              SETUP
            </Text>

            <SetupSlot
              iconName="cube-outline"
              label="Embedding Model"
              value={selectedEmbeddingModel?.name ?? null}
              placeholder="Pick an embedding model"
              ready={selectedEmbeddingModel?.localPath != null}
              onPress={() => setShowingEmbeddingPicker(true)}
            />

            <SetupSlot
              iconName="chatbubble-ellipses-outline"
              label="Language Model"
              value={selectedLLMModel?.name ?? null}
              placeholder="Pick a language model"
              ready={selectedLLMModel?.localPath != null}
              onPress={() => setShowingLLMPicker(true)}
            />

            <SetupSlot
              iconName="document-text-outline"
              label="Document"
              value={documentName}
              placeholder={
                areModelsReady
                  ? 'Tap to load a document'
                  : 'Select both models first'
              }
              ready={isDocumentLoaded}
              onPress={
                isDocumentLoaded ? handleChangeDocument : handleSelectDocument
              }
              disabled={!areModelsReady || isLoadingDocument}
            />

            {isLoadingDocument ? (
              <View style={styles.loadingBar}>
                <ActivityIndicator size="small" color={colors.primary} />
                <Text
                  style={[Typography.caption, { color: colors.textSecondary }]}
                >
                  Extracting + ingesting document…
                </Text>
              </View>
            ) : null}
          </View>

          {error ? (
            <View
              style={[
                styles.errorBanner,
                { backgroundColor: `${colors.error}18` },
              ]}
            >
              <AppIcon name="alert-circle" size={16} color={colors.error} />
              <Text
                style={[Typography.caption, styles.errorText, { color: colors.error }]}
                numberOfLines={3}
              >
                {error}
              </Text>
              <TouchableOpacity onPress={() => setError(null)} hitSlop={8}>
                <AppIcon name="close" size={16} color={colors.error} />
              </TouchableOpacity>
            </View>
          ) : null}

          {messages.length === 0 && showDocumentPlaceholder ? (
            <View style={styles.emptyState}>
              <View
                style={[
                  styles.emptyIconWrap,
                  { backgroundColor: colors.primarySoft },
                ]}
              >
                <AppIcon
                  name="document-text-outline"
                  size={36}
                  color={colors.primary}
                />
              </View>
              <Text style={[Typography.title3, { color: colors.text }]}>
                Ask your documents
              </Text>
              <Text
                style={[
                  Typography.body,
                  styles.emptySubtitle,
                  { color: colors.textSecondary },
                ]}
              >
                Pick two models and a PDF, JSON or text file to start asking
                grounded questions.
              </Text>
            </View>
          ) : null}

          {messages.length === 0 && isDocumentLoaded ? (
            <View style={styles.hintBox}>
              <Text style={[Typography.caption, { color: colors.textSecondary }]}>
                Try: “Summarize this document.” or “What is the main idea of
                section 2?”
              </Text>
            </View>
          ) : null}

          {messages.map((msg, index) => (
            <View
              key={index}
              style={[
                styles.bubbleRow,
                msg.role === 'user' ? styles.bubbleRowUser : styles.bubbleRowAssistant,
              ]}
            >
              <View
                style={[
                  styles.bubble,
                  msg.role === 'user'
                    ? {
                        backgroundColor: colors.userBubble,
                        borderBottomRightRadius: 4,
                      }
                    : {
                        backgroundColor: colors.assistantBubble,
                        borderBottomLeftRadius: 4,
                      },
                ]}
              >
                <Text
                  style={[
                    Typography.body,
                    {
                      color:
                        msg.role === 'user'
                          ? colors.onUserBubble
                          : colors.onAssistantBubble,
                      lineHeight: 22,
                    },
                  ]}
                >
                  {msg.text}
                </Text>
              </View>
            </View>
          ))}

          {isQuerying ? (
            <View style={styles.queryingRow}>
              <ActivityIndicator size="small" color={colors.primary} />
              <Text style={[Typography.caption, { color: colors.textSecondary }]}>
                Searching document…
              </Text>
            </View>
          ) : null}
        </ScrollView>

        <View
          style={[
            styles.inputBar,
            { backgroundColor: colors.background, borderTopColor: colors.border },
          ]}
        >
          <View
            style={[
              styles.inputField,
              { backgroundColor: colors.surfaceAlt, borderColor: colors.border },
            ]}
          >
            <TextInput
              style={[styles.textInput, { color: colors.text }]}
              placeholder={
                isDocumentLoaded
                  ? 'Ask a question about the document…'
                  : 'Load a document to start'
              }
              placeholderTextColor={colors.textTertiary}
              value={currentQuestion}
              onChangeText={setCurrentQuestion}
              editable={isDocumentLoaded && !isQuerying}
              returnKeyType="send"
              onSubmitEditing={handleAskQuestion}
              multiline
            />
          </View>
          <TouchableOpacity
            style={[
              styles.sendButton,
              {
                backgroundColor: canAskQuestion
                  ? colors.primary
                  : colors.surfaceAlt,
              },
            ]}
            onPress={handleAskQuestion}
            disabled={!canAskQuestion || isQuerying}
            activeOpacity={0.8}
          >
            {isQuerying ? (
              <ActivityIndicator size="small" color={colors.onPrimary} />
            ) : (
              <AppIcon
                name="send"
                size={18}
                color={canAskQuestion ? colors.onPrimary : colors.textTertiary}
              />
            )}
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>

      <ModelSelectionSheet
        visible={showingEmbeddingPicker}
        context={ModelSelectionContext.RagEmbedding}
        onModelSelected={handleEmbeddingModelSelected}
        onClose={() => setShowingEmbeddingPicker(false)}
      />
      <ModelSelectionSheet
        visible={showingLLMPicker}
        context={ModelSelectionContext.RagLLM}
        onModelSelected={handleLLMModelSelected}
        onClose={() => setShowingLLMPicker(false)}
      />
    </SafeAreaView>
  );
};

const slotStyles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.mediumLarge,
    borderRadius: BorderRadius.large,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: Padding.padding14,
    paddingVertical: Padding.padding12,
  },
  iconWrap: {
    width: 36,
    height: 36,
    borderRadius: BorderRadius.medium,
    alignItems: 'center',
    justifyContent: 'center',
  },
  textWrap: {
    flex: 1,
    gap: 2,
  },
});

const createStyles = (colors: ThemeColors) =>
  StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: colors.background,
    },
    flex1: { flex: 1 },
    centered: {
      flex: 1,
      justifyContent: 'center',
      alignItems: 'center',
      padding: Padding.padding24,
      gap: Spacing.small,
    },
    loadingText: { marginTop: Spacing.small },
    errorTitle: { marginTop: Spacing.medium },
    errorHint: { marginTop: Spacing.small, textAlign: 'center' },

    scrollArea: { flex: 1 },
    scrollContent: {
      paddingHorizontal: Padding.padding16,
      paddingTop: Spacing.mediumLarge,
      paddingBottom: Spacing.xxLarge,
      gap: Spacing.mediumLarge,
    },
    sectionLabel: {
      fontWeight: '600',
      letterSpacing: 0.6,
      marginBottom: Spacing.xSmall,
    },
    setupGroup: {
      gap: Spacing.small,
    },
    loadingBar: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.small,
      paddingVertical: Spacing.small,
      paddingHorizontal: Spacing.xSmall,
    },
    errorBanner: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.small,
      padding: Padding.padding12,
      borderRadius: BorderRadius.medium,
    },
    errorText: { flex: 1 },

    emptyState: {
      alignItems: 'center',
      gap: Spacing.small,
      paddingVertical: Spacing.xxxLarge,
    },
    emptyIconWrap: {
      width: 72,
      height: 72,
      borderRadius: 36,
      alignItems: 'center',
      justifyContent: 'center',
      marginBottom: Spacing.small,
    },
    emptySubtitle: {
      textAlign: 'center',
      maxWidth: 300,
      paddingHorizontal: Padding.padding16,
    },
    hintBox: {
      paddingHorizontal: Padding.padding12,
      paddingVertical: Padding.padding8,
    },

    bubbleRow: {
      marginTop: Spacing.small,
    },
    bubbleRowUser: { alignItems: 'flex-end' },
    bubbleRowAssistant: { alignItems: 'flex-start' },
    bubble: {
      maxWidth: '82%',
      paddingHorizontal: Padding.padding14,
      paddingVertical: Spacing.smallMedium,
      borderRadius: BorderRadius.large,
    },
    queryingRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.small,
      paddingVertical: Spacing.small,
    },

    inputBar: {
      flexDirection: 'row',
      alignItems: 'flex-end',
      borderTopWidth: StyleSheet.hairlineWidth,
      paddingHorizontal: Padding.padding12,
      paddingVertical: Spacing.smallMedium,
      gap: Spacing.small,
    },
    inputField: {
      flex: 1,
      borderRadius: BorderRadius.xLarge,
      borderWidth: StyleSheet.hairlineWidth,
      paddingHorizontal: Padding.padding14,
      paddingVertical: Platform.OS === 'ios' ? 8 : 2,
      minHeight: 42,
      maxHeight: 120,
      justifyContent: 'center',
    },
    textInput: {
      ...Typography.body,
      padding: 0,
    },
    sendButton: {
      width: 42,
      height: 42,
      borderRadius: 21,
      alignItems: 'center',
      justifyContent: 'center',
    },
  });

export default RAGScreen;
