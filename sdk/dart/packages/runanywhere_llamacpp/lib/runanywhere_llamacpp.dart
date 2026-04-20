// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

library runanywhere_llamacpp;

class RunanywhereLlamacpp {
  /// Confirms the native llamacpp plugin is linked. Engines statically
  /// compiled into libracommons_core self-register at dynamic-init
  /// time; this method is a signal for sample-app UI gating.
  static bool register({int priority = 100}) => true;
}
