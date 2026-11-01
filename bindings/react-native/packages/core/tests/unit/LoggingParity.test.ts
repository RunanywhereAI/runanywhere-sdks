import { LogLevel } from '../../src/Foundation/Logging/Models/LogLevel';
import { LoggingConfiguration } from '../../src/Foundation/Logging/Models/LoggingConfiguration';
import {
  LoggingManager,
  setCommonsLogLevelSink,
} from '../../src/Foundation/Logging/Services/LoggingManager';
import {
  configureLogging,
  setLogLevel,
  setDebugMode,
} from '../../src/Public/Extensions/RunAnywhere+Logging';

describe('LoggingParity (React Native)', () => {
  let previousConfig: any;
  let mockSetMinLevel: jest.Mock;

  beforeEach(() => {
    previousConfig = { ...LoggingManager.shared.configuration };
    mockSetMinLevel = jest.fn();
    setCommonsLogLevelSink(mockSetMinLevel);
  });

  afterEach(() => {
    setCommonsLogLevelSink(null);
    LoggingManager.shared.configure(previousConfig);
  });

  test('LogLevel enum values match C-ABI integers', () => {
    expect(LogLevel.LOG_LEVEL_TRACE).toBe(0);
    expect(LogLevel.LOG_LEVEL_DEBUG).toBe(1);
    expect(LogLevel.LOG_LEVEL_INFO).toBe(2);
    expect(LogLevel.LOG_LEVEL_WARNING).toBe(3);
    expect(LogLevel.LOG_LEVEL_ERROR).toBe(4);
    expect(LogLevel.LOG_LEVEL_FATAL).toBe(5);
  });

  test('LoggingManager setMinLogLevel synchronizes with native commons logger', () => {
    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_DEBUG);
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_DEBUG);

    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_ERROR);
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_ERROR);
  });

  test('LoggingManager configure synchronizes with native commons logger', () => {
    LoggingManager.shared.configure(
      LoggingConfiguration.fromPartial({
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_WARNING,
      })
    );
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_WARNING);
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_WARNING);
  });

  test('Public RunAnywhere+Logging entrypoints synchronize with commons logger', () => {
    setLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_DEBUG);
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_DEBUG);

    setLogLevel(LogLevel.LOG_LEVEL_WARNING);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_WARNING);
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_WARNING);

    setDebugMode(true);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_DEBUG);
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_DEBUG);

    setDebugMode(false);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_INFO);
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_INFO);

    configureLogging(
      LoggingConfiguration.fromPartial({
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_FATAL,
      })
    );
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_FATAL);
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_FATAL);
  });
});
