/** Test seam for QHexRT's probe-independent catalog decision. */

#ifndef RAC_QHEXRT_MODEL_CATALOG_INTERNAL_H
#define RAC_QHEXRT_MODEL_CATALOG_INTERNAL_H

#include "rac/qhexrt/rac_qhexrt.h"

namespace rac::qhexrt::catalog {

rac_result_t register_for_arch_proto(const uint8_t* request_bytes, size_t request_size,
                                     rac_qhexrt_hexagon_arch_t detected_arch,
                                     rac_bool_t engine_available, rac_bool_t* out_registered,
                                     rac_proto_buffer_t* out_model);

}  // namespace rac::qhexrt::catalog

#endif  // RAC_QHEXRT_MODEL_CATALOG_INTERNAL_H
