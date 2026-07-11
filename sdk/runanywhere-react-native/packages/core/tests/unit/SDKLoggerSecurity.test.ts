import {
  LoggingManager,
  sanitizeLogMessage,
  type LogDestination,
  type LogEntry,
} from '../../src/Foundation/Logging/Services/LoggingManager';
import { SDKLogger } from '../../src/Foundation/Logging/Logger/SDKLogger';

describe('SDKLogger secret safety', () => {
  test('logError keeps arbitrary exception and context values out of destinations', () => {
    const entries: LogEntry[] = [];
    const consoleError = jest.spyOn(console, 'error').mockImplementation(() => undefined);
    const destination: LogDestination = {
      identifier: 'sdk-logger-security-test',
      isAvailable: true,
      write: (entry) => entries.push(entry),
      flush: () => undefined,
    };
    LoggingManager.shared.addDestination(destination);
    try {
      new SDKLogger('SecurityTest').logError(
        new Error('request failed with opaque-mobile-key-123'),
        'Authorization: opaque-mobile-key-123'
      );
    } finally {
      LoggingManager.shared.removeDestination(destination);
    }

    expect(entries).toHaveLength(1);
    expect(entries[0]?.message).toBe('SDK operation failed');
    expect(entries[0]?.metadata).toMatchObject({
      error_name: 'Error',
      context_provided: true,
    });
    expect(JSON.stringify(entries[0])).not.toContain('opaque-mobile-key-123');
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('opaque-mobile-key-123');
    consoleError.mockRestore();
  });

  test('redacts secret-bearing free-form message text while preserving context', () => {
    const raw =
      'Cloud provider failed at https://api.example.test/v1/transcribe' +
      '?api_key=opaque-query-key with Authorization: Bearer opaque-bearer-token, ' +
      'token=opaque-token password="opaque password" and sk-abcdefgh12345678';

    const sanitized = sanitizeLogMessage(raw);

    expect(sanitized).toContain(
      'Cloud provider failed at https://api.example.test/v1/transcribe'
    );
    expect(sanitized).toContain('api_key=[REDACTED]');
    expect(sanitized).toContain('Authorization: [REDACTED]');
    expect(sanitized).toContain('token=[REDACTED]');
    expect(sanitized).toContain('password=[REDACTED]');
    expect(sanitized).toContain('[REDACTED-KEY]');
    for (const secret of [
      'opaque-query-key',
      'opaque-bearer-token',
      'opaque-token',
      'opaque password',
      'sk-abcdefgh12345678',
    ]) {
      expect(sanitized).not.toContain(secret);
    }
  });

  test('sanitizes representative interpolated errors before every destination', () => {
    const entries: LogEntry[] = [];
    const secret = 'provider-secret-123';
    const consoleError = jest
      .spyOn(console, 'error')
      .mockImplementation(() => undefined);
    const destination: LogDestination = {
      identifier: 'sdk-logger-message-security-test',
      isAvailable: true,
      write: (entry) => entries.push(entry),
      flush: () => undefined,
    };
    LoggingManager.shared.addDestination(destination);
    try {
      const providerError = new Error(
        `request failed: password=${secret}; ` +
          `https://user:${secret}@api.example.test/v1`
      );
      new SDKLogger('CloudSTT').error(
        `cloud provider handler failed: ${providerError.message}`,
        { detail: `access_token=${secret}` }
      );
    } finally {
      LoggingManager.shared.removeDestination(destination);
      consoleError.mockRestore();
    }

    expect(entries).toHaveLength(1);
    expect(entries[0]?.message).toContain('cloud provider handler failed');
    expect(entries[0]?.message).not.toContain(secret);
    expect(entries[0]?.message).toContain('password=[REDACTED]');
    expect(entries[0]?.message).toContain(
      'https://[REDACTED]@api.example.test/v1'
    );
    expect(entries[0]?.metadata).toEqual({
      detail: 'access_token=[REDACTED]',
    });
  });
});
