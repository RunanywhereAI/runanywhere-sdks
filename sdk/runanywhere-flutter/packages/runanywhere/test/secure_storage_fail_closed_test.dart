// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('secure-storage fail-closed contract', () {
    test('auth installs synchronous storage before native token restore', () {
      final source = File(
        'lib/native/dart_bridge_auth.dart',
      ).readAsStringSync();

      final storage = source.indexOf('DartBridgeSecureStorage.instance;');
      final init = source.indexOf('initAuth(storagePtr)');
      final load = source.indexOf('final loadResult = loadFn()');

      expect(storage, greaterThanOrEqualTo(0));
      expect(init, greaterThan(storage));
      expect(load, greaterThan(init));
      expect(source, contains('loadResult != RacResultCode.errorFileNotFound'));
      expect(source, contains('SDKException.throwIfError(loadResult)'));
    });

    test('auth clear and callbacks propagate native status', () {
      final auth = File('lib/native/dart_bridge_auth.dart').readAsStringSync();
      final state = File(
        'lib/native/dart_bridge_state.dart',
      ).readAsStringSync();

      for (final source in <String>[auth, state]) {
        expect(
          source,
          contains(
            'lookupFunction<Int32 Function(), int Function()>(\n'
            '      \'rac_auth_clear\'',
          ),
        );
        expect(source, contains('SDKException.throwIfError(clear'));
      }
      expect(auth, isNot(contains('_secureCache')));
      expect(auth, isNot(contains('unawaited(')));
      expect(auth, contains('DartBridgeSecureStorage.instance.storePointers'));
      expect(
        auth,
        contains('DartBridgeSecureStorage.instance.retrievePointers'),
      );
      expect(auth, contains('DartBridgeSecureStorage.instance.deletePointer'));
    });

    test('device identity has no non-durable fallback', () {
      final device = File(
        'lib/native/dart_bridge_device.dart',
      ).readAsStringSync();
      final publicApi = File('lib/public/runanywhere.dart').readAsStringSync();

      expect(device, isNot(contains('SharedPreferences fallback')));
      expect(device, isNot(contains('Last resort: generate UUID without')));
      expect(
        device,
        contains('nativeStorage.store(_keyDeviceUUID, candidate)'),
      );
      expect(
        device.indexOf('nativeStorage.store(_keyDeviceUUID, candidate)'),
        lessThan(device.indexOf('_cachedDeviceId = candidate')),
      );
      expect(publicApi, isNot(contains("'unknown-device'")));
      expect(publicApi, contains('throw SDKException.notInitialized'));
    });

    test('shutdown revalidates device and auth state on reinitialize', () {
      final bridge = File('lib/native/dart_bridge.dart').readAsStringSync();
      final device = File(
        'lib/native/dart_bridge_device.dart',
      ).readAsStringSync();
      final state = File(
        'lib/native/dart_bridge_state.dart',
      ).readAsStringSync();
      final publicApi = File('lib/public/runanywhere.dart').readAsStringSync();

      expect(bridge, contains('runCleanup(DartBridgeDevice.shutdown);'));
      expect(bridge, contains('runCleanup(DartBridgeFileManager.unregister);'));
      expect(bridge, contains('DartBridgeState.instance.shutdown('));
      expect(bridge, contains('runCleanup(DartBridgeAuth.reset);'));
      expect(bridge, contains('runCleanup(DartBridgeHTTP.instance.shutdown);'));
      expect(
        bridge,
        contains('runCleanup(HTTPClientAdapter.shared.shutdown);'),
      );
      expect(bridge, contains('runCleanup(DartBridgePlatform.unregister);'));
      expect(
        bridge.indexOf('DartBridgeState.instance.shutdown('),
        lessThan(bridge.indexOf('await DartBridgeTelemetry.shutdown();')),
      );
      expect(
        bridge.indexOf('DartBridgeState.instance.shutdown('),
        lessThan(bridge.indexOf('runCleanup(DartBridgeEvents.unregister);')),
      );
      expect(
        bridge.indexOf('DartBridgeState.instance.shutdown('),
        lessThan(
          bridge.indexOf('runCleanup(DartBridgeHTTP.instance.shutdown);'),
        ),
      );
      expect(
        bridge.indexOf('DartBridgeState.instance.shutdown('),
        lessThan(bridge.indexOf('runCleanup(DartBridgePlatform.unregister);')),
      );
      expect(state, contains("'rac_shutdown'"));
      expect(state, contains('if (requireNative) rethrow;'));
      expect(state, contains('return false;'));
      expect(state, contains('return true;'));
      expect(bridge, contains('Error.throwWithStackTrace'));
      expect(bridge, isNot(contains("'warning': result.warning")));
      expect(
        publicApi,
        isNot(contains('HTTP retry warning: \${proto.warning}')),
      );
      expect(publicApi, isNot(contains('HTTP retry proto failed: \$e')));
      expect(device, contains("'rac_device_manager_clear_callbacks'"));
      expect(device, contains('_cachedDeviceId = null;'));
      expect(device, contains('_callbacksRegistered = false;'));
      expect(publicApi, contains('await DartBridge.shutdown();'));
      expect(
        publicApi,
        contains('static Future<void>? _initializationFuture;'),
      );
      expect(publicApi, contains('static Future<void>? _resetFuture;'));
      expect(publicApi, contains('await initializationInProgress;'));
      expect(publicApi, contains('await servicesInProgress;'));
      expect(publicApi, contains('if (resetInProgress != null)'));
      expect(publicApi, contains('DartBridge.beginShutdown();'));
      final retiringInit = publicApi.indexOf(
        'final initializationInProgress = _initializationFuture;',
      );
      final disownRetiringInit = publicApi.indexOf(
        '_initializationFuture = null;',
        retiringInit,
      );
      final resetOperation = publicApi.indexOf(
        'final operation = () async {',
        retiringInit,
      );
      expect(retiringInit, greaterThanOrEqualTo(0));
      expect(disownRetiringInit, greaterThan(retiringInit));
      expect(disownRetiringInit, lessThan(resetOperation));
      expect(bridge, contains('_isInitialized && !_isShuttingDown'));
      expect(
        bridge,
        contains("throw StateError('SDK shutdown is in progress')"),
      );
      final http = File('lib/native/dart_bridge_http.dart').readAsStringSync();
      expect(http, contains('_apiKey = null;'));
      expect(http, contains('_baseURL = null;'));
      expect(http, contains('_isConfigured = false;'));
      final telemetry = File(
        'lib/native/dart_bridge_telemetry.dart',
      ).readAsStringSync();
      expect(telemetry, contains('_inFlightHttpRequests'));
      expect(telemetry, contains('await Future.wait'));
      expect(
        telemetry,
        contains('_setTelemetrySink(nullptr, requireSuccess: true);'),
      );
      expect(telemetry, contains('var managerDestroyed = false;'));
      expect(telemetry, contains('if (managerDestroyed)'));
      expect(telemetry, contains('managerDestroyed = true;'));
      final httpAdapter = File(
        'lib/adapters/http_client_adapter.dart',
      ).readAsStringSync();
      expect(httpAdapter, contains('class _HttpAdapterSnapshot'));
      expect(httpAdapter, contains('_requireCurrentConfiguration'));
      expect(httpAdapter, contains('_redirectsAllowedForHeaders'));
      expect(httpAdapter, contains("'authorization'"));
      expect(httpAdapter, contains("'apikey'"));
      final rawRequest = httpAdapter.substring(
        httpAdapter.indexOf('Future<HttpClientResponse> rawRequest'),
        httpAdapter.indexOf('Future<HttpClientResponse> send'),
      );
      expect(rawRequest, contains('_redirectsAllowedForHeaders('));
      expect(httpAdapter, isNot(contains('Token resolver failed: \$e')));
      expect(httpAdapter, isNot(contains("'\${spec.method} \${spec.url}'")));
      expect(state, isNot(contains('state shutdown: \$e')));
      expect(telemetry, isNot(contains('shutdown: \$e')));
      final plugin = File(
        'android/src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt',
      ).readAsStringSync();
      expect(plugin, isNot(contains('\${t.message}')));
    });

    test('shutdown retains borrowed owners until native quiescence', () {
      final bridge = File('lib/native/dart_bridge.dart').readAsStringSync();
      final device = File(
        'lib/native/dart_bridge_device.dart',
      ).readAsStringSync();
      final events = File(
        'lib/native/dart_bridge_events.dart',
      ).readAsStringSync();
      final nativeBindings = File(
        'lib/core/native/rac_native.dart',
      ).readAsStringSync();
      final platform = File(
        'lib/native/dart_bridge_platform.dart',
      ).readAsStringSync();

      expect(bridge, contains('var nativeShutdownComplete = false;'));
      expect(
        bridge,
        contains('nativeShutdownComplete = invokedNativeShutdown'),
      );
      expect(bridge, contains('if (nativeShutdownComplete)'));
      expect(bridge, contains('if (telemetryShutdownComplete)'));

      final clearCallbacks = device.indexOf('clearCallbacks();');
      final freeCallbacks = device.indexOf(
        'calloc.free(callbacks);',
        clearCallbacks,
      );
      expect(clearCallbacks, greaterThanOrEqualTo(0));
      expect(freeCallbacks, greaterThan(clearCallbacks));
      expect(
        device.substring(clearCallbacks, freeCallbacks),
        contains('rethrow;'),
      );

      expect(platform, contains('_loggerCallable?.close();'));
      expect(platform, contains('calloc.free(adapter);'));
      expect(platform, contains('_adapterPtr = null;'));
      expect(platform, contains('_servicesRegistered = false;'));

      expect(
        nativeBindings,
        contains('final RacSdkEventSubscribeDart rac_sdk_event_subscribe;'),
      );
      expect(
        nativeBindings,
        contains('final RacSdkEventUnsubscribeDart rac_sdk_event_unsubscribe;'),
      );
      final unsubscribe = events.indexOf(
        'bindings.rac_sdk_event_unsubscribe(subscriptionId);',
      );
      final quiesce = events.indexOf(
        'bindings.rac_sdk_event_quiesce();',
        unsubscribe,
      );
      final close = events.indexOf('callback.close();', quiesce);
      final release = events.indexOf('_eventCallback = null;', close);
      expect(unsubscribe, greaterThanOrEqualTo(0));
      expect(quiesce, greaterThan(unsubscribe));
      expect(close, greaterThan(quiesce));
      expect(release, greaterThan(close));
      expect(events.substring(unsubscribe, release), contains('return;'));
      expect(
        events.substring(unsubscribe, release),
        isNot(contains('finally')),
      );
    });

    test('credential redirects and changed error logs fail closed', () {
      final adapter = File(
        'lib/adapters/http_client_adapter.dart',
      ).readAsStringSync();
      final device = File(
        'lib/native/dart_bridge_device.dart',
      ).readAsStringSync();
      final http = File('lib/native/dart_bridge_http.dart').readAsStringSync();
      final auth = File('lib/native/dart_bridge_auth.dart').readAsStringSync();
      final platform = File(
        'lib/native/dart_bridge_platform.dart',
      ).readAsStringSync();
      final telemetry = File(
        'lib/native/dart_bridge_telemetry.dart',
      ).readAsStringSync();

      expect(adapter, contains("'proxy-authorization'"));
      expect(adapter, contains("'x-api-key'"));
      expect(adapter, contains("'cookie'"));
      expect(adapter, isNot(contains('_hostname(')));
      expect(device, contains('request.followRedirects = false;'));
      expect(http, contains('followRedirects: false,'));
      expect(http, contains('followRedirects: extraHeaders.isEmpty,'));

      for (final source in <String>[auth, device, http, platform, telemetry]) {
        expect(source, isNot(matches(RegExp(r'\$e(?:\W|$)'))));
        expect(source, isNot(contains('stack.toString()')));
      }
      expect(device, isNot(contains('Device registration POST to:')));
      expect(device, isNot(contains(r'$responseBody')));
      expect(http, isNot(contains("metadata: {'baseURL':")));
    });

    test('platform callbacks never acknowledge queued persistence', () {
      final platform = File(
        'lib/native/dart_bridge_platform.dart',
      ).readAsStringSync();
      final androidStore = File(
        'android/src/main/kotlin/ai/runanywhere/sdk/NoBackupCiphertextStore.kt',
      ).readAsStringSync();
      final appleBridge = File(
        'ios/runanywhere/Sources/runanywhere_native/SecureStorageBridge.mm',
      ).readAsStringSync();

      expect(platform, isNot(contains('_pendingSecureWrites')));
      expect(platform, isNot(contains('_secureStorageCache')));
      expect(platform, isNot(contains('FlutterSecureStorage')));
      expect(platform, contains('storePointers(key, value)'));
      expect(platform, contains('deletePointer(key)'));
      expect(androidStore, contains('atomicFile.finishWrite(output)'));
      expect(appleBridge, contains('SecItemUpdate'));
      expect(appleBridge, contains('SecItemAdd'));
      expect(appleBridge, contains('SecItemDelete'));
      expect(
        appleBridge,
        contains(
          'if (data.length == 0) {\n'
          '            return RAC_ERROR_SECURE_STORAGE_FAILED;',
        ),
      );
    });

    test(
      'Android JNI preserves standard UTF-8 bytes and auth buffer bounds',
      () {
        final nativeBridge = File(
          'android/src/main/cpp/NativePortHelpers.cpp',
        ).readAsStringSync();
        final dartBridge = File(
          'lib/native/dart_bridge_secure_storage.dart',
        ).readAsStringSync();

        expect(nativeBridge, contains('"set", "([B[B)Z"'));
        expect(nativeBridge, contains('"get", "([B)[B"'));
        expect(nativeBridge, contains('"delete", "([B)Z"'));
        expect(nativeBridge, isNot(contains('NewStringUTF')));
        expect(nativeBridge, isNot(contains('GetStringUTFChars')));
        expect(nativeBridge, contains('value_size + 1 > buffer_size'));
        expect(
          nativeBridge,
          contains('value_size == 0 ? RAC_ERROR_SECURE_STORAGE_FAILED'),
        );
        expect(dartBridge, contains('static const int maxValueBytes = 2048'));
      },
    );
  });
}
