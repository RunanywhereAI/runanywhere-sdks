/* Public-ABI smoke for the C++ desktop kit. No protobuf, no CLI. */
#include <stdio.h>
#include <string.h>

#include "rac/core/rac_core.h"

int main(void) {
    const rac_version_t version = rac_get_version();
    if (version.string == NULL || version.string[0] == '\0') {
        fprintf(stderr, "rac_get_version returned an empty string\n");
        return 1;
    }
    printf("RunAnywhere %s (%u.%u.%u)\n", version.string, (unsigned)version.major,
           (unsigned)version.minor, (unsigned)version.patch);
    return 0;
}
