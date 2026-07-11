jest.mock('../../src/native', () => ({
  isNativeModuleAvailable: jest.fn(() => false),
  requireNativeModule: jest.fn(),
}));

import {
  decodeLoadedPluginJSON,
  decodeLoadedPluginsJSON,
  decodeRegisteredPluginNamesJSON,
} from '../../src/Public/Extensions/RunAnywhere+PluginLoader';
import { decodeCloudSttProviderConfigJSON } from '../../src/Public/Extensions/Hybrid/CloudSTT';
import { parseRAGMetadataJSON } from '../../src/Public/Extensions/RAG/RunAnywhere+RAG';

describe('external JSON boundaries', () => {
  describe('plugin loader native results', () => {
    test('decodes only the expected strongly typed shapes', () => {
      expect(decodeRegisteredPluginNamesJSON('["llamacpp","onnx"]')).toEqual([
        'llamacpp',
        'onnx',
      ]);
      expect(
        decodeLoadedPluginsJSON(
          '[{"name":"llamacpp","path":"/plugins/libllamacpp.so"}]'
        )
      ).toEqual([
        { name: 'llamacpp', path: '/plugins/libllamacpp.so' },
      ]);
      expect(
        decodeLoadedPluginJSON(
          '{"name":"onnx","path":"/plugins/libonnx.so"}'
        )
      ).toEqual({ name: 'onnx', path: '/plugins/libonnx.so' });
    });

    test.each([
      ['registered names', () => decodeRegisteredPluginNamesJSON('["onnx",42]')],
      ['loaded list root', () => decodeLoadedPluginsJSON('{"name":"onnx"}')],
      ['loaded list member', () => decodeLoadedPluginsJSON('[{"name":"onnx"}]')],
      ['loaded result', () => decodeLoadedPluginJSON('null')],
      ['malformed JSON', () => decodeLoadedPluginJSON('{')],
    ])('rejects an invalid %s response', (_label, decode) => {
      expect(decode).toThrow(/invalid JSON result/i);
    });
  });

  test('Cloud STT narrows object fields and rejects non-object roots', () => {
    expect(
      decodeCloudSttProviderConfigJSON(
        JSON.stringify({
          provider: 'sarvam',
          api_key: 'client-key',
          model: 'saarika:v2.5',
          base_url: 'https://api.example.test',
          language_code: 'en-IN',
          timeout_ms: 30_000,
          ignored: { nested: true },
        })
      )
    ).toEqual({
      provider: 'sarvam',
      apiKey: 'client-key',
      model: 'saarika:v2.5',
      baseUrl: 'https://api.example.test',
      languageCode: 'en-IN',
      timeoutMs: 30_000,
    });
    expect(decodeCloudSttProviderConfigJSON('null')).toEqual({});
    expect(decodeCloudSttProviderConfigJSON('[]')).toEqual({});
    expect(decodeCloudSttProviderConfigJSON('{')).toEqual({});
    expect(
      decodeCloudSttProviderConfigJSON(
        '{"provider":7,"api_key":false,"timeout_ms":"slow"}'
      )
    ).toEqual({});
  });

  test('RAG metadata accepts an object and rejects other JSON roots', () => {
    expect(
      parseRAGMetadataJSON(
        '{"source":"notes.txt","page":7,"verified":true,"empty":null}'
      )
    ).toEqual({
      source: 'notes.txt',
      page: '7',
      verified: 'true',
      empty: 'null',
    });
    expect(parseRAGMetadataJSON('null')).toEqual({});
    expect(parseRAGMetadataJSON('["not","metadata"]')).toEqual({});
    expect(parseRAGMetadataJSON('{')).toEqual({});
  });
});
