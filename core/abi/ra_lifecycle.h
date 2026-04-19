// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Component lifecycle state machine. Ports the capability surface from
// `sdk/runanywhere-commons/include/rac/core/capabilities/rac_lifecycle.h`.
//
// Every L3 service (LLM, STT, TTS, VAD, ...) transitions through this
// enum in order. Frontends observe the state via a callback registered
// at session-create time; consumers typically display a spinner until
// state reaches READY and then surface errors at ERROR.

#ifndef RA_LIFECYCLE_H
#define RA_LIFECYCLE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ra_lifecycle_state_t;

enum {
    RA_LIFECYCLE_UNINITIALIZED = 0,   // created but not bootstrapped
    RA_LIFECYCLE_INITIALIZING  = 1,   // dependencies being wired up
    RA_LIFECYCLE_READY         = 2,   // capabilities registered, waiting
    RA_LIFECYCLE_LOADING       = 3,   // model download / load in flight
    RA_LIFECYCLE_LOADED        = 4,   // model resident, ready to run
    RA_LIFECYCLE_RUNNING       = 5,   // actively processing a request
    RA_LIFECYCLE_ERROR         = 6,   // terminal error; consult ra_status_t
    RA_LIFECYCLE_DESTROYING    = 7,   // teardown in progress
};

// Returns a human-readable state name. Never NULL.
const char* ra_lifecycle_state_str(ra_lifecycle_state_t state);

// Lifecycle transition callback — fired on every state change.
typedef void (*ra_lifecycle_callback_t)(ra_lifecycle_state_t prev,
                                         ra_lifecycle_state_t next,
                                         void*                user_data);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_LIFECYCLE_H
