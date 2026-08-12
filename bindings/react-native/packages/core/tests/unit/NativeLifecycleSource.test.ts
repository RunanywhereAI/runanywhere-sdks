import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function readBridgeSource(file: string): string {
  return readFileSync(resolve(__dirname, '../../cpp/bridges', file), 'utf8');
}

function readCppSource(file: string): string {
  return readFileSync(resolve(__dirname, '../../cpp', file), 'utf8');
}

function functionBody(source: string, signature: string, nextSignature: string): string {
  const start = source.indexOf(signature);
  const end = source.indexOf(nextSignature, start + signature.length);
  expect(start).toBeGreaterThanOrEqual(0);
  expect(end).toBeGreaterThan(start);
  return source.slice(start, end);
}

describe('native lifecycle source invariants', () => {
  test('partial-init rollback and shutdown use one complete teardown path', () => {
    const source = readBridgeSource('InitBridge.cpp');
    const commonsShutdown = functionBody(
      source,
      'void InitBridge::shutdownCommons()',
      'void InitBridge::releasePlatformState()'
    );
    expect(commonsShutdown).toContain(
      'DeviceBridge::shared().unregisterCallbacks();'
    );
    expect(commonsShutdown).toContain('rac_shutdown();');
    expect(commonsShutdown).not.toContain('HTTPBridge::shared().reset();');

    const platformRelease = functionBody(
      source,
      'void InitBridge::releasePlatformState()',
      'void InitBridge::resetNativeState()'
    );
    expect(platformRelease).toContain('HTTPBridge::shared().reset();');
    expect(platformRelease).not.toContain('rac_shutdown();');

    for (const sensitiveState of [
      'wipeAndClear(apiKey_);',
      'wipeAndClear(baseURL_);',
      'wipeAndClear(deviceId_);',
      'wipeAndClear(phase2RequestBytes_);',
    ]) {
      expect(platformRelease).toContain(sensitiveState);
    }
    expect(platformRelease).toContain('adapterRegistered_ = false;');

    const rollback = functionBody(
      source,
      'void InitBridge::resetNativeState()',
      'bool InitBridge::secureSet('
    );
    expect(rollback.indexOf('shutdownCommons();')).toBeLessThan(
      rollback.indexOf('releasePlatformState();')
    );
    expect(source.match(/rac_shutdown\(\);/g)?.length ?? 0).toBe(1);
    expect(source).not.toContain('rac_auth_reset();');
    expect(source).not.toContain('rac_state_shutdown();');
    expect(source).not.toContain('rac_sdk_reset();');
    expect(source.match(/resetNativeState\(\);/g)?.length ?? 0).toBe(4);
    expect(source).not.toContain('static std::string s_deviceId');
  });

  test('normal destroy flushes terminal telemetry before local release', () => {
    const source = readCppSource('HybridRunAnywhereCore.cpp');
    const destroy = functionBody(
      source,
      'std::shared_ptr<Promise<void>> HybridRunAnywhereCore::destroy()',
      'std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isInitialized()'
    );
    const orderedCalls = [
      'resetAllGlobalComponentHandles();',
      'InitBridge::shared().shutdownCommons();',
      'TelemetryBridge::shared().shutdown();',
      'InitBridge::shared().releasePlatformState();',
    ];
    let previous = -1;
    for (const call of orderedCalls) {
      const current = destroy.indexOf(call);
      expect(current).toBeGreaterThan(previous);
      previous = current;
    }
    expect(destroy).not.toContain('InitBridge::shared().shutdown();');

    const retry = functionBody(
      source,
      'HybridRunAnywhereCore::retryHTTPSetupProto()',
      '// Canonical rac_result_t -> serialized SDKError mapping.'
    );
    expect(retry).toContain(
      'std::lock_guard<std::mutex> lock(initMutex_);'
    );
  });

  test('telemetry callback uses an immutable manager snapshot outside the state lock', () => {
    const source = readBridgeSource('TelemetryBridge.cpp');
    const header = readBridgeSource('TelemetryBridge.hpp');
    const flush = functionBody(
      source,
      'void TelemetryBridge::flush()',
      'void TelemetryBridge::registerEventsCallback()'
    );
    expect(flush.indexOf('++activeOperations_;')).toBeLessThan(
      flush.indexOf('rac_telemetry_manager_flush(manager);')
    );
    expect(flush.indexOf('rac_telemetry_manager_flush(manager);')).toBeLessThan(
      flush.indexOf('--activeOperations_;')
    );

    const callback = source.slice(
      source.lastIndexOf('static void telemetryHttpCallback(')
    );
    expect(callback).toMatch(
      /static_cast<TelemetryCallbackContext\s*\*>\(userData\)/
    );
    expect(callback).toContain('context->manager');
    expect(callback).toContain('context->environment');
    expect(callback).not.toContain('bridge->getHandle()');
    expect(callback).not.toContain('bridge->getEnvironment()');
    expect(callback).not.toContain('fullURL.c_str()');
    expect(callback).not.toContain('errorMessage.c_str()');
    expect(callback).toContain('"Telemetry HTTP request failed"');
    expect(header).not.toContain('getHandle() const');
    expect(header).not.toContain('getEnvironment() const');
    expect(source).not.toContain('TelemetryBridge::~TelemetryBridge()');
  });

  test('device and HTTP bridge state can be safely rebuilt after reset', () => {
    const device = readBridgeSource('DeviceBridge.cpp');
    const unregister = functionBody(
      device,
      'void DeviceBridge::unregisterCallbacks()',
      'bool DeviceBridge::isRegistered() const'
    );
    expect(unregister).toContain('rac_device_manager_clear_callbacks();');
    expect(unregister).toContain('callbacksRegistered_ = false;');
    expect(unregister).toContain('g_deviceCallbacks = nullptr;');
    expect(unregister).toContain('g_deviceCallbackStrings.clear();');

    const getDeviceId = functionBody(
      device,
      'std::string DeviceBridge::getDeviceId() const',
      'DeviceInfo DeviceBridge::getDeviceInfo() const'
    );
    expect(getDeviceId).toContain(
      'std::lock_guard<std::mutex> lock(platformCallbacksMutex_);'
    );
    expect(getDeviceId).toContain('platformCallbacks_.getDeviceId()');

    const http = readBridgeSource('HTTPBridge.cpp');
    const reset = functionBody(
      http,
      'void HTTPBridge::reset()',
      'std::string HTTPBridge::buildURL('
    );
    expect(reset).toContain('std::lock_guard<std::mutex> lock(mutex_);');
    expect(reset).toContain('wipeAndClear(apiKey_);');
    expect(reset).toContain('wipeAndClear(*authToken_);');
    expect(reset).toContain('authToken_.reset();');
    expect(reset).toContain('baseURL_.clear();');
    expect(reset).toContain('configured_ = false;');
  });

  test('SDK event subscription insertion failure retires native ownership safely', () => {
    const source = readCppSource('HybridRunAnywhereCore+Events.cpp');
    const subscribe = functionBody(
      source,
      'HybridRunAnywhereCore::subscribeSDKEventsProto(',
      'HybridRunAnywhereCore::unsubscribeSDKEventsProto('
    );
    const insertion = subscribe.indexOf(
      '.emplace(subscriptionId, registration)'
    );
    const rollback = subscribe.indexOf('if (insertionError != nullptr)');
    const deactivate = subscribe.indexOf(
      'registration->active.store(false, std::memory_order_release);',
      rollback
    );
    const unsubscribe = subscribe.indexOf(
      'rac_sdk_event_unsubscribe(subscriptionId);',
      deactivate
    );
    const quiesce = subscribe.indexOf('rac_sdk_event_quiesce();', unsubscribe);
    const release = subscribe.indexOf('delete registration;', quiesce);
    const rethrow = subscribe.indexOf(
      'std::rethrow_exception(insertionError);',
      release
    );

    expect(insertion).toBeGreaterThanOrEqual(0);
    expect(rollback).toBeGreaterThan(insertion);
    expect(deactivate).toBeGreaterThan(rollback);
    expect(unsubscribe).toBeGreaterThan(deactivate);
    expect(quiesce).toBeGreaterThan(unsubscribe);
    expect(release).toBeGreaterThan(quiesce);
    expect(rethrow).toBeGreaterThan(release);
    expect(subscribe.slice(rollback, rethrow)).not.toContain(
      'std::lock_guard<std::mutex> lock(g_sdkEventProtoMutex);'
    );
  });

  test('control-plane HTTP never redirects or logs private request details', () => {
    const common = readCppSource('HybridRunAnywhereCore+Common.hpp');
    const core = readCppSource('HybridRunAnywhereCore.cpp');
    const init = readBridgeSource('InitBridge.cpp');
    const device = readBridgeSource('DeviceBridge.cpp');
    const http = readBridgeSource('HTTPBridge.cpp');

    expect(init).toContain('req.follow_redirects = RAC_FALSE;');
    expect(common).toContain(
      'req.follow_redirects = hasSensitiveHeaders ? RAC_FALSE : RAC_TRUE;'
    );
    for (const sensitiveHeader of [
      'authorization',
      'proxy-authorization',
      'apikey',
      'x-api-key',
      'x-auth-token',
      'x-access-token',
      'cookie',
    ]) {
      expect(common).toContain(`normalized == "${sensitiveHeader}"`);
    }

    expect(init).not.toContain(
      '"HTTP " + std::to_string(statusCode) + ": " + responseBody'
    );
    expect(init).not.toContain(
      'LOGE("%s failed: %s", symbolName, out.error_message)'
    );
    expect(init).not.toContain(
      'LOGE("%s returned proto error: %s", symbolName, out.error_message)'
    );
    expect(init).not.toContain(
      'LOGE("rac_sdk_retry_http_proto failed: %s", out.error_message)'
    );

    for (const privateLog of [
      'getModelBaseDirectory (Android): %s',
      'Model paths base directory set to: %s',
      'httpPostSync via rac_http_client_* to: %s',
    ]) {
      expect(init).not.toContain(privateLog);
    }
    expect(core).not.toContain('Model assignment HTTP GET: %s');
    expect(core).not.toContain('strdup(e.what())');
    expect(device).not.toContain('Making HTTP POST to: %s');
    expect(http).not.toContain('baseURL=%s');
  });
});
