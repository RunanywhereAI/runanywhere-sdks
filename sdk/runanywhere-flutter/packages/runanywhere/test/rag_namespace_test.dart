// SPDX-License-Identifier: Apache-2.0
//
// Characterizes `RunAnywhere.rag`'s second-open policy (PR #605 review
// issue 10).
//
// The Flutter RAG bridge owns a single process-wide native pipeline (no
// per-session handle), matching RN (`Rag.ts`) and Web (`rag.ts`) rather than
// Swift/Kotlin's handle-based multi-session `RagSession` — those two SDKs
// give each session its own native handle, so they never faced this
// decision. Given the shared-pipeline SDKs already reject a second
// concurrent open with `SDKException.invalidState('A RAG session is already
// open; close it before opening another')`, Flutter now matches that policy
// instead of silently superseding the active session.
//
// `open()` needs `DartBridge.isInitialized` to be true before it reaches the
// active-session check, so — like the rest of this package's namespace
// tests that touch `DartBridge` state — the policy itself is verified by
// reading the namespace source rather than driving the full native path.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/public/api/namespaces/rag.dart').readAsStringSync();

  group('rag second-open policy (single-active must reject)', () {
    test('open() rejects a second concurrent session', () {
      expect(source, contains('RagSession._active != null'));
      expect(source, contains('A RAG session is already open'));
    });

    test('the reject check runs before any session is created or replaced', () {
      final rejectIndex = source.indexOf('RagSession._active != null');
      final registerIndex = source.indexOf('DartBridgeRAG.shared.register()');
      final createPipelineIndex = source.indexOf('createPipelineAsync');
      final activeAssignmentIndex = source.indexOf('_active = this');

      expect(rejectIndex, greaterThan(-1));
      expect(registerIndex, greaterThan(-1));
      expect(createPipelineIndex, greaterThan(-1));
      expect(activeAssignmentIndex, greaterThan(-1));

      expect(
        rejectIndex,
        lessThan(registerIndex),
        reason: 'must reject before touching the native RAG backend',
      );
      expect(
        rejectIndex,
        lessThan(createPipelineIndex),
        reason: 'must reject before creating the native pipeline',
      );
      expect(
        rejectIndex,
        lessThan(activeAssignmentIndex),
        reason: 'must reject before a new session replaces the active one',
      );
    });

    test('documentation no longer claims silent superseding', () {
      expect(source, isNot(contains('supersedes any earlier one')));
    });

    test('a closed/superseded session still reports itself as closed', () {
      // `_requireLive()` is the only path left that can report a stale
      // session, now that a second `open()` can no longer supersede one.
      expect(source, contains("SDKException.invalidState('RAG session is closed')"));
    });
  });
}
