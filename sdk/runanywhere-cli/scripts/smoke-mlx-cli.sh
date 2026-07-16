#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

CLI="${RUNANYWHERE_MLX_CLI:-$REPO_ROOT/.build/debug/RunAnywhereMLXCLI}"
HOME_DIR="${RUNANYWHERE_MLX_SMOKE_HOME:-/tmp/runanywhere-mlx-cli-smoke}"
PULL_MODE="${RUNANYWHERE_MLX_SMOKE_PULL:-1}"

LLM_MODEL="${RUNANYWHERE_MLX_SMOKE_LLM:-mlx-qwen3-0.6b-4bit}"
VLM_MODEL="${RUNANYWHERE_MLX_SMOKE_VLM:-mlx-fastvlm-0.5b-bf16}"
STT_MODEL="${RUNANYWHERE_MLX_SMOKE_STT:-mlx-qwen3-asr-0.6b-8bit}"
TTS_MODEL="${RUNANYWHERE_MLX_SMOKE_TTS:-mlx-soprano-1.1-80m-5bit}"

if [[ ! -x "$CLI" || ! -f "$(dirname "$CLI")/mlx.metallib" ]]; then
  "$SCRIPT_DIR/build-mlx-cli.sh"
fi

mkdir -p "$HOME_DIR"

pull_if_enabled() {
  local model="$1"
  if [[ "$PULL_MODE" == "1" ]]; then
    "$CLI" --home "$HOME_DIR" pull "$model"
  fi
}

require_nonempty_file() {
  local path="$1"
  if [[ ! -s "$path" ]]; then
    echo "expected non-empty file: $path" >&2
    exit 1
  fi
}

require_nonempty_text() {
  local label="$1"
  local value="$2"
  if [[ -z "${value//[[:space:]]/}" ]]; then
    echo "$label produced empty output" >&2
    exit 1
  fi
}

make_default_image() {
  local out="$1"
  base64 --decode >"$out" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAGQAAABkCAIAAAD/gAIDAAAAiklEQVR4nO3QQQ3AIADAQMDwMPrvQJkQxZbB7iTn9cw7wF2mB6wH7AbYDbAbYDfAbgDdALsBdgPsBtgNsBtgN8BugN0AuwF2A+wG2A2wG2A3wG6A3QC7AXYD7AbYDbAbYDfAboDdALsBdgPsBtgNsBtgN8BugN0AuwF2A+wG2A2wG2A3wG6A3QC7AXYDXBuUBgGkrp6WAAAAAElFTkSuQmCC
PNG
}

echo "MLX CLI backend smoke"
"$CLI" --home "$HOME_DIR" backends --json | grep -q '"name":"mlx"'
"$CLI" --home "$HOME_DIR" backends --json | grep -q '"name":"llamacpp"'

echo "LLM: $LLM_MODEL"
pull_if_enabled "$LLM_MODEL"
llm_output="$("$CLI" --home "$HOME_DIR" run "$LLM_MODEL" "Say OK in one short sentence." --max-tokens 16 --temp 0.1)"
require_nonempty_text "LLM" "$llm_output"
printf '%s\n' "$llm_output"

echo "TTS: $TTS_MODEL"
pull_if_enabled "$TTS_MODEL"
tts_wav="$HOME_DIR/mlx-smoke-tts.wav"
rm -f "$tts_wav"
"$CLI" --home "$HOME_DIR" tts "$TTS_MODEL" --text "Hello from MLX text to speech." --output "$tts_wav"
require_nonempty_file "$tts_wav"

echo "STT: $STT_MODEL"
pull_if_enabled "$STT_MODEL"
stt_output="$("$CLI" --home "$HOME_DIR" stt "$STT_MODEL" --input "$tts_wav")"
require_nonempty_text "STT" "$stt_output"
printf '%s\n' "$stt_output"

echo "VLM: $VLM_MODEL"
pull_if_enabled "$VLM_MODEL"
image_path="${RUNANYWHERE_MLX_SMOKE_IMAGE:-$HOME_DIR/mlx-smoke-image.png}"
if [[ -z "${RUNANYWHERE_MLX_SMOKE_IMAGE:-}" ]]; then
  make_default_image "$image_path"
fi
vlm_output="$("$CLI" --home "$HOME_DIR" run "$VLM_MODEL" --image "$image_path" \
  "Describe the image in one short sentence." --max-tokens 32 --temp 0.1)"
require_nonempty_text "VLM" "$vlm_output"
printf '%s\n' "$vlm_output"

echo "MLX CLI smoke passed"
