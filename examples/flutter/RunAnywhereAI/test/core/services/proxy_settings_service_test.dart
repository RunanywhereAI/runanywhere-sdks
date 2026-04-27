import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere_ai/core/models/proxy_settings.dart';
import 'package:runanywhere_ai/core/services/proxy_settings_service.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};

  setUp(() {
    secureStore.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = (call.arguments as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final key = arguments['key'] as String?;

      switch (call.method) {
        case 'read':
          return key == null ? null : secureStore[key];
        case 'write':
          if (key != null) {
            secureStore[key] = arguments['value'] as String;
          }
          return null;
        case 'delete':
          if (key != null) {
            secureStore.remove(key);
          }
          return null;
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'containsKey':
          return key != null && secureStore.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(secureStore);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('loads legacy general proxy settings even when legacy credentials exist',
      () async {
    SharedPreferences.setMockInitialValues({
      PreferenceKeys.proxyEnabled: true,
      PreferenceKeys.proxyScheme: ProxyScheme.http.wireValue,
      PreferenceKeys.proxyHost: 'proxy.runanywhere.ai',
      PreferenceKeys.proxyPort: 8080,
      PreferenceKeys.proxyBypassLocal: false,
    });
    secureStore[_prefixed(KeychainKeys.proxyGeneralUsername)] = 'alice';
    secureStore[_prefixed(KeychainKeys.proxyGeneralPassword)] = 'secret';

    final settings = await ProxySettingsService.shared.load(ProxyScope.general);

    expect(settings.enabled, isTrue);
    expect(settings.scheme, ProxyScheme.http);
    expect(settings.host, 'proxy.runanywhere.ai');
    expect(settings.port, 8080);
    expect(settings.username, 'alice');
    expect(settings.password, 'secret');
    expect(settings.bypassLocal, isFalse);
  });

  test('clear removes legacy general proxy settings so they do not reappear',
      () async {
    SharedPreferences.setMockInitialValues({
      PreferenceKeys.proxyEnabled: true,
      PreferenceKeys.proxyHost: 'proxy.runanywhere.ai',
      PreferenceKeys.proxyPort: 8080,
    });
    secureStore[_prefixed(KeychainKeys.proxyGeneralUsername)] = 'alice';
    secureStore[_prefixed(KeychainKeys.proxyGeneralPassword)] = 'secret';

    await ProxySettingsService.shared.clear(ProxyScope.general);
    final settings = await ProxySettingsService.shared.load(ProxyScope.general);

    expect(settings.enabled, isFalse);
    expect(settings.host, isEmpty);
    expect(settings.port, isNull);
    expect(settings.username, isEmpty);
    expect(settings.password, isEmpty);
  });

  test('validation rejects SOCKS5 while it is temporarily disabled', () {
    const settings = ProxySettings(
      enabled: true,
      scheme: ProxyScheme.socks5,
      host: 'proxy.runanywhere.ai',
      port: 1080,
    );

    final result = ProxySettingsService.shared.validate(settings);

    expect(result.isValid, isFalse);
    expect(result.message, contains('SOCKS5'));
  });

  test('save trims whitespace-only credentials instead of persisting them',
      () async {
    const settings = ProxySettings(
      enabled: true,
      scheme: ProxyScheme.http,
      host: 'proxy.runanywhere.ai',
      port: 8080,
      username: '   ',
      password: '   ',
      bypassLocal: true,
    );

    final result = await ProxySettingsService.shared.save(
      ProxyScope.general,
      settings,
    );
    final reloaded = await ProxySettingsService.shared.load(ProxyScope.general);

    expect(result.isValid, isTrue);
    expect(reloaded.username, isEmpty);
    expect(reloaded.password, isEmpty);
    expect(
      secureStore.containsKey(_prefixed(KeychainKeys.proxyGeneralUsername)),
      isFalse,
    );
    expect(
      secureStore.containsKey(_prefixed(KeychainKeys.proxyGeneralPassword)),
      isFalse,
    );
  });

  test(
      'save keeps trimmed host consistent between cache and persisted settings',
      () async {
    const settings = ProxySettings(
      enabled: true,
      scheme: ProxyScheme.http,
      host: '  proxy.runanywhere.ai  ',
      port: 8080,
      bypassLocal: true,
    );

    final result = await ProxySettingsService.shared.save(
      ProxyScope.download,
      settings,
    );
    final cached = ProxySettingsService.shared.getCurrent(ProxyScope.download);
    final reloaded =
        await ProxySettingsService.shared.load(ProxyScope.download);

    expect(result.isValid, isTrue);
    expect(cached.host, 'proxy.runanywhere.ai');
    expect(reloaded.host, 'proxy.runanywhere.ai');
  });
}

String _prefixed(String key) => 'com.runanywhere.RunAnywhereAI_$key';
