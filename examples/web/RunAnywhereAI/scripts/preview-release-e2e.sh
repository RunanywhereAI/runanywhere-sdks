#!/usr/bin/env bash
set -euo pipefail

# A real HTTPS origin keeps the local release journey faithful to production:
# the production SDK configuration remains HTTPS and browser requests exercise
# Vite's same-origin control-plane relay instead of disabling CORS in Chrome.
cert_dir="$(mktemp -d "${TMPDIR:-/tmp}/runanywhere-web-e2e.XXXXXX")"
cleanup() {
  rm -rf "$cert_dir"
}
trap cleanup EXIT INT TERM

key_path="$cert_dir/localtest.me-key.pem"
cert_path="$cert_dir/localtest.me-cert.pem"

openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 1 \
  -keyout "$key_path" \
  -out "$cert_path" \
  -subj '/CN=localtest.me' \
  -addext 'subjectAltName=DNS:localtest.me' \
  >/dev/null 2>&1

export RA_E2E_HTTPS_KEY_PATH="$key_path"
export RA_E2E_HTTPS_CERT_PATH="$cert_path"

npm run build
npm run preview -- --host 127.0.0.1 --port 43173 --strictPort
