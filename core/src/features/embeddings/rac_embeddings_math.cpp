/**
 * @file rac_embeddings_math.cpp
 * @brief Backend-independent vector calculations for embeddings.
 */

#include <cmath>

#include "rac/core/rac_error.h"
#include "rac/features/embeddings/rac_embeddings_types.h"

namespace {

double squared_norm(const float* vector, size_t dimension) {
    double sum_squares = 0.0;
    for (size_t i = 0; i < dimension; ++i) {
        const double value = static_cast<double>(vector[i]);
        sum_squares += value * value;
    }
    return sum_squares;
}

}  // namespace

extern "C" {

rac_result_t rac_embeddings_norm(const float* vector, size_t dimension, float* out_norm) {
    if (!out_norm || (!vector && dimension > 0)) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_norm =
        dimension == 0 ? 0.0f : static_cast<float>(std::sqrt(squared_norm(vector, dimension)));
    return RAC_SUCCESS;
}

rac_result_t rac_embeddings_similarity(const float* lhs, size_t lhs_dimension, const float* rhs,
                                       size_t rhs_dimension, float* out_similarity) {
    if (!out_similarity || (!lhs && lhs_dimension > 0) || (!rhs && rhs_dimension > 0)) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_similarity = 0.0f;
    if (lhs_dimension == 0 || lhs_dimension != rhs_dimension) {
        return RAC_SUCCESS;
    }

    double dot_product = 0.0;
    for (size_t i = 0; i < lhs_dimension; ++i) {
        dot_product += static_cast<double>(lhs[i]) * static_cast<double>(rhs[i]);
    }

    const double lhs_norm = std::sqrt(squared_norm(lhs, lhs_dimension));
    const double rhs_norm = std::sqrt(squared_norm(rhs, rhs_dimension));
    if (lhs_norm == 0.0 || rhs_norm == 0.0) {
        return RAC_SUCCESS;
    }

    *out_similarity = static_cast<float>(dot_product / (lhs_norm * rhs_norm));
    return RAC_SUCCESS;
}

}  // extern "C"
