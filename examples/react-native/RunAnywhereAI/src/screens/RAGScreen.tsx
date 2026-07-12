/**
 * RAGScreen - Document Q&A
 *
 * Matches iOS DocumentRAGView.swift flow:
 * 1. Select embedding model (ONNX) and LLM model (LlamaCpp) via shared ModelSelectionSheet
 * 2. Pick a document (txt/json) via system file picker
 * 3. Pipeline auto-creates on document selection, text is extracted and ingested
 * 4. Chat-based Q&A interface with user/assistant message bubbles
 *
 * Architecture:
 * - Uses @runanywhere/core RAG pipeline (compiled into RACommons)
 * - Reuses the shared ModelSelectionSheet with RagEmbedding/RagLLM contexts
 * - Document picker via @react-native-documents/picker
 */

import React, { useEffect, useState, useRef, useCallback } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
  Switch,
} from 'react-native';
import Animated, {
  useAnimatedKeyboard,
  useAnimatedStyle,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { NativeModules } from 'react-native';
import { pick as documentPick } from '@react-native-documents/picker';
import { Icon, useTheme } from '../theme/system';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model/ModelSelectionSheet';

import AsyncStorage from '@react-native-async-storage/async-storage';
import { RunAnywhere } from '@runanywhere/core';
import type { ModelInfo as SDKModelInfo } from '@runanywhere/proto-ts/model_types';
import { GENERATION_SETTINGS_KEYS } from '../types/settings';
import { RAGConfiguration, RAGDocument } from '@runanywhere/proto-ts/rag';
import { rAGConfigurationDefaults } from '@runanywhere/proto-ts/convenience/rag_convenience';

// MARK: - Types

interface ChatMessage {
  role: 'user' | 'assistant';
  text: string;
}

// MARK: - Document Text Extraction

const { DocumentService: NativeDocumentService } = NativeModules;

async function extractTextFromFile(filePath: string): Promise<string> {
  if (NativeDocumentService?.extractText) {
    return NativeDocumentService.extractText(filePath);
  }
  throw new Error('DocumentService native module not available');
}

// MARK: - Component

export const RAGScreen: React.FC = () => {
  const { colors, typography, dimens } = useTheme();
  const insets = useSafeAreaInsets();
  const keyboard = useAnimatedKeyboard();

  // IME padding: the activity is adjustResize under edge-to-edge, but the window
  // isn't lifted for us, so lift the content by the keyboard height (minus the
  // bottom inset reanimated already includes). Rests on the bottom safe-area
  // inset / screen padding when the keyboard is closed.
  const keyboardStyle = useAnimatedStyle(() => ({
    paddingBottom:
      keyboard.height.value > 0
        ? Math.max(keyboard.height.value - insets.bottom, dimens.spacing.sm)
        : Math.max(insets.bottom, dimens.screenPadding),
  }));

  // Nitro state
  const [isNitroReady, setIsNitroReady] = useState(false);
  const [nitroError, setNitroError] = useState<string | null>(null);

  // Model selection
  const [selectedEmbeddingModel, setSelectedEmbeddingModel] =
    useState<SDKModelInfo | null>(null);
  const [selectedLLMModel, setSelectedLLMModel] = useState<SDKModelInfo | null>(
    null
  );
  const [showingEmbeddingPicker, setShowingEmbeddingPicker] = useState(false);
  const [showingLLMPicker, setShowingLLMPicker] = useState(false);

  // Document state
  const [documents, setDocuments] = useState<string[]>([]);
  const [isLoadingDocument, setIsLoadingDocument] = useState(false);

  // Setup card collapse
  const [setupExpanded, setSetupExpanded] = useState(true);

  // Chat state
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [currentQuestion, setCurrentQuestion] = useState('');
  const [isQuerying, setIsQuerying] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // RAG retrieval options. Rerank is a pipeline setting (RAGConfiguration);
  // multi-query is a per-query option (RAGQueryOptions).
  const [rerankEnabled, setRerankEnabled] = useState(false);
  const [multiQueryEnabled, setMultiQueryEnabled] = useState(false);

  const scrollViewRef = useRef<ScrollView>(null);

  const areModelsReady =
    selectedEmbeddingModel?.id != null &&
    selectedEmbeddingModel.id.length > 0 &&
    selectedLLMModel?.id != null &&
    selectedLLMModel.id.length > 0;

  const hasDocuments = documents.length > 0;
  const collapsible = areModelsReady && hasDocuments;
  const showFullSetup = setupExpanded || !collapsible;

  const canAskQuestion =
    hasDocuments && !isQuerying && currentQuestion.trim().length > 0;

  // Auto-collapse once ready
  useEffect(() => {
    if (areModelsReady && hasDocuments) setSetupExpanded(false);
  }, [areModelsReady, hasDocuments]);

  // MARK: - Initialization

  useEffect(() => {
    let mounted = true;
    const timer = setTimeout(() => {
      if (mounted) {
        setIsNitroReady(true);
        setNitroError(null);
      }
    }, 500);

    return () => {
      mounted = false;
      clearTimeout(timer);
    };
  }, []);

  // Cleanup pipeline on unmount
  useEffect(() => {
    return () => {
      if (hasDocuments) {
        RunAnywhere.ragDestroyPipeline().catch(console.error);
      }
    };
  }, [hasDocuments]);

  // MARK: - Document Loading

  const handleSelectDocument = useCallback(async () => {
    if (!areModelsReady || !isNitroReady) return;

    const embeddingModelId = selectedEmbeddingModel?.id;
    const llmModelId = selectedLLMModel?.id;
    if (!embeddingModelId || !llmModelId) return;

    try {
      const [result] = await documentPick({
        type: ['application/pdf', 'text/plain', 'application/json'],
      });

      const fileUri = result.uri;
      if (!fileUri) return;

      setIsLoadingDocument(true);
      setError(null);

      const text = await extractTextFromFile(fileUri);

      const config = RAGConfiguration.fromPartial({
        ...rAGConfigurationDefaults(),
        embeddingModelId,
        llmModelId,
        rerankResults: rerankEnabled,
      });

      // Each document is queried in isolation. ragCreatePipeline destroys the
      // prior session, so the fresh index holds only this document — replace the
      // list rather than appending, which would misrepresent a wiped corpus as
      // multiple loaded documents and answer "not enough info" for earlier ones.
      await RunAnywhere.ragCreatePipeline(config);
      await RunAnywhere.ragIngest(RAGDocument.fromPartial({ text }));

      const name = result.name || 'Document';
      setDocuments([name]);
    } catch (err: unknown) {
      if (
        typeof err === 'object' &&
        err !== null &&
        'code' in err &&
        (err as { code?: unknown }).code === 'OPERATION_CANCELED'
      ) {
        return;
      }
      const msg =
        err instanceof Error ? err.message : 'Failed to load document';
      setError(msg);
      console.error('[RAGScreen] Document load error:', err);
    } finally {
      setIsLoadingDocument(false);
    }
  }, [
    areModelsReady,
    isNitroReady,
    selectedEmbeddingModel,
    selectedLLMModel,
    rerankEnabled,
  ]);

  const handleClearAll = useCallback(async () => {
    // Reset local state even if teardown fails, so the UI never references a
    // pipeline that may already be gone (and no unhandled rejection escapes to
    // the Switch/onValueChange caller).
    try {
      await RunAnywhere.ragDestroyPipeline();
    } catch (err) {
      console.error('[RAGScreen] Pipeline destroy failed:', err);
    }
    setDocuments([]);
    setMessages([]);
    setError(null);
    setCurrentQuestion('');
    setSetupExpanded(true);
  }, []);

  // Rerank is a pipeline-level setting, so changing it rebuilds the pipeline.
  // The current corpus is dropped (re-add documents), matching a model change.
  const handleRerankChange = useCallback(
    async (value: boolean) => {
      try {
        if (documents.length > 0) {
          await RunAnywhere.ragDestroyPipeline();
          setDocuments([]);
          setMessages([]);
          setCurrentQuestion('');
          setSetupExpanded(true);
        }
        setError(null);
        setRerankEnabled(value);
      } catch (err) {
        const msg =
          err instanceof Error
            ? err.message
            : 'Failed to update rerank setting';
        setError(msg);
        console.error('[RAGScreen] Rerank toggle failed:', err);
      }
    },
    [documents.length]
  );

  // MARK: - Q&A

  const handleAskQuestion = useCallback(async () => {
    const question = currentQuestion.trim();
    if (!question || !hasDocuments) return;

    setMessages((prev) => [...prev, { role: 'user', text: question }]);
    setCurrentQuestion('');
    setIsQuerying(true);
    setError(null);

    try {
      const thinkingStr = await AsyncStorage.getItem(
        GENERATION_SETTINGS_KEYS.THINKING_MODE_ENABLED
      );
      const thinkingModeEnabled = thinkingStr === 'true';
      const supportsThinking = selectedLLMModel?.supportsThinking ?? false;
      const result = await RunAnywhere.ragQuery(question, {
        disableThinking: supportsThinking && !thinkingModeEnabled,
        enableMultiQuery: multiQueryEnabled,
      });
      setMessages((prev) => [
        ...prev,
        { role: 'assistant', text: result.answer },
      ]);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Query failed';
      setError(msg);
      setMessages((prev) => [
        ...prev,
        { role: 'assistant', text: `Error: ${msg}` },
      ]);
    } finally {
      setIsQuerying(false);
    }

    setTimeout(() => {
      scrollViewRef.current?.scrollToEnd({ animated: true });
    }, 100);
  }, [currentQuestion, hasDocuments, selectedLLMModel, multiQueryEnabled]);

  // MARK: - Model Selection Callbacks

  const handleEmbeddingModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      setSelectedEmbeddingModel(model);
      setShowingEmbeddingPicker(false);
    },
    []
  );

  const handleLLMModelSelected = useCallback(async (model: SDKModelInfo) => {
    setSelectedLLMModel(model);
    setShowingLLMPicker(false);
  }, []);

  // MARK: - Error / Loading state for NitroModules

  if (nitroError) {
    return (
      <View
        style={[
          styles.fill,
          { backgroundColor: colors.background, paddingTop: insets.top },
        ]}
      >
        <View style={styles.centered}>
          <Icon name="info" size={48} color={colors.error} />
          <Text
            style={[
              typography.titleMedium,
              { color: colors.error, marginTop: dimens.spacing.md },
            ]}
          >
            NitroModules Error
          </Text>
          <Text
            style={[
              typography.bodyMedium,
              {
                color: colors.onSurfaceVariant,
                marginTop: dimens.spacing.sm,
                textAlign: 'center',
              },
            ]}
          >
            {nitroError}
          </Text>
        </View>
      </View>
    );
  }

  if (!isNitroReady) {
    return (
      <View
        style={[
          styles.fill,
          { backgroundColor: colors.background, paddingTop: insets.top },
        ]}
      >
        <View style={styles.centered}>
          <ActivityIndicator size="large" color={colors.primary} />
          <Text
            style={[
              typography.bodyMedium,
              { color: colors.onSurfaceVariant, marginTop: dimens.spacing.md },
            ]}
          >
            Initializing…
          </Text>
        </View>
      </View>
    );
  }

  // MARK: - Render

  const addLabel = documents.length === 0 ? 'Add document' : 'Replace document';

  return (
    <View
      style={[
        styles.fill,
        { backgroundColor: colors.background, paddingTop: insets.top },
      ]}
    >
      <Animated.View
        style={[
          styles.fill,
          {
            paddingHorizontal: dimens.screenPadding,
            paddingTop: dimens.screenPadding,
            gap: dimens.spacing.md,
          },
          keyboardStyle,
        ]}
      >
        {/* Setup card / compact bar */}
        {showFullSetup ? (
          <View
            style={[
              styles.card,
              {
                backgroundColor: colors.surfaceContainerHigh,
                borderRadius: dimens.radius.lg,
              },
            ]}
          >
            {/* Collapse header (only when collapsible) */}
            {collapsible && (
              <>
                <TouchableOpacity
                  style={[
                    styles.collapseHeader,
                    {
                      paddingHorizontal: dimens.spacing.lg,
                      paddingVertical: dimens.spacing.sm,
                    },
                  ]}
                  onPress={() => setSetupExpanded(false)}
                  activeOpacity={0.7}
                >
                  <Text
                    style={[
                      typography.bodySmall,
                      { color: colors.onSurfaceVariant, flex: 1 },
                    ]}
                  >
                    Setup
                  </Text>
                  <Icon
                    name="chevronDown"
                    size={dimens.icon.sm}
                    color={colors.onSurfaceVariant}
                  />
                </TouchableOpacity>
                <View
                  style={[
                    styles.divider,
                    { backgroundColor: colors.outlineVariant },
                  ]}
                />
              </>
            )}

            {/* Embedding model row */}
            <TouchableOpacity
              style={[
                styles.setupRow,
                {
                  paddingHorizontal: dimens.spacing.lg,
                  paddingVertical: dimens.spacing.md,
                },
              ]}
              onPress={() => setShowingEmbeddingPicker(true)}
              activeOpacity={0.7}
            >
              <Icon
                name="storage"
                size={dimens.icon.md}
                color={
                  selectedEmbeddingModel
                    ? colors.primary
                    : colors.onSurfaceVariant
                }
              />
              <View style={styles.setupRowText}>
                <Text
                  style={[
                    typography.bodySmall,
                    { color: colors.onSurfaceVariant },
                  ]}
                >
                  Embedding model
                </Text>
                <Text
                  style={[typography.bodyLarge, { color: colors.onSurface }]}
                  numberOfLines={1}
                >
                  {selectedEmbeddingModel?.name ?? 'Tap to select'}
                </Text>
              </View>
              <Icon
                name="chevronRight"
                size={dimens.icon.sm}
                color={colors.onSurfaceVariant}
              />
            </TouchableOpacity>

            <View
              style={[
                styles.divider,
                { backgroundColor: colors.outlineVariant },
              ]}
            />

            {/* LLM model row */}
            <TouchableOpacity
              style={[
                styles.setupRow,
                {
                  paddingHorizontal: dimens.spacing.lg,
                  paddingVertical: dimens.spacing.md,
                },
              ]}
              onPress={() => setShowingLLMPicker(true)}
              activeOpacity={0.7}
            >
              <Icon
                name="chat"
                size={dimens.icon.md}
                color={
                  selectedLLMModel ? colors.primary : colors.onSurfaceVariant
                }
              />
              <View style={styles.setupRowText}>
                <Text
                  style={[
                    typography.bodySmall,
                    { color: colors.onSurfaceVariant },
                  ]}
                >
                  Language model
                </Text>
                <Text
                  style={[typography.bodyLarge, { color: colors.onSurface }]}
                  numberOfLines={1}
                >
                  {selectedLLMModel?.name ?? 'Tap to select'}
                </Text>
              </View>
              <Icon
                name="chevronRight"
                size={dimens.icon.sm}
                color={colors.onSurfaceVariant}
              />
            </TouchableOpacity>

            <View
              style={[
                styles.divider,
                { backgroundColor: colors.outlineVariant },
              ]}
            />

            {/* Documents section */}
            <View
              style={{ padding: dimens.spacing.lg, gap: dimens.spacing.sm }}
            >
              <View style={styles.docsHeader}>
                <Text
                  style={[
                    typography.bodySmall,
                    { color: colors.onSurfaceVariant, flex: 1 },
                  ]}
                >
                  {documents.length === 0
                    ? 'Documents'
                    : `${documents.length} document${documents.length === 1 ? '' : 's'}`}
                </Text>
                {documents.length > 0 && (
                  <TouchableOpacity onPress={handleClearAll} hitSlop={8}>
                    <Text
                      style={[
                        typography.labelMedium,
                        { color: colors.primary },
                      ]}
                    >
                      Clear
                    </Text>
                  </TouchableOpacity>
                )}
              </View>

              {documents.map((name, i) => (
                <View
                  key={i}
                  style={[styles.docRow, { gap: dimens.spacing.sm }]}
                >
                  <Icon
                    name="storage"
                    size={dimens.icon.sm}
                    color={colors.primary}
                  />
                  <Text
                    style={[
                      typography.bodyMedium,
                      { color: colors.onSurface, flex: 1 },
                    ]}
                    numberOfLines={1}
                  >
                    {name}
                  </Text>
                </View>
              ))}

              {/* Add document button */}
              <TouchableOpacity
                style={[
                  styles.addDocButton,
                  {
                    backgroundColor: colors.surfaceContainerHighest,
                    borderRadius: dimens.radius.md,
                    padding: dimens.spacing.md,
                    opacity: areModelsReady && !isLoadingDocument ? 1 : 0.5,
                  },
                ]}
                onPress={handleSelectDocument}
                disabled={!areModelsReady || isLoadingDocument}
                activeOpacity={0.7}
              >
                {isLoadingDocument ? (
                  <>
                    <ActivityIndicator size="small" color={colors.primary} />
                    <Text
                      style={[
                        typography.bodyMedium,
                        {
                          color: colors.onSurface,
                          marginLeft: dimens.spacing.sm,
                        },
                      ]}
                    >
                      Reading…
                    </Text>
                  </>
                ) : (
                  <>
                    <Icon
                      name="plus"
                      size={dimens.icon.sm}
                      color={
                        areModelsReady
                          ? colors.primary
                          : colors.onSurfaceVariant
                      }
                    />
                    <Text
                      style={[
                        typography.bodyMedium,
                        {
                          color: areModelsReady
                            ? colors.primary
                            : colors.onSurfaceVariant,
                          marginLeft: dimens.spacing.sm,
                        },
                      ]}
                    >
                      {areModelsReady ? addLabel : 'Pick models first'}
                    </Text>
                  </>
                )}
              </TouchableOpacity>
            </View>

            <View
              style={[
                styles.divider,
                { backgroundColor: colors.outlineVariant },
              ]}
            />

            {/* Retrieval options */}
            <View
              style={{ padding: dimens.spacing.lg, gap: dimens.spacing.md }}
            >
              <Text
                style={[
                  typography.bodySmall,
                  { color: colors.onSurfaceVariant },
                ]}
              >
                Retrieval
              </Text>
              <View style={styles.optionRow}>
                <View style={{ flex: 1 }}>
                  <Text
                    style={[typography.bodyLarge, { color: colors.onSurface }]}
                  >
                    Rerank results
                  </Text>
                  <Text
                    style={[
                      typography.bodySmall,
                      { color: colors.onSurfaceVariant },
                    ]}
                  >
                    LLM re-scores retrieved chunks for relevance
                  </Text>
                </View>
                <Switch
                  value={rerankEnabled}
                  onValueChange={handleRerankChange}
                />
              </View>
              <View style={styles.optionRow}>
                <View style={{ flex: 1 }}>
                  <Text
                    style={[typography.bodyLarge, { color: colors.onSurface }]}
                  >
                    Multi-query expansion
                  </Text>
                  <Text
                    style={[
                      typography.bodySmall,
                      { color: colors.onSurfaceVariant },
                    ]}
                  >
                    Rewrites the question into variants, fuses results
                  </Text>
                </View>
                <Switch
                  value={multiQueryEnabled}
                  onValueChange={setMultiQueryEnabled}
                />
              </View>
            </View>
          </View>
        ) : (
          /* Compact bar */
          <TouchableOpacity
            style={[
              styles.compactBar,
              {
                backgroundColor: colors.surfaceContainerHigh,
                borderRadius: dimens.radius.lg,
                paddingHorizontal: dimens.spacing.lg,
                paddingVertical: dimens.spacing.md,
              },
            ]}
            onPress={() => setSetupExpanded(true)}
            activeOpacity={0.7}
          >
            <Icon name="storage" size={dimens.icon.sm} color={colors.primary} />
            <Text
              style={[
                typography.bodyMedium,
                { color: colors.onSurface, flex: 1 },
              ]}
              numberOfLines={1}
            >
              {documents.length} document{documents.length === 1 ? '' : 's'}
            </Text>
            {isLoadingDocument ? (
              <ActivityIndicator size="small" color={colors.primary} />
            ) : (
              <TouchableOpacity onPress={handleSelectDocument} hitSlop={8}>
                <Icon
                  name="plus"
                  size={dimens.icon.md}
                  color={colors.primary}
                />
              </TouchableOpacity>
            )}
            <Icon
              name="chevronDown"
              size={dimens.icon.sm}
              color={colors.onSurfaceVariant}
            />
          </TouchableOpacity>
        )}

        {/* Error text */}
        {error && (
          <Text style={[typography.bodySmall, { color: colors.error }]}>
            {error}
          </Text>
        )}

        {/* Conversation pane */}
        <View style={styles.fill}>
          <ScrollView
            ref={scrollViewRef}
            style={styles.fill}
            contentContainerStyle={[
              styles.messagesContent,
              { gap: dimens.spacing.md },
            ]}
          >
            {messages.length === 0 ? (
              <View style={styles.emptyState}>
                <Icon name="rag" size={dimens.icon.lg} color={colors.primary} />
                <Text
                  style={[
                    typography.bodyLarge,
                    {
                      color: colors.onSurfaceVariant,
                      textAlign: 'center',
                      marginTop: dimens.spacing.md,
                    },
                  ]}
                >
                  {!areModelsReady
                    ? 'Pick an embedding model and an LLM to begin'
                    : !hasDocuments
                      ? 'Add a document, then ask a question about it'
                      : 'Ask a question about your documents'}
                </Text>
              </View>
            ) : (
              <>
                {messages.map((msg, index) => (
                  <View
                    key={index}
                    style={[
                      styles.bubbleRow,
                      msg.role === 'user'
                        ? styles.bubbleRowUser
                        : styles.bubbleRowAssistant,
                    ]}
                  >
                    <View
                      style={[
                        styles.bubble,
                        {
                          backgroundColor:
                            msg.role === 'user'
                              ? colors.primary
                              : colors.surfaceContainerHigh,
                          borderRadius: dimens.radius.md,
                          paddingHorizontal: dimens.spacing.md,
                          paddingVertical: dimens.spacing.sm,
                        },
                      ]}
                    >
                      <Text
                        style={[
                          typography.bodyLarge,
                          {
                            color:
                              msg.role === 'user'
                                ? colors.onPrimary
                                : colors.onSurface,
                          },
                        ]}
                      >
                        {msg.text}
                      </Text>
                    </View>
                  </View>
                ))}
                {isQuerying && (
                  <View
                    style={[styles.queryingRow, { gap: dimens.spacing.sm }]}
                  >
                    <ActivityIndicator
                      size="small"
                      color={colors.onSurfaceVariant}
                    />
                    <Text
                      style={[
                        typography.bodyMedium,
                        { color: colors.onSurfaceVariant },
                      ]}
                    >
                      Searching your documents…
                    </Text>
                  </View>
                )}
              </>
            )}
          </ScrollView>
        </View>

        {/* Input bar */}
        <View style={styles.inputBar}>
          <View
            style={[
              styles.inputWrapper,
              { backgroundColor: colors.surfaceContainerHigh },
            ]}
          >
            <TextInput
              style={[
                styles.textInput,
                typography.bodyLarge,
                { color: colors.onSurface },
              ]}
              placeholder="Ask about your documents"
              placeholderTextColor={colors.onSurfaceVariant}
              value={currentQuestion}
              onChangeText={setCurrentQuestion}
              editable={hasDocuments && !isQuerying}
              returnKeyType="send"
              onSubmitEditing={handleAskQuestion}
              multiline
              maxLength={2000}
            />
          </View>
          <TouchableOpacity
            onPress={handleAskQuestion}
            disabled={!canAskQuestion}
            activeOpacity={0.8}
            style={[
              styles.sendButton,
              {
                backgroundColor: canAskQuestion
                  ? colors.primary
                  : colors.surfaceVariant,
              },
            ]}
          >
            <Icon
              name="send"
              size={20}
              color={
                canAskQuestion ? colors.onPrimary : colors.onSurfaceVariant
              }
            />
          </TouchableOpacity>
        </View>
      </Animated.View>

      {/* Model Selection Sheets */}
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
    </View>
  );
};

// MARK: - Styles

const styles = StyleSheet.create({
  fill: {
    flex: 1,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  card: {
    overflow: 'hidden',
  },
  collapseHeader: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  divider: {
    height: StyleSheet.hairlineWidth,
  },
  setupRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  setupRowText: {
    flex: 1,
    gap: 2,
  },
  docsHeader: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  docRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  optionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  addDocButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  compactBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  messagesContent: {
    flexGrow: 1,
  },
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 48,
    paddingHorizontal: 32,
  },
  bubbleRow: {
    flexDirection: 'row',
  },
  bubbleRowUser: {
    justifyContent: 'flex-end',
  },
  bubbleRowAssistant: {
    justifyContent: 'flex-start',
  },
  bubble: {
    maxWidth: '80%',
  },
  queryingRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  inputBar: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 8,
  },
  inputWrapper: {
    flex: 1,
    borderRadius: 24,
    paddingHorizontal: 16,
    paddingVertical: 6,
  },
  textInput: {
    minHeight: 32,
    maxHeight: 120,
    paddingTop: 6,
    paddingBottom: 6,
  },
  sendButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    justifyContent: 'center',
    alignItems: 'center',
  },
});

export default RAGScreen;
