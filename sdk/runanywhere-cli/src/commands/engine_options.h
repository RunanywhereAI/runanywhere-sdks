/**
 * @file engine_options.h
 * @brief Shared parsing for rcli engine/framework hints.
 */

#ifndef RCLI_COMMANDS_ENGINE_OPTIONS_H
#define RCLI_COMMANDS_ENGINE_OPTIONS_H

#include <string>

#include "model_types.pb.h"

namespace rcli::commands {

bool parse_engine_hint(const std::string& engine,
                       runanywhere::v1::InferenceFramework* out_framework,
                       std::string* error);

}  // namespace rcli::commands

#endif  // RCLI_COMMANDS_ENGINE_OPTIONS_H
