/**
 * Example: RAG Pipeline Usage
 * 
 * This example demonstrates how to use the RunAnywhere RAG package
 * for on-device retrieval-augmented generation.
 */

import React, { useEffect, useState } from 'react';
import { View, Text, TextInput, Button, ScrollView, StyleSheet, ActivityIndicator } from 'react-native';
import { createRAG, createRAGConfig, type RAGResult } from '@runanywhere/rag';
import { downloadModel } from '@runanywhere/core';

export default function RAGExample() {
  const [rag] = useState(() => createRAG());
  const [isReady, setIsReady] = useState(false);
  const [question, setQuestion] = useState('');
  const [result, setResult] = useState<RAGResult | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    initializeRAG();
    return () => {
      rag.destroy().catch(console.error);
    };
  }, []);

  const initializeRAG = async () => {
    try {
      setIsLoading(true);
      setError(null);

      // Download models if needed
      const embeddingModelPath = await downloadModel({
        url: 'https://example.com/models/all-MiniLM-L6-v2.onnx',
        filename: 'embedding-model.onnx',
      });

      const llmModelPath = await downloadModel({
        url: 'https://example.com/models/phi-2-q4.gguf',
        filename: 'llm-model.gguf',
      });

      // Initialize RAG pipeline
      await rag.initialize(
        createRAGConfig(embeddingModelPath, llmModelPath, {
          topK: 3,
          similarityThreshold: 0.7,
          maxContextTokens: 2048,
          chunkSize: 512,
          chunkOverlap: 50,
        })
      );

      // Add sample documents
      await rag.addDocuments([
        {
          text: `React Native is a popular framework for building mobile applications using React and JavaScript. 
                 It allows developers to write code once and deploy it on both iOS and Android platforms. 
                 React Native uses native components instead of web components, providing a truly native user experience.`,
          metadata: { source: 'react-native-docs', topic: 'introduction' },
        },
        {
          text: `TypeScript is a strongly typed programming language that builds on JavaScript. 
                 It adds optional static typing, classes, and interfaces to JavaScript, making it easier to write 
                 and maintain large-scale applications. TypeScript code compiles to plain JavaScript.`,
          metadata: { source: 'typescript-docs', topic: 'overview' },
        },
        {
          text: `RunAnywhere is an AI SDK that enables developers to run machine learning models directly on mobile devices. 
                 It supports various backends including LlamaCPP for LLMs, ONNX for embeddings, and Whisper for speech recognition. 
                 All processing happens on-device, ensuring privacy and offline functionality.`,
          metadata: { source: 'runanywhere-docs', topic: 'features' },
        },
        {
          text: `Retrieval-Augmented Generation (RAG) is a technique that combines information retrieval with text generation. 
                 It first retrieves relevant documents from a knowledge base, then uses them as context for generating answers. 
                 This approach improves accuracy and allows LLMs to access up-to-date information.`,
          metadata: { source: 'ai-concepts', topic: 'rag' },
        },
      ]);

      setIsReady(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to initialize RAG');
      console.error('RAG initialization error:', err);
    } finally {
      setIsLoading(false);
    }
  };

  const handleQuery = async () => {
    if (!question.trim()) {
      setError('Please enter a question');
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
      alert('Documents cleared successfully');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to clear documents');
    }
  };

  const getDocumentCount = async () => {
    try {
      const count = await rag.getDocumentCount();
      alert(`Document count: ${count}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to get document count');
    }
  };

  if (isLoading && !isReady) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" />
        <Text style={styles.loadingText}>Initializing RAG pipeline...</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container}>
      <Text style={styles.title}>RAG Example</Text>

      {error && (
        <View style={styles.errorContainer}>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}

      {isReady && (
        <>
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Ask a Question</Text>
            <TextInput
              style={styles.input}
              placeholder="e.g., What is React Native?"
              value={question}
              onChangeText={setQuestion}
              multiline
              editable={!isLoading}
            />
            <Button
              title={isLoading ? 'Processing...' : 'Query'}
              onPress={handleQuery}
              disabled={isLoading}
            />
          </View>

          {result && (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Answer</Text>
              <View style={styles.answerContainer}>
                <Text style={styles.answerText}>{result.answer}</Text>
              </View>

              <Text style={styles.subsectionTitle}>Timing</Text>
              <Text style={styles.infoText}>
                Retrieval: {result.retrievalTimeMs.toFixed(1)}ms
              </Text>
              <Text style={styles.infoText}>
                Generation: {result.generationTimeMs.toFixed(1)}ms
              </Text>
              <Text style={styles.infoText}>
                Total: {result.totalTimeMs.toFixed(1)}ms
              </Text>

              <Text style={styles.subsectionTitle}>Sources</Text>
              {result.retrievedChunks.map((chunk, index) => (
                <View key={index} style={styles.chunkContainer}>
                  <Text style={styles.chunkHeader}>
                    Chunk {index + 1} (Score: {chunk.similarityScore.toFixed(3)})
                  </Text>
                  <Text style={styles.chunkText}>{chunk.text}</Text>
                  {chunk.metadataJson && (
                    <Text style={styles.metadataText}>
                      Metadata: {chunk.metadataJson}
                    </Text>
                  )}
                </View>
              ))}

              {result.contextUsed && (
                <>
                  <Text style={styles.subsectionTitle}>Context Used</Text>
                  <Text style={styles.contextText}>{result.contextUsed}</Text>
                </>
              )}
            </View>
          )}

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Document Management</Text>
            <View style={styles.buttonRow}>
              <Button title="Get Count" onPress={getDocumentCount} />
              <View style={styles.buttonSpacer} />
              <Button title="Clear All" onPress={handleClearDocuments} color="red" />
            </View>
          </View>
        </>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
    backgroundColor: '#f5f5f5',
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 16,
    textAlign: 'center',
  },
  loadingText: {
    marginTop: 16,
    fontSize: 16,
    color: '#666',
  },
  section: {
    marginBottom: 24,
    backgroundColor: 'white',
    padding: 16,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 12,
  },
  subsectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginTop: 16,
    marginBottom: 8,
  },
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 4,
    padding: 12,
    marginBottom: 12,
    minHeight: 80,
    textAlignVertical: 'top',
  },
  errorContainer: {
    backgroundColor: '#ffe6e6',
    padding: 12,
    borderRadius: 4,
    marginBottom: 16,
  },
  errorText: {
    color: '#cc0000',
  },
  answerContainer: {
    backgroundColor: '#f9f9f9',
    padding: 12,
    borderRadius: 4,
    borderLeftWidth: 4,
    borderLeftColor: '#4CAF50',
  },
  answerText: {
    fontSize: 16,
    lineHeight: 24,
  },
  infoText: {
    fontSize: 14,
    color: '#666',
    marginBottom: 4,
  },
  chunkContainer: {
    backgroundColor: '#f0f0f0',
    padding: 12,
    borderRadius: 4,
    marginBottom: 8,
  },
  chunkHeader: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 8,
    color: '#333',
  },
  chunkText: {
    fontSize: 14,
    lineHeight: 20,
    color: '#555',
  },
  metadataText: {
    fontSize: 12,
    color: '#888',
    marginTop: 8,
    fontStyle: 'italic',
  },
  contextText: {
    fontSize: 14,
    color: '#666',
    backgroundColor: '#f9f9f9',
    padding: 12,
    borderRadius: 4,
  },
  buttonRow: {
    flexDirection: 'row',
  },
  buttonSpacer: {
    width: 12,
  },
});
