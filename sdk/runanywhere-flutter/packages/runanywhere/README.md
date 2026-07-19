# RunAnywhere Flutter SDK

[![pub package](https://img.shields.io/pub/v/runanywhere.svg)](https://pub.dev/packages/runanywhere)
[![License](https://img.shields.io/badge/License-RunAnywhere-blue.svg)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE)

Privacy-first, on-device AI SDK for Flutter. Run LLMs, Speech-to-Text, Text-to-Speech, and Voice AI directly on user devices.

## Installation

**Step 1:** Add packages to `pubspec.yaml`:

```yaml
dependencies:
  runanywhere: ^0.20.11
  runanywhere_onnx: ^0.20.11      # STT, TTS, VAD
  runanywhere_llamacpp: ^0.20.11  # LLM text generation
```

**Step 2:** Configure platforms (see below).

---

## iOS Setup (Required)

After adding the packages, you **must** update your iOS Podfile for the SDK to work.

### 1. Update `ios/Podfile`

Make these **two critical changes**:

```ruby
# Change 1: Set minimum iOS version to 17.5
platform :ios, '17.5'

# ... (keep existing flutter_root function and setup) ...

target 'Runner' do
  # Change 2: Add static linkage - THIS IS REQUIRED
  use_frameworks! :linkage => :static

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.5'
      # Required for microphone permission (STT/Voice features)
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_MICROPHONE=1',
      ]
    end
  end
end
```

> **Important:** Without `use_frameworks! :linkage => :static`, you will see "symbol not found" errors at runtime.

For a pub.dev dependency, CocoaPods downloads the version-matched RACommons
XCFramework and verifies its immutable SHA-256 checksum automatically. Source
checkouts use a locally staged framework when present.

### 2. Update `ios/Runner/Info.plist`

Add microphone permission for STT/Voice features:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for speech recognition</string>
```

### 3. Run pod install

```bash
cd ios && pod install
```

---

## Android Setup

Add microphone permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

---

## Quick Start

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SDK and register backends
  await RunAnywhere.initialize();
  await Onnx.register();
  await LlamaCpp.register();

  runApp(MyApp());
}
```

### Text Generation (LLM)

```dart
final stream = RunAnywhere.llm
    .generateStream('Tell me a joke', LLMGenerationOptions(maxTokens: 128));
await for (final event in stream) {
  if (event.isFinal) break;
  if (event.token.isNotEmpty) print(event.token);
}
```

### Speech-to-Text

```dart
final result = await RunAnywhere.stt.transcribe(audioData);
print(result.text);
```

---

## Platform Support

| Platform | Minimum Version |
|----------|-----------------|
| iOS      | 17.5+           |
| Android  | API 24+         |

## Documentation

- [Full Documentation](https://runanywhere.ai)
- [Flutter Starter Example](https://github.com/RunanywhereAI/flutter-starter-example)

## Related Packages

- [runanywhere](https://pub.dev/packages/runanywhere) — Core SDK (this package)
- [runanywhere_llamacpp](https://pub.dev/packages/runanywhere_llamacpp) — LLM backend
- [runanywhere_onnx](https://pub.dev/packages/runanywhere_onnx) — STT/TTS/VAD backend

## License

RunAnywhere License (Apache 2.0 based, with additional commercial-use terms). See [LICENSE](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE).

Commercial licensing: san@runanywhere.ai
