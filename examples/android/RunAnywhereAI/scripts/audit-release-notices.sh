#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STRICT=0
APK=""

usage() {
    echo "Usage: $0 [--strict] [--apk PATH]" >&2
    echo "  --strict  Fail when a local RunAnywhere AAR has no notice evidence or --apk is omitted." >&2
    echo "  --apk     Inspect the exact release APK that will be archived or submitted." >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict)
            STRICT=1
            shift
            ;;
        --apk)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            APK="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

for command_name in jq python3 unzip shasum; do
    command -v "$command_name" >/dev/null || {
        echo "ERROR: required command not found: $command_name" >&2
        exit 2
    }
done

cd "$APP_ROOT"
./gradlew \
    :app:generateReleaseSbom \
    --no-daemon \
    --max-workers=2

SBOM="app/build/reports/release-sbom.cdx.json"
INVENTORY="app/build/reports/release-notice-inventory.json"
python3 scripts/generate-release-notice-inventory.py \
    --sbom "$SBOM" \
    --local-aars libs \
    --output "$INVENTORY"

jq -e '
    .bomFormat == "CycloneDX" and
    .specVersion == "1.5" and
    (.components | type == "array")
' "$SBOM" >/dev/null
jq -e '
    .schemaVersion == 1 and
    (.components | type == "array") and
    (.componentCount == (.components | length)) and
    (.componentsWithNoticeEntries + .componentsWithoutNoticeEntries == .componentCount)
' "$INVENTORY" >/dev/null

# Both reports must describe the same exact artifact coordinates and hashes.
if ! diff -u \
    <(jq -S '[.components[] | {group, name, version, sha256: .hashes[0].content}]' "$SBOM") \
    <(jq -S '[.components[] | {group, name, version, sha256}]' "$INVENTORY") \
    >/dev/null; then
    echo "ERROR: SBOM and notice inventory component hashes differ" >&2
    exit 1
fi

expected_aars=(
    runanywhere-sdk
    runanywhere-llamacpp
    runanywhere-onnx
    runanywhere-qhexrt
)
for name in "${expected_aars[@]}"; do
    count="$(jq --arg name "$name" '[
        .components[] |
        select(.group == "com.runanywhere.local" and .name == $name)
    ] | length' "$INVENTORY")"
    if [[ "$count" -ne 1 ]]; then
        echo "ERROR: expected exactly one local AAR component named $name, found $count" >&2
        exit 1
    fi
done

echo "SBOM: $SBOM"
echo "Notice inventory: $INVENTORY"
echo "Components: $(jq -r '.componentCount' "$INVENTORY")"
echo "Components with notice-like archive paths: $(jq -r '.componentsWithNoticeEntries' "$INVENTORY")"
echo "Components without notice-like archive paths: $(jq -r '.componentsWithoutNoticeEntries' "$INVENTORY")"
echo
echo "Local AAR notice evidence:"
jq -r '
    .components[] |
    select(.group == "com.runanywhere.local") |
    "  \(.name): \(if (.noticeEntries | length) == 0 then "MISSING" else (.noticeEntries | join(", ")) end)"
' "$INVENTORY"

missing_local="$(jq '[
    .components[] |
    select(.group == "com.runanywhere.local" and (.noticeEntries | length) == 0)
] | length' "$INVENTORY")"

if [[ -n "$APK" ]]; then
    if [[ "$APK" != /* ]]; then
        APK="$APP_ROOT/$APK"
    fi
    [[ -f "$APK" ]] || { echo "ERROR: APK not found: $APK" >&2; exit 2; }
    apk_notice_entries="$(unzip -Z1 "$APK" | grep -E -i '(^|/)(license|notice|copying|copyright)([._/-].*|$)' || true)"
    apk_notice_count="$(printf '%s\n' "$apk_notice_entries" | sed '/^$/d' | wc -l | tr -d ' ')"
    echo
    echo "APK SHA-256: $(shasum -a 256 "$APK" | awk '{print $1}')"
    echo "APK notice-like paths: $apk_notice_count"
    if [[ -n "$apk_notice_entries" ]]; then
        printf '%s\n' "$apk_notice_entries" | sed 's/^/  /'
    fi
elif [[ "$STRICT" -eq 1 ]]; then
    echo "ERROR: --strict requires --apk with the exact release artifact" >&2
    exit 1
fi

echo
echo "This is archive evidence, not legal approval. Review docs/THIRD_PARTY_NOTICES_AUDIT.md."

if [[ "$STRICT" -eq 1 && "$missing_local" -ne 0 ]]; then
    echo "ERROR: $missing_local local RunAnywhere AAR(s) have no packaged notice evidence" >&2
    exit 1
fi
