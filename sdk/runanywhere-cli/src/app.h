/**
 * @file app.h
 * @brief Shared rcli app wiring for the binary and in-process tests.
 */

#ifndef RCLI_APP_H
#define RCLI_APP_H

#include <CLI11.hpp>

#include "bootstrap.h"

namespace rcli {

void configure_app(CLI::App& app, GlobalOptions& options);
int run(int argc, char** argv);

}  // namespace rcli

#endif  // RCLI_APP_H
