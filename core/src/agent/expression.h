// SPDX-License-Identifier: Apache-2.0
//
// `{{ Node Name.field.path }}` resolution against the outputs of nodes that
// have already run.
//
// A reference that cannot be resolved is an error, not an empty string. A
// workflow that quietly substitutes nothing produces a wrong answer that looks
// like a right one, which is worse than a failed node the canvas can point at.

#pragma once

#include <string>
#include <unordered_map>
#include <vector>

namespace rac::agent {

struct ExpressionContext {
    /// Node display name to the JSON bodies of that node's output items.
    std::unordered_map<std::string, std::vector<std::string>> node_outputs;

    /// Bound to `item` while a loop body runs.
    bool has_current_item = false;
    std::string current_item_json;
};

/// Substitute every `{{ ... }}` in @p expression.
///
/// When the whole expression is a single reference, the resolved value is
/// returned verbatim, so an object or array survives as JSON instead of being
/// flattened to a string. Mixed text and references always yields a string.
///
/// Returns false and fills @p out_error on an unresolvable reference or
/// unbalanced braces.
bool resolve_expression(const std::string& expression, const ExpressionContext& context,
                        std::string* out_value, std::string* out_error);

}  // namespace rac::agent
