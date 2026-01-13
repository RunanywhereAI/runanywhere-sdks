# RunAnywhereAI - React Native Example

A sample React Native app demonstrating the RunAnywhere React Native SDK's on-device AI capabilities.

## Features

- **AI Chat** - Interactive conversations with streaming responses
- **Model Management** - Download and manage AI models
- **Voice** - Speech-to-text and text-to-speech
- **Cross-Platform** - iOS and Android support

## Requirements

- Node.js 18+
- React Native 0.71+
- iOS: Xcode 15+, iOS 15.1+
- Android: Android Studio, API 24+

## Setup

```bash
# Clone the repo
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/react-native/RunAnywhereAI

# Install dependencies
npm install
# or
yarn install
```

## Running

### iOS

```bash
cd ios && pod install && cd ..
npx react-native run-ios
```

### Android

```bash
npx react-native run-android
```

## SDK Integration

The app demonstrates:

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';

// Initialize
await RunAnywhere.initialize({
  apiKey: 'dev',
  environment: SDKEnvironment.Development,
});

// Register backend
LlamaCPP.register();

// Generate text
const response = await RunAnywhere.chat('Hello!');

// Stream generation
RunAnywhere.generateStream('Tell me a story', undefined, (token) => {
  console.log(token);
});
```

See the [React Native SDK documentation](../../../sdk/runanywhere-react-native/README.md) for full API reference.

## Architecture

- **TypeScript** - Type-safe codebase
- **React Navigation** - Tab-based navigation
- **Zustand** - State management

## Contributing

See [CONTRIBUTING.md](../../../CONTRIBUTING.md) for guidelines.

## License

Apache License 2.0 - See [LICENSE](../../../LICENSE)
