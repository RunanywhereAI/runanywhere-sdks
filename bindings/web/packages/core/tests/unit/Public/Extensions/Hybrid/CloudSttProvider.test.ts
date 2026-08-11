import { describe, expect, it } from 'vitest';
import {
  parseCloudSttProviderConfig,
} from '../../../../../src/Public/Extensions/Hybrid/CloudSttProvider';

describe('Cloud STT provider config boundary', () => {
  it('decodes the supported snake-case string fields', () => {
    expect(parseCloudSttProviderConfig(JSON.stringify({
      provider: 'custom',
      model: 'speech-v2',
      api_key: 'opaque-key',
      base_url: 'https://speech.example.test',
      language_code: 'en-US',
      ignored: 'not part of the typed request',
    }))).toEqual({
      provider: 'custom',
      model: 'speech-v2',
      api_key: 'opaque-key',
      base_url: 'https://speech.example.test',
      language_code: 'en-US',
    });
  });

  it.each([
    'not-json',
    'null',
    '[]',
    '42',
    '"string"',
  ])('rejects a non-object JSON payload: %s', (payload) => {
    expect(parseCloudSttProviderConfig(payload)).toEqual({});
  });

  it('drops fields with unexpected runtime types', () => {
    expect(parseCloudSttProviderConfig(JSON.stringify({
      provider: { nested: 'custom' },
      model: 7,
      api_key: ['secret'],
      base_url: null,
      language_code: false,
    }))).toEqual({});
  });

  it('retains valid fields while dropping invalid siblings', () => {
    expect(parseCloudSttProviderConfig(JSON.stringify({
      provider: 'custom',
      model: null,
      api_key: 'opaque-key',
    }))).toEqual({
      provider: 'custom',
      api_key: 'opaque-key',
    });
  });
});
