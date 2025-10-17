#ifndef CPU_FEATURES_H
#define CPU_FEATURES_H

#include <string>

namespace cpu_features {

/**
 * Detects ARM CPU features by reading /proc/cpuinfo
 * Returns the best available library variant suffix
 */
std::string detect_best_variant();

/**
 * Check individual CPU features
 */
bool has_fp16();
bool has_dotprod();
bool has_i8mm();
bool has_sve();

/**
 * Get CPU info string for debugging
 */
std::string get_cpu_info();

} // namespace cpu_features

#endif // CPU_FEATURES_H
