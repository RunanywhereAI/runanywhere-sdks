// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_lifecycle.h"

const char* ra_lifecycle_state_str(ra_lifecycle_state_t state) {
    switch (state) {
        case RA_LIFECYCLE_UNINITIALIZED: return "Uninitialized";
        case RA_LIFECYCLE_INITIALIZING:  return "Initializing";
        case RA_LIFECYCLE_READY:         return "Ready";
        case RA_LIFECYCLE_LOADING:       return "Loading";
        case RA_LIFECYCLE_LOADED:        return "Loaded";
        case RA_LIFECYCLE_RUNNING:       return "Running";
        case RA_LIFECYCLE_ERROR:         return "Error";
        case RA_LIFECYCLE_DESTROYING:    return "Destroying";
        default:                         return "Unknown";
    }
}
