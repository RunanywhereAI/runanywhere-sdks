import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere_ai/core/models/proxy_settings.dart';

void main() {
  test('supported proxy scheme values exclude SOCKS5', () {
    expect(ProxyScheme.supportedValues, isNot(contains(ProxyScheme.socks5)));
    expect(ProxyScheme.supportedValues, contains(ProxyScheme.http));
    expect(ProxyScheme.supportedValues, contains(ProxyScheme.https));
  });

  test('copyWith can explicitly clear the saved port', () {
    const settings = ProxySettings(
      enabled: true,
      scheme: ProxyScheme.http,
      host: 'proxy.local',
      port: 8080,
    );

    final updated = settings.copyWith(clearPort: true);

    expect(updated.port, isNull);
    expect(updated.host, 'proxy.local');
    expect(updated.enabled, isTrue);
  });
}
