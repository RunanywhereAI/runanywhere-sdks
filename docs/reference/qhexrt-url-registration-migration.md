# QHexRT URL registration migration

The native curated catalog and its `rac_qhexrt_catalog_*` C ABI are removed by
the explicit URL registration refactor in #685. Flutter, React Native, and Kotlin remove
`QHexRT.modelSupportsArchitecture`, `QHexRT.modelRequiresHfAuth`, and
`QHexRT.registerModelForDevice` as part of retiring their QHexRT catalog facades. Consumers
must migrate these calls before upgrading; this is a breaking API removal.

Applications own their curated model list, eligibility restrictions, and any
HF-auth preflight. Probe the device with `QHexRT.probeNpu()`, filter the list,
and submit eligible models through `RunAnywhere.models.register()`.

Commons and the engine still resolve logical bundle references, register model
metadata, and manage downloads and inference. For logical bundle references,
registration validates known architecture pins in the first repository folder
(such as `/v79` or `/v79/model.json`) against the current device before network
resolution or registry changes. Matching pins are preserved; mismatches return
`RAC_ERROR_INVALID_ARGUMENT`. Direct `/resolve/` or `/blob/` URLs register a single
file and do not receive this bundle-folder check, so callers must filter any
incompatible direct URLs before registration.

Kotlin's `ModelRegistration.url`, `ModelRegistration.archive`, and
`ModelRegistration.multiFile` factories, and the deprecated URL, archive, and
multi-file `registerModel` overloads, keep their original positional parameter
order. New metadata parameters are appended.
Hidden forwarding overloads retain the original JVM methods and default-argument
bridges for consumers already compiled against the older signatures. New code
should use `RunAnywhere.models.register(ModelRegistration...)`.

