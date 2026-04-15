import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_secure_storage_windows_example/main.dart' as app;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

// For legacy behavior investigation, change bellow line.
// Note that "Special charactors handling" cases can cause app crash
// or file creation outside of app support directory.

const useMethodChannelOnly = false;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> cleanUpFiles() async {
    // Clean up current & legacy files.
    final directory = await getApplicationSupportDirectory();
    if (directory.existsSync()) {
      directory
          .listSync(recursive: false, followLinks: false)
          .whereType<File>()
          .where((f) =>
              path.basename(f.path) == 'flutter_secure_storage.dat' ||
              f.path.endsWith('.secure'))
          .forEach((f) => f.deleteSync());
    }

    // Check parent directory, too.
    if (directory.parent.existsSync()) {
      directory.parent
          .listSync(recursive: false, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.secure'))
          .forEach((f) => f.deleteSync());
    }
  }

  setUpAll(() async {
    await cleanUpFiles();
  });

  tearDown(() async {
    await cleanUpFiles();
  });

  app.MyAppState getState(
    WidgetTester tester, {
    required bool useBackwardCompatibility,
  }) {
    final state = tester.state<app.MyAppState>(find.byType(app.MyApp));

    state.useBackwardCompatibilityKey.currentState!.value =
        useBackwardCompatibility;
    state.useMethodChannelOnlyKey.currentState!.value = useMethodChannelOnly;

    return state;
  }

  Future<String> checkSuccess(
    WidgetTester tester,
    app.MyAppState state, {
    String? expectedDetail,
  }) async {
    printOnFailure('checkSuccess');
    await tester.pumpAndSettle();

    expect(
      state.resultSummaryFieldController.text,
      'SUCCESS',
      reason: 'Failed: ${state.resultDetailFieldController}',
    );

    if (expectedDetail != null) {
      expect(state.resultDetailFieldController.text, expectedDetail);
    }

    return state.resultDetailFieldController.text;
  }

  Future<void> doTestSuite(
    WidgetTester tester, {
    required String key1,
    String? key2,
    String? writingValue1,
    String? writingValue2,
    bool useBackwardCompatibility = true,
  }) async {
    app.main();
    await tester.pumpAndSettle();

    final state = getState(
      tester,
      useBackwardCompatibility: useBackwardCompatibility,
    );

    // write 1
    state.keyFieldController.text = key1;
    state.valueFieldController.text = writingValue1 ?? '';

    await tester.tap(find.text('Write'));
    final value1 = await checkSuccess(tester, state);

    late final String value2;
    if (key2 != null) {
      // write 2
      state.keyFieldController.text = key2;
      state.valueFieldController.text = writingValue2 ?? '';
      await tester.tap(find.text('Write'));
      value2 = await checkSuccess(tester, state);
    }

    state.valueFieldController.text = '';

    // read for write 1
    state.keyFieldController.text = key1;
    await tester.tap(find.text('Read'));
    await checkSuccess(tester, state, expectedDetail: value1);

    if (key2 != null) {
      // read for write 2
      state.keyFieldController.text = key2;
      await tester.tap(find.text('Read'));
      await checkSuccess(tester, state, expectedDetail: value2);
    }

    // containsKey for write 1
    state.keyFieldController.text = key1;
    await tester.tap(find.text('ContainsKey'));
    await checkSuccess(tester, state, expectedDetail: 'true');

    if (key2 != null) {
      // containsKey for write 2
      state.keyFieldController.text = key2;
      await tester.tap(find.text('ContainsKey'));
      await checkSuccess(tester, state, expectedDetail: 'true');
    }

    // readAll
    await tester.tap(find.text('ReadAll'));
    await checkSuccess(
      tester,
      state,
      // Standard map's order and toString() result should be stable
      // even if there are no guarantee nand backward compatibility.
      expectedDetail:
          (key2 != null ? {key1: value1, key2: value2} : {key1: value1})
              .toString(),
    );

    // delete for write 1
    state.keyFieldController.text = key1;
    await tester.tap(find.text('Delete'));
    await checkSuccess(tester, state);

    // read for delete
    await tester.tap(find.text('Read'));
    await checkSuccess(tester, state, expectedDetail: '<null>');

    // containsKey for delete
    await tester.tap(find.text('ContainsKey'));
    await checkSuccess(tester, state, expectedDetail: 'false');

    // readAll for delete
    await tester.tap(find.text('ReadAll'));
    await checkSuccess(
      tester, state,
      // Standard map's order and toString() result should be stable
      // even if there are no guarantee nand backward compatibility.
      expectedDetail: (key2 == null ? {} : {key2: value2}).toString(),
    );

    if (key2 == null) {
      // re-write for deleteAll
      state.keyFieldController.text = key1;
      state.valueFieldController.text = writingValue1 ?? '';
      await tester.tap(find.text('Write'));
      await checkSuccess(tester, state);
      // clear
      state.valueFieldController.text = '';
    }

    // deleteAll
    await tester.tap(find.text('DeleteAll'));
    await checkSuccess(tester, state);

    // read for delete 2
    state.keyFieldController.text = key2 ?? key1;
    await tester.tap(find.text('Read'));
    await checkSuccess(tester, state, expectedDetail: '<null>');

    // containsKey for delete 2
    await tester.tap(find.text('ContainsKey'));
    await checkSuccess(tester, state, expectedDetail: 'false');

    // readAll for delete
    await tester.tap(find.text('ReadAll'));
    await checkSuccess(
      tester, state,
      // Standard map's order and toString() result should be stable
      // even if there are no guarantee nand backward compatibility.
      expectedDetail: {}.toString(),
    );
  }

  group(
    'Basic test',
    () {
      testWidgets('Smoke test', (tester) async {
        await doTestSuite(tester, key1: 'key1', key2: 'key2');
      });
    },
    skip: kIsWeb || !Platform.isWindows
        ? 'These tests only work on Windows'
        : null,
  );

  group(
    'Backwards compatibilty cases',
    () {
      Future<void> checkMigration(
        WidgetTester tester,
        app.MyAppState state,
      ) async {
        printOnFailure('checkMigration');
        await tester.tap(find.text('LegacyReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {}.toString(),
        );
      }

      testWidgets('readAll - empty, empty', (tester) async {
        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {}.toString(),
        );
        await checkMigration(tester, state);
      });

      testWidgets('readAll - 1 entry, 1 entry, different keys', (tester) async {
        const key1 = 'key1';
        const key2 = 'key2';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key1;
        await tester.tap(find.text('Write'));
        final value1 = await checkSuccess(tester, state);

        state.keyFieldController.text = key2;
        await tester.tap(find.text('LegacyWrite'));
        final value2 = await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {key1: value1, key2: value2}.toString(),
        );
        await checkMigration(tester, state);
      });

      testWidgets('readAll - 1 entry, 1 entry, same keys', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        final value = await checkSuccess(tester, state);

        await tester.tap(find.text('LegacyWrite'));
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {key: value}.toString(),
        );
        await checkMigration(tester, state);
      });

      testWidgets('readAll - empty, 1entry', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('LegacyWrite'));
        final value = await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {key: value}.toString(),
        );
        await checkMigration(tester, state);
      });

      testWidgets('readAll - 1entry, empty', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        final value = await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {key: value}.toString(),
        );
        await checkMigration(tester, state);
      });

      testWidgets('readAll - 2 entries, 2 entries, same keys and diffrent keys',
          (tester) async {
        const key1 = 'key1';
        const key2 = 'key2';
        const key3 = 'key3';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key1;
        await tester.tap(find.text('Write'));
        final value1 = await checkSuccess(tester, state);

        state.keyFieldController.text = key2;
        await tester.tap(find.text('Write'));
        final value2 = await checkSuccess(tester, state);

        state.keyFieldController.text = key3;
        await tester.tap(find.text('LegacyWrite'));
        final value3 = await checkSuccess(tester, state);

        state.keyFieldController.text = key1;
        await tester.tap(find.text('LegacyWrite'));
        final value4 = await checkSuccess(tester, state);

        assert(value1 != value4);

        // Do test
        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {key1: value1, key2: value2, key3: value3}.toString(),
        );
        await checkMigration(tester, state);
      });

      testWidgets('read - exists, exists', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        final value = await checkSuccess(tester, state);

        await tester.tap(find.text('LegacyWrite'));
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: value);
        await checkMigration(tester, state);
      });

      testWidgets('read - does not exist, exists', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('LegacyWrite'));
        final value = await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: value);
        await checkMigration(tester, state);
      });

      testWidgets('read - exists, does not exist', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        final value = await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: value);
        await checkMigration(tester, state);
      });

      testWidgets('read - does not exist, does not exist', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Do test
        state.keyFieldController.text = key;
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: '<null>');
        await checkMigration(tester, state);
      });

      testWidgets('containsKey - exists, exists', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        await checkSuccess(tester, state);

        await tester.tap(find.text('LegacyWrite'));
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('ContainsKey'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: 'true');
        // containsKey does not execute auto-migration
      });

      testWidgets('containsKey - does not exist, exists', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('LegacyWrite'));
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('ContainsKey'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: 'true');
        // containsKey does not execute auto-migration
      });

      testWidgets('containsKey - exists, does not exist', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('ContainsKey'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: 'true');
        // containsKey does not execute auto-migration
      });

      testWidgets('containsKey - does not exist, does not exist',
          (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Do test
        state.keyFieldController.text = key;
        await tester.tap(find.text('ContainsKey'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: 'false');
        // containsKey does not execute auto-migration
      });

      testWidgets('write - new', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Do test
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();
        final writtenValue = await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        final readValue = await checkSuccess(tester, state);
        expect(readValue, writtenValue);
      });

      testWidgets('write - overwrite', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Do test
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();
        final writtenValue1 = await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();
        final writtenValue2 = await checkSuccess(tester, state);
        await checkMigration(tester, state);

        assert(writtenValue1 != writtenValue2);

        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        final readValue = await checkSuccess(tester, state);
        expect(readValue, writtenValue2);
      });

      testWidgets('write - legacy value exists', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('LegacyWrite'));
        await tester.pumpAndSettle();
        final legacyValue = await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();
        final writtenValue = await checkSuccess(tester, state);
        await checkMigration(tester, state);

        assert(writtenValue != legacyValue);

        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        final readValue = await checkSuccess(tester, state);
        expect(readValue, writtenValue);
      });

      testWidgets('delete - exists, exists', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state);
        await tester.tap(find.text('LegacyWrite'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('ContainsKey'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: 'false');
      });

      testWidgets('delete - exists, does not exist', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('ContainsKey'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: 'false');
      });

      testWidgets('delete - does not exist, exists', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('LegacyWrite'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('ContainsKey'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: 'false');
      });

      testWidgets('delete - does not exist, does not exist', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Do test
        state.keyFieldController.text = key;
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('ContainsKey'));
        await tester.pumpAndSettle();
        await checkSuccess(tester, state, expectedDetail: 'false');
      });

      testWidgets('deleteAll - empty, empty', (tester) async {
        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        await tester.tap(find.text('DeleteAll'));
        await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {}.toString(),
        );
      });

      testWidgets('deleteAll - 1 entry, 1 entry, different keys',
          (tester) async {
        const key1 = 'key1';
        const key2 = 'key2';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key1;
        await tester.tap(find.text('Write'));
        await checkSuccess(tester, state);

        state.keyFieldController.text = key2;
        await tester.tap(find.text('LegacyWrite'));
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('DeleteAll'));
        await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {}.toString(),
        );
      });

      testWidgets('deleteAll - 1 entry, 1 entry, same keys', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        await checkSuccess(tester, state);

        await tester.tap(find.text('LegacyWrite'));
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('DeleteAll'));
        await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {}.toString(),
        );
      });

      testWidgets('deleteAll - empty, 1entry', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('LegacyWrite'));
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('DeleteAll'));
        await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {}.toString(),
        );
      });

      testWidgets('deleteAll - 1entry, empty', (tester) async {
        const key = 'key';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key;
        await tester.tap(find.text('Write'));
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('DeleteAll'));
        await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {}.toString(),
        );
      });

      testWidgets(
          'deleteAll - 2 entries, 2 entries, same keys and diffrent keys',
          (tester) async {
        const key1 = 'key1';
        const key2 = 'key2';
        const key3 = 'key3';

        app.main();
        await tester.pumpAndSettle();

        final state = getState(
          tester,
          useBackwardCompatibility: true,
        );

        // Prepare
        state.keyFieldController.text = key1;
        await tester.tap(find.text('Write'));
        await checkSuccess(tester, state);

        state.keyFieldController.text = key2;
        await tester.tap(find.text('Write'));
        await checkSuccess(tester, state);

        state.keyFieldController.text = key3;
        await tester.tap(find.text('LegacyWrite'));
        await checkSuccess(tester, state);

        state.keyFieldController.text = key1;
        await tester.tap(find.text('LegacyWrite'));
        await checkSuccess(tester, state);

        // Do test
        await tester.tap(find.text('DeleteAll'));
        await checkSuccess(tester, state);
        await checkMigration(tester, state);

        await tester.tap(find.text('ReadAll'));
        await tester.pumpAndSettle();
        await checkSuccess(
          tester,
          state,
          // Standard map's order and toString() result should be stable
          // even if there are no guarantee nand backward compatibility.
          expectedDetail: {}.toString(),
        );
      });
    },
    skip: kIsWeb || !Platform.isWindows
        ? 'These tests only work on Windows'
        : null,
  );

  group(
    'Special charactors handling',
    () {
      testWidgets('URL', (tester) async {
        await doTestSuite(
          tester,
          key1: 'http://example.com',
          useBackwardCompatibility: false,
        );
      });

      testWidgets('Double dot', (tester) async {
        await doTestSuite(
          tester,
          key1: '/../a',
        );
      });

      testWidgets('Long key', (tester) async {
        await doTestSuite(
          tester,
          key1:
              String.fromCharCodes(Iterable.generate(256, (_) => 65 /* 'A' */)),
          useBackwardCompatibility: false,
        );
      });

      testWidgets('Empty key & value', (tester) async {
        await doTestSuite(
          tester,
          key1: '',
          writingValue1: '',
        );
      });

      for (final char in <String, int>{
        'ASCII whitespace': 0x20,
        'Nbsp': 0xA0,
        'Full-width space': 0x3000,
      }.entries) {
        testWidgets(
            'Space key & value - ${char.key} (U+${char.value.toRadixString(16).padLeft(4, '0')})',
            (tester) async {
          await doTestSuite(
            tester,
            key1: String.fromCharCode(char.value),
            writingValue1: String.fromCharCode(char.value),
          );
        });
      }

      for (final char in <String, int>{
        'Horizontal tab': 0x09,
      }.entries) {
        testWidgets(
            'Space key & value - ${char.key} (U+${char.value.toRadixString(16).padLeft(4, '0')})',
            (tester) async {
          await doTestSuite(
            tester,
            key1: String.fromCharCode(char.value),
            writingValue1: String.fromCharCode(char.value),
            useBackwardCompatibility: false,
          );
        });
      }

      for (final char in <String, String>{
        'Latin-1 (French)': 'cl\u00E9',
        'CJK (Japanese)': '\u30AD\u30FC',
        'Surrogate Pair (Emoji)': '\uD83D\uDD11',
      }.entries) {
        testWidgets('Non ASCII key & value - ${char.key}', (tester) async {
          await doTestSuite(
            tester,
            key1: char.value,
            writingValue1: char.value,
          );
        });
      }

      testWidgets('Only casing is differ', (tester) async {
        await doTestSuite(
          tester,
          key1: 'key',
          key2: 'KEY',
        );
      });
    },
    skip: kIsWeb || !Platform.isWindows
        ? 'These tests only work on Windows'
        : null,
  );
}
