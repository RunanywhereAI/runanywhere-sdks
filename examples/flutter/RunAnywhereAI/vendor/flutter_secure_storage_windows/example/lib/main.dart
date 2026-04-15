import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_windows/flutter_secure_storage_windows.dart';

// testing application.
void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  final TextEditingController keyFieldController = TextEditingController();
  final TextEditingController valueFieldController = TextEditingController();
  final TextEditingController resultSummaryFieldController =
      TextEditingController();
  final TextEditingController resultDetailFieldController =
      TextEditingController();
  final GlobalKey<LabeledCheckboxState> useMethodChannelOnlyKey = GlobalKey();
  final GlobalKey<LabeledCheckboxState> useBackwardCompatibilityKey =
      GlobalKey();

  Future<TestResult>? _future;

  FlutterSecureStoragePlatform _flutterSecureStorageWindowsPlugin =
      FlutterSecureStorageWindows();
  final Map<String, String> _options = {'useBackwardCompatibility': 'false'};

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            TextField(
              controller: keyFieldController,
              decoration: const InputDecoration(label: Text('Key')),
            ),
            TextField(
              controller: valueFieldController,
              decoration: const InputDecoration(label: Text('Value')),
            ),
            LabeledCheckbox(
              key: useMethodChannelOnlyKey,
              initialValue: false,
              label: 'UseMethodChannelOnly',
              onChanged: (useMethodChannelOnly) {
                setState(() {
                  _flutterSecureStorageWindowsPlugin = useMethodChannelOnly
                      ? MethodChannelFlutterSecureStorage()
                      : FlutterSecureStorageWindows();
                });
              },
            ),
            LabeledCheckbox(
              key: useBackwardCompatibilityKey,
              initialValue: false,
              label: 'UseBackwardCompatibility',
              onChanged: (useBackwardCompatibility) {
                setState(() {
                  _options['useBackwardCompatibility'] =
                      useBackwardCompatibility.toString();
                });
              },
            ),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ElevatedButton(
                    onPressed: doRead,
                    child: const Text('Read'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ElevatedButton(
                    onPressed: doReadAll,
                    child: const Text('ReadAll'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ElevatedButton(
                    onPressed: doContainsKey,
                    child: const Text('ContainsKey'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ElevatedButton(
                    onPressed: doWrite,
                    child: const Text('Write'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ElevatedButton(
                    onPressed: doDelete,
                    child: const Text('Delete'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ElevatedButton(
                    onPressed: doDeleteAll,
                    child: const Text('DeleteAll'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ElevatedButton(
                    onPressed: doLegacyWrite,
                    child: const Text('LegacyWrite'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ElevatedButton(
                    onPressed: doLegacyReadAll,
                    child: const Text('LegacyReadAll'),
                  ),
                ),
              ],
            ),
            if (_future != null)
              FutureBuilder<TestResult>(
                builder: (context, snapshot) {
                  if (!snapshot.hasData && !snapshot.hasError) {
                    return const CircularProgressIndicator();
                  }

                  resultSummaryFieldController.text =
                      (snapshot.data?.success ?? false) ? 'SUCCESS' : 'FAIL';

                  return TextField(
                    controller: resultSummaryFieldController,
                    decoration: const InputDecoration(label: Text('Result')),
                  );
                },
                future: _future,
              ),

            if (_future != null)
              FutureBuilder<TestResult>(
                builder: (context, snapshot) {
                  if (!snapshot.hasData && !snapshot.hasError) {
                    return const CircularProgressIndicator();
                  }

                  resultDetailFieldController.text =
                      snapshot.error?.toString() ??
                          snapshot.data!.detail ??
                          '<null>';

                  return Column(
                    children: [
                      TextField(
                        controller: resultSummaryFieldController,
                        decoration:
                            const InputDecoration(label: Text('Result')),
                      ),
                      TextField(
                        controller: resultDetailFieldController,
                        decoration:
                            const InputDecoration(label: Text('Detail')),
                      ),
                    ],
                  );
                },
                future: _future,
              ),
            // const Expanded(child: SizedBox()),
          ]),
        ),
      ),
    );
  }

  Future<TestResult> doTestCore(FutureOr<TestResult> Function() test) async {
    late final TestResult result;
    try {
      result = await test();
    } catch (e, s) {
      debugPrint(e.toString());
      debugPrintStack(stackTrace: s);
      result = TestResult(success: false, detail: e.toString());
    }

    return result;
  }

  void doTest(FutureOr<TestResult> Function() test) {
    setState(() {
      _future = doTestCore(test);
    });
  }

  void doRead() => doTest(() async {
        final key = keyFieldController.text;
        return TestResult(
          success: true,
          detail: await _flutterSecureStorageWindowsPlugin.read(
            key: key,
            options: _options,
          ),
        );
      });

  void doReadAll() => doTest(() async {
        return TestResult(
          success: true,
          detail: (await _flutterSecureStorageWindowsPlugin.readAll(
            options: _options,
          ))
              .toString(),
        );
      });

  void doContainsKey() => doTest(() async {
        final key = keyFieldController.text;
        return TestResult(
          success: true,
          detail: (await _flutterSecureStorageWindowsPlugin.containsKey(
            key: key,
            options: _options,
          ))
              .toString(),
        );
      });

  void doWrite() => doTest(() async {
        final key = keyFieldController.text;
        final value = valueFieldController.text.isNotEmpty
            ? valueFieldController.text
            : DateTime.now().toIso8601String();
        await _flutterSecureStorageWindowsPlugin.write(
          key: key,
          value: value,
          options: _options,
        );
        return TestResult(success: true, detail: value);
      });

  void doDelete() => doTest(() async {
        final key = keyFieldController.text;
        await _flutterSecureStorageWindowsPlugin.delete(
          key: key,
          options: _options,
        );
        return TestResult(
          success: true,
          detail: null,
        );
      });

  void doDeleteAll() => doTest(() async {
        await _flutterSecureStorageWindowsPlugin.deleteAll(
          options: _options,
        );
        return TestResult(
          success: true,
          detail: null,
        );
      });

  void doLegacyWrite() => doTest(() async {
        final key = keyFieldController.text;
        final value = valueFieldController.text.isNotEmpty
            ? valueFieldController.text
            : DateTime.now().toIso8601String();
        // call MethodChannelFlutterSecureStorage directly
        final legacyStorage = MethodChannelFlutterSecureStorage();
        await legacyStorage.write(
          key: key,
          value: value,
          options: _options,
        );
        return TestResult(success: true, detail: value);
      });

  void doLegacyReadAll() => doTest(() async {
        // call MethodChannelFlutterSecureStorage directly
        final legacyStorage = MethodChannelFlutterSecureStorage();
        return TestResult(
            success: true,
            detail: (await legacyStorage.readAll(
              options: _options,
            ))
                .toString());
      });
}

class TestResult {
  final bool success;
  final String? detail;
  TestResult({
    required this.success,
    required this.detail,
  });
}

class LabeledCheckbox extends StatefulWidget {
  final String label;
  final EdgeInsetsGeometry padding;
  final bool initialValue;
  final ValueChanged<bool>? onChanged;
  const LabeledCheckbox({
    Key? key,
    required this.label,
    this.padding = const EdgeInsets.all(4),
    this.initialValue = false,
    this.onChanged,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => LabeledCheckboxState._();
}

class LabeledCheckboxState extends State<LabeledCheckbox> {
  late bool _value;

  bool get value => _value;
  set value(bool v) {
    setState(() {
      _value = v;
    });

    widget.onChanged?.call(v);
  }

  LabeledCheckboxState._();

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {
          value = !value;
        },
        child: Padding(
          padding: widget.padding,
          child: Row(children: [
            Expanded(child: Text(widget.label)),
            Checkbox(
                value: value,
                onChanged: (newValue) {
                  if (newValue != null) {
                    value = newValue;
                  }
                })
          ]),
        ),
      );
}
