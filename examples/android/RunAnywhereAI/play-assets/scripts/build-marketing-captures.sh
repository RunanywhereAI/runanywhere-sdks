#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RAW_DIR="${ASSET_ROOT}/screenshots/v81"
OUTPUT_DIR="${ASSET_ROOT}/play-console/phone"
ICON="${ASSET_ROOT}/play-console/icon/play-icon-512.png"

command -v magick >/dev/null 2>&1 || {
    echo "ImageMagick 7 is required (missing: magick)" >&2
    exit 1
}

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/runanywhere-play-assets.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

render_capture() {
    local source="$1"
    local output="$2"
    local headline="$3"
    local subtitle="$4"
    local card_one_title="$5"
    local card_one_body="$6"
    local card_two_title="$7"
    local card_two_body="$8"
    local card_three_title="$9"
    local card_three_body="${10}"
    local screenshot_card="${TMP_DIR}/$(basename "${output}" .png)-screen.png"

    magick "${source}" \
        -crop 3032x1440+0+0 +repage \
        -resize 1540x \
        -bordercolor '#3a3a3d' -border 5 \
        "${screenshot_card}"

    magick -size 1800x3200 gradient:'#171719-#09090a' \
        -fill 'rgba(255,91,0,0.10)' -draw 'circle 1700,100 2180,100' \
        \( "${ICON}" -resize 88x88 \) -geometry +120+95 -composite \
        -font Arial-Bold -pointsize 54 -fill '#f5f5f5' \
        -gravity NorthWest -annotate +232+108 'RunAnywhere' \
        -font Arial-Bold -pointsize 118 -fill '#ffffff' \
        -annotate +120+260 "${headline}" \
        -font Arial -pointsize 52 -fill '#b7b7bb' \
        -annotate +120+555 "${subtitle}" \
        \( "${screenshot_card}" -background '#000000' -shadow 60x18+0+24 \) \
        -geometry +130+790 -composite \
        "${screenshot_card}" -geometry +130+760 -composite \
        -fill '#171719' -stroke '#2d2d31' -strokewidth 3 \
        -draw 'roundrectangle 120,1690 1680,2020 38,38' \
        -draw 'roundrectangle 120,2100 1680,2430 38,38' \
        -draw 'roundrectangle 120,2510 1680,2840 38,38' \
        -stroke none -fill '#ff5b00' -font Arial-Bold -pointsize 60 \
        -annotate +175+1750 "${card_one_title}" \
        -annotate +175+2160 "${card_two_title}" \
        -annotate +175+2570 "${card_three_title}" \
        -fill '#d0d0d3' -font Arial -pointsize 42 \
        -annotate +175+1840 "${card_one_body}" \
        -annotate +175+2250 "${card_two_body}" \
        -annotate +175+2660 "${card_three_body}" \
        -alpha off -depth 8 -strip "PNG24:${output}"

    local metadata
    metadata="$(magick identify -format '%wx%h|%[type]|%z' "${output}")"
    if [[ "${metadata}" != '1800x3200|TrueColor|8' ]]; then
        echo "Unexpected output metadata for ${output}: ${metadata}" >&2
        exit 1
    fi
}

mkdir -p "${OUTPUT_DIR}"

render_capture \
    "${RAW_DIR}/06-qhexrt-v81-landscape.png" \
    "${OUTPUT_DIR}/06-qhexrt-v81.png" \
    $'Local models.\nReal NPU.' \
    'Qwen3.5 running locally on a Hexagon v81 NPU' \
    'Hexagon v81 acceleration' \
    'QHexRT and QNN execute the model on-device.' \
    'On-device model execution' \
    'Generation runs locally after model download.' \
    'Performance you can see' \
    'TTFT, tokens, and throughput after every answer.'

render_capture \
    "${RAW_DIR}/07-web-search-landscape.png" \
    "${OUTPUT_DIR}/07-web-search.png" \
    $'Local intelligence.\nLive answers.' \
    'Search the web only when you choose' \
    'Search on your terms' \
    'Web access stays off until you enable it.' \
    'Visible tool traces' \
    'See when search_web is invoked.' \
    'Source-aware replies' \
    'Answers include the source URL used.'

echo "Prepared Play phone captures:"
magick identify -format '%w x %h | %[type] | %z-bit | %i\n' \
    "${OUTPUT_DIR}/06-qhexrt-v81.png" \
    "${OUTPUT_DIR}/07-web-search.png"
