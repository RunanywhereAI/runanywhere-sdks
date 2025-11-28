# RunAnywhere AI - Flutter Example App

A comprehensive Flutter example application demonstrating the RunAnywhere Flutter SDK's on-device AI capabilities.

## Features

### 1. Chat Interface
- Real-time streaming text generation
- Chat history with user and assistant messages
- Error handling and loading states

### 2. Storage Management
- View available models
- Download models with progress tracking
- Load models for generation
- Track model status (downloaded, active)

### 3. Settings
- Configure generation parameters (max tokens, temperature)
- View SDK information (version, environment)
- Monitor memory statistics
- Toggle streaming mode

### 4. Quiz Generator
- Generate educational quizzes from topics
- Interactive quiz interface
- Answer validation and feedback

### 5. Voice Assistant
- Voice transcription (placeholder for audio recording)
- Voice-to-text conversation
- Real-time responses

## Getting Started

### Prerequisites

- Flutter SDK >= 3.0.0
- Dart >= 3.0.0
- iOS 13.0+ / Android API 21+

### Installation

1. Navigate to the example app directory:
```bash
cd examples/flutter/RunAnywhereAI
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## SDK Integration

The example app demonstrates:

- **SDK Initialization**: Proper initialization with environment detection
- **Text Generation**: Both streaming and non-streaming generation
- **Model Management**: Loading and managing AI models
- **Event Handling**: Subscribing to SDK events
- **Error Handling**: Comprehensive error handling throughout

## Architecture

The app follows MVVM-like patterns:

- **Features**: Feature-specific views and logic
- **Core**: Shared services, design system, utilities
- **App**: Application-level configuration and navigation

## Design System

The app uses a consistent design system:

- **Colors**: `AppColors` - Semantic color palette
- **Typography**: `AppTypography` - Text styles
- **Spacing**: `AppSpacing` - Consistent spacing values

## Notes

- The SDK is initialized in development mode by default
- Some features (like voice recording) require platform-specific implementations
- Model downloads require valid model URLs from the backend
