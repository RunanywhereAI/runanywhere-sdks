// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import { getNativeBridge } from '@runanywhere/core';

const NAME = 'genie';

export const Engine = {
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
