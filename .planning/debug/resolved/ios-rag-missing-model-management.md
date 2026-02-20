---
status: resolved
trigger: "iOS example app RAG feature has no model download/selection UI. RAGViewModel uses empty placeholder model paths, causing pipeline creation to fail with error -102 (notInitialized)."
created: 2026-02-20T00:00:00Z
updated: 2026-02-20T00:01:00Z
---

## Current Focus

hypothesis: CONFIRMED - DocumentRAGView has hardcoded empty strings for embeddingModelPath and llmModelPath. There is a full model management system (ModelSelectionSheet, ModelListViewModel) used by other features that can be reused.
test: Implement model selection UI in DocumentRAGView using existing ModelSelectionSheet with a new .rag context
expecting: User selects embedding model (ONNX) and LLM model (GGUF) before loading a document, paths flow into RAGConfiguration
next_action: Add .rag case to ModelSelectionContext, add model selection UI to DocumentRAGView, wire paths into RAGConfiguration

## Symptoms

expected: Users should be able to download embedding, vocab, and LLM models from within the iOS app, then select them before using RAG
actual: No model download/selection UI exists. RAGViewModel uses empty/placeholder model paths in RAGConfiguration. Pipeline creation fails with -102.
errors: [rag] Failed to create RAG pipeline: -102 | error_code=notInitialized, source_file=SDKError.swift
reproduction: Open iOS example app -> navigate to RAG feature -> try to load a document -> fails
timeline: New feature, model management deferred with placeholder paths.

## Eliminated

(none - root cause confirmed immediately from code inspection)

## Evidence

- timestamp: 2026-02-20T00:01:00Z
  checked: DocumentRAGView.swift lines 22-28
  found: ragConfig computed property uses empty strings: embeddingModelPath: "", llmModelPath: ""
  implication: Direct cause of -102 error. Pipeline cannot initialize without valid model paths.

- timestamp: 2026-02-20T00:01:00Z
  checked: RAGConfiguration (RAGTypes.swift)
  found: Needs embeddingModelPath (ONNX) and llmModelPath (GGUF). embeddingDimension defaults to 384.
  implication: Two model files needed. embeddingModelPath -> ONNX embedding model, llmModelPath -> GGUF LLM model.

- timestamp: 2026-02-20T00:01:00Z
  checked: ModelSelectionSheet.swift, ModelSelectionContext enum
  found: Existing reusable sheet with contexts: .llm, .stt, .tts, .voice, .vlm. Filters models by ModelCategory.
  implication: Can add .rag context with categories [.language] for LLM and [.speechRecognition or custom] for embedding. Actually need two separate selections.

- timestamp: 2026-02-20T00:01:00Z
  checked: ModelListViewModel.swift
  found: Shared singleton, handles download/selection for all features. Uses RunAnywhere.availableModels() from SDK registry.
  implication: Model management infra is already complete. Only need to add UI in RAGView to select the two models.

- timestamp: 2026-02-20T00:01:00Z
  checked: ModelCategory enum (ModelTypes.swift)
  found: Categories: language, speechRecognition, speechSynthesis, vision, imageGeneration, multimodal, audio
  implication: Embedding models will likely be .language or a category registered by RAG module. Need to check what categories RAG models are registered under.

- timestamp: 2026-02-20T00:01:00Z
  checked: ChatInterfaceView.swift - how Chat uses model selection
  found: Uses @State var showingModelSelection, presents ModelSelectionSheet(context: .llm) as adaptiveSheet
  implication: RAGView can follow same pattern but needs TWO selections: one for embedding model, one for LLM model.

## Resolution

root_cause: DocumentRAGView.ragConfig uses empty strings for both embeddingModelPath and llmModelPath. No UI exists to let users select or download the required models (ONNX embedding model + GGUF LLM model) before attempting to load a document.

fix: |
  1. Added .ragEmbedding and .ragLLM cases to ModelSelectionContext with:
     - ragEmbedding: filters to ONNX framework, language category
     - ragLLM: filters to llamaCpp framework, language category
     - New allowedFrameworks property for framework-level filtering
  2. Updated ModelSelectionSheet to:
     - Filter availableModels by allowedFrameworks when set
     - Filter shouldShowFramework by allowedFrameworks
     - Skip memory-loading for RAG contexts (just select file path)
     - Fast-dismiss for RAG context (no loading overlay needed)
  3. Rewrote DocumentRAGView to:
     - Add @State vars: selectedEmbeddingModel, selectedLLMModel
     - Show model setup section at top with two tappable picker rows
     - ragConfig computed property returns RAGConfiguration only when both models have localPath
     - Disable "Select Document" button until areModelsReady
     - Updated empty state to guide user through model selection first
     - Pass ragConfig to loadDocument via handleFileImport

verification: Needs build and run on device/simulator. User should be able to tap embedding model row -> ModelSelectionSheet shows ONNX language models -> select one -> localPath wired in. Same for LLM (llamaCpp). Then Select Document becomes enabled. Loading a document creates pipeline with real paths.
files_changed:
  - examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/ModelSelectionSheet.swift
  - examples/ios/RunAnywhereAI/RunAnywhereAI/Features/RAG/Views/DocumentRAGView.swift
