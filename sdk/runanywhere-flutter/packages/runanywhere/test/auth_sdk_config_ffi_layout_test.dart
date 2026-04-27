import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart' as auth_bridge;
import 'package:runanywhere/native/dart_bridge_environment.dart'
    as environment_bridge;

void main() {
  test('auth SDK config struct matches native SDK config layout', () {
    expect(
      sizeOf<auth_bridge.RacSdkConfigStruct>(),
      sizeOf<environment_bridge.RacSdkConfigStruct>(),
    );
  });
}
