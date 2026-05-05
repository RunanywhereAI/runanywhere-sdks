/**
 * Vision Tab — placeholder.
 *
 * The vision view previously captured webcam frames through
 * `VideoCapture` (still present in core) and dispatched VLM inference
 * through `VLMWorkerBridge.shared.process(...)`. The worker bridge lived
 * in `@runanywhere/web-llamacpp` and was deleted in the V2 cleanup.
 */

import type { TabLifecycle } from '../app';
import { renderFeatureUnavailable } from '../components/feature-unavailable';

export function initVisionTab(el: HTMLElement): TabLifecycle {
  renderFeatureUnavailable(el, {
    title: 'Vision',
    description:
      'Live VLM camera description. Returns once the proto-byte VLM bridge ' +
      'in `@runanywhere/web-llamacpp` re-lands and registers a VLM handle.',
    requires: [
      'VideoCapture',
      'VLMProtoAdapter.process',
      'RunAnywhere.modelLifecycle.load',
    ],
  });

  return {};
}
