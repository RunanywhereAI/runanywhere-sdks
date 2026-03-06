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
 * - Document picker via react-native-document-picker
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
  SafeAreaView,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { NativeModules } from 'react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import DocumentPicker from 'react-native-document-picker';
import { Colors } from '../theme/colors';
import { Typography, FontWeight } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';
import {
  ModelSelectionSheet,
  ModelSelectionContext,
} from '../components/model/ModelSelectionSheet';

import {
  type ModelInfo as SDKModelInfo,
  initializeNitroModulesGlobally,
  ragCreatePipeline,
  ragDestroyPipeline,
  ragIngest,
  ragQuery,
} from '@runanywhere/core';

// MARK: - Types

interface ChatMessage {
  role: 'user' | 'assistant';
  text: string;
}

// MARK: - Path Resolution Helpers (matching iOS DocumentRAGView)

function resolveEmbeddingFilePath(localPath: string): string {
  // Multi-file ONNX models set localPath to the folder.
  // Return the path to model.onnx inside.
  if (!localPath.endsWith('.onnx')) {
    return `${localPath}/model.onnx`;
  }
  return localPath;
}

function resolveLLMFilePath(localPath: string): string {
  // Single-file LlamaCpp models: localPath may point to the .gguf directly,
  // or to a directory containing it.
  if (localPath.endsWith('.gguf') || localPath.endsWith('.bin')) {
    return localPath;
  }
  // Assume directory - the SDK already resolves to the gguf path in most cases
  return localPath;
}

// MARK: - Document Text Extraction

const { DocumentService: NativeDocumentService } = NativeModules;

/**
 * Extract text from a document using native PDFKit (for PDF) or string parsing.
 * Mirrors iOS DocumentService.swift - handles PDF, JSON, and plain text.
 */
async function extractTextFromFile(filePath: string): Promise<string> {
  if (NativeDocumentService?.extractText) {
    return NativeDocumentService.extractText(filePath);
  }
  throw new Error('DocumentService native module not available');
}

// MARK: - Component

export const RAGScreen: React.FC = () => {
  // Nitro state
  const [isNitroReady, setIsNitroReady] = useState(false);
  const [nitroError, setNitroError] = useState<string | null>(null);

  // Model selection
  const [selectedEmbeddingModel, setSelectedEmbeddingModel] =
    useState<SDKModelInfo | null>(null);
  const [selectedLLMModel, setSelectedLLMModel] =
    useState<SDKModelInfo | null>(null);
  const [showingEmbeddingPicker, setShowingEmbeddingPicker] = useState(false);
  const [showingLLMPicker, setShowingLLMPicker] = useState(false);

  // Document state
  const [documentName, setDocumentName] = useState<string | null>(null);
  const [isDocumentLoaded, setIsDocumentLoaded] = useState(false);
  const [isLoadingDocument, setIsLoadingDocument] = useState(false);

  // Chat state
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [currentQuestion, setCurrentQuestion] = useState('');
  const [isQuerying, setIsQuerying] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const scrollViewRef = useRef<ScrollView>(null);

  const areModelsReady =
    selectedEmbeddingModel?.localPath != null &&
    selectedLLMModel?.localPath != null;

  const canAskQuestion =
    isDocumentLoaded &&
    !isQuerying &&
    currentQuestion.trim().length > 0;

  // MARK: - Initialization

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

  // Cleanup pipeline on unmount
  useEffect(() => {
    return () => {
      if (isDocumentLoaded) {
        ragDestroyPipeline().catch(console.error);
      }
    };
  }, [isDocumentLoaded]);

  // MARK: - Document Loading

  const handleSelectDocument = useCallback(async () => {
    if (!areModelsReady || !isNitroReady) return;

    try {
      const result = await DocumentPicker.pickSingle({
        type: [DocumentPicker.types.pdf, DocumentPicker.types.plainText, DocumentPicker.types.json],
        copyTo: 'cachesDirectory',
      });

      const fileUri = result.fileCopyUri || result.uri;
      if (!fileUri) return;

      setIsLoadingDocument(true);
      setError(null);

      // Extract text from the picked file
      const text = await extractTextFromFile(fileUri);

      // Build RAG configuration matching iOS ragConfig computed property.
      // With multi-file registration, vocab.txt is co-located with model.onnx,
      // so the C++ pipeline auto-discovers it (no embeddingConfigJSON needed).
      const embeddingPath = resolveEmbeddingFilePath(
        selectedEmbeddingModel!.localPath!
      );
      const llmPath = resolveLLMFilePath(selectedLLMModel!.localPath!);

      const config = {
        embeddingModelPath: embeddingPath,
        llmModelPath: llmPath,
        topK: 5,
        similarityThreshold: 0.25,
        maxContextTokens: 2048,
        chunkSize: 512,
        chunkOverlap: 50,
      };

      // Create pipeline and ingest document (same as iOS loadDocument)
      await ragCreatePipeline(config);
      await ragIngest(text);

      setDocumentName(result.name || 'Document');
      setIsDocumentLoaded(true);
    } catch (err) {
      if (DocumentPicker.isCancel(err)) {
        return; // User cancelled
      }
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

    // Re-open document picker
    handleSelectDocument();
  }, [handleSelectDocument]);

  // MARK: - Q&A

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

    setTimeout(() => {
      scrollViewRef.current?.scrollToEnd({ animated: true });
    }, 100);
  }, [currentQuestion, isDocumentLoaded]);

  // MARK: - Model Selection Callbacks

  const handleEmbeddingModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      setSelectedEmbeddingModel(model);
      setShowingEmbeddingPicker(false);
    },
    []
  );

  const handleLLMModelSelected = useCallback(
    async (model: SDKModelInfo) => {
      setSelectedLLMModel(model);
      setShowingLLMPicker(false);
    },
    []
  );

  // MARK: - Error state for NitroModules

  if (nitroError) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>Document Q&A</Text>
        </View>
        <View style={styles.centered}>
          <Icon name="alert-circle-outline" size={64} color={Colors.primaryRed} />
          <Text style={styles.errorTitle}>NitroModules Error</Text>
          <Text style={styles.errorHintText}>{nitroError}</Text>
        </View>
      </SafeAreaView>
    );
  }

  if (!isNitroReady) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>Document Q&A</Text>
        </View>
        <View style={styles.centered}>
          <ActivityIndicator size="large" color={Colors.primaryBlue} />
          <Text style={styles.loadingText}>Initializing...</Text>
        </View>
      </SafeAreaView>
    );
  }

  // MARK: - Render

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        style={styles.flex1}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        {/* Model Setup Section */}
        <View style={styles.modelSection}>
          <TouchableOpacity
            style={styles.modelRow}
            onPress={() => setShowingEmbeddingPicker(true)}
          >
            <Icon name="cube-outline" size={20} color={Colors.textSecondary} />
            <Text style={styles.modelLabel}>Embedding Model</Text>
            <View style={styles.modelRowRight}>
              {selectedEmbeddingModel ? (
                <>
                  <Text style={styles.modelName} numberOfLines={1}>
                    {selectedEmbeddingModel.name}
                  </Text>
                  <Icon
                    name="checkmark-circle"
                    size={16}
                    color={Colors.primaryGreen}
                  />
                </>
              ) : (
                <>
                  <Text style={styles.modelPlaceholder}>Not selected</Text>
                  <Icon
                    name="chevron-forward"
                    size={16}
                    color={Colors.textTertiary}
                  />
                </>
              )}
            </View>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.modelRow}
            onPress={() => setShowingLLMPicker(true)}
          >
            <Icon
              name="chatbubble-ellipses-outline"
              size={20}
              color={Colors.textSecondary}
            />
            <Text style={styles.modelLabel}>LLM Model</Text>
            <View style={styles.modelRowRight}>
              {selectedLLMModel ? (
                <>
                  <Text style={styles.modelName} numberOfLines={1}>
                    {selectedLLMModel.name}
                  </Text>
                  <Icon
                    name="checkmark-circle"
                    size={16}
                    color={Colors.primaryGreen}
                  />
                </>
              ) : (
                <>
                  <Text style={styles.modelPlaceholder}>Not selected</Text>
                  <Icon
                    name="chevron-forward"
                    size={16}
                    color={Colors.textTertiary}
                  />
                </>
              )}
            </View>
          </TouchableOpacity>
        </View>

        {/* Document Status Bar */}
        <View style={styles.documentBar}>
          {isLoadingDocument ? (
            <View style={styles.documentBarInner}>
              <ActivityIndicator size="small" color={Colors.textSecondary} />
              <Text style={styles.documentBarText}>Loading document...</Text>
            </View>
          ) : isDocumentLoaded && documentName ? (
            <View style={styles.documentBarInner}>
              <Icon
                name="checkmark-circle"
                size={20}
                color={Colors.primaryGreen}
              />
              <Text style={styles.documentName} numberOfLines={1}>
                {documentName}
              </Text>
              <TouchableOpacity onPress={handleChangeDocument}>
                <Text style={styles.changeButton}>Change</Text>
              </TouchableOpacity>
            </View>
          ) : (
            <TouchableOpacity
              style={[
                styles.selectDocButton,
                !areModelsReady && styles.selectDocButtonDisabled,
              ]}
              onPress={handleSelectDocument}
              disabled={!areModelsReady}
            >
              <Icon name="document-text-outline" size={20} color="#fff" />
              <Text style={styles.selectDocButtonText}>Select Document</Text>
            </TouchableOpacity>
          )}
        </View>

        {/* Error Banner */}
        {error && (
          <View style={styles.errorBanner}>
            <Icon name="alert-circle" size={16} color={Colors.primaryRed} />
            <Text style={styles.errorBannerText} numberOfLines={2}>
              {error}
            </Text>
            <TouchableOpacity onPress={() => setError(null)}>
              <Icon name="close" size={16} color={Colors.textSecondary} />
            </TouchableOpacity>
          </View>
        )}

        {/* Messages Area */}
        <ScrollView
          ref={scrollViewRef}
          style={styles.messagesArea}
          contentContainerStyle={styles.messagesContent}
        >
          {messages.length === 0 ? (
            <View style={styles.emptyState}>
              <Icon
                name="document-text-outline"
                size={48}
                color={Colors.textTertiary}
              />
              {isDocumentLoaded ? (
                <>
                  <Text style={styles.emptyTitle}>Document loaded</Text>
                  <Text style={styles.emptySubtitle}>
                    Ask a question below to get started
                  </Text>
                </>
              ) : !areModelsReady ? (
                <>
                  <Text style={styles.emptyTitle}>Select models to get started</Text>
                  <Text style={styles.emptySubtitle}>
                    Choose an embedding model and an LLM model above, then pick a
                    document
                  </Text>
                </>
              ) : (
                <>
                  <Text style={styles.emptyTitle}>No document selected</Text>
                  <Text style={styles.emptySubtitle}>
                    Pick a PDF, JSON, or text document to start asking questions
                  </Text>
                </>
              )}
            </View>
          ) : (
            <>
              {messages.map((msg, index) => (
                <View
                  key={index}
                  style={[
                    styles.messageBubbleRow,
                    msg.role === 'user'
                      ? styles.messageBubbleRowUser
                      : styles.messageBubbleRowAssistant,
                  ]}
                >
                  <View
                    style={[
                      styles.messageBubble,
                      msg.role === 'user'
                        ? styles.messageBubbleUser
                        : styles.messageBubbleAssistant,
                    ]}
                  >
                    <Text
                      style={[
                        styles.messageBubbleText,
                        msg.role === 'user' && styles.messageBubbleTextUser,
                      ]}
                    >
                      {msg.text}
                    </Text>
                  </View>
                </View>
              ))}
              {isQuerying && (
                <View style={styles.queryingRow}>
                  <ActivityIndicator size="small" color={Colors.textSecondary} />
                  <Text style={styles.queryingText}>Searching document...</Text>
                </View>
              )}
            </>
          )}
        </ScrollView>

        {/* Input Bar */}
        <View style={styles.inputBar}>
          <TextInput
            style={styles.textInput}
            placeholder="Ask a question..."
            placeholderTextColor={Colors.textSecondary}
            value={currentQuestion}
            onChangeText={setCurrentQuestion}
            editable={isDocumentLoaded && !isQuerying}
            returnKeyType="send"
            onSubmitEditing={handleAskQuestion}
            multiline
          />
          {isQuerying ? (
            <ActivityIndicator
              size="small"
              color={Colors.textSecondary}
              style={styles.sendButton}
            />
          ) : (
            <TouchableOpacity
              style={styles.sendButton}
              onPress={handleAskQuestion}
              disabled={!canAskQuestion}
            >
              <Icon
                name="arrow-up-circle"
                size={32}
                color={
                  canAskQuestion ? Colors.primaryBlue : Colors.textTertiary
                }
              />
            </TouchableOpacity>
          )}
        </View>
      </KeyboardAvoidingView>

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
    </SafeAreaView>
  );
};

// MARK: - Styles

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  flex1: {
    flex: 1,
  },
  header: {
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Colors.borderLight,
  },
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Padding.padding20,
  },
  loadingText: {
    ...Typography.body,
    color: Colors.textSecondary,
    marginTop: Spacing.medium,
  },
  errorTitle: {
    ...Typography.headline,
    color: Colors.primaryRed,
    marginTop: Spacing.medium,
  },
  errorHintText: {
    ...Typography.body,
    color: Colors.textSecondary,
    marginTop: Spacing.small,
    textAlign: 'center',
  },

  // Model Setup Section
  modelSection: {
    backgroundColor: Colors.backgroundPrimary,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Colors.borderLight,
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
  },
  modelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: Spacing.smallMedium,
    gap: Spacing.mediumLarge,
  },
  modelLabel: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  modelRowRight: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: Spacing.xSmall,
  },
  modelName: {
    ...Typography.subheadline,
    fontWeight: FontWeight.medium,
    color: Colors.textPrimary,
    maxWidth: 180,
  },
  modelPlaceholder: {
    ...Typography.subheadline,
    color: Colors.primaryBlue,
  },

  // Document Status Bar
  documentBar: {
    backgroundColor: Colors.backgroundPrimary,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Colors.borderLight,
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding12,
    alignItems: 'center',
  },
  documentBarInner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.mediumLarge,
    width: '100%',
  },
  documentBarText: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
  },
  documentName: {
    ...Typography.subheadline,
    fontWeight: FontWeight.medium,
    color: Colors.textPrimary,
    flex: 1,
  },
  changeButton: {
    ...Typography.caption,
    color: Colors.primaryBlue,
  },
  selectDocButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primaryBlue,
    paddingHorizontal: Padding.padding24,
    paddingVertical: Padding.padding12,
    borderRadius: BorderRadius.large,
    gap: Spacing.small,
  },
  selectDocButtonDisabled: {
    backgroundColor: Colors.textTertiary,
  },
  selectDocButtonText: {
    ...Typography.headline,
    color: '#fff',
  },

  // Error Banner
  errorBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: `${Colors.primaryRed}15`,
    paddingHorizontal: Padding.padding16,
    paddingVertical: Spacing.smallMedium,
    gap: Spacing.small,
  },
  errorBannerText: {
    ...Typography.caption,
    color: Colors.primaryRed,
    flex: 1,
  },

  // Messages Area
  messagesArea: {
    flex: 1,
    backgroundColor: Colors.backgroundSecondary,
  },
  messagesContent: {
    padding: Padding.padding16,
    flexGrow: 1,
  },
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: Padding.padding60,
    gap: Spacing.smallMedium,
  },
  emptyTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
    marginTop: Spacing.medium,
  },
  emptySubtitle: {
    ...Typography.subheadline,
    color: Colors.textSecondary,
    textAlign: 'center',
    paddingHorizontal: Padding.padding40,
  },

  // Message Bubbles
  messageBubbleRow: {
    marginBottom: Spacing.mediumLarge,
  },
  messageBubbleRowUser: {
    alignItems: 'flex-end',
  },
  messageBubbleRowAssistant: {
    alignItems: 'flex-start',
  },
  messageBubble: {
    maxWidth: '80%',
    paddingHorizontal: Padding.padding14,
    paddingVertical: Spacing.smallMedium,
    borderRadius: BorderRadius.large,
  },
  messageBubbleUser: {
    backgroundColor: Colors.primaryBlue,
    borderBottomRightRadius: 4,
  },
  messageBubbleAssistant: {
    backgroundColor: Colors.backgroundPrimary,
    borderBottomLeftRadius: 4,
  },
  messageBubbleText: {
    ...Typography.body,
    color: Colors.textPrimary,
    lineHeight: 22,
  },
  messageBubbleTextUser: {
    color: '#fff',
  },
  queryingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.small,
    paddingVertical: Spacing.small,
  },
  queryingText: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },

  // Input Bar
  inputBar: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    backgroundColor: Colors.backgroundPrimary,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: Colors.borderLight,
    paddingHorizontal: Padding.padding12,
    paddingVertical: Spacing.smallMedium,
    gap: Spacing.small,
  },
  textInput: {
    flex: 1,
    ...Typography.body,
    color: Colors.textPrimary,
    minHeight: 36,
    maxHeight: 100,
    paddingHorizontal: Padding.padding12,
    paddingVertical: Spacing.small,
  },
  sendButton: {
    paddingBottom: 2,
  },
});

export default RAGScreen;
