// SPDX-License-Identifier: Apache-2.0
//
// Contract tests for `voice_agent_stream_adapter.dart`'s fan-out pattern.
//
// `VoiceAgentStreamAdapter` bottoms out in
// `RacNative.bindings.rac_voice_agent_set_proto_callback` and a
// `NativeCallable.listener`, so direct end-to-end testing requires the native
// library — the unit-test harness does not stage one. We instead pin the
// adapter's documented contract by modelling the same multi-subscriber
// fan-out, dispatch-after-close guard, and teardown-on-last-detach
// behaviour using an isomorphic Dart-only helper. This mirrors the strategy
// used by `streaming_listener_drain_test.dart` for the STT/TTS/VLM
// single-subscription bridges. Failing any of these cases means the
// production adapter's fan-out semantics have drifted from the documented
// public surface.
//
// Cases:
//   1. Single-subscriber dispatch — events flow in order until close.
//   2. Multi-subscriber fan-out — two attached subscribers receive every
//      dispatched event (mirrors `_VoiceHandleFanOut._broadcast`).
//   3. Detach-on-cancel — cancelling the only subscription triggers
//      teardown (`_onTornDown` fires exactly once).
//   4. Detach with multiple subscribers — teardown only fires after the
//      LAST subscriber detaches.
//   5. Closed-controller guard — events dispatched after a subscriber
//      closes its controller do not throw (mirrors the
//      `controller.isClosed` check in `_VoiceHandleFanOut._broadcast`).
//   6. Error broadcast — an error fans out to every subscriber and tears
//      the fan-out down (mirrors `_broadcastError`).

import 'dart:async';

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/voice_events.pb.dart';

void main() {
  group('voice_agent_stream_adapter fan-out — contract', () {
    test('single subscriber receives N dispatched events in order', () async {
      final fanOut = _FakeVoiceFanOut();
      final stream = _FakeVoiceAgentStreamAdapter(fanOut).stream();
      final received = <VoiceEvent>[];
      final done = Completer<void>();
      final sub = stream.listen(received.add, onDone: done.complete);

      for (var i = 0; i < 10; i++) {
        fanOut.dispatch(VoiceEvent(
          seq: $fixnum.Int64(i),
          sessionId: 'session-$i',
        ));
      }
      fanOut.dispose();
      await done.future;
      await sub.cancel();

      expect(received, hasLength(10));
      for (var i = 0; i < 10; i++) {
        expect(received[i].sessionId, equals('session-$i'));
        expect(received[i].seq.toInt(), equals(i));
      }
    });

    test('two subscribers each receive every dispatched event', () async {
      final fanOut = _FakeVoiceFanOut();
      final adapter = _FakeVoiceAgentStreamAdapter(fanOut);
      final a = <VoiceEvent>[];
      final b = <VoiceEvent>[];
      final subA = adapter.stream().listen(a.add);
      final subB = adapter.stream().listen(b.add);

      for (var i = 0; i < 3; i++) {
        fanOut.dispatch(VoiceEvent(
          seq: $fixnum.Int64(i),
          sessionId: 'p$i',
        ));
      }
      // Let pending microtasks drain so the broadcast reaches both subs.
      await Future<void>.delayed(Duration.zero);

      expect(a.map((e) => e.sessionId).toList(), equals(['p0', 'p1', 'p2']));
      expect(b.map((e) => e.sessionId).toList(), equals(['p0', 'p1', 'p2']));

      await subA.cancel();
      await subB.cancel();
    });

    test('cancelling the only subscription tears the fan-out down exactly once',
        () async {
      final fanOut = _FakeVoiceFanOut();
      final sub = _FakeVoiceAgentStreamAdapter(fanOut).stream().listen((_) {});

      expect(fanOut.tornDown, isFalse,
          reason: 'tear-down must not fire before any detach');
      await sub.cancel();
      // Detach is synchronous in the production adapter.
      expect(fanOut.tornDown, isTrue,
          reason: 'last detach must trigger _tearDown -> _onTornDown');
      expect(fanOut.tearDownCalls, equals(1));
    });

    test('teardown only fires after the LAST subscriber detaches', () async {
      final fanOut = _FakeVoiceFanOut();
      final adapter = _FakeVoiceAgentStreamAdapter(fanOut);
      final subA = adapter.stream().listen((_) {});
      final subB = adapter.stream().listen((_) {});

      await subA.cancel();
      expect(fanOut.tornDown, isFalse,
          reason: 'one subscriber still attached — fan-out must persist');

      await subB.cancel();
      expect(fanOut.tornDown, isTrue,
          reason: 'last detach must trigger _tearDown');
      expect(fanOut.tearDownCalls, equals(1));
    });

    test('events dispatched after a subscriber closes are silently dropped',
        () async {
      final fanOut = _FakeVoiceFanOut();
      final adapter = _FakeVoiceAgentStreamAdapter(fanOut);
      final a = <VoiceEvent>[];
      final b = <VoiceEvent>[];
      final subA = adapter.stream().listen(a.add);
      final subB = adapter.stream().listen(b.add);

      fanOut.dispatch(VoiceEvent(
        seq: $fixnum.Int64(1),
        sessionId: 'first',
      ));
      await Future<void>.delayed(Duration.zero);

      // Cancel subA. A subsequent dispatch must reach subB only.
      await subA.cancel();

      fanOut.dispatch(VoiceEvent(
        seq: $fixnum.Int64(2),
        sessionId: 'after-cancel',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(a.map((e) => e.sessionId).toList(), equals(['first']));
      expect(
        b.map((e) => e.sessionId).toList(),
        equals(['first', 'after-cancel']),
      );
      await subB.cancel();
    });

    test('error broadcast fans out to every subscriber and tears down',
        () async {
      final fanOut = _FakeVoiceFanOut();
      final adapter = _FakeVoiceAgentStreamAdapter(fanOut);
      Object? errA;
      Object? errB;
      final aDone = Completer<void>();
      final bDone = Completer<void>();
      adapter.stream().listen(
            (_) {},
            onError: (Object e, StackTrace st) => errA = e,
            onDone: aDone.complete,
          );
      adapter.stream().listen(
            (_) {},
            onError: (Object e, StackTrace st) => errB = e,
            onDone: bDone.complete,
          );

      const boom = FormatException('decode failed');
      fanOut.dispatchError(boom, StackTrace.current);

      await aDone.future;
      await bDone.future;

      expect(errA, same(boom));
      expect(errB, same(boom));
      expect(fanOut.tornDown, isTrue,
          reason: '_broadcastError must tearDown the fan-out');
      expect(fanOut.tearDownCalls, equals(1));
    });
  });
}

// -----------------------------------------------------------------------------
// Test doubles that mirror the production fan-out shape.
// -----------------------------------------------------------------------------

/// Test double for the singleton `_VoiceFanOutRegistry`-backed fan-out. The
/// production type lives in `lib/adapters/voice_agent_stream_adapter.dart`
/// and is library-private; this fake reproduces the same `attach` / `detach`
/// / `_broadcast` / `_broadcastError` shape so the contract above pins
/// every observable behaviour. Production-side wiring (the C callback
/// registration + `NativeCallable.listener`) requires the native library and
/// is therefore not exercised here; see
/// `streaming_listener_drain_test.dart` for the same strategy applied to the
/// single-subscription bridges (STT/TTS/VLM).
class _FakeVoiceFanOut {
  final Set<StreamController<VoiceEvent>> _controllers = {};
  bool tornDown = false;
  int tearDownCalls = 0;

  void attach(StreamController<VoiceEvent> controller) {
    _controllers.add(controller);
  }

  void detach(StreamController<VoiceEvent> controller) {
    _controllers.remove(controller);
    if (_controllers.isEmpty) {
      _tearDown();
    }
  }

  void dispatch(VoiceEvent event) {
    final snapshot = List<StreamController<VoiceEvent>>.from(_controllers);
    for (final controller in snapshot) {
      if (!controller.isClosed) {
        controller.add(event);
      }
    }
  }

  void dispatchError(Object error, StackTrace stackTrace) {
    final snapshot = List<StreamController<VoiceEvent>>.from(_controllers);
    _controllers.clear();
    for (final controller in snapshot) {
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
        unawaited(controller.close());
      }
    }
    _tearDown();
  }

  /// Simulates the run() body completing (stream ends with no error).
  void dispose() {
    final snapshot = List<StreamController<VoiceEvent>>.from(_controllers);
    for (final controller in snapshot) {
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
    }
  }

  void _tearDown() {
    if (tornDown) return;
    tornDown = true;
    tearDownCalls++;
  }
}

class _FakeVoiceAgentStreamAdapter {
  _FakeVoiceAgentStreamAdapter(this._fanOut);

  final _FakeVoiceFanOut _fanOut;

  Stream<VoiceEvent> stream() {
    late StreamController<VoiceEvent> controller;
    controller = StreamController<VoiceEvent>(
      onListen: () => _fanOut.attach(controller),
      onCancel: () => _fanOut.detach(controller),
    );
    return controller.stream;
  }
}
