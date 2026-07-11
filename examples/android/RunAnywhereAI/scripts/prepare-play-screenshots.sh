#!/usr/bin/env bash

set -euo pipefail

if (( $# < 2 )); then
  echo "Usage: $0 OUTPUT_DIR SCREENSHOT.png [SCREENSHOT.png ...]" >&2
  exit 2
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick 7 (magick) is required." >&2
  exit 1
fi

output_dir=$1
shift
mkdir -p "$output_dir"

for input in "$@"; do
  if [[ ! -f "$input" ]]; then
    echo "Missing screenshot: $input" >&2
    exit 1
  fi

  read -r width height < <(magick identify -format '%w %h\n' "$input")
  if [[ "$width" != 1440 || "$height" != 3200 ]]; then
    echo "Expected a 1440x3200 device capture, got ${width}x${height}: $input" >&2
    exit 1
  fi

  output="$output_dir/$(basename "$input")"
  magick "$input" \
    -colorspace sRGB \
    -background '#141414' \
    -alpha remove -alpha off \
    -gravity center -extent 1800x3200 \
    "PNG24:$output"

  read -r out_width out_height image_type depth < <(
    magick identify -format '%w %h %[type] %z\n' "$output"
  )
  if [[ "$out_width" != 1800 || "$out_height" != 3200 || "$image_type" != TrueColor || "$depth" != 8 ]]; then
    echo "Invalid Play screenshot output: $output" >&2
    exit 1
  fi
done

(
  cd "$output_dir"
  shasum -a 256 -- *.png > SHA256SUMS
)

echo "Prepared $(($#)) Play phone screenshot(s) in $output_dir"
