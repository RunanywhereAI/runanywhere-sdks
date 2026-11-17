// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/logging.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere/public/extensions/runanywhere_logging.dart';

void main() {
  group('Logging parity (Flutter)', () {
    late LoggingConfiguration previousConfig;
    late int previousCommonsLevel;

    setUp(() {
      previousConfig = SDKLoggerConfig.shared.configuration.deepCopy();
      previousCommonsLevel = DartBridge.getCommonsMinLogLevel();
    });

    tearDown(() {
      SDKLoggerConfig.shared.configure(previousConfig);
      DartBridge.setCommonsMinLogLevel(previousCommonsLevel);
    });

    test('LogLevel to RacLogLevel mapping', () {
      expect(LogLevel.LOG_LEVEL_TRACE.toRacLogLevel(), equals(RacLogLevel.trace));
      expect(LogLevel.LOG_LEVEL_DEBUG.toRacLogLevel(), equals(RacLogLevel.debug));
      expect(LogLevel.LOG_LEVEL_INFO.toRacLogLevel(), equals(RacLogLevel.info));
      expect(LogLevel.LOG_LEVEL_WARNING.toRacLogLevel(), equals(RacLogLevel.warning));
      expect(LogLevel.LOG_LEVEL_ERROR.toRacLogLevel(), equals(RacLogLevel.error));
      expect(LogLevel.LOG_LEVEL_FATAL.toRacLogLevel(), equals(RacLogLevel.fatal));
    });

    test('RacLogLevel to LogLevel mapping', () {
      expect(racLogLevelToProto(RacLogLevel.trace), equals(LogLevel.LOG_LEVEL_TRACE));
      expect(racLogLevelToProto(RacLogLevel.debug), equals(LogLevel.LOG_LEVEL_DEBUG));
      expect(racLogLevelToProto(RacLogLevel.info), equals(LogLevel.LOG_LEVEL_INFO));
      expect(racLogLevelToProto(RacLogLevel.warning), equals(LogLevel.LOG_LEVEL_WARNING));
      expect(racLogLevelToProto(RacLogLevel.error), equals(LogLevel.LOG_LEVEL_ERROR));
      expect(racLogLevelToProto(RacLogLevel.fatal), equals(LogLevel.LOG_LEVEL_FATAL));
      expect(racLogLevelToProto(999), equals(LogLevel.LOG_LEVEL_INFO));
    });

    test('SDKLoggerConfig setMinLogLevel updates configuration', () {
      SDKLoggerConfig.shared.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
      expect(SDKLoggerConfig.shared.configuration.minLogLevel, equals(LogLevel.LOG_LEVEL_DEBUG));

      SDKLoggerConfig.shared.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR);
      expect(SDKLoggerConfig.shared.configuration.minLogLevel, equals(LogLevel.LOG_LEVEL_ERROR));
    });

    test('RunAnywhereLogging public entrypoints synchronize log level', () {
      RunAnywhereLogging.setLogLevel(LogLevel.LOG_LEVEL_DEBUG);
      expect(SDKLoggerConfig.shared.configuration.minLogLevel, equals(LogLevel.LOG_LEVEL_DEBUG));

      RunAnywhereLogging.setLogLevel(LogLevel.LOG_LEVEL_WARNING);
      expect(SDKLoggerConfig.shared.configuration.minLogLevel, equals(LogLevel.LOG_LEVEL_WARNING));

      RunAnywhereLogging.setDebugMode(true);
      expect(SDKLoggerConfig.shared.configuration.minLogLevel, equals(LogLevel.LOG_LEVEL_DEBUG));

      RunAnywhereLogging.setDebugMode(false);
      expect(SDKLoggerConfig.shared.configuration.minLogLevel, equals(LogLevel.LOG_LEVEL_INFO));

      final config = LoggingConfiguration(
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_ERROR,
      );
      RunAnywhereLogging.configureLogging(config);
      expect(SDKLoggerConfig.shared.configuration.minLogLevel, equals(LogLevel.LOG_LEVEL_ERROR));
    });
  });
}
