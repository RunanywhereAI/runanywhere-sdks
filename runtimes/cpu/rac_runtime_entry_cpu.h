/**
 * @file rac_runtime_entry_cpu.h
 * @brief Public entry-point declaration for the built-in CPU runtime plugin.
 *
 * Task T4.1 — the CPU runtime is always-available. Consumers who want to
 * force a static link (so the registrar TU survives iOS's dead-symbol
 * stripper) should reference `rac_runtime_static_marker_cpu` or call
 * `rac_runtime_entry_cpu()` directly from host init.
 */

#ifndef RAC_RUNTIMES_CPU_ENTRY_H
#define RAC_RUNTIMES_CPU_ENTRY_H

#include "rac/plugin/rac_runtime_vtable.h"

#ifdef __cplusplus
extern "C" {
#endif

RAC_RUNTIME_ENTRY_DECL(cpu);

#ifdef __cplusplus
}
#endif

#endif /* RAC_RUNTIMES_CPU_ENTRY_H */
