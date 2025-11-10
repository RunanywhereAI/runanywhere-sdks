/// RunAnywhere Flutter SDK
///
/// Main entry point for the RunAnywhere SDK
///
/// Example usage:
/// ```dart
/// import 'package:runanywhere_flutter/runanywhere.dart';
///
/// // Initialize the SDK
/// await RunAnywhere.initialize(
///   apiKey: 'dev',
///   baseURL: 'localhost',
///   environment: SDKEnvironment.development,
/// );
///
/// // Generate text
/// final response = await RunAnywhere.chat('Hello, how are you?');
/// print(response);
///
/// // Stream generation
/// RunAnywhere.generateStream('Tell me a story').listen((token) {
///   print(token);
/// });
///
/// // Voice transcription
/// final transcript = await RunAnywhere.transcribe(audioData);
/// print(transcript);
/// ```
library runanywhere_flutter;

// Public API
export 'public/runanywhere.dart';
export 'public/events/event_bus.dart';
export 'public/events/sdk_event.dart';
export 'public/errors/sdk_error.dart';
export 'public/models/configuration/sdk_environment.dart';
export 'public/models/configuration/sdk_init_params.dart';
export 'public/models/generation_result.dart';
export 'public/models/generation_options.dart';
export 'public/models/model_info.dart';
export 'public/models/performance_metrics.dart';
