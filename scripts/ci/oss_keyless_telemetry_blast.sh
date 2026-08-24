#!/usr/bin/env bash
# Retired from runanywhere-sdks. The CLI (and its telemetry blast) lives in
# RunanywhereAI/RCLI — build rcli against a published C++ desktop kit, then:
#   rcli telemetry blast ...
echo "oss_keyless_telemetry_blast.sh no longer builds in-tree rcli." >&2
echo "Use RunanywhereAI/RCLI (scripts/e2e.sh / rcli telemetry blast) against a released kit." >&2
exit 2
