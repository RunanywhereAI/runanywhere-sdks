/** Test seam for QHexRT's probe-independent catalog decision. */

#ifndef RAC_QHEXRT_MODEL_CATALOG_INTERNAL_H
#define RAC_QHEXRT_MODEL_CATALOG_INTERNAL_H

#include "rac/qhexrt/rac_qhexrt.h"

namespace rac::qhexrt::catalog {

rac_result_t register_for_arch_proto(const uint8_t* request_bytes, size_t request_size,
                                     rac_qhexrt_hexagon_arch_t detected_arch,
                                     rac_bool_t engine_available, rac_bool_t* out_registered,
                                     rac_proto_buffer_t* out_model);

/** One row of the arch/auth policy table, as the catalog actually stores it. */
struct PolicyRow {
    const char* id;
    uint8_t arch_mask;
    bool requires_hf_auth;
};

/**
 * Test seam: read row @p index of the policy table, false when out of range.
 *
 * Exposed so tests can drive their expectations off the table itself. Copying
 * the arch sets into the test by hand is what let them drift behind catalog
 * rows (lfm2_5_2_6b, and the three cosmos3_edge_* rows, were all granted archs
 * the test still denied).
 */
bool policy_row_at(size_t index, PolicyRow* out_row);

/** The bit @p arch occupies in PolicyRow::arch_mask. */
uint8_t policy_arch_bit(rac_qhexrt_hexagon_arch_t arch);

}  // namespace rac::qhexrt::catalog

#endif  // RAC_QHEXRT_MODEL_CATALOG_INTERNAL_H
