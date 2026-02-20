---
status: resolved
trigger: "ios-rag-embedding-download - embedding model and vocab not downloading in iOS example app RAG pipeline"
created: 2026-02-20T01:00:00Z
updated: 2026-02-20T01:20:00Z
---

## Current Focus

hypothesis: CONFIRMED - Three separate issues prevent embedding model from appearing/downloading in RAG
test: Traced full model registration and selection flow
expecting: Fix requires changes in 3 places
next_action: Apply fixes

## Symptoms

expected: RAG pipeline in iOS example app should be able to download embedding model and vocab file
actual: Only the language model can be downloaded; embedding model picker shows no models
errors: Silent - embedding model picker is empty
reproduction: Open iOS example app, go to RAG feature, try to select embedding model
started: Current state on RAG-Swift branch

## Eliminated

## Evidence

- timestamp: 2026-02-20
  checked: RunAnywhereAIApp.swift registerModulesAndModels()
  found: No embedding models registered. Only LLM (llamaCpp), VLM, STT (onnx), TTS (onnx), Diffusion (coreml) models registered. No ONNX embedding/RAG models at all.
  implication: The embedding model picker (ModelSelectionSheet with .ragEmbedding context) has zero models to show because none are registered.

- timestamp: 2026-02-20
  checked: ModelSelectionSheet.relevantCategories for .ragEmbedding
  found: Returns [.language] - filters by .language category. ModelSelectionSheet.allowedFrameworks for .ragEmbedding returns [.onnx].
  implication: Even if we register an embedding model, it must have category=.language to appear in the picker. But the correct category should be .embedding.

- timestamp: 2026-02-20
  checked: ModelCategory enum in ModelTypes.swift
  found: Only has: language, speechRecognition, speechSynthesis, vision, imageGeneration, multimodal, audio. Missing .embedding case.
  implication: Embedding models cannot be properly categorized in the Swift SDK.

- timestamp: 2026-02-20
  checked: C header rac_model_types.h in RACommons.xcframework
  found: RAC_MODEL_CATEGORY_EMBEDDING = 7 IS defined in the C layer. The C++ layer supports embedding category.
  implication: The Swift SDK ModelCategory enum is out of sync with the C layer - needs .embedding case added.

- timestamp: 2026-02-20
  checked: ModelTypes+CppBridge.swift toC() and init(from:)
  found: No case for .embedding / RAC_MODEL_CATEGORY_EMBEDDING. The default fallback in init(from:) maps unknowns to .audio.
  implication: If we add .embedding to Swift enum, we also need to add it to the C bridge conversion.

- timestamp: 2026-02-20
  checked: React Native App.tsx for embedding model registration
  found: Registers two ONNX models with ModelCategory.Embedding:
    1. all-minilm-l6-v2: https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx (single file, ~25MB)
    2. all-minilm-l6-v2-vocab: https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt (single file, ~500KB)
  implication: iOS should register the same models. These are the standard embedding + vocab pair for RAG.

- timestamp: 2026-02-20
  checked: ModelSelectionSheet selection behavior for .ragEmbedding context
  found: line 246: guard model.localPath != nil else { return } - only allows selecting downloaded models. Since vocab is a separate model entry, users would need to know which model is the embedding ONNX vs the vocab.
  implication: The view needs to be able to show embedding category models AND the picker filter must include .embedding category.

## Resolution

root_cause: |
  THREE issues prevent embedding model download in iOS RAG:

  1. **No embedding/vocab models registered in RunAnywhereAIApp.swift**
     - registerModulesAndModels() never calls RunAnywhere.registerModel for all-MiniLM-L6-v2
     - React Native registers these two models; iOS app does not
     - URLs: model.onnx from Hugging Face Xenova/all-MiniLM-L6-v2

  2. **ModelCategory enum in Swift SDK missing .embedding case**
     - C layer has RAC_MODEL_CATEGORY_EMBEDDING = 7
     - Swift ModelCategory only has: language, speechRecognition, speechSynthesis, vision, imageGeneration, multimodal, audio
     - ModelTypes+CppBridge.swift toC()/init(from:) don't handle embedding

  3. **ModelSelectionSheet .ragEmbedding context filters by .language category**
     - relevantCategories returns [.language] for .ragEmbedding
     - Should return [.embedding] instead (once .embedding is added to Swift SDK)

fix: |
  Changes in 3 places:

  1. sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/ModelTypes.swift
     - Add .embedding = "embedding" case to ModelCategory enum
     - Update requiresContextLength and supportsThinking computed properties

  2. sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/ModelTypes+CppBridge.swift
     - Add .embedding case to toC() returning RAC_MODEL_CATEGORY_EMBEDDING
     - Add RAC_MODEL_CATEGORY_EMBEDDING case to init(from:) returning .embedding
     - Fix default fallback (currently maps to .audio, should map to .language or keep .audio)

  3. examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/ModelSelectionSheet.swift
     - Change .ragEmbedding relevantCategories to return [.embedding]

  4. examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift
     - Register all-MiniLM-L6-v2 ONNX embedding model (single .onnx file, .embedding modality)
     - Register all-MiniLM-L6-v2 vocab file (single vocab.txt, .embedding modality)

verification: |
  All code changes applied. The fix adds:
  1. .embedding case to ModelCategory enum - syncs Swift with C layer (RAC_MODEL_CATEGORY_EMBEDDING = 7)
  2. C bridge mappings for the new embedding case in ModelTypes+CppBridge and CppBridge+ModelAssignment
  3. Two ONNX embedding models registered in app startup (model + vocab)
  4. ModelSelectionSheet .ragEmbedding now filters by [.embedding] category and excludes vocab files
  5. DocumentRAGView resolves vocab path and passes it as embeddingConfigJSON to RAGConfiguration
  6. RunAnywhere+Frameworks.swift embedding capability now maps to [.embedding] category

files_changed:
  - sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/ModelTypes.swift
  - sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/ModelTypes+CppBridge.swift
  - sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelAssignment.swift
  - sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/RunAnywhere+Frameworks.swift
  - examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/ModelSelectionSheet.swift
  - examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift
  - examples/ios/RunAnywhereAI/RunAnywhereAI/Features/RAG/Views/DocumentRAGView.swift
