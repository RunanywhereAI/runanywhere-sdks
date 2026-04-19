// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// llama.cpp L2 engine plugin. Implements the generate_text and embed
// primitives over GGUF models.

#ifndef RA_ENGINES_LLAMACPP_PLUGIN_H
#define RA_ENGINES_LLAMACPP_PLUGIN_H

#include "ra_plugin.h"

#ifdef __cplusplus
extern "C" {
#endif

// Populates `out` with the llama.cpp vtable. Returns RA_OK on success.
ra_status_t ra_plugin_entry(ra_engine_vtable_t* out);

#ifdef __cplusplus
}
#endif

#endif  // RA_ENGINES_LLAMACPP_PLUGIN_H
