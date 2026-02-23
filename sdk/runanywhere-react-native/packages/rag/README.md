# @runanywhere/rag

React Native package for RunAnywhere RAG (Retrieval-Augmented Generation) pipeline.

## Features

- 🚀 **On-device RAG** - Complete RAG pipeline running locally on mobile devices
- 📚 **Document Management** - Add documents, automatically chunk and embed them
- 🔍 **Semantic Search** - Find relevant chunks using vector similarity (USearch)
- 🤖 **Contextual Generation** - Generate answers using retrieved context (LlamaCPP)
- 🎯 **High Performance** - Native C++ implementation with zero-copy data passing
- 📦 **Small Footprint** - Efficient vector storage with HNSW indexing
- 🔒 **Privacy-First** - All processing happens on-device, no data leaves the device

## Installation

```bash
npm install @runanywhere/rag
# or
yarn add @runanywhere/rag
```

### Peer Dependencies

This package requires:
- `@runanywhere/core` >= 0.16.0
- `@runanywhere/llamacpp` >= 0.17.0
- `@runanywhere/onnx` >= 0.17.0
- `react-native` >= 0.74.0
- `react-native-nitro-modules` >= 0.31.3

### Platform Setup

#### iOS

The package includes pre-built native static libraries for iOS. After installation:

1. Install CocoaPods dependencies:
   ```bash
   cd ios && pod install
   ```

2. The native libraries will be automatically linked via CocoaPods.

For more details, see [ios/NATIVE_LIBRARIES.md](ios/NATIVE_LIBRARIES.md).

#### Android

The package includes pre-built native shared libraries for Android. The libraries will be automatically included during the build process.

Supported architectures:
- arm64-v8a (64-bit ARM)
- armeabi-v7a (32-bit ARM)
- x86_64 (64-bit x86 for emulators)

For more details, see [android/NATIVE_LIBRARIES.md](android/NATIVE_LIBRARIES.md).

## Usage

### Basic Example

```typescript
import { createRAG, createRAGConfig } from '@runanywhere/rag';

// Create RAG instance
const rag = createRAG();

// Initialize with model paths
await rag.initialize(
  createRAGConfig(
    '/path/to/embedding-model.onnx',  // ONNX embedding model
    '/path/to/llm-model.gguf'         // GGUF language model
  )
);

// Add documents to knowledge base
await rag.addDocument({
  text: 'React Native is a framework for building mobile applications...',
  metadata: { source: 'documentation', page: 1 }
});

await rag.addDocument({
  text: 'TypeScript is a typed superset of JavaScript...',
  metadata: { source: 'documentation', page: 2 }
});

// Query the RAG system
const result = await rag.query('What is React Native?');

console.log('Answer:', result.answer);
console.log('Sources:', result.retrievedChunks);
console.log('Generation time:', result.generationTimeMs, 'ms');
console.log('Total time:', result.totalTimeMs, 'ms');

// Cleanup
await rag.destroy();
```

### Advanced Configuration

```typescript
import { RAGConfig } from '@runanywhere/rag';

const config: RAGConfig = {
  embeddingModelPath: '/path/to/embedding.onnx',
  llmModelPath: '/path/to/llm.gguf',
  
  // Embedding configuration
  embeddingDimension: 384,        // Embedding vector size
  
  // Retrieval configuration
  topK: 5,                        // Number of chunks to retrieve
  similarityThreshold: 0.7,       // Minimum similarity score (0-1)
  
  // Context configuration
  maxContextTokens: 2048,         // Max tokens in context window
  chunkSize: 512,                 // Tokens per chunk
  chunkOverlap: 50,               // Overlap between chunks
  
  // Prompt template
  promptTemplate: `You are a helpful AI assistant.

Context:
{context}

Question: {query}

Answer:`,
  
  // Optional model configs
  embeddingConfigJson: JSON.stringify({ /* ONNX config */ }),
  llmConfigJson: JSON.stringify({ /* LLM config */ })
};

await rag.initialize(config);
```

### Batch Document Upload

```typescript
const documents = [
  { text: 'Document 1...', metadata: { id: 1 } },
  { text: 'Document 2...', metadata: { id: 2 } },
  { text: 'Document 3...', metadata: { id: 3 } },
];

await rag.addDocuments(documents);
```

### Query Options

```typescript
const result = await rag.query('What is TypeScript?', {
  maxTokens: 256,        // Max tokens to generate
  temperature: 0.7,      // Sampling temperature (0-1)
  topP: 0.9,            // Nucleus sampling
  topK: 40,             // Top-k sampling
  systemPrompt: 'You are a programming expert.'
});
```

### Using Retrieved Sources

```typescript
const result = await rag.query('Explain RAG');

for (const chunk of result.retrievedChunks) {
  console.log('Chunk ID:', chunk.chunkId);
  console.log('Text:', chunk.text);
  console.log('Score:', chunk.similarityScore);
  
  // Access metadata if added during document upload
  if (chunk.metadataJson) {
    const metadata = JSON.parse(chunk.metadataJson);
    console.log('Source:', metadata.source);
  }
}
```

### Document Management

```typescript
// Get document count
const count = await rag.getDocumentCount();
console.log('Documents:', count);

// Get statistics
const stats = await rag.getStatistics();
console.log('Stats:', stats);

// Clear all documents
await rag.clearDocuments();
```

## API Reference

### RAG Class

#### `initialize(config: RAGConfig): Promise<void>`
Initialize the RAG pipeline with configuration.

#### `addDocument(document: Document): Promise<void>`
Add a single document to the knowledge base.

#### `addDocuments(documents: Document[]): Promise<void>`
Add multiple documents in batch.

#### `query(question: string, options?: QueryOptions): Promise<RAGResult>`
Query the RAG system with a question.

#### `clearDocuments(): Promise<void>`
Clear all documents from the knowledge base.

#### `getDocumentCount(): Promise<number>`
Get the number of documents.

#### `getStatistics(): Promise<RAGStatistics>`
Get pipeline statistics.

#### `destroy(): Promise<void>`
Destroy the pipeline and free resources.

### Types

```typescript
interface RAGConfig {
  embeddingModelPath: string;
  llmModelPath: string;
  embeddingDimension?: number;
  topK?: number;
  similarityThreshold?: number;
  maxContextTokens?: number;
  chunkSize?: number;
  chunkOverlap?: number;
  promptTemplate?: string;
  embeddingConfigJson?: string;
  llmConfigJson?: string;
}

interface Document {
  text: string;
  metadata?: Record<string, any>;
}

interface RAGQuery {
  question: string;
  systemPrompt?: string;
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
}

interface RAGResult {
  answer: string;
  retrievedChunks: RAGChunk[];
  contextUsed?: string;
  retrievalTimeMs: number;
  generationTimeMs: number;
  totalTimeMs: number;
}

interface RAGChunk {
  chunkId: string;
  text?: string;
  similarityScore: number;
  metadataJson?: string;
}

interface RAGStatistics {
  documentCount: number;
  chunkCount: number;
  vectorStoreSize: number;
  statsJson: string;
}
```

## Model Requirements

### Embedding Model
- Format: ONNX
- Recommended: sentence-transformers models (e.g., all-MiniLM-L6-v2)
- Dimension: 384 (default) or specified in config

### Language Model
- Format: GGUF (quantized)
- Recommended: LLaMA 2/3, Mistral, Phi models
- Size: Depends on device capabilities (mobile: 1B-7B params)

## Performance Tips

1. **Model Selection**
   - Use quantized models (Q4_K_M or Q5_K_M) for best performance
   - Smaller embedding models reduce indexing time
   - Match embedding dimension with model output

2. **Chunking Strategy**
   - Adjust `chunkSize` based on model context window
   - Use `chunkOverlap` to preserve context across chunks
   - Larger chunks = more context, but fewer retrievals

3. **Retrieval Tuning**
   - Increase `topK` for more comprehensive context
   - Adjust `similarityThreshold` to filter irrelevant chunks
   - Monitor `retrievalTimeMs` to optimize parameters

4. **Context Management**
   - Set `maxContextTokens` to match model's context window
   - Longer context = better answers, but slower generation
   - Use custom `promptTemplate` to optimize token usage

## Architecture

```
┌─────────────┐
│  Documents  │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│   Chunking      │  Split into overlapping chunks
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│   Embedding     │  ONNX embedding model
│   (ONNX)        │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  Vector Store   │  USearch (HNSW index)
│  (USearch)      │
└─────────────────┘

Query Flow:
┌─────────┐
│ Question│
└────┬────┘
     │
     ▼
┌─────────────┐
│  Embed      │  ONNX
└────┬────────┘
     │
     ▼
┌─────────────┐
│  Search     │  USearch similarity search
└────┬────────┘
     │
     ▼
┌─────────────┐
│  Context    │  Build context from top-K chunks
│  Builder    │
└────┬────────┘
     │
     ▼
┌─────────────┐
│  Generate   │  LlamaCPP text generation
│  (LlamaCPP) │
└────┬────────┘
     │
     ▼
┌─────────────┐
│   Answer    │
└─────────────┘
```

## Implementation Details

- **Strategy Pattern**: Pluggable embedding and generation providers
- **C++ Core**: High-performance native implementation
- **Nitrogen Bridge**: Zero-copy data passing between JS and C++
- **Vector Search**: USearch with HNSW for fast approximate nearest neighbors
- **Memory Management**: RAII and smart pointers for leak-free operation
- **Thread Safety**: Mutex-protected pipeline for concurrent access

## Troubleshooting

### "RAG pipeline not created"
- Ensure you call `initialize()` before other methods
- Check that model paths are correct and accessible

### "Failed to add document"
- Verify embedding model is loaded correctly
- Check that document text is not empty

### "RAG query failed"
- Ensure documents have been added to the knowledge base
- Verify LLM model is loaded and has sufficient resources

### Performance Issues
- Use smaller, quantized models for mobile devices
- Reduce `topK` and `maxContextTokens` for faster queries
- Profile with `getStatistics()` to identify bottlenecks

## License

See the main SDK license.

## Support

For issues and feature requests, visit: https://github.com/RunanywhereAI/sdks
