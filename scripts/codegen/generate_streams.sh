#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
    cat <<EOF
Usage: scripts/codegen/generate_streams.sh

Render the shared TypeScript AsyncIterable stream wrappers for every
server-streaming RPC. Both RN and Web consume the generated files via the
@runanywhere/proto-ts package, so a single render pass writes the canonical
output once.

Uses the Nunjucks template at scripts/codegen/templates/ts_async_iterable.njk,
rendered by a small Node helper once per (service, rpc, response) triple.

Output: sdk/shared/proto-ts/src/streams/
EOF
}

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $arg" ;;
    esac
done

OUT_DIR="${RAC_ROOT}/sdk/shared/proto-ts/src/streams"
TEMPLATE="${SCRIPT_DIR}/templates/ts_async_iterable.njk"

mkdir -p "${OUT_DIR}"

if ! command -v node >/dev/null 2>&1; then
    error "node not found. Stream codegen requires Node 18+."
    exit 127
fi

# Tuples = (service_name, service_lower, request_type, response_type, rpc_name, request_module, response_module)
# Request and response modules are separate so a service whose response type
# lives in a different proto file (e.g. VoiceAgent's response is VoiceEvent
# from voice_events.proto) renders correctly.
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
    ['VoiceAgent',       'voice_agent',       'VoiceAgentRequest',          'VoiceEvent',                  'Stream',         '../voice_agent_service', '../voice_events'],
    ['LLM',              'llm',               'LLMGenerateRequest',         'LLMStreamEvent',              'Generate',       '../llm_service',         '../llm_service'],
    ['Download',         'download',          'DownloadSubscribeRequest',   'DownloadProgress',            'Subscribe',      '../download_service',    '../download_service'],
    ['VLM',              'vlm',               'VLMGenerationRequest',       'VLMStreamEvent',              'Stream',         '../vlm_options',         '../vlm_options'],
    ['STT',              'stt',               'STTTranscriptionRequest',    'STTStreamEvent',              'Stream',         '../stt_options',         '../stt_options'],
    ['TTS',              'tts',               'TTSSynthesisRequest',        'TTSStreamEvent',              'Stream',         '../tts_options',         '../tts_options'],
    ['VAD',              'vad',               'VADProcessRequest',          'VADStreamEvent',              'Stream',         '../vad_options',         '../vad_options'],
    ['Chat',             'chat',              'ChatGenerationRequest',      'ChatStreamEvent',             'Stream',         '../chat',                '../chat'],
    ['Diffusion',        'diffusion',         'DiffusionGenerationRequest', 'DiffusionStreamEvent',        'Stream',         '../diffusion_options',   '../diffusion_options'],
    ['RAG',              'rag',               'RAGQueryRequest',            'RAGStreamEvent',              'Stream',         '../rag',                 '../rag'],
    ['SDKEvents',        'sdk_events',        'SDKEventSubscribeRequest',   'SDKEvent',                    'Subscribe',      '../sdk_events',          '../sdk_events'],
    ['StructuredOutput', 'structured_output', 'StructuredOutputRequest',    'StructuredOutputStreamEvent', 'GenerateStream', '../structured_output',   '../structured_output'],
];
// Derive source_proto from request_module: '../voice_agent_service' ->
// 'idl/voice_agent_service.proto'. Kept in this driver so the template stays
// agnostic of per-service naming exceptions (e.g. VLM lives in
// vlm_options.proto, not vlm_service.proto).
function sourceProtoFromRequestModule(reqMod) {
    const base = reqMod.replace(/^\.\.\//, '');
    return 'idl/' + base + '.proto';
}
for (const [s, l, req, resp, rpc, reqMod, respMod] of tuples) {
    const out = '${OUT_DIR}/' + l + '_service_stream.ts';
    const vars = {
        service_name: s,
        service_lower: l,
        request_type: req,
        response_type: resp,
        rpc_name: rpc,
        request_module: reqMod,
        response_module: respMod,
        source_proto: sourceProtoFromRequestModule(reqMod),
    };
    fs.writeFileSync(out, render(vars));
    console.log('  wrote', out);
}
"

node -e "${RENDER_NODE_SCRIPT}"
ok "shared TS AsyncIterable streams → ${OUT_DIR}"
