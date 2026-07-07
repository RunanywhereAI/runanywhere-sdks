/**
 * @file main.cpp
 * @brief rcli — RunAnywhere desktop CLI entry point.
 *
 * Thin dispatch layer: global flags + CLI11 subcommands. All real work
 * happens in commons behind the rac_* C ABI (see AGENTS.md layering rule).
 *
 * Exit codes: 0 success, 1 runtime/SDK error, 2 usage error.
 */

#include "app.h"

int main(int argc, char** argv) {
    return rcli::run(argc, argv);
}
