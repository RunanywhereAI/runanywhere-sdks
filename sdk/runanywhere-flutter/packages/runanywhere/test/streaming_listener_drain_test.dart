// SPDX-License-Identifier: Apache-2.0
//
// Listener/queue drain contract tests for the three Flutter streaming
// surfaces — `RunAnywhereSTT.transcribeStream`,
// `RunAnywhereTTS.synthesizeStream`, and `RunAnywhereVLM.processImageStream`.
//
// Why a contract test (vs. driving the public APIs end-to-end):
//   The three streaming surfaces all bottom out in `NativeCallable.listener`
//   wired to a single-subscription `StreamController<T>`. The unit-test
//   harness has no native library loaded, so we cannot exercise the real
//   FFI binding directly. We use two complementary strategies:
//
//   (A) Contract-level cases (`FakeNativeListenerStream<T>` groups below)
//       model the *exact same* listener-backed `StreamController<T>` pattern
//       so we can pin the three queue/cancel/single-subscription behaviours
//       cheaply against the proto element types each bridge yields.
//
//   (B) Real-wrapper cases (the `DartBridgeTTS.synthesizeStreamLifecycleProto
//       — real wrapper, fake FFI` group, pass2-syn-023) drive the production
//       bridge wrapper through injected seams
//       (`setSynthesizeStreamLifecycleProtoForTesting` /
//       `setStopLifecycleProtoForTesting`). The seam replaces only the FFI
//       call itself; the dispatch closure, FLUTTER-IOS-001 drain loop,
//       closed-controller guard, and `onCancel -> stopLifecycleProto` path
//       are the real production code. Reverting either the drain loop or
//       the cancel→stop block makes these cases fail.
//
//     1. Queue-N drain — listener pushes 10 typed events; consumer receives
//        them in order, matching the `controller.add(event)` body in
//        `runanywhere_stt.dart`, `dart_bridge_tts.dart`, and
//        `dart_bridge_vlm.dart`.
//     2. Drain-while-cancellation — consumer cancels mid-stream; further
//        listener invocations are dropped (closed-controller guard) and the
//        bridge cleanup callback fires (mirroring `nativeCb?.close()`,
//        `stopLifecycleProto()`, and `cancel()`).
//     3. Concurrent listener — second `.listen()` on the same Stream
//        throws `StateError`, matching the single-subscription
//        `StreamController` selected by every bridge.
//
// The tests use the actual proto types each public stream yields
// (`STTPartialResult`, `TTSOutput`, `VLMStreamEvent`) so any future change
// to a bridge's element type fails this file at compile time.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/stt_options.pb.dart';
import 'package:runanywhere/generated/tts_options.pb.dart';
import 'package:runanywhere/generated/vlm_options.pb.dart';
import 'package:runanywhere/native/dart_bridge_tts.dart';

import 'helpers/fake_native_listener.dart';

void main() {
  // -------------------------------------------------------------------------
  // STT — RunAnywhereSTT.transcribeStream
  // -------------------------------------------------------------------------
  group('streaming listener drain — transcribeStream (STTPartialResult)', () {
    test('queue-N drain delivers 10 listener events in order', () async {
      final fake = FakeNativeListenerStream<STTPartialResult>();
      final received = <STTPartialResult>[];
      final completer = Completer<void>();
      final subscription =
          fake.stream.listen(received.add, onDone: completer.complete);

      for (var i = 0; i < 10; i++) {
        fake.dispatch(STTPartialResult(
          text: 'partial-$i',
          isFinal: i == 9,
          segmentIndex: i,
        ));
      }
      await fake.close();
      await completer.future;
      await subscription.cancel();

      expect(received, hasLength(10));
      for (var i = 0; i < 10; i++) {
        expect(received[i].text, equals('partial-$i'));
        expect(received[i].segmentIndex, equals(i));
      }
      expect(received.last.isFinal, isTrue);
    });

    test('drain-while-cancellation halts after subscription cancel', () async {
      var nativeCallableClosed = 0;
      final fake = FakeNativeListenerStream<STTPartialResult>()
        ..cancelCleanup = () => nativeCallableClosed++;
      final received = <STTPartialResult>[];

      late StreamSubscription<STTPartialResult> subscription;
      subscription = fake.stream.listen((event) async {
        received.add(event);
        if (received.length == 2) {
          await subscription.cancel();
        }
      });

      for (var i = 0; i < 5; i++) {
        fake.dispatch(STTPartialResult(text: 'p$i', segmentIndex: i));
        await Future<void>.delayed(Duration.zero);
      }

      expect(received, hasLength(2));
      expect(received.map((p) => p.text).toList(), equals(['p0', 'p1']));
      expect(fake.cancelled, isTrue,
          reason: 'subscription.cancel() must trigger the controller '
              'onCancel hook used by transcribeStream to close the '
              'NativeCallable');
      expect(nativeCallableClosed, equals(1),
          reason: 'transcribeStream.onCancel must close nativeCb exactly '
              'once on subscription cancel');

      // Bridge's finally block closes the controller after the FFI returns;
      // simulate that here and verify post-close dispatches are dropped by
      // the listener's `isClosed` short-circuit.
      await fake.close();
      fake.dispatch(STTPartialResult(text: 'post-close', segmentIndex: 99));
      expect(received, hasLength(2),
          reason: 'closed-controller guard in the listener must drop '
              'late-arriving events');
    });

    test(
        'concurrent listener is rejected — single-subscription bridge contract',
        () async {
      final fake = FakeNativeListenerStream<STTPartialResult>();
      final firstSubscription = fake.stream.listen((_) {});

      expect(
        () => fake.stream.listen((_) {}),
        throwsA(isA<StateError>()),
        reason: 'transcribeStream uses StreamController<STTPartialResult>() — '
            'second listen must fail rather than fan out',
      );

      await firstSubscription.cancel();
      await fake.close();
    });
  });

  // -------------------------------------------------------------------------
  // TTS — RunAnywhereTTS.synthesizeStream
  // -------------------------------------------------------------------------
  group('streaming listener drain — synthesizeStream (TTSOutput)', () {
    test('queue-N drain delivers 10 listener events in order', () async {
      final fake = FakeNativeListenerStream<TTSOutput>();
      final received = <TTSOutput>[];
      final completer = Completer<void>();
      final subscription =
          fake.stream.listen(received.add, onDone: completer.complete);

      for (var i = 0; i < 10; i++) {
        fake.dispatch(TTSOutput(
          chunkIndex: i,
          isFinal: i == 9,
          sampleRate: 22050,
        ));
      }
      await fake.close();
      await completer.future;
      await subscription.cancel();

      expect(received, hasLength(10));
      for (var i = 0; i < 10; i++) {
        expect(received[i].chunkIndex, equals(i));
        expect(received[i].sampleRate, equals(22050));
      }
      expect(received.last.isFinal, isTrue);
    });

    test('drain-while-cancellation halts after subscription cancel', () async {
      var stopLifecycleCalls = 0;
      final fake = FakeNativeListenerStream<TTSOutput>()
        ..cancelCleanup = () => stopLifecycleCalls++;
      final received = <TTSOutput>[];

      late StreamSubscription<TTSOutput> subscription;
      subscription = fake.stream.listen((event) async {
        received.add(event);
        if (received.length == 2) {
          await subscription.cancel();
        }
      });

      for (var i = 0; i < 5; i++) {
        fake.dispatch(TTSOutput(chunkIndex: i, sampleRate: 22050));
        await Future<void>.delayed(Duration.zero);
      }

      expect(received, hasLength(2));
      expect(received.map((o) => o.chunkIndex).toList(), equals([0, 1]));
      expect(fake.cancelled, isTrue,
          reason: 'subscription.cancel() must trigger '
              'synthesizeStreamLifecycleProto.onCancel');
      expect(stopLifecycleCalls, equals(1),
          reason: 'synthesizeStreamLifecycleProto.onCancel must call '
              'stopLifecycleProto exactly once on subscription cancel');

      // Bridge's run() finally closes the controller; verify the
      // closed-controller guard in the listener body drops late events.
      await fake.close();
      fake.dispatch(TTSOutput(chunkIndex: 99, sampleRate: 22050));
      expect(received, hasLength(2));
    });

    test(
        'concurrent listener is rejected — single-subscription bridge contract',
        () async {
      final fake = FakeNativeListenerStream<TTSOutput>();
      final firstSubscription = fake.stream.listen((_) {});

      expect(
        () => fake.stream.listen((_) {}),
        throwsA(isA<StateError>()),
        reason:
            'synthesizeStreamLifecycleProto uses StreamController<TTSStreamEvent>'
            '(sync: false) — second listen must fail',
      );

      await firstSubscription.cancel();
      await fake.close();
    });

    test('TTSStreamEvent terminal kind is observable to the listener',
        () async {
      // Smoke check that mirrors the bridge's terminal-event short-circuit
      // (`event.kind == TTS_STREAM_EVENT_KIND_COMPLETED`). Production code
      // uses this kind to break out of the FFI drain loop.
      final fake = FakeNativeListenerStream<TTSStreamEvent>();
      final received = <TTSStreamEvent>[];
      final subscription = fake.stream.listen(received.add);

      fake.dispatch(TTSStreamEvent(
        kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_AUDIO_CHUNK,
      ));
      fake.dispatch(TTSStreamEvent(
        kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED,
      ));
      await fake.close();
      await subscription.cancel();

      expect(received, hasLength(2));
      expect(
        received.last.kind,
        equals(TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED),
      );
    });
  });

  // -------------------------------------------------------------------------
  // TTS — REAL bridge wrapper, via the pass2-syn-023 injection seams.
  //
  // Unlike the fake-listener cases above, these tests drive
  // `DartBridgeTTS.synthesizeStreamLifecycleProto` directly — exercising the
  // production drain loop and `onCancel -> stopLifecycleProto` path. The
  // seam (`setSynthesizeStreamLifecycleProtoForTesting`) replaces the FFI
  // call with a Dart-side fake; the rest of the wrapper (dispatch closure,
  // closed-controller guard, drain microtasks, controller.close) is the
  // real code path.
  // -------------------------------------------------------------------------
  group('DartBridgeTTS.synthesizeStreamLifecycleProto — real wrapper, fake FFI',
      () {
    tearDown(() {
      DartBridgeTTS.setSynthesizeStreamLifecycleProtoForTesting(null);
      DartBridgeTTS.setStopLifecycleProtoForTesting(null);
    });

    test(
        'delivers 50 chunk events + terminal before close (production drain loop)',
        () async {
      // The fake FFI dispatches 50 chunk events synchronously, then schedules
      // the terminal COMPLETED event onto a `Future.microtask`, then returns
      // RAC_SUCCESS. This mirrors how `NativeCallable.listener` queues
      // callbacks during a blocking FFI call: the production callbacks land
      // on the event loop AFTER the synchronous FFI returns. The only path
      // that lets the terminal arrive before `controller.close()` is the
      // production `await drainPendingStreamCallbacks(...)` microtask loop —
      // remove that line in `dart_bridge_tts.dart` and this test must fail
      // (the COMPLETED event would be dropped because the controller closes
      // before the queued microtask runs). (pass3-syn-121)
      DartBridgeTTS.setSynthesizeStreamLifecycleProtoForTesting(
        (request, dispatch, terminalObserved) async {
          for (var i = 0; i < 50; i++) {
            dispatch(TTSStreamEvent(
              kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_AUDIO_CHUNK,
            ));
          }
          // Terminal event arrives asynchronously, simulating the production
          // NativeCallable.listener queueing behavior. Without the production
          // drain loop, `controller.close()` runs before this microtask fires
          // and the COMPLETED event is silently dropped.
          unawaited(Future<void>.microtask(() {
            dispatch(TTSStreamEvent(
              kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED,
            ));
          }));
          return 0; // RAC_SUCCESS
        },
      );

      final stream = DartBridgeTTS.shared.synthesizeStreamLifecycleProto(
        TTSSynthesisRequest(text: 'hello'),
      );

      final received = await stream.toList();

      expect(received, hasLength(51),
          reason: 'All 50 chunks + the terminal COMPLETED event must reach '
              'the subscriber before close — regression-tests the production '
              'drain microtask loop and dispatch closure.');
      expect(
        received.last.kind,
        equals(TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED),
      );
      final chunkCount = received
          .where((e) =>
              e.kind == TTSStreamEventKind.TTS_STREAM_EVENT_KIND_AUDIO_CHUNK)
          .length;
      expect(chunkCount, equals(50));
    });

    test('subscription.cancel mid-stream invokes stopLifecycleProto exactly once',
        () async {
      var stopCalls = 0;
      DartBridgeTTS.setStopLifecycleProtoForTesting(() {
        stopCalls++;
        return TTSServiceState();
      });

      final cancelSignal = Completer<void>();
      DartBridgeTTS.setSynthesizeStreamLifecycleProtoForTesting(
        (request, dispatch, terminalObserved) async {
          // Dispatch a couple of audio chunks then yield so the subscriber
          // can observe + cancel, then verify dispatch becomes a no-op after
          // close (the dispatch closure's closed-controller guard).
          dispatch(TTSStreamEvent(
            kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_AUDIO_CHUNK,
          ));
          dispatch(TTSStreamEvent(
            kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_AUDIO_CHUNK,
          ));
          await cancelSignal.future;
          // Late dispatch — must be silently dropped by the production
          // closed-controller guard.
          dispatch(TTSStreamEvent(
            kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_AUDIO_CHUNK,
          ));
          return 0;
        },
      );

      final stream = DartBridgeTTS.shared.synthesizeStreamLifecycleProto(
        TTSSynthesisRequest(text: 'hello'),
      );

      final received = <TTSStreamEvent>[];
      late StreamSubscription<TTSStreamEvent> sub;
      final cancelled = Completer<void>();
      sub = stream.listen((event) async {
        received.add(event);
        if (received.length == 2) {
          await sub.cancel();
          cancelSignal.complete();
          cancelled.complete();
        }
      });

      await cancelled.future;
      // Let any post-cancel microtasks run.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(stopCalls, equals(1),
          reason: 'Production controller.onCancel must call '
              'stopLifecycleProto exactly once on subscription cancel — '
              'regression-tests the cancel cleanup path.');
    });
  });

  // -------------------------------------------------------------------------
  // VLM — RunAnywhereVLM.processImageStream
  // -------------------------------------------------------------------------
  group('streaming listener drain — processImageStream (VLMStreamEvent)', () {
    test('queue-N drain delivers 10 listener events in order with '
        'auto-close on isFinal', () async {
      // Mirrors the VLM bridge: `event.isFinal` triggers controller.close().
      final fake = FakeNativeListenerStream<VLMStreamEvent>(
        autoCloseOnFinal: true,
        isFinal: (event) => event.isFinal,
      );
      final received = <VLMStreamEvent>[];
      final completer = Completer<void>();
      final subscription =
          fake.stream.listen(received.add, onDone: completer.complete);

      for (var i = 0; i < 10; i++) {
        fake.dispatch(VLMStreamEvent(
          tokenIndex: i,
          token: 'tok-$i',
          isFinal: i == 9,
          kind: i == 9
              ? VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED
              : VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN,
        ));
      }
      await completer.future;
      await subscription.cancel();

      expect(received, hasLength(10));
      for (var i = 0; i < 10; i++) {
        expect(received[i].tokenIndex, equals(i));
        expect(received[i].token, equals('tok-$i'));
      }
      expect(received.last.isFinal, isTrue);
      expect(fake.isClosed, isTrue,
          reason: 'isFinal=true must auto-close the controller, matching '
              'processImageStreamProto');
    });

    test('drain-while-cancellation halts after subscription cancel', () async {
      var cancelCalls = 0;
      final fake = FakeNativeListenerStream<VLMStreamEvent>()
        ..cancelCleanup = () => cancelCalls++;
      final received = <VLMStreamEvent>[];

      late StreamSubscription<VLMStreamEvent> subscription;
      subscription = fake.stream.listen((event) async {
        received.add(event);
        if (received.length == 2) {
          await subscription.cancel();
        }
      });

      for (var i = 0; i < 5; i++) {
        fake.dispatch(VLMStreamEvent(
          tokenIndex: i,
          token: 't$i',
          kind: VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN,
        ));
        await Future<void>.delayed(Duration.zero);
      }

      expect(received, hasLength(2));
      expect(received.map((e) => e.token).toList(), equals(['t0', 't1']));
      expect(fake.cancelled, isTrue,
          reason: 'subscription.cancel() must trigger '
              'processImageStreamProto.onCancel');
      expect(cancelCalls, equals(1),
          reason: 'processImageStreamProto.onCancel must call cancel() '
              'exactly once on subscription cancel');

      // Bridge's run() finally closes the controller; closed-controller
      // guard must drop any late-arriving listener events.
      await fake.close();
      fake.dispatch(VLMStreamEvent(
        tokenIndex: 99,
        token: 'post-close',
        kind: VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN,
      ));
      expect(received, hasLength(2));
    });

    test(
        'concurrent listener is rejected — single-subscription bridge contract',
        () async {
      final fake = FakeNativeListenerStream<VLMStreamEvent>();
      final firstSubscription = fake.stream.listen((_) {});

      expect(
        () => fake.stream.listen((_) {}),
        throwsA(isA<StateError>()),
        reason: 'processImageStreamProto uses StreamController<VLMStreamEvent>'
            '(sync: false) — second listen must fail',
      );

      await firstSubscription.cancel();
      await fake.close();
    });
  });
}
