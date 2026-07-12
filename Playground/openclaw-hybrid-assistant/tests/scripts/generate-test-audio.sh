#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIO_DIR="${SCRIPT_DIR}/../audio"

for command in sox espeak; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "error: ${command} is required to generate test audio" >&2
        exit 1
    fi
done

mkdir -p "${AUDIO_DIR}"
temporary_wav="$(mktemp "${TMPDIR:-/tmp}/openclaw-speech.XXXXXX.wav")"
trap 'rm -f "${temporary_wav}"' EXIT

sox -n -r 16000 -c 1 -b 16 "${AUDIO_DIR}/silence.wav" trim 0.0 3.0
sox -n -r 16000 -c 1 -b 16 "${AUDIO_DIR}/noise.wav" synth 3.0 pinknoise vol 0.05
espeak -w "${temporary_wav}" "What is the weather today?"
sox "${temporary_wav}" -r 16000 -c 1 -b 16 "${AUDIO_DIR}/speech.wav" pad 0.25 1.5

echo "Generated 16 kHz fixtures in ${AUDIO_DIR}:"
printf '  %s\n' silence.wav noise.wav speech.wav
