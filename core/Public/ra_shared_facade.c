// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// One-line sentinel source for the racommons_core shared library target.
// The actual ra_* / rac_* symbols come from the static archives linked in
// via -Wl,-all_load. This file exists solely to give CMake a compilation
// unit for the SHARED target declaration.

const int ra_shared_facade_loaded = 1;
