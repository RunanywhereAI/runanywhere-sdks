// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_version.h"

#ifndef RA_BUILD_INFO_STRING
#define RA_BUILD_INFO_STRING "2.0.0+dev"
#endif

unsigned int ra_abi_version(void) {
    return RA_ABI_VERSION;
}

unsigned int ra_plugin_api_version(void) {
    return RA_PLUGIN_API_VERSION;
}

const char* ra_build_info(void) {
    return RA_BUILD_INFO_STRING;
}
