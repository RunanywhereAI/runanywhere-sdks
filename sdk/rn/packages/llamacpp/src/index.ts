// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Thin register-at-startup hook. The native llamacpp engine is
// statically compiled into libracommons_core (RA_STATIC_PLUGINS=ON),
// so the actual registration happens via C++ ctor-init. This module
// just confirms the registration so host apps can gate their UI.

import { getNativeBridge } from '@runanywhere/core';

export const LlamaCPP = {
  /// Record intent to use llama.cpp. Returns true when the engine is
  /// linked into the running native bundle.
  register(priority: number = 100): boolean {
    try {
      const bridge = getNativeBridge();
      bridge.buildInfo();
      return true;
    } catch {
      return false;
    }
  }
};
