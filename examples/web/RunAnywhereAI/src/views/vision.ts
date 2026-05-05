/**
 * Vision Tab — placeholder.
 *
 * VLM worker bridge is at `@runanywhere/web-llamacpp/vlm-worker`. This
 * view is awaiting WEB-08 re-land — see gaps/gaps/inconsistencies/web.md.
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
