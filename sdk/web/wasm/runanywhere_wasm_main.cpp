// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Emscripten entry point — stitches the C ABI into a WASM module. All
// engine plugins are compiled in statically (RA_STATIC_PLUGINS=ON), so they
// self-register at ctor-init time. The C ABI functions are exported by
// Emscripten linker flags (see CMakeLists.txt).

// No custom code needed beyond keeping the dynamic-init side effects alive.
// The static initializers in each engine plugin run before main() and call
// ra_registry_register_static().
int main() { return 0; }
