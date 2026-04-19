// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import 'dart:async';

import 'runanywhere.dart';
import 'voice_event.dart';

class VoiceSession {
  final SolutionConfig _config;
  final int            _nativeHandle;

  VoiceSession._(this._config, this._nativeHandle);

  factory VoiceSession.create(SolutionConfig config) {
    // TODO(phase-3): encode SolutionConfig to proto3 bytes,
    //                call ra_pipeline_create_from_solution via FFI.
    return VoiceSession._(config, 0);
  }

  Stream<VoiceEvent> run() async* {
    if (_nativeHandle == 0) {
      yield VoiceError(
        -6,
        'RunAnywhere v2 native core not linked; '
        'see frontends/dart/CONTRIBUTING.md',
      );
      return;
    }
    // TODO(phase-3): FFI callback bridge decodes proto3 VoiceEvent bytes
    // and yields them here.
  }

  void stop() {
    // TODO(phase-3): ra_pipeline_cancel(_nativeHandle)
  }

  SolutionConfig get config => _config;
}
