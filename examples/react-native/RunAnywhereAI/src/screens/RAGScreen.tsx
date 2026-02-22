/**
 * RAGScreen - Tab 4: Retrieval-Augmented Generation
 *
 * Demonstrates on-device RAG (Retrieval-Augmented Generation) with:
 * - Document management (add, batch, clear)
 * - Semantic search using ONNX embeddings (all-MiniLM-L6-v2)
 * - Contextual answer generation with ONNX (TinyLlama-1.1B)
 * - Source attribution and timing metrics
 *
 * Architecture:
 * - Uses @runanywhere/rag package
 * - Integrates with app settings for model paths
 * - Follows app UI patterns (ChatScreen, STTScreen, etc.)
 *
 * Reference: packages/rag/example/RAGExample.tsx
 */

import React, { useEffect, useState, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
  Alert,
  SafeAreaView,
  Modal,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import Icon from 'react-native-vector-icons/Ionicons';
import { Colors } from '../theme/colors';
import { Typography } from '../theme/typography';
import { Spacing, Padding, BorderRadius } from '../theme/spacing';

// Import RunAnywhere RAG SDK
import { createRAG, createRAGConfig, type RAGResult } from '@runanywhere/rag';

// Import RunAnywhere Core SDK for model catalog AND global Nitro initialization
import { RunAnywhere, ModelFormat, type ModelInfo as SDKModelInfo, initializeNitroModulesGlobally } from '@runanywhere/core';

// Sample documents for demo
const SAMPLE_DOCUMENTS = [
  {
    text: `React Native is a popular framework for building mobile applications using React and JavaScript. 
           It allows developers to write code once and deploy it on both iOS and Android platforms. 
           React Native uses native components instead of web components, providing a truly native user experience.`,
    metadata: { source: 'react-native-docs', topic: 'introduction', page: 1 },
  },
  {
    text: `TypeScript is a strongly typed programming language that builds on JavaScript. 
           It adds optional static typing, classes, and interfaces to JavaScript, making it easier to write 
           and maintain large-scale applications. TypeScript code compiles to plain JavaScript.`,
    metadata: { source: 'typescript-docs', topic: 'overview', page: 1 },
  },
  {
    text: `RunAnywhere is an AI SDK that enables developers to run machine learning models directly on mobile devices. 
           It supports various backends including ONNX for embeddings and text generation (TinyLlama), LlamaCPP for larger LLMs, and Whisper for speech recognition. 
           All processing happens on-device, ensuring privacy and offline functionality.`,
    metadata: { source: 'runanywhere-docs', topic: 'features', page: 1 },
  },
  {
    text: `Retrieval-Augmented Generation (RAG) is a technique that combines information retrieval with text generation. 
           It first retrieves relevant documents from a knowledge base, then uses them as context for generating answers. 
           This approach improves accuracy and allows LLMs to access up-to-date information without retraining.`,
    metadata: { source: 'ai-concepts', topic: 'rag', page: 1 },
  },
];

export const RAGScreen: React.FC = () => {
  const [rag, setRag] = useState<any>(null);
  const [ragError, setRagError] = useState<string | null>(null);
  const [isReady, setIsReady] = useState(false);
  const [question, setQuestion] = useState('');
  const [result, setResult] = useState<RAGResult | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isInitializing, setIsInitializing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [documentCount, setDocumentCount] = useState(0);
  const [embeddingModel, setEmbeddingModel] = useState<SDKModelInfo | null>(null);
  const [llmModel, setLlmModel] = useState<SDKModelInfo | null>(null);
  const [availableModels, setAvailableModels] = useState<SDKModelInfo[]>([]);
  const [showModelSelection, setShowModelSelection] = useState(false);
  const [modelSelectionContext, setModelSelectionContext] = useState<'embedding' | 'llm'>('embedding');
  const scrollViewRef = useRef<ScrollView>(null);

  // Initialize RAG instance once on component mount using proper singleton pattern
  // This ensures NitroModules is initialized exactly once, preventing JSI global conflicts
  useEffect(() => {
    let isMounted = true;

    const initRAG = async () => {
      try {
        setIsInitializing(true);
        console.debug('[RAGScreen] Initializing global NitroModules...');
        
        // FIRST: Initialize NitroModules globally to ensure install() is called exactly once
        await initializeNitroModulesGlobally();
        console.debug('[RAGScreen] Global NitroModules initialized');
        
        // THEN: Create RAG instance (will use the already-initialized singleton)
        const ragInstance = createRAG();
        
        if (isMounted) {
          setRag(ragInstance);
          setRagError(null);
          console.debug('[RAGScreen] RAG module initialized successfully');
        }
      } catch (err) {
        if (isMounted) {
          const errorMsg = err instanceof Error ? err.message : 'Failed to initialize RAG module';
          setRagError(errorMsg);
          console.error('[RAGScreen] RAG module initialization failed:', err);
        }
      } finally {
        if (isMounted) {
          setIsInitializing(false);
        }
      }
    };

    // Start initialization after a small delay to ensure JSI context is ready
    const timer = setTimeout(() => {
      if (isMounted) {
        initRAG();
      }
    }, 500);

    return () => {
      isMounted = false;
      clearTimeout(timer);
    };
  }, []);

  // Load available models on mount
  useEffect(() => {
    loadAvailableModels();
  }, []);

  // Refresh available models whenever this tab comes into focus
  // This ensures newly downloaded models appear after returning from Settings
  useFocusEffect(
    React.useCallback(() => {
      console.debug('[RAGScreen] Tab focused, refreshing available models...');
      loadAvailableModels();
    }, [])
  );

  // Cleanup RAG instance on unmount
  useEffect(() => {
    return () => {
      if (rag) {
        rag.destroy().catch(console.error);
      }
    };
  }, [rag]);

  /**
   * Load available models from catalog
   */
  const loadAvailableModels = async () => {
    try {
      const allModels = await RunAnywhere.getAvailableModels();
      setAvailableModels(allModels);
      console.warn('[RAGScreen] Available models:', allModels.length);
    } catch (error) {
      console.warn('[RAGScreen] Error loading models:', error);
    }
  };

  const stripModelExtension = (modelId: string): string => {
    return modelId
      .replace(/\.tar\.bz2$/i, '')
      .replace(/\.tar\.gz$/i, '')
      .replace(/\.zip$/i, '')
      .replace(/\.gguf$/i, '')
      .replace(/\.onnx$/i, '')
      .replace(/\.bin$/i, '');
  };

  const resolveModelPath = (model: SDKModelInfo, modelsDir: string): string | null => {
    // ALWAYS prefer localPath if it's provided - it's already the full path
    // FileSystem.getModelPath() now returns the complete path:
    // - For LlamaCpp: /path/to/model.gguf
    // - For ONNX SingleFile: /path/to/model.onnx (our fix returns full file path, not directory)
    // - For ONNX Archives: /path/to/extracted/directory or /path/to/nested/model.onnx
    if (model.localPath) {
      return model.localPath;
    }

    // If no localPath, construct it from modelsDir
    if (!modelsDir) {
      return null;
    }

    const baseId = stripModelExtension(model.id);
    const downloadURL = (model as any).downloadURL as string | undefined;
    const isOnnxById = model.id.toLowerCase().includes('minilm') || model.id.toLowerCase().includes('embedding') || model.id.toLowerCase().includes('vocab');
    const isOnnxByName = model.name.toLowerCase().includes('minilm') || model.name.toLowerCase().includes('embedding') || model.name.toLowerCase().includes('vocab');
    const isOnnxByUrl = !!downloadURL && downloadURL.toLowerCase().includes('.onnx');
    const framework =
      model.preferredFramework ||
      (model.format === ModelFormat.ONNX ||
      model.format === ModelFormat.Zip ||
      model.format === ModelFormat.Folder ||
      model.compatibleFrameworks?.includes('ONNX') ||
      isOnnxById ||
      isOnnxByName ||
      isOnnxByUrl
        ? 'ONNX'
        : 'LlamaCpp');

    const baseDir = `${modelsDir}/${framework}/${baseId}`;

    if (framework === 'LlamaCpp') {
      const ext = model.format === ModelFormat.Bin ? '.bin' : '.gguf';
      return `${baseDir}/${baseId}${ext}`;
    }

    // For ONNX framework, try to get actual filename from download URL if available
    if (isOnnxByUrl && downloadURL) {
      try {
        const urlParts = downloadURL.split('/');
        const fileName = urlParts[urlParts.length - 1] || 'model.onnx';
        return `${baseDir}/${fileName}`;
      } catch {
        return `${baseDir}/model.onnx`;
      }
    }

    return `${baseDir}/model.onnx`;
  };

  const resolveVocabPath = (embeddingPath: string): string | null => {
    if (!embeddingPath) {
      return null;
    }

    if (embeddingPath.endsWith('.onnx')) {
      const lastSlash = embeddingPath.lastIndexOf('/');
      if (lastSlash === -1) {
        return null;
      }
      return `${embeddingPath.substring(0, lastSlash)}/vocab.txt`;
    }

    return `${embeddingPath}/vocab.txt`;
  };

  const initializeRAG = async () => {
    try {
      setIsInitializing(true);
      setError(null);

      console.debug('[RAGScreen] Initialize RAG button pressed');

      // Check if RAG module is available
      if (!rag) {
        const msg = ragError || 'RAG module is not available. Please try again.';
        setError(msg);
        console.error('[RAGScreen] RAG module not initialized:', ragError);
        setIsInitializing(false);
        return;
      }

      // Check if models are selected
      if (!embeddingModel || !llmModel) {
        const msg = 'Please select both embedding and LLM models';
        setError(msg);
        console.warn('[RAGScreen]', msg);
        setIsInitializing(false);
        return;
      }

      const selectedModelsLog = {
        embedding: {
          id: embeddingModel.id,
          name: embeddingModel.name,
          isDownloaded: embeddingModel.isDownloaded,
          category: embeddingModel.category,
          format: embeddingModel.format,
          preferredFramework: embeddingModel.preferredFramework,
          compatibleFrameworks: embeddingModel.compatibleFrameworks,
          localPath: embeddingModel.localPath,
          downloadURL: (embeddingModel as any).downloadURL,
        },
        llm: {
          id: llmModel.id,
          name: llmModel.name,
          isDownloaded: llmModel.isDownloaded,
          category: llmModel.category,
          format: llmModel.format,
          preferredFramework: llmModel.preferredFramework,
          compatibleFrameworks: llmModel.compatibleFrameworks,
          localPath: llmModel.localPath,
          downloadURL: (llmModel as any).downloadURL,
        }
      };
      console.debug('[RAGScreen] Selected models:', JSON.stringify(selectedModelsLog));

      // Check if models are downloaded
      if (!embeddingModel.isDownloaded || !llmModel.isDownloaded) {
        const msg = 'Both models must be downloaded. Please download them in Settings tab first.';
        setError(msg);
        console.warn('[RAGScreen]', msg, { embeddingDownloaded: embeddingModel.isDownloaded, llmDownloaded: llmModel.isDownloaded });
        setIsInitializing(false);
        return;
      }

      console.debug('[RAGScreen] Getting models directory...');
      const modelsDir = await RunAnywhere.getModelsDirectory();
      console.debug('[RAGScreen] Models directory:', modelsDir);

      const embeddingPath = resolveModelPath(embeddingModel, modelsDir);
      const llmPath = resolveModelPath(llmModel, modelsDir);
      const vocabModel = availableModels.find((model) => model.id === 'all-minilm-l6-v2-vocab');
      const vocabPath = vocabModel && vocabModel.isDownloaded
        ? resolveModelPath(vocabModel, modelsDir)
        : (embeddingPath ? resolveVocabPath(embeddingPath) : null);

      console.warn('[RAGScreen] Resolved paths:', { embeddingPath, llmPath, modelsDir });

      if (!embeddingPath || !llmPath) {
        const msg = `Unable to resolve model paths. Embedding: ${embeddingPath}, LLM: ${llmPath}`;
        setError(msg);
        console.error('[RAGScreen]', msg);
        setIsInitializing(false);
        return;
      }

      console.warn('[RAGScreen] Starting RAG initialization with:', { embeddingPath, llmPath });

      // Initialize RAG pipeline
      console.warn('[RAGScreen] Calling rag.initialize...');
      await rag.initialize(
        createRAGConfig(embeddingPath, llmPath, {
          topK: 5,
          similarityThreshold: 0.25,
          maxContextTokens: 2048,
          chunkSize: 512,
          chunkOverlap: 50,
          embeddingConfigJson: vocabPath
            ? JSON.stringify({ vocab_path: vocabPath })
            : undefined,
        })
      );

      console.warn('[RAGScreen] RAG.initialize completed successfully');

      // Add sample documents
      console.warn('[RAGScreen] Adding sample documents...');
      await rag.addDocuments(SAMPLE_DOCUMENTS);

      const count = await rag.getDocumentCount();
      console.warn('[RAGScreen] Successfully added documents, count:', count);
      
      setDocumentCount(count);
      setIsReady(true);
      setError(null);
      
      const successMsg = `RAG initialized successfully with ${count} documents`;
      console.warn('[RAGScreen]', successMsg);
      Alert.alert('Success', successMsg);
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to initialize RAG';
      setError(errorMsg);
      console.error('[RAGScreen] RAG initialization error:', { 
        error: err,
        message: errorMsg,
        embeddingModel: embeddingModel ? { id: embeddingModel.id, name: embeddingModel.name } : null,
        llmModel: llmModel ? { id: llmModel.id, name: llmModel.name } : null,
        ragAvailable: !!rag,
        ragError
      });
      Alert.alert('RAG Initialization Error', errorMsg);
    } finally {
      setIsInitializing(false);
    }
  };

  const handleQuery = async () => {
    if (!question.trim()) {
      Alert.alert('Error', 'Please enter a question');
      return;
    }

    try {
      setIsLoading(true);
      setError(null);

      const queryResult = await rag.query(question, {
        maxTokens: 256,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
      });

      setResult(queryResult);
      
      // Scroll to results
      setTimeout(() => {
        scrollViewRef.current?.scrollToEnd({ animated: true });
      }, 100);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Query failed');
      console.error('Query error:', err);
    } finally {
      setIsLoading(false);
    }
  };

  const handleClearDocuments = async () => {
    try {
      await rag.clearDocuments();
      setResult(null);
      setDocumentCount(0);
      Alert.alert('Success', 'Documents cleared successfully');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to clear documents');
    }
  };

  const handleAddDocuments = async () => {
    try {
      await rag.addDocuments(SAMPLE_DOCUMENTS);
      const count = await rag.getDocumentCount();
      setDocumentCount(count);
      Alert.alert('Success', `Added ${SAMPLE_DOCUMENTS.length} documents`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to add documents');
    }
  };

  const getDisplayedGenerationMs = (ragResult: RAGResult): number => {
    const raw = Number.isFinite(ragResult.generationTimeMs) ? ragResult.generationTimeMs : 0;
    if (raw > 0) {
      return raw;
    }
    const total = Number.isFinite(ragResult.totalTimeMs) ? ragResult.totalTimeMs : 0;
    const retrieval = Number.isFinite(ragResult.retrievalTimeMs) ? ragResult.retrievalTimeMs : 0;
    const fallback = total - retrieval;
    return fallback > 0 ? fallback : 0;
  };

  // Show error if RAG module failed to initialize
  if (ragError) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>RAG prototype</Text>
        </View>
        <ScrollView style={styles.content}>
          <View style={styles.errorContainer}>
            <Icon name="alert-circle-outline" size={64} color={Colors.error} />
            <Text style={styles.errorTitle}>RAG Module Error</Text>
            <Text style={styles.errorMessage}>{ragError}</Text>
            <Text style={styles.errorHint}>
              This error occurs in Bridgeless mode if NitroModules JSI bindings are not properly initialized.
              Try restarting the app or checking that react-native-nitro-modules is correctly linked.
            </Text>
          </View>
        </ScrollView>
      </SafeAreaView>
    );
  }

  // Show loading if RAG is initializing
  if (!rag) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>RAG prototype</Text>
        </View>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={Colors.primary} />
          <Text style={styles.loadingText}>Initializing RAG module...</Text>
        </View>
      </SafeAreaView>
    );
  }

  // Show model required overlay if not initialized
  if (!isReady && !isInitializing) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>RAG prototype</Text>
        </View>
        
        {/* Model Selection Section */}
        <View style={styles.modelSelection}>
          <Text style={styles.ragSectionTitle}>Required Models</Text>
          
          <TouchableOpacity
            style={styles.modelButton}
            onPress={() => {
              setModelSelectionContext('embedding');
              setShowModelSelection(true);
            }}
          >
            <View style={styles.modelInfo}>
              <Text style={styles.modelLabel}>Embedding Model (ONNX)</Text>
              <Text style={styles.modelName}>
                {embeddingModel ? embeddingModel.name : 'Not selected'}
              </Text>
            </View>
            <Icon name="chevron-forward" size={20} color={Colors.textSecondary} />
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.modelButton}
            onPress={() => {
              setModelSelectionContext('llm');
              setShowModelSelection(true);
            }}
          >
            <View style={styles.modelInfo}>
              <Text style={styles.modelLabel}>LLM Model (GGUF)</Text>
              <Text style={styles.modelName}>
                {llmModel ? llmModel.name : 'Not selected'}
              </Text>
            </View>
            <Icon name="chevron-forward" size={20} color={Colors.textSecondary} />
          </TouchableOpacity>
        </View>

        {!embeddingModel || !llmModel ? (
          <View style={styles.overlayHint}>
            <Icon name="information-circle-outline" size={48} color={Colors.textSecondary} />
            <Text style={styles.overlayHintText}>
              Select embedding (ONNX) and LLM (GGUF) models above to get started
            </Text>
          </View>
        ) : (
          <View style={styles.overlayHint}>
            <TouchableOpacity 
              style={[styles.initButton, isInitializing && styles.buttonDisabled]} 
              onPress={initializeRAG}
              disabled={isInitializing}
            >
              <Text style={styles.initButtonText}>
                {isInitializing ? 'Initializing...' : 'Initialize RAG'}
              </Text>
            </TouchableOpacity>
          </View>
        )}

        {/* Model Selection Modal */}
        <Modal
          visible={showModelSelection}
          animationType="slide"
          presentationStyle="pageSheet"
          onRequestClose={() => setShowModelSelection(false)}
        >
          <SafeAreaView style={styles.modalContainer}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>
                {modelSelectionContext === 'embedding' ? 'Select Embedding Model' : 'Select LLM Model'}
              </Text>
              <TouchableOpacity onPress={() => setShowModelSelection(false)}>
                <Icon name="close" size={28} color={Colors.textPrimary} />
              </TouchableOpacity>
            </View>
            <ScrollView style={styles.modalContent}>
              {availableModels
                .filter(m => {
                  // Filter by model type and category
                  if (modelSelectionContext === 'embedding') {
                    // Embedding models - check category or format
                    return (
                      m.category === 'embedding' || 
                      m.format === 'onnx' ||
                      m.id.toLowerCase().includes('minilm') ||
                      m.id.toLowerCase().includes('embedding')
                    );
                  } else {
                    // LLM models - check category or format
                    return (
                      m.category === 'language' ||
                      m.category === 'multimodal' ||
                      m.format === 'gguf' ||
                      m.id.toLowerCase().includes('llama') ||
                      m.id.toLowerCase().includes('llm') ||
                      m.id.toLowerCase().includes('mistral') ||
                      m.id.toLowerCase().includes('qwen') ||
                      m.id.toLowerCase().includes('tinyllama')
                    );
                  }
                })
                .map((model) => (
                  <TouchableOpacity
                    key={model.id}
                    style={[
                      styles.modelOption,
                      !model.isDownloaded && styles.modelOptionDisabled
                    ]}
                    onPress={() => {
                      if (!model.isDownloaded) {
                        Alert.alert(
                          'Model Not Downloaded',
                          `Please download "${model.name}" from the Settings tab first.`,
                          [{ text: 'OK' }]
                        );
                        return;
                      }
                      if (modelSelectionContext === 'embedding') {
                        setEmbeddingModel(model);
                      } else {
                        setLlmModel(model);
                      }
                      setShowModelSelection(false);
                    }}
                  >
                    <View style={styles.modelOptionContent}>
                      <View>
                        <Text style={[
                          styles.modelOptionName,
                          !model.isDownloaded && styles.modelOptionNameDisabled
                        ]}>
                          {model.name}
                        </Text>
                        <Text style={styles.modelOptionMeta}>
                          {model.format?.toUpperCase() || 'Unknown'} • {model.isDownloaded ? 'Downloaded' : 'Not downloaded'}
                        </Text>
                      </View>
                      {model.isDownloaded && (
                        <Icon name="checkmark-circle" size={24} color={Colors.success} />
                      )}
                      {!model.isDownloaded && (
                        <Icon name="cloud-download-outline" size={24} color={Colors.textTertiary} />
                      )}
                    </View>
                  </TouchableOpacity>
                ))}
            </ScrollView>
          </SafeAreaView>
        </Modal>
      </SafeAreaView>
    );
  }

  // Show loading during initialization
  if (isInitializing) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>RAG prototype</Text>
        </View>
        <View style={styles.centered}>
          <ActivityIndicator size="large" color={Colors.primaryBlue} />
          <Text style={styles.loadingText}>Initializing RAG pipeline...</Text>
          <Text style={styles.loadingSubtext}>
            Loading models and adding documents
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>RAG prototype</Text>
        <View style={styles.headerActions}>
          <TouchableOpacity
            style={styles.iconButton}
            onPress={() => {
              Alert.alert(
                'RAG Info',
                `Documents: ${documentCount}\nStatus: ${isReady ? 'Ready' : 'Not Ready'}\n\nRAG combines semantic search with AI generation to answer questions using your documents as context.`
              );
            }}
          >
            <Icon name="information-circle-outline" size={24} color={Colors.primaryBlue} />
          </TouchableOpacity>
        </View>
      </View>

      <ScrollView ref={scrollViewRef} style={styles.content} contentContainerStyle={styles.contentContainer}>
        {/* Error Banner */}
        {error && (
          <View style={styles.errorContainer}>
            <Icon name="alert-circle" size={20} color={Colors.primaryRed} />
            <Text style={styles.errorText}>{error}</Text>
          </View>
        )}

        {/* Status Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Status</Text>
          <View style={styles.statusCard}>
            <View style={styles.statusRow}>
              <Text style={styles.statusLabel}>Documents:</Text>
              <Text style={styles.statusValue}>{documentCount}</Text>
            </View>
            <View style={styles.statusRow}>
              <Text style={styles.statusLabel}>Pipeline:</Text>
              <Text style={[styles.statusValue, { color: Colors.primaryGreen }]}>Ready</Text>
            </View>
          </View>
        </View>

        {/* Query Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Ask a Question</Text>
          <TextInput
            style={styles.input}
            placeholder="e.g., What is React Native?"
            placeholderTextColor={Colors.textSecondary}
            value={question}
            onChangeText={setQuestion}
            multiline
            editable={!isLoading}
          />
          <TouchableOpacity
            style={[styles.button, isLoading && styles.buttonDisabled]}
            onPress={handleQuery}
            disabled={isLoading}
          >
            {isLoading ? (
              <ActivityIndicator size="small" color={Colors.textWhite} />
            ) : (
              <>
                <Icon name="search" size={20} color={Colors.textWhite} />
                <Text style={styles.buttonText}>Query</Text>
              </>
            )}
          </TouchableOpacity>
        </View>

        {/* Results Section */}
        {result && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Answer</Text>
            <View style={styles.answerContainer}>
              <Text style={styles.answerText}>{result.answer}</Text>
            </View>

            <Text style={styles.subsectionTitle}>Timing</Text>
            <View style={styles.timingContainer}>
              <View style={styles.timingItem}>
                <Text style={styles.timingLabel}>Retrieval</Text>
                <Text style={styles.timingValue}>{result.retrievalTimeMs.toFixed(1)}ms</Text>
              </View>
              <View style={styles.timingItem}>
                <Text style={styles.timingLabel}>Generation</Text>
                <Text style={styles.timingValue}>{getDisplayedGenerationMs(result).toFixed(1)}ms</Text>
              </View>
              <View style={styles.timingItem}>
                <Text style={styles.timingLabel}>Total</Text>
                <Text style={styles.timingValue}>{result.totalTimeMs.toFixed(1)}ms</Text>
              </View>
            </View>

            <Text style={styles.subsectionTitle}>Sources ({result.retrievedChunks.length})</Text>
            {result.retrievedChunks.map((chunk, index) => (
              <View key={index} style={styles.chunkContainer}>
                <View style={styles.chunkHeader}>
                  <Text style={styles.chunkTitle}>Source {index + 1}</Text>
                  <Text style={styles.chunkScore}>
                    {(chunk.similarityScore * 100).toFixed(1)}%
                  </Text>
                </View>
                <Text style={styles.chunkText} numberOfLines={3}>
                  {chunk.text}
                </Text>
                {chunk.metadataJson && (
                  <Text style={styles.metadataText} numberOfLines={1}>
                    {chunk.metadataJson}
                  </Text>
                )}
              </View>
            ))}
          </View>
        )}

        {/* Document Management Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Document Management</Text>
          <View style={styles.buttonRow}>
            <TouchableOpacity style={[styles.button, styles.buttonSecondary]} onPress={handleAddDocuments}>
              <Icon name="add-circle-outline" size={20} color={Colors.primaryBlue} />
              <Text style={[styles.buttonText, styles.buttonTextSecondary]}>Add Docs</Text>
            </TouchableOpacity>
            <View style={styles.buttonSpacer} />
            <TouchableOpacity
              style={[styles.button, styles.buttonDanger]}
              onPress={() => {
                Alert.alert(
                  'Clear Documents',
                  'Are you sure you want to clear all documents?',
                  [
                    { text: 'Cancel', style: 'cancel' },
                    { text: 'Clear', onPress: handleClearDocuments, style: 'destructive' },
                  ]
                );
              }}
            >
              <Icon name="trash-outline" size={20} color={Colors.textWhite} />
              <Text style={styles.buttonText}>Clear</Text>
            </TouchableOpacity>
          </View>
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
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Padding.padding16,
    paddingVertical: Padding.padding8,
    backgroundColor: Colors.backgroundPrimary,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  title: {
    ...Typography.title2,
    color: Colors.textPrimary,
  },
  headerActions: {
    flexDirection: 'row',
    gap: Spacing.small,
  },
  iconButton: {
    padding: Spacing.small,
  },
  content: {
    flex: 1,
  },
  contentContainer: {
    padding: Padding.padding16,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Padding.padding20,
  },
  loadingText: {
    ...Typography.body,
    color: Colors.textPrimary,
    marginTop: Spacing.medium,
  },
  loadingSubtext: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginTop: Spacing.small,
  },
  section: {
    marginBottom: Spacing.large,
  },
  sectionTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
    marginBottom: Spacing.small,
  },
  subsectionTitle: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    marginTop: Spacing.medium,
    marginBottom: Spacing.small,
  },
  errorContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.badgeRed,
    padding: Padding.padding8,
    borderRadius: BorderRadius.medium,
    marginBottom: Spacing.medium,
    gap: Spacing.small,
  },
  errorText: {
    ...Typography.caption,
    color: Colors.primaryRed,
    flex: 1,
  },
  statusCard: {
    backgroundColor: Colors.backgroundSecondary,
    padding: Padding.padding16,
    borderRadius: BorderRadius.medium,
  },
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: Spacing.xSmall,
  },
  statusLabel: {
    ...Typography.body,
    color: Colors.textSecondary,
  },
  statusValue: {
    ...Typography.body,
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  input: {
    ...Typography.body,
    backgroundColor: Colors.backgroundSecondary,
    borderColor: Colors.borderLight,
    borderWidth: 1,
    borderRadius: BorderRadius.medium,
    padding: Padding.padding16,
    marginBottom: Spacing.small,
    minHeight: 100,
    color: Colors.textPrimary,
    textAlignVertical: 'top',
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primaryBlue,
    paddingVertical: Padding.padding8,
    paddingHorizontal: Padding.padding16,
    borderRadius: BorderRadius.medium,
    gap: Spacing.small,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonSecondary: {
    backgroundColor: Colors.backgroundSecondary,
    borderWidth: 1,
    borderColor: Colors.primaryBlue,
  },
  buttonDanger: {
    backgroundColor: Colors.primaryRed,
  },
  buttonText: {
    ...Typography.body,
    color: Colors.textWhite,
    fontWeight: '600',
  },
  buttonTextSecondary: {
    color: Colors.primaryBlue,
  },
  buttonRow: {
    flexDirection: 'row',
  },
  buttonSpacer: {
    width: Spacing.small,
  },
  answerContainer: {
    backgroundColor: Colors.backgroundSecondary,
    padding: Padding.padding16,
    borderRadius: BorderRadius.medium,
    borderLeftWidth: 4,
    borderLeftColor: Colors.primaryGreen,
  },
  answerText: {
    ...Typography.body,
    color: Colors.textPrimary,
    lineHeight: 24,
  },
  timingContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    backgroundColor: Colors.backgroundSecondary,
    padding: Padding.padding8,
    borderRadius: BorderRadius.medium,
  },
  timingItem: {
    alignItems: 'center',
  },
  timingLabel: {
    ...Typography.caption2,
    color: Colors.textSecondary,
  },
  timingValue: {
    ...Typography.body,
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  chunkContainer: {
    backgroundColor: Colors.backgroundSecondary,
    padding: Padding.padding16,
    borderRadius: BorderRadius.medium,
    marginBottom: Spacing.small,
  },
  chunkHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.small,
  },
  chunkTitle: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  chunkScore: {
    ...Typography.caption,
    color: Colors.primaryGreen,
    fontWeight: '600',
  },
  chunkText: {
    ...Typography.caption,
    color: Colors.textSecondary,
    lineHeight: 20,
  },
  metadataText: {
    ...Typography.caption2,
    color: Colors.textTertiary,
    marginTop: Spacing.small,
    fontStyle: 'italic',
  },
  // Model Selection Styles
  modelSelection: {
    padding: Padding.padding20,
    backgroundColor: Colors.backgroundPrimary,
  },
  ragSectionTitle: {
    ...Typography.subheadline,
    color: Colors.textPrimary,
    fontWeight: '600',
    marginBottom: Spacing.medium,
  },
  overlayHint: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Padding.padding30,
  },
  overlayHintText: {
    ...Typography.body,
    color: Colors.textSecondary,
    textAlign: 'center',
    marginTop: Spacing.medium,
  },
  initButton: {
    backgroundColor: Colors.primaryBlue,
    paddingVertical: Padding.padding12,
    paddingHorizontal: Padding.padding30,
    borderRadius: BorderRadius.medium,
  },
  initButtonText: {
    ...Typography.body,
    color: Colors.textWhite,
    fontWeight: '600',
  },
  modelButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: Colors.backgroundSecondary,
    padding: Padding.padding16,
    borderRadius: BorderRadius.medium,
    marginBottom: Spacing.small,
  },
  modelInfo: {
    flex: 1,
  },
  modelLabel: {
    ...Typography.caption,
    color: Colors.textSecondary,
    marginBottom: 4,
  },
  modelName: {
    ...Typography.body,
    color: Colors.textPrimary,
    fontWeight: '500',
  },
  modalContainer: {
    flex: 1,
    backgroundColor: Colors.backgroundPrimary,
  },
  modalHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: Padding.padding20,
    borderBottomWidth: 1,
    borderBottomColor: Colors.borderLight,
  },
  modalTitle: {
    ...Typography.headline,
    color: Colors.textPrimary,
    fontWeight: '600',
  },
  modalContent: {
    flex: 1,
    padding: Padding.padding20,
  },
  modelOption: {
    backgroundColor: Colors.backgroundSecondary,
    padding: Padding.padding16,
    borderRadius: BorderRadius.medium,
    marginBottom: Spacing.small,
  },
  modelOptionDisabled: {
    opacity: 0.6,
  },
  modelOptionContent: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    width: '100%',
  },
  modelOptionName: {
    ...Typography.body,
    color: Colors.textPrimary,
    fontWeight: '500',
    marginBottom: 4,
  },
  modelOptionNameDisabled: {
    color: Colors.textTertiary,
  },
  modelOptionPath: {
    ...Typography.caption,
    color: Colors.textSecondary,
  },
  modelOptionMeta: {
    ...Typography.caption2,
    color: Colors.textSecondary,
    marginTop: 2,
  },
});

export default RAGScreen;
