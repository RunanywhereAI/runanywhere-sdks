import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

void main() {
  test('maps SDK environments to native auth environment values', () {
    expect(
      DartBridgeAuth.environmentToNativeValueForTesting(
        SDKEnvironment.development,
      ),
      0,
    );
    expect(
      DartBridgeAuth.environmentToNativeValueForTesting(
        SDKEnvironment.staging,
      ),
      1,
    );
    expect(
      DartBridgeAuth.environmentToNativeValueForTesting(
        SDKEnvironment.production,
      ),
      2,
    );
  });

  test('builds redacted auth log metadata without request or token bodies', () {
    final url = Uri.parse('https://api.runanywhere.ai/authenticate');
    const requestJson = '{"api_key":"secret-key","device_id":"device-123"}';
    final response = http.Response(
      '{"access_token":"secret-token","refresh_token":"another-secret"}',
      200,
    );

    final requestMetadata = DartBridgeAuth.authRequestLogMetadataForTesting(
      url,
      requestJson,
    );
    final responseMetadata = DartBridgeAuth.authResponseLogMetadataForTesting(
      url,
      response,
    );

    expect(requestMetadata, {
      'host': 'api.runanywhere.ai',
      'path': '/authenticate',
      'bodyLength': requestJson.length,
    });
    expect(responseMetadata, {
      'host': 'api.runanywhere.ai',
      'path': '/authenticate',
      'bodyLength': response.body.length,
      'statusCode': 200,
    });
    expect(requestMetadata.values, isNot(contains(requestJson)));
    expect(responseMetadata.values, isNot(contains(response.body)));
  });

  test('copies UTF-8 bytes into secure storage callback buffer', () {
    final buffer = calloc<Uint8>(16).cast<Utf8>();

    try {
      final written = copyUtf8StringToBufferForTesting('你好', buffer, 16);
      final bytes = buffer.cast<Uint8>().asTypedList(written);

      expect(written, utf8.encode('你好').length);
      expect(bytes, utf8.encode('你好'));
      expect(buffer.cast<Uint8>()[written], 0);
    } finally {
      calloc.free(buffer);
    }
  });

  test('fails when the secure storage callback buffer is too small', () {
    final buffer = calloc<Uint8>(4).cast<Utf8>();

    try {
      expect(copyUtf8StringToBufferForTesting('你好', buffer, 4), -1);
    } finally {
      calloc.free(buffer);
    }
  });
}
