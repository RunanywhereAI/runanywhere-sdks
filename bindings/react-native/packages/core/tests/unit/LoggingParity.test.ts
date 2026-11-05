import { LoggingConfiguration } from '@runanywhere/proto-ts/logging';
import { LogLevel } from '../../src/Foundation/Logging/Models/LogLevel';
import {
  LoggingManager,
  setCommonsLogLevelSink,
} from '../../src/Foundation/Logging/Services/LoggingManager';
import {
  configureLogging,
  setLogLevel,
  setDebugMode,
} from '../../src/Public/Extensions/RunAnywhere+Logging';

// Commons level updates are queued; let the queue drain.
const settle = () => new Promise((resolve) => setImmediate(resolve));

describe('LoggingParity (React Native)', () => {
  let previousConfig: LoggingConfiguration;
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

  test('LoggingManager setMinLogLevel synchronizes with native commons logger', async () => {
    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_DEBUG);
    await settle();
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_DEBUG);

    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_ERROR);
    await settle();
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_ERROR);
  });

  test('LoggingManager configure synchronizes with native commons logger', async () => {
    LoggingManager.shared.configure(
      LoggingConfiguration.fromPartial({
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_WARNING,
      })
    );
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_WARNING);
    await settle();
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_WARNING);
  });

  test('Public RunAnywhere+Logging entrypoints synchronize with commons logger', async () => {
    setLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_DEBUG);
    await settle();
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_DEBUG);

    setLogLevel(LogLevel.LOG_LEVEL_WARNING);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_WARNING);
    await settle();
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_WARNING);

    setDebugMode(true);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_DEBUG);
    await settle();
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_DEBUG);

    setDebugMode(false);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_INFO);
    await settle();
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_INFO);

    configureLogging(
      LoggingConfiguration.fromPartial({
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_FATAL,
      })
    );
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(LogLevel.LOG_LEVEL_FATAL);
    await settle();
    expect(mockSetMinLevel).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_FATAL);
  });

  test('commons level updates apply in call order and rejections are contained', async () => {
    let commonsLevel: LogLevel | undefined;
    const pending: Array<() => void> = [];
    // Native completes calls out of order; the first one also rejects.
    setCommonsLogLevelSink((level) => {
      if (level === LogLevel.LOG_LEVEL_DEBUG) {
        return Promise.reject(new Error('native logger unavailable'));
      }
      return new Promise<void>((resolve) => {
        pending.push(() => {
          commonsLevel = level;
          resolve();
        });
      });
    });
    const unhandled = jest.fn();
    process.on('unhandledRejection', unhandled);
    try {
      LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
      LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_INFO);
      LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR);
      for (let i = 0; i < 10; i++) {
        await settle();
        pending.reverse().forEach((complete) => complete());
        pending.length = 0;
      }
      expect(commonsLevel).toBe(LogLevel.LOG_LEVEL_ERROR);
      expect(unhandled).not.toHaveBeenCalled();
    } finally {
      process.off('unhandledRejection', unhandled);
    }
  });
});
