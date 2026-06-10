/**
 * @file rac_embeddings_proto_adapters.h
 * @brief Embeddings C ABI <-> proto adapters (split out of foundation/rac_proto_adapters.h
 *        to restore commons header layering: foundation/ MUST NOT depend on features/).
 */

#ifndef RAC_EMBEDDINGS_PROTO_ADAPTERS_H
#define RAC_EMBEDDINGS_PROTO_ADAPTERS_H

#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
#include <cstddef>
#include <cstdint>
#endif

#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_types.h"

#ifdef __cplusplus

namespace runanywhere::v1 {
class EmbeddingsConfiguration;
class EmbeddingsOptions;
class EmbeddingsResult;
class EmbeddingVector;
}  // namespace runanywhere::v1

namespace rac::foundation {

bool rac_embeddings_options_from_proto(const ::runanywhere::v1::EmbeddingsOptions& in,
                                       rac_embeddings_options_t* out);

bool rac_embedding_vector_to_proto(const rac_embedding_vector_t* in,
                                   ::runanywhere::v1::EmbeddingVector* out);
bool rac_embedding_vector_from_proto(const ::runanywhere::v1::EmbeddingVector& in,
                                     rac_embedding_vector_t* out);

bool rac_embeddings_result_to_proto(const rac_embeddings_result_t* in,
                                    ::runanywhere::v1::EmbeddingsResult* out);
}  // namespace rac::foundation

#endif  // __cplusplus

#endif  // RAC_EMBEDDINGS_PROTO_ADAPTERS_H
