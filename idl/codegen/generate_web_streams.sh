#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# generate_web_streams.sh — compatibility entrypoint for shared TS stream
# wrappers. RN and Web now consume @runanywhere/proto-ts.
#
# The transport interface is identical at the type level — what plugs into
# `transport.subscribe()` differs (Nitro callback vs Emscripten callback)
# but the consumer signature (AsyncIterable<T>) is the same.
#
# Output:
#   sdk/runanywhere-proto-ts/src/streams/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-proto-ts/src/streams"
TEMPLATE="${SCRIPT_DIR}/templates/ts_async_iterable.njk"

mkdir -p "${OUT_DIR}"

if ! command -v node >/dev/null 2>&1; then
    echo "error: node not found. GAP 09 Web stream codegen requires Node 18+." >&2
    exit 127
fi

RENDER_NODE_SCRIPT="
const fs = require('fs');
const tpl = fs.readFileSync('${TEMPLATE}', 'utf8');
function render(vars) {
    return Object.keys(vars).reduce(
        (acc, k) => acc.replaceAll('{{ ' + k + ' }}', vars[k])
                       .replaceAll('{{ ' + k + ' | lower }}', vars[k].toLowerCase()),
        tpl.replace(/\{#[\s\S]*?#\}\\n?/g, ''));
}
// Tuples = (service_name, service_lower, request_type, response_type, rpc_name, request_module, response_module)
// Separate request/response modules so a service whose response type lives
// in a different proto file (VoiceAgent's VoiceEvent is in voice_events.proto)
// renders correctly.
const tuples = [
    ['VoiceAgent', 'voice_agent', 'VoiceAgentRequest',      'VoiceEvent',       'Stream',    '../voice_agent_service', '../voice_events'],
    ['LLM',        'llm',         'LLMGenerateRequest',     'LLMStreamEvent',   'Generate',  '../llm_service',         '../llm_service'],
    ['Download',   'download',    'DownloadSubscribeRequest','DownloadProgress','Subscribe', '../download_service',    '../download_service'],
];
for (const [s, l, req, resp, rpc, reqMod, respMod] of tuples) {
    const out = '${OUT_DIR}/' + l + '_service_stream.ts';
    const vars = { service_name: s, service_lower: l, request_type: req, response_type: resp, rpc_name: rpc, request_module: reqMod, response_module: respMod };
    fs.writeFileSync(out, render(vars));
    console.log('  wrote', out);
}
"

node -e "${RENDER_NODE_SCRIPT}"
echo "✓ shared TS AsyncIterable streams → ${OUT_DIR}"
