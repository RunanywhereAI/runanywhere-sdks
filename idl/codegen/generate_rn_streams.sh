#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# generate_rn_streams.sh — compatibility entrypoint for shared TS stream
# wrappers. RN and Web now consume @runanywhere/proto-ts.
#
# Uses the in-tree Nunjucks template at
# idl/codegen/templates/ts_async_iterable.njk. The actual rendering is done
# by a tiny Node helper invoked once per (service, rpc, response) triple.
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
    echo "error: node not found. GAP 09 RN stream codegen requires Node 18+." >&2
    exit 127
fi

# Tuples = (service_name, service_lower, request_type, response_type, rpc_name, request_module, response_module)
# Request and response modules are separate so a service whose response type
# lives in a different proto file (e.g. VoiceAgent's response is VoiceEvent
# from voice_events.proto, not voice_agent_service.proto) renders correctly.
RENDER_NODE_SCRIPT="
const fs = require('fs');
const tpl = fs.readFileSync('${TEMPLATE}', 'utf8');
function render(vars) {
    return Object.keys(vars).reduce(
        (acc, k) => acc.replaceAll('{{ ' + k + ' }}', vars[k])
                       .replaceAll('{{ ' + k + ' | lower }}', vars[k].toLowerCase()),
        tpl.replace(/\{#[\s\S]*?#\}\\n?/g, ''));
}
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
