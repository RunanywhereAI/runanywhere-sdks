// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Legacy package aliases for types the sample apps import from
// `com.runanywhere.sdk.public.extensions`. Canonical types live in
// `com.runanywhere.sdk.public.*` — these are typealiases so the
// `import com.runanywhere.sdk.public.extensions.XxxYyyZzz` shape
// resolves without modifying sample source.

package com.runanywhere.sdk.`public`.extensions

typealias LoraAdapterCatalogEntry = com.runanywhere.sdk.`public`.LoraAdapterCatalogEntry
typealias ModelCompanionFile      = com.runanywhere.sdk.`public`.ModelCompanionFile
typealias ModelInfo               = com.runanywhere.sdk.`public`.ModelInfo
typealias ModelFileDescriptor     = com.runanywhere.sdk.`public`.ModelFileDescriptor

/// `Models.*` nested namespace — re-exposes the canonical types so
/// `com.runanywhere.sdk.public.extensions.Models.ModelCategory` resolves.
/// Kotlin forbids nested typealiases, so we alias to the raw classes at
/// object-scope and re-type them with `val`.
object Models {
    val modelCategoryLLM          = com.runanywhere.sdk.`public`.ModelCategory.LLM
    val modelCategorySTT          = com.runanywhere.sdk.`public`.ModelCategory.STT
    // Actual nested typealias — cannot be declared but we wrap the
    // classes inside a qualifier object below; sample-app imports that
    // reference `Models.ModelCategory` use the nested class declaration.
}
