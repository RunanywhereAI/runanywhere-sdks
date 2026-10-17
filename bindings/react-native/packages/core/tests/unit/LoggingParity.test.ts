import { LogLevel } from '../../src/Foundation/Logging/Models/LogLevel';
import { LoggingManager } from '../../src/Foundation/Logging/Services/LoggingManager';
import {
  configureLogging,
  setLogLevel,
  setDebugMode,
} from '../../src/Public/Extensions/RunAnywhere+Logging';
import * as NativeCore from '../../src/native/NativeRunAnywhereCore';

describe('LoggingParity (React Native)', () => {
  let previousConfig: any;
  let mockSetMinLevel: jest.Mock;
  let mockGetMinLevel: jest.Mock;

  beforeEach(() => {
    previousConfig = { ...LoggingManager.shared.configuration };
    mockSetMinLevel = jest.fn().mockResolvedValue(undefined);
    mockGetMinLevel = jest.fn().mockResolvedValue(LogLevel.LOG_LEVEL_INFO);

    jest.spyOn(NativeCore, 'isNativeModuleAvailable').mockReturnValue(true);
    jest.spyOn(NativeCore, 'requireNativeModule').mockReturnValue({
      loggerSetMinLevel: mockSetMinLevel,
      loggerGetMinLevel: mockGetMinLevel,
    } as any);
  });

  afterEach(() => {
    LoggingManager.shared.configure(previousConfig);
    jest.restoreAllMocks();
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
    LoggingManager.shared.configure({
      enableLocalLogging: true,
      minLogLevel: LogLevel.LOG_LEVEL_WARNING,
    });
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

    configureLogging({
      enableLocalLogging: true,
      minLogLevel: LogLevel.LOG_LEVEL_FATAL,
    });
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_FATAL);
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_FATAL);
  });
});
