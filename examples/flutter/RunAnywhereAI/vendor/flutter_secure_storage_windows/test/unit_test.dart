import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_windows/src/flutter_secure_storage_windows_ffi.dart'
    as ffi;
import 'package:flutter_secure_storage_windows/src/flutter_secure_storage_windows_ffi.dart';
import 'package:flutter_secure_storage_windows/src/flutter_secure_storage_windows_stub.dart'
    as stub;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FutureOr<void> cleanUpFiles() async {
    // Clean up current & legacy files.
    final directory = await getApplicationSupportDirectory();
    if (directory.existsSync()) {
      directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) =>
              path.basename(f.path) == encryptedJsonFileName ||
              f.path.endsWith('.secure'),)
          .forEach((f) => f.deleteSync());
    }
  }

  setUpAll(() async {
    await cleanUpFiles();
  });

  tearDown(() async {
    await cleanUpFiles();
  });

  group('Basic test cases', () {
    FlutterSecureStoragePlatform createTarget() {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (methodCall) async {
          assert(false, 'MethodChanel is called.');
          return null;
        },
      );
      return ffi.FlutterSecureStorageWindows();
    }

    Map<String, String> createOptions() =>
        {'useBackwardCompatibility': 'false'};

    test(
      'readAll - empty',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        final result = await target.readAll(options: options);
        expect(result, isEmpty);
      }),
    );

    test(
      'readAll - 1 entries',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key = 'KEY';
        const value = 'VALUE';
        await target.write(key: key, value: value, options: options);
        final result = await target.readAll(options: options);
        expect(result.length, 1);
        expect(result[key], value);
      }),
    );

    test(
      'readAll - 2 entries',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key1 = 'KEY1';
        const value1 = 'VALUE1';
        const key2 = 'KEY2';
        const value2 = 'VALUE2';
        await target.write(key: key1, value: value1, options: options);
        await target.write(key: key2, value: value2, options: options);
        final result = await target.readAll(options: options);
        expect(result.length, 2);
        expect(result[key1], value1);
        expect(result[key2], value2);
      }),
    );

    test(
      'read - exists',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key = 'KEY';
        const value = 'VALUE';
        await target.write(key: key, value: value, options: options);
        final result = await target.read(key: key, options: options);
        expect(result, isNotNull);
        expect(result, value);
      }),
    );

    test(
      'read - does not exist',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key = 'KEY';
        final result = await target.read(key: key, options: options);
        expect(result, isNull);
      }),
    );

    test(
      'containsKey - exists',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key = 'KEY';
        const value = 'VALUE';
        await target.write(key: key, value: value, options: options);
        expect(
          await target.containsKey(key: key, options: options),
          isTrue,
        );
      }),
    );

    test(
      'containsKey - does not exist',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key = 'KEY';
        expect(
          await target.containsKey(key: key, options: options),
          isFalse,
        );
      }),
    );

    test(
      'write - new',
      () => withFfi(() async {
        // Just checking file was created. Its contents should be tested via "read" test.

        final target = createTarget();
        final options = createOptions();
        const key = 'KEY';
        const value = 'VALUE';
        await target.write(key: key, value: value, options: options);

        final directory = await getApplicationSupportDirectory();
        final file = File(path.join(directory.path, encryptedJsonFileName));
        expect(file.existsSync(), isTrue);
        expect(file.statSync().size, greaterThan(0));
        // May be encrypted
        final content = file.readAsBytesSync();
        expect(
          content,
          isNot(
            Uint8List.fromList(
              utf8.encode('{"$key":"$value"}'),
            ),
          ),
        );
        try {
          final map = jsonDecode(utf8.decode(content));
          if (map is! Map || map[key] != value) {
            throw const FormatException('might be encrypted');
          }

          fail('might not be encrypted');
        } on FormatException catch (_) {
          // OK
        }
      }),
    );

    test(
      'write - overwrite',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key = 'KEY';
        const value1 = 'VALUE1';
        const value2 = 'VALUE2';
        await target.write(key: key, value: value1, options: options);
        await target.write(key: key, value: value2, options: options);

        final result = await target.read(key: key, options: options);
        expect(result, isNotNull);
        expect(result, value2);

        final results = await target.readAll(options: options);
        expect(results.length, 1);
        expect(results[key], value2);
      }),
    );

    test(
      'delete - exists',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key = 'KEY';
        const value = 'VALUE';
        await target.write(key: key, value: value, options: options);
        expect(
          await target.containsKey(key: key, options: options),
          isTrue,
        );

        await target.delete(key: key, options: options);
        expect(
          await target.containsKey(key: key, options: options),
          isFalse,
        );
      }),
    );

    test(
      'delete - does not exist',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key = 'KEY';
        expect(
          await target.containsKey(key: key, options: options),
          isFalse,
        );

        await target.delete(key: key, options: options);

        expect(
          await target.containsKey(key: key, options: options),
          isFalse,
        );
      }),
    );

    test(
      'deleteAll - empty',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        await target.deleteAll(options: options);
        expect(
          await target.readAll(options: options),
          isEmpty,
        );
      }),
    );

    test(
      'deleteAll - 1 entries',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key = 'KEY';
        const value = 'VALUE';
        await target.write(key: key, value: value, options: options);
        await target.deleteAll(options: options);
        expect(
          await target.readAll(options: options),
          isEmpty,
        );
      }),
    );

    test(
      'deleteAll - 2 entries',
      () => withFfi(() async {
        final target = createTarget();
        final options = createOptions();
        const key1 = 'KEY1';
        const value1 = 'VALUE1';
        const key2 = 'KEY2';
        const value2 = 'VALUE2';
        await target.write(key: key1, value: value1, options: options);
        await target.write(key: key2, value: value2, options: options);
        await target.deleteAll(options: options);
        expect(
          await target.readAll(options: options),
          isEmpty,
        );
      }),
    );
  });

  // These cases depend on 'Basic cases' are passed corrrectly.
  // Just test backward compatibility logics.
  group('Backwards compatibilty cases', () {
    FlutterSecureStoragePlatform createTarget(
      Future<Object?> Function(MethodCall) handler,
    ) {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        handler,
      );
      return ffi.createFlutterSecureStorageWindows(
        MethodChannelFlutterSecureStorage(),
        ffi.DpapiJsonFileMapStorage(),
      );
    }

    Map<String, String> createOptions() => {'useBackwardCompatibility': 'true'};

    test(
      'readAll - empty, empty',
      () => withFfi(() async {
        var readAllCalled = 0;
        var deleteAllCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'readAll':
              readAllCalled++;
              return <String, String>{};
            case 'deleteAll':
              deleteAllCalled++;
              return null;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();
        final result = await target.readAll(options: options);
        expect(result, isEmpty);
        expect(readAllCalled, 1);
        expect(deleteAllCalled, 0);
      }),
    );
    test(
      'readAll - 1 entry, 1 entry, different keys',
      () => withFfi(() async {
        const newKey = 'KEY1';
        const newValue = 'VALUE1';
        const oldKey = 'KEY2';
        const oldValue = 'VALUE2';

        var readAllCalled = 0;
        var deleteAllCalled = 0;
        var onInit = true;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'readAll':
              readAllCalled++;
              return deleteAllCalled > 0 ? {} : {oldKey: oldValue};
            case 'deleteAll':
              deleteAllCalled++;
              return null;
            case 'delete':
              if (onInit) {
                return null;
              }
          }
          fail('Unexpected method call: ${call.method}');
        });
        final options = createOptions();
        await target.write(key: newKey, value: newValue, options: options);
        onInit = false;
        final result1 = await target.readAll(options: options);
        expect(result1.length, 2);
        expect(result1[oldKey], oldValue);
        expect(result1[newKey], newValue);
        expect(readAllCalled, 1);
        expect(deleteAllCalled, 1);

        final result2 = await target.readAll(options: options);
        expect(result2.length, 2);
        expect(result2[oldKey], oldValue);
        expect(result2[newKey], newValue);
        expect(readAllCalled, 2);
        expect(deleteAllCalled, 1);
      }),
    );

    test(
      'readAll - 1 entry, 1 entry, same keys',
      () => withFfi(() async {
        const newKey = 'KEY';
        const newValue = 'VALUE1';
        const oldKey = newKey;
        const oldValue = 'VALUE2';

        var readAllCalled = 0;
        var deleteAllCalled = 0;
        var onInit = true;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'readAll':
              readAllCalled++;
              return deleteAllCalled > 0 ? {} : {oldKey: oldValue};
            case 'deleteAll':
              deleteAllCalled++;
              return null;
            case 'delete':
              if (onInit) {
                return null;
              }
          }
          fail('Unexpected method call: ${call.method}');
        });
        final options = createOptions();
        await target.write(key: newKey, value: newValue, options: options);
        onInit = false;
        final result1 = await target.readAll(options: options);
        expect(result1.length, 1);
        expect(result1[oldKey], newValue);
        expect(result1[newKey], newValue);
        expect(readAllCalled, 1);
        expect(deleteAllCalled, 1);

        final result2 = await target.readAll(options: options);
        expect(result2.length, 1);
        expect(result1[oldKey], newValue);
        expect(result1[newKey], newValue);
        expect(readAllCalled, 2);
        expect(deleteAllCalled, 1);
      }),
    );

    test(
      'readAll - empty, 1entry',
      () => withFfi(() async {
        const oldKey = 'KEY';
        const oldValue = 'VALUE2';

        var readCalled = 0;
        var readAllCalled = 0;
        var deleteAllCalled = 0;
        var deleteCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'read':
              readCalled++;
              return deleteAllCalled > 0
                  ? null
                  : (call.arguments as Map<String, dynamic>)['key'] == oldKey
                      ? oldValue
                      : null;
            case 'readAll':
              readAllCalled++;
              return deleteAllCalled > 0 ? {} : {oldKey: oldValue};
            case 'deleteAll':
              deleteAllCalled++;
              return null;
            case 'delete':
              deleteCalled++;
              return null;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });

        final options = createOptions();
        final result1 = await target.readAll(options: options);
        expect(result1.length, 1);
        expect(result1[oldKey], oldValue);
        expect(readCalled, 0);
        expect(readAllCalled, 1);
        expect(deleteAllCalled, 1);
        expect(deleteCalled, 0);

        final result2 = await target.readAll(options: options);
        expect(result2.length, 1);
        expect(result2[oldKey], oldValue);
        expect(readCalled, 0);
        expect(readAllCalled, 2);
        expect(deleteAllCalled, 1);
        expect(deleteCalled, 0);

        final result3 = await target.read(key: oldKey, options: options);
        expect(result3, oldValue);
        // auto-migrated
        expect(readCalled, 0);
        expect(readAllCalled, 2);
        expect(deleteAllCalled, 1);
        expect(deleteCalled, 1);
      }),
    );

    test(
      'readAll - 1entry, empty',
      () => withFfi(() async {
        const newKey = 'KEY';
        const newValue = 'VALUE1';

        var readAllCalled = 0;
        var deleteAllCalled = 0;
        var onInit = true;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'readAll':
              readAllCalled++;
              return <String, String>{};
            case 'deleteAll':
              deleteAllCalled++;
              return null;
            case 'delete':
              if (onInit) {
                return null;
              }
          }
          fail('Unexpected method call: ${call.method}');
        });
        final options = createOptions();
        await target.write(key: newKey, value: newValue, options: options);
        onInit = false;
        final result1 = await target.readAll(options: options);
        expect(result1.length, 1);
        expect(result1[newKey], newValue);
        expect(readAllCalled, 1);
        expect(deleteAllCalled, 0);

        final result2 = await target.readAll(options: options);
        expect(result2.length, 1);
        expect(result1[newKey], newValue);
        expect(readAllCalled, 2);
        expect(deleteAllCalled, 0);
      }),
    );

    test(
      'readAll - 2 entries, 2 entries, same keys and diffrent keys',
      () => withFfi(() async {
        const newKey1 = 'KEY1';
        const newValue1 = 'VALUE1';
        const newKey2 = 'KEY2';
        const newValue2 = 'VALUE2';
        const oldKey1 = 'KEY3';
        const oldValue1 = 'VALUE3';
        const oldKey2 = newKey1;
        const oldValue2 = 'VALUE4';

        var readAllCalled = 0;
        var deleteAllCalled = 0;
        var onInit = true;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'readAll':
              readAllCalled++;
              return deleteAllCalled > 0
                  ? {}
                  : {oldKey1: oldValue1, oldKey2: oldValue2};
            case 'deleteAll':
              deleteAllCalled++;
              return null;
            case 'delete':
              if (onInit) {
                return null;
              }
          }
          fail('Unexpected method call: ${call.method}');
        });
        final options = createOptions();
        await target.write(key: newKey1, value: newValue1, options: options);
        await target.write(key: newKey2, value: newValue2, options: options);
        onInit = false;
        final result1 = await target.readAll(options: options);
        expect(result1.length, 3);
        expect(result1[newKey1], newValue1);
        expect(result1[newKey2], newValue2);
        expect(result1[oldKey1], oldValue1);
        expect(result1[oldKey2], newValue1);
        expect(readAllCalled, 1);
        expect(deleteAllCalled, 1);

        final result2 = await target.readAll(options: options);
        expect(result2.length, 3);
        expect(result1[newKey1], newValue1);
        expect(result1[newKey2], newValue2);
        expect(result1[oldKey1], oldValue1);
        expect(result1[oldKey2], newValue1);
        expect(readAllCalled, 2);
        expect(deleteAllCalled, 1);
      }),
    );

    test(
      'read - exists, exists',
      () => withFfi(() async {
        const key = 'KEY';
        const newValue = 'VALUE1';
        const oldValue = 'VALUE2';

        var readCalled = 0;
        var deleteCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'read':
              readCalled++;
              return deleteCalled > 0 ? null : {key: oldValue};
            case 'delete':
              deleteCalled++;
              return null;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();
        await target.write(key: key, value: newValue, options: options);
        expect(deleteCalled, 1);
        final result1 = await target.read(key: key, options: options);
        expect(result1, newValue);
        expect(readCalled, 0);
        expect(deleteCalled, 2);

        final result2 = await target.read(key: key, options: options);
        expect(result2, newValue);
        expect(readCalled, 0);
        expect(deleteCalled, 3);
      }),
    );

    test(
      'read - does not exist, exists',
      () => withFfi(() async {
        const key = 'KEY';
        const value = 'VALUE';

        var readCalled = 0;
        var deleteCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'read':
              readCalled++;
              return deleteCalled > 0 ? null : value;
            case 'delete':
              deleteCalled++;
              return null;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();
        final result1 = await target.read(key: key, options: options);
        expect(result1, value);
        expect(readCalled, 1);
        expect(deleteCalled, 1);

        final result2 = await target.read(key: key, options: options);
        expect(result2, value);
        expect(readCalled, 1);
        expect(deleteCalled, 2);
      }),
    );

    test(
      'read - exists, does not exist',
      () => withFfi(() async {
        const key = 'KEY';
        const value = 'VALUE';

        var readCalled = 0;
        var deleteCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'read':
              readCalled++;
              return null;
            case 'delete':
              deleteCalled++;
              return null;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();
        await target.write(key: key, value: value, options: options);
        expect(deleteCalled, 1);

        final result1 = await target.read(key: key, options: options);
        expect(result1, value);
        expect(readCalled, 0);
        expect(deleteCalled, 2);

        final result2 = await target.read(key: key, options: options);
        expect(result2, value);
        expect(readCalled, 0);
        expect(deleteCalled, 3);
      }),
    );

    test(
      'read - does not exist, does not exist',
      () => withFfi(() async {
        const key = 'KEY';

        var readCalled = 0;
        var deleteCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'read':
              readCalled++;
              return null;
            case 'delete':
              deleteCalled++;
              return null;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();

        final result1 = await target.read(key: key, options: options);
        expect(result1, isNull);
        expect(readCalled, 1);
        expect(deleteCalled, 1);

        final result2 = await target.read(key: key, options: options);
        expect(result2, isNull);
        expect(readCalled, 2);
        expect(deleteCalled, 2);
      }),
    );

    test(
      'containsKey - exists, exists',
      () => withFfi(() async {
        const key = 'KEY';
        const newValue = 'VALUE1';

        var containsKeyCalled = 0;
        var deleteCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'containsKey':
              containsKeyCalled++;
              return deleteCalled > 0 && (call.arguments as Map<String, dynamic>)['key'] == key;
            case 'delete':
              deleteCalled++;
              return null;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();
        await target.write(key: key, value: newValue, options: options);
        expect(deleteCalled, 1);
        expect(
          await target.containsKey(key: key, options: options),
          isTrue,
        );
        expect(containsKeyCalled, 0);
        expect(deleteCalled, 1);

        expect(
          await target.containsKey(key: key, options: options),
          isTrue,
        );
        expect(containsKeyCalled, 0);
        expect(deleteCalled, 1);
      }),
    );

    test(
      'containsKey - does not exist, exists',
      () => withFfi(() async {
        const key = 'KEY';

        var containsKeyCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'containsKey':
              containsKeyCalled++;
              return (call.arguments as Map<String, dynamic>)['key'] == key;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();
        expect(
          await target.containsKey(key: key, options: options),
          isTrue,
        );
        expect(containsKeyCalled, 1);

        expect(
          await target.containsKey(key: key, options: options),
          isTrue,
        );
        expect(containsKeyCalled, 2);
      }),
    );

    test(
      'containsKey - exists, does not exist',
      () => withFfi(() async {
        const key = 'KEY';
        const newValue = 'VALUE1';

        var containsKeyCalled = 0;
        var onInit = true;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'containsKey':
              containsKeyCalled++;
              return false;
            case 'delete':
              if (onInit) {
                return null;
              }
              break;
          }
          fail('Unexpected method call: ${call.method}');
        });
        final options = createOptions();
        await target.write(key: key, value: newValue, options: options);
        onInit = false;
        expect(
          await target.containsKey(key: key, options: options),
          isTrue,
        );
        expect(containsKeyCalled, 0);

        expect(
          await target.containsKey(key: key, options: options),
          isTrue,
        );
        expect(containsKeyCalled, 0);
      }),
    );

    test(
      'containsKey - does not exist, does not exist',
      () => withFfi(() async {
        const key = 'KEY';

        var containsKeyCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'containsKey':
              containsKeyCalled++;
              return false;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();
        expect(
          await target.containsKey(key: key, options: options),
          isFalse,
        );
        expect(containsKeyCalled, 1);

        expect(
          await target.containsKey(key: key, options: options),
          isFalse,
        );
        expect(containsKeyCalled, 2);
      }),
    );

    test(
      'write - new',
      () async {
        const key = 'KEY';
        const value = 'VALUE';

        var deleteCalled = 0;
        final target = createTarget((call) async {
          if (call.method == 'delete') {
            deleteCalled++;
            return null;
          }

          fail('Unexpected method call: ${call.method}');
        });
        final options = createOptions();
        await target.write(key: key, value: value, options: options);
        expect(deleteCalled, 1);

        final result = await target.read(key: key, options: options);
        expect(result, value);
        expect(deleteCalled, 2);
      },
    );

    test(
      'write - overwrite',
      () async {
        const key = 'KEY';
        const value1 = 'VALUE1';
        const value2 = 'VALUE2';

        var deleteCalled = 0;
        final target = createTarget((call) async {
          if (call.method == 'delete') {
            deleteCalled++;
            return null;
          }

          fail('Unexpected method call: ${call.method}');
        });
        final options = createOptions();
        await target.write(key: key, value: value1, options: options);
        expect(deleteCalled, 1);
        await target.write(key: key, value: value2, options: options);
        expect(deleteCalled, 2);

        final result = await target.read(key: key, options: options);
        expect(result, value2);
        expect(deleteCalled, 3);
      },
    );

    test(
      'delete - exists, any',
      () => withFfi(() async {
        const key = 'KEY';
        const newValue = 'VALUE1';

        var deleteCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'delete':
              deleteCalled++;
              return null;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();
        await target.write(key: key, value: newValue, options: options);
        expect(deleteCalled, 1);
        await target.delete(key: key, options: options);
        expect(deleteCalled, 2);
      }),
    );

    test(
      'delete - does not exist, any',
      () => withFfi(() async {
        var deleteCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'delete':
              deleteCalled++;
              return null;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();
        await target.delete(key: 'KEY', options: options);
        expect(deleteCalled, 1);
      }),
    );

    test(
      'deleteAll - empty, any',
      () => withFfi(() async {
        var deleteAllCalled = 0;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'deleteAll':
              deleteAllCalled++;
              return null;
            default:
              fail('Unexpected method call: ${call.method}');
          }
        });
        final options = createOptions();
        await target.deleteAll(options: options);
        expect(deleteAllCalled, 1);
      }),
    );
    test(
      'deleteAll - 1 entry, any',
      () => withFfi(() async {
        const key = 'KEY';
        const newValue = 'VALUE1';

        var deleteAllCalled = 0;
        var onInit = true;
        final target = createTarget((call) async {
          switch (call.method) {
            case 'deleteAll':
              deleteAllCalled++;
              return null;
            case 'delete':
              if (onInit) {
                return null;
              }
              break;
          }
          fail('Unexpected method call: ${call.method}');
        });
        final options = createOptions();
        await target.write(key: key, value: newValue, options: options);
        onInit = false;
        await target.deleteAll(options: options);
        expect(deleteAllCalled, 1);
      }),
    );
  });

  group('Stub does not work at all', () {
    test(
      'constructor',
      () async {
        expect(
          () => stub.FlutterSecureStorageWindows(),
          throwsAssertionError,
        );
      },
    );
  });

  group('Special charactors handling', () {
    FlutterSecureStoragePlatform createTarget() {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (methodCall) async {
          switch (methodCall.method) {
            case 'read':
              return null;
            case 'readAll':
              return <String, String>{};
            case 'containsKey':
              return false;
            case 'write':
              fail('write on MethodChanel causes error for special chars.');
            case 'delete':
            case 'deleteAll':
              return null;
            default:
              fail('Unexpected method call: $methodCall');
          }
        },
      );
      return ffi.FlutterSecureStorageWindows();
    }

    Map<String, String> createOptions() => {'useBackwardCompatibility': 'true'};

    Future<void> testSpecialCharactor(
      String key, {
      String? value,
    }) async {
      final target = createTarget();
      final options = createOptions();

      final realValue = value ?? DateTime.now().toIso8601String();

      await target.write(key: key, value: realValue, options: options);

      expect(await target.containsKey(key: key, options: options), isTrue);
      expect(await target.read(key: key, options: options), realValue);
      expect(await target.readAll(options: options), {key: realValue});
      await target.delete(key: key, options: options);
      expect(await target.containsKey(key: key, options: options), isFalse);
      expect(await target.read(key: key, options: options), isNull);
      expect(await target.readAll(options: options), isEmpty);

      await target.write(key: '$key#1', value: realValue, options: options);
      await target.write(key: '$key#2', value: realValue, options: options);

      expect(
        await target.containsKey(key: '$key#1', options: options),
        isTrue,
      );
      expect(
        await target.containsKey(key: '$key#2', options: options),
        isTrue,
      );
      await target.deleteAll(options: options);

      expect(
        await target.containsKey(key: '$key#1', options: options),
        isFalse,
      );
      expect(
        await target.containsKey(key: '$key#2', options: options),
        isFalse,
      );
    }

    test('URL', () => testSpecialCharactor('http://example.com'));
    test(
      'Long key',
      () => testSpecialCharactor(
        String.fromCharCodes(Iterable.generate(256, (_) => 65 /* 'A' */)),
      ),
    );
    test(
      'Empty key & value',
      () => testSpecialCharactor('', value: ''),
    );

    test('Only casing is differ', () async {
      final target = createTarget();
      final options = createOptions();
      const key1 = 'KEY';
      const key2 = 'key';
      const value1 = 'Value1';
      const value2 = 'Value2';

      await target.write(key: key1, value: value1, options: options);
      await target.write(key: key2, value: value2, options: options);
      final results = await target.readAll(options: options);
      expect(results.length, 2);
      expect(results[key1], value1);
      expect(results[key2], value2);

      expect(await target.read(key: key1, options: options), value1);
      expect(await target.read(key: key2, options: options), value2);
      expect(await target.containsKey(key: key1, options: options), isTrue);
      expect(await target.containsKey(key: key2, options: options), isTrue);

      await target.delete(key: key1, options: options);
      expect(await target.read(key: key1, options: options), isNull);
      expect(await target.read(key: key2, options: options), value2);
      expect(await target.containsKey(key: key1, options: options), isFalse);
      expect(await target.containsKey(key: key2, options: options), isTrue);

      await target.write(key: key2, value: value2, options: options);
      await target.deleteAll(options: options);
      expect(await target.read(key: key1, options: options), isNull);
      expect(await target.read(key: key2, options: options), isNull);
      expect(await target.containsKey(key: key1, options: options), isFalse);
      expect(await target.containsKey(key: key2, options: options), isFalse);
    });
  });
}

bool canTest() {
  if (!Platform.isWindows) {
    markTestSkipped('This test must be run on Windows.');
    return false;
  }

  return true;
}

FutureOr<void> withFfi(
  FutureOr<void> Function() test,
) async {
  if (!canTest()) {
    return;
  }

  await test();
}
