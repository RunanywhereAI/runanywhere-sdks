#ifndef RAC_SWIFT_PRIMITIVE_FORWARDER_H
#define RAC_SWIFT_PRIMITIVE_FORWARDER_H

// Forwarder, not a copy. These four headers define the plugin ABI
// (RAC_PLUGIN_API_VERSION, the vtable layout, the primitive wire values). A
// duplicated copy here silently went stale twice -- it never received the ABI v9
// rerank promotion, so this mirror still called wire value 11 "reserved" while
// commons had shipped it as RAC_PRIMITIVE_RERANK. Forwarding to the canonical
// header makes that drift impossible; core/include is already on the search path,
// as the 28 other forwarders in this directory show.
#include "rac/plugin/rac_primitive.h"

#endif  // RAC_SWIFT_PRIMITIVE_FORWARDER_H
