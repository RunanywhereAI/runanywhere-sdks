import { LoggingConfiguration } from '@runanywhere/proto-ts/logging';
import { LogLevel } from '../../src/Foundation/Logging/Models/LogLevel';
import {
  LoggingManager,
  setCommonsLogLevelSink,
  whenCommonsLogLevelSynced,
} from '../../src/Foundation/Logging/Services/LoggingManager';

interface PendingCall {
  level: LogLevel;
  resolve: () => void;
  reject: (error: Error) => void;
}

/**
 * Stands in for `loggerSetMinLevel` on the Nitro thread pool: every call
 * returns a promise the test settles by hand, and the level only lands in
 * "commons" when that promise resolves. Calls that were allowed to run at the
 * same time could therefore finish in any order.
 */
function fakeNativeLogger() {
  const state = { commonsLevel: null as LogLevel | null };
  const calls: PendingCall[] = [];
  const sink = jest.fn(
    (level: LogLevel) =>
      new Promise<void>((resolve, reject) => {
        calls.push({
          level,
          resolve: () => {
            state.commonsLevel = level;
            resolve();
          },
          reject,
        });
      })
  );
  return { sink, calls, state };
}

/** Let queued promise callbacks run. */
function flush(): Promise<void> {
  return new Promise((resolve) => setImmediate(resolve));
}

describe('Commons log level sync (React Native)', () => {
  let previousConfig: LoggingConfiguration;

  beforeEach(() => {
    previousConfig = { ...LoggingManager.shared.configuration };
    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_INFO);
  });

  afterEach(async () => {
    setCommonsLogLevelSink(null);
    await whenCommonsLogLevelSynced();
    LoggingManager.shared.configure(previousConfig);
  });

  /** Register the fake and settle the push of the current level that registration triggers. */
  async function registerFake() {
    const native = fakeNativeLogger();
    setCommonsLogLevelSink(native.sink);
    native.calls[0].resolve();
    await whenCommonsLogLevelSynced();
    native.calls.length = 0;
    native.sink.mockClear();
    return native;
  }

  test('two rapid changes leave commons at the later level', async () => {
    const native = await registerFake();

    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR);

    // The second change waits for the first instead of racing it.
    expect(native.calls.map((c) => c.level)).toEqual([
      LogLevel.LOG_LEVEL_DEBUG,
    ]);

    native.calls[0].resolve();
    await flush();
    expect(native.calls.map((c) => c.level)).toEqual([
      LogLevel.LOG_LEVEL_DEBUG,
      LogLevel.LOG_LEVEL_ERROR,
    ]);

    native.calls[1].resolve();
    await whenCommonsLogLevelSynced();
    expect(native.state.commonsLevel).toBe(LogLevel.LOG_LEVEL_ERROR);
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(
      LogLevel.LOG_LEVEL_ERROR
    );
  });

  test('a burst of changes sends only the latest after the in-flight call', async () => {
    const native = await registerFake();

    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_INFO);
    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_WARNING);
    LoggingManager.shared.configure(
      LoggingConfiguration.fromPartial({
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_FATAL,
      })
    );

    native.calls[0].resolve();
    await flush();
    native.calls[1].resolve();
    await whenCommonsLogLevelSynced();

    expect(native.calls.map((c) => c.level)).toEqual([
      LogLevel.LOG_LEVEL_DEBUG,
      LogLevel.LOG_LEVEL_FATAL,
    ]);
    expect(native.state.commonsLevel).toBe(LogLevel.LOG_LEVEL_FATAL);
  });

  test('a rejected native call does not produce an unhandled rejection', async () => {
    const unhandled = jest.fn();
    process.on('unhandledRejection', unhandled);
    try {
      const sink = jest.fn(() =>
        Promise.reject(new Error('native logger unavailable'))
      );
      setCommonsLogLevelSink(sink);
      LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_WARNING);

      await whenCommonsLogLevelSynced();
      await flush();

      expect(sink).toHaveBeenCalledWith(LogLevel.LOG_LEVEL_WARNING);
      expect(unhandled).not.toHaveBeenCalled();
    } finally {
      process.off('unhandledRejection', unhandled);
    }
  });

  test('later changes still reach commons after a rejection', async () => {
    const native = await registerFake();

    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR);
    native.calls[0].reject(new Error('transient failure'));
    await flush();
    native.calls[1].resolve();
    await whenCommonsLogLevelSynced();

    expect(native.state.commonsLevel).toBe(LogLevel.LOG_LEVEL_ERROR);
  });

  test('a sink that throws synchronously does not break setMinLogLevel', async () => {
    setCommonsLogLevelSink(() => {
      throw new Error('native module missing');
    });

    expect(() =>
      LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR)
    ).not.toThrow();
    await expect(whenCommonsLogLevelSynced()).resolves.toBeUndefined();
    expect(LoggingManager.shared.configuration.minLogLevel).toBe(
      LogLevel.LOG_LEVEL_ERROR
    );
  });

  test('whenCommonsLogLevelSynced waits for a queued change, not just the first call', async () => {
    const native = await registerFake();

    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR);

    let settled = false;
    const done = whenCommonsLogLevelSynced().then(() => {
      settled = true;
    });

    native.calls[0].resolve();
    await flush();
    expect(settled).toBe(false);

    native.calls[1].resolve();
    await done;
    expect(settled).toBe(true);
    expect(native.state.commonsLevel).toBe(LogLevel.LOG_LEVEL_ERROR);
  });

  test('removing the sink drops a change still waiting to be sent', async () => {
    const native = await registerFake();

    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR);
    setCommonsLogLevelSink(null);

    native.calls[0].resolve();
    await whenCommonsLogLevelSynced();

    expect(native.calls.map((c) => c.level)).toEqual([
      LogLevel.LOG_LEVEL_DEBUG,
    ]);
  });

  test('a synchronous sink is still called immediately for every change', () => {
    const sink = jest.fn();
    setCommonsLogLevelSink(sink);
    sink.mockClear();

    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_DEBUG);
    LoggingManager.shared.setMinLogLevel(LogLevel.LOG_LEVEL_ERROR);

    expect(sink.mock.calls.map(([level]) => level)).toEqual([
      LogLevel.LOG_LEVEL_DEBUG,
      LogLevel.LOG_LEVEL_ERROR,
    ]);
  });
});
