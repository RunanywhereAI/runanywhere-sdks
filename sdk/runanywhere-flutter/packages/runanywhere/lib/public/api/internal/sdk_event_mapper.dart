// SPDX-License-Identifier: Apache-2.0
//
// Projects the generated SDKEvent firehose onto the four public breadcrumbs.

import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show ModelCategory;
import 'package:runanywhere/generated/sdk_events.pb.dart' as events_pb;
import 'package:runanywhere/generated/sdk_events.pbenum.dart'
    show InitializationStage, ModelEventKind;
import 'package:runanywhere/public/api/types/events.dart';

/// Maps generated SDK events to the public [SdkEvent] grammar.
abstract final class SdkEventMapper {
  /// Translate [event], or return null when it carries no public breadcrumb.
  static SdkEvent? map(events_pb.SDKEvent event) {
    if (event.hasInitialization()) {
      switch (event.initialization.stage) {
        case InitializationStage.INITIALIZATION_STAGE_COMPLETED:
          return const SdkReady();
        case InitializationStage.INITIALIZATION_STAGE_FAILED:
          return SdkError(
            event.initialization.error.isEmpty
                ? 'SDK initialization failed'
                : event.initialization.error,
            recoverable: false,
          );
        default:
          return null;
      }
    }
    if (event.hasComponentLifecycle()) {
      final lifecycle = event.componentLifecycle;
      if (lifecycle.modelId.isEmpty) return null;
      switch (lifecycle.currentState) {
        case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY:
          return SdkModelLoaded(
            lifecycle.modelId,
            lifecycle.hasSnapshot()
                ? lifecycle.snapshot.category
                : _unspecifiedCategory,
          );
        case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED:
        case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_SHUTDOWN:
          return SdkModelUnloaded(lifecycle.modelId);
        default:
          return null;
      }
    }
    if (event.hasModel()) {
      final model = event.model;
      switch (model.kind) {
        case ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED:
          return SdkModelUnloaded(model.modelId);
        case ModelEventKind.MODEL_EVENT_KIND_LOAD_FAILED:
        case ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_FAILED:
          return SdkError(
            model.error.isEmpty ? 'Model operation failed' : model.error,
            recoverable: true,
          );
        default:
          return null;
      }
    }
    if (event.hasFailure()) {
      return SdkError(
        event.failure.error.message,
        recoverable: event.failure.recoverable,
      );
    }
    if (event.hasError()) {
      return SdkError(event.error.message, recoverable: true);
    }
    return null;
  }

  static const ModelCategory _unspecifiedCategory =
      ModelCategory.MODEL_CATEGORY_UNSPECIFIED;
}
