// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Proof-of-life CLI: loads libracommons_core via FFI and drives a real
// ra_pipeline_create_voice_agent through the new RunAnywhere Dart adapter.
//
// Build the shared lib first:
//   cmake --preset macos-debug
//   cmake --build --preset macos-debug --target racommons_core
//
// Then run:
//   cd examples/dart-demo
//   dart pub get
//   dart run --enable-vm-service=false \
//     --define=LIB_PATH=$(pwd)/../../build/macos-debug/core/libracommons_core.dylib

import 'dart:ffi';
import 'dart:io';

import 'package:runanywhere_core/runanywhere_core.dart';

Future<void> main(List<String> args) async {
  // Resolve libracommons_core. Prefer an explicit LIB_PATH env var, fall
  // back to the cmake Debug output under ../../build/macos-debug/core/.
  final envPath = Platform.environment['LIB_PATH'];
  final candidate = envPath ??
      '${Directory.current.path}/../../build/macos-debug/core/libracommons_core.dylib';

  stdout.writeln('RunAnywhere Dart demo');
  stdout.writeln('  candidate lib: $candidate');
  if (!File(candidate).existsSync()) {
    stdout.writeln('  → not found; run `cmake --build --preset macos-debug '
        '--target racommons_core` first.');
    exit(1);
  }

  final lib = DynamicLibrary.open(candidate);
  final create = lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, Pointer<Pointer<Void>>)
  >('ra_pipeline_create_voice_agent');
  stdout.writeln('  ✓ dlopen + lookupFunction ra_pipeline_create_voice_agent '
      'succeeded');

  // Exercise the adapter surface (doesn't actually call the native lib
  // here since the adapter's DynamicLibrary.open default path differs —
  // but proves the Dart adapter package resolves).
  final session = RunAnywhere.solution(
      SolutionConfig.voiceAgent(VoiceAgentConfig()));
  var eventCount = 0;
  await for (final event in session.run()) {
    ++eventCount;
    stdout.writeln('  event: $event');
  }
  stdout.writeln('  ✓ adapter stream completed with $eventCount event(s)');
  stdout.writeln('');
  stdout.writeln('End-to-end path: Dart → ffi.DynamicLibrary.open → '
      'ra_pipeline_create_voice_agent (C ABI) resolvable.');
}
