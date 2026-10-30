# QHexRT URL registration migration

The native curated catalog and its `rac_qhexrt_catalog_*` C ABI are removed by
the explicit URL registration refactor in #685. Both Flutter and React Native remove
`QHexRT.modelSupportsArchitecture`, `QHexRT.modelRequiresHfAuth`, and
`QHexRT.registerModelForDevice` as part of retiring their QHexRT catalog facades. Consumers
must migrate these calls before upgrading; this is a breaking API removal.

Applications own their curated model list, eligibility restrictions, and any
HF-auth preflight. Probe the device with `QHexRT.probeNpu()`, filter the list,
and submit eligible models through `RunAnywhere.models.register()`.

Commons and the engine still resolve logical bundle references, register model
metadata, and manage downloads and inference. Explicitly pinned variant URLs
are preserved; registration does not validate a pinned architecture against the
current device. Callers must reject incompatible pins before registration.

Kotlin's deprecated URL, archive, and multi-file `registerModel` overloads keep
their original positional parameter order. New metadata parameters are appended.
Hidden forwarding overloads retain the original JVM methods and default-argument
bridges for consumers already compiled against the older signatures. New code
should use `RunAnywhere.models.register(ModelRegistration...)`.

