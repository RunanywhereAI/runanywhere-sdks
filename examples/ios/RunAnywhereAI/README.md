# RunAnywhereAI iOS Sample App

This sample iOS app demonstrates how to integrate multiple local LLM frameworks for on-device AI inference.

## Features

- **Multi-Framework Support**: Integrates multiple LLM frameworks including:
  - llama.cpp (GGUF models)
  - Core ML (Apple's native ML framework)
  - MLX (Apple Silicon optimized)
  - Mock service for testing

- **Chat Interface**: Full-featured chat UI with streaming responses
- **Model Management**: Browse and select from available models
- **Performance Monitoring**: Track tokens/second, memory usage, and response times
- **Settings**: Configure generation parameters (temperature, max tokens, etc.)

## Project Structure

```
RunAnywhereAI/
├── Models/
│   ├── ChatMessage.swift
│   ├── ModelInfo.swift
│   └── GenerationOptions.swift
├── Services/
│   ├── LLMService/
│   │   ├── LLMProtocol.swift
│   │   ├── MockLLMService.swift
│   │   ├── CoreMLService.swift
│   │   ├── LlamaCppService.swift
│   │   └── MLXService.swift
│   ├── UnifiedLLMService.swift
│   ├── ModelManager.swift
│   └── PerformanceMonitor.swift
├── ViewModels/
│   ├── ChatViewModel.swift
│   └── ModelListViewModel.swift
├── Views/
│   ├── ChatView.swift
│   ├── ModelListView.swift
│   └── SettingsView.swift
└── ContentView.swift
```

## Getting Started

1. Open `RunAnywhereAI.xcodeproj` in Xcode
2. Build and run the app
3. Go to the Models tab to select an LLM service
4. Start chatting!

## Adding Real LLM Support

The current implementation uses mock services. To add real LLM support:

1. **For llama.cpp**:
   - Add llama.cpp library to the project
   - Update `LlamaCppService.swift` with actual llama.cpp calls

2. **For Core ML**:
   - Convert your model to Core ML format
   - Update `CoreMLService.swift` to load and run the model

3. **For MLX**:
   - Add MLX Swift packages
   - Update `MLXService.swift` with MLX model loading

## Requirements

- iOS 13.0+ (iOS 17.0+ for MLX and advanced Core ML features)
- Xcode 14.0+
- Swift 5.0+

## License

This sample code is part of the RunAnywhereAI SDK project.