import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere_ai/core/models/proxy_settings.dart';
import 'package:runanywhere_ai/core/services/example_http_service.dart';

void main() {
  test('builds an HTTP proxy directive for supported schemes', () {
    const settings = ProxySettings(
      enabled: true,
      scheme: ProxyScheme.http,
      host: 'proxy.local',
      port: 8080,
    );

    expect(
      ExampleHttpService.proxyDirectiveForTesting(settings),
      'PROXY proxy.local:8080',
    );
  });

  test('does not build a PAC PROXY directive for SOCKS5 schemes', () {
    const settings = ProxySettings(
      enabled: true,
      scheme: ProxyScheme.socks5,
      host: 'proxy.local',
      port: 1080,
    );

    expect(ExampleHttpService.proxyDirectiveForTesting(settings), isNull);
  });

  test('throws when an enabled proxy uses an unsupported scheme', () {
    const settings = ProxySettings(
      enabled: true,
      scheme: ProxyScheme.socks5,
      host: 'proxy.local',
      port: 1080,
      bypassLocal: false,
    );

    expect(
      () => ExampleHttpService.shared.findProxyDirectiveForTesting(
        settings,
        'example.com',
      ),
      throwsStateError,
    );
  });
}
