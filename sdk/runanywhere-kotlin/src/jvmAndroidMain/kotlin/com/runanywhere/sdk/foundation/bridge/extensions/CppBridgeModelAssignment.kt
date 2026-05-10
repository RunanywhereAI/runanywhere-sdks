/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Bridge for the C++ model assignment manager.
 *
 * Mirrors the Swift surface in
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelAssignment.swift`,
 * which exposes:
 *   - register(autoFetch: Bool)              -> rac_model_assignment_set_callbacks
 *   - fetch(forceRefresh: Bool)              -> rac_model_assignment_fetch
 *   - getByFramework(framework)              -> rac_model_assignment_get_by_framework
 *   - getByCategory(category)                -> rac_model_assignment_get_by_category
 *
 * The corresponding `rac_model_assignment_*` JNI thunks are NOT yet exposed
 * through `RunAnywhereBridge` (no `racModelAssignment*` external funs exist),
 * and the underlying `rac_assignment_callbacks_t` HTTP-GET callback bridge
 * has not been wired up on the C++ side for Kotlin/JVM.
 *
 * TODO: commons CPP-02 follow-up.
 *   1. Add the JNI thunks `racModelAssignmentSetCallbacks`,
 *      `racModelAssignmentFetch`, `racModelAssignmentGetByFramework`, and
 *      `racModelAssignmentGetByCategory` to
 *      `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` and
 *      declare them on `RunAnywhereBridge`.
 *   2. Replace this stub with the real wrapper that registers an HTTP-GET
 *      callback (delegating to OkHttp via `CppBridgeHTTP`) and decodes the
 *      returned `rac_model_info_t` array into `ai.runanywhere.proto.v1.ModelInfo`
 *      records — matching the iOS `RAModelInfo` flow.
 *
 * Until then this object is intentionally empty so callers can compile-check
 * against the namespace without invoking unimplemented JNI symbols.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

/**
 * Stub for the model-assignment bridge. See file-level KDoc for follow-up details.
 *
 * No methods are exposed yet because none of the underlying
 * `rac_model_assignment_*` JNI bindings exist on `RunAnywhereBridge`. This
 * object is reserved as the future home of the Kotlin equivalent of Swift's
 * `CppBridge.ModelAssignment` extension.
 */
object CppBridgeModelAssignment
