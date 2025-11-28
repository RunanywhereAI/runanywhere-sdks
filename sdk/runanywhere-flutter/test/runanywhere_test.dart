import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/runanywhere.dart';

void main() {
  group('RunAnywhere SDK Tests', () {
    test('SDK initialization', () async {
      await RunAnywhere.initialize(
        apiKey: 'test',
        baseURL: 'localhost',
        environment: SDKEnvironment.development,
      );

      expect(RunAnywhere.isSDKInitialized, isTrue);
      expect(RunAnywhere.getCurrentEnvironment(), equals(SDKEnvironment.development));
    });

    test('SDK reset', () {
      RunAnywhere.reset();
      expect(RunAnywhere.isSDKInitialized, isFalse);
    });

    test('Event bus access', () {
      final eventBus = RunAnywhere.events;
      expect(eventBus, isNotNull);
    });

    test('Service container access', () {
      final container = RunAnywhere.serviceContainer;
      expect(container, isNotNull);
    });
  });

  group('Component State Tests', () {
    test('ComponentState enum values', () {
      expect(ComponentState.notInitialized.value, equals('not_initialized'));
      expect(ComponentState.ready.value, equals('ready'));
      expect(ComponentState.failed.value, equals('failed'));
    });
  });

  group('Error Handling Tests', () {
    test('SDKError creation', () {
      final error = SDKError.notInitialized();
      expect(error.type, equals(SDKErrorType.notInitialized));
      expect(error.message, contains('not been initialized'));
    });

    test('SDKError modelNotFound', () {
      final error = SDKError.modelNotFound('test-model');
      expect(error.type, equals(SDKErrorType.modelNotFound));
      expect(error.message, contains('test-model'));
    });
  });
}

