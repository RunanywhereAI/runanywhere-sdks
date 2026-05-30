#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# generate_streams.sh — render the shared TypeScript AsyncIterable stream
# wrappers for every server-streaming RPC. Both RN and Web consume the
# generated files via the @runanywhere/proto-ts package, so a single
# render pass writes the canonical output once.
#
# Replaces the byte-identical pair generate_rn_streams.sh
# + generate_web_streams.sh, both of which used to write to the same
# OUT_DIR (sdk/shared/proto-ts/src/streams). Running both in sequence was
# a silent overwrite trap — any unilateral edit to one script would be
# overwritten on the next generate_all.sh run by the unchanged copy in
# the other script.
#
# Uses the in-tree Nunjucks template at
# idl/codegen/templates/ts_async_iterable.njk. The actual rendering is
# done by a tiny Node helper invoked once per (service, rpc, response)
# triple.
#
# Output:
#   sdk/shared/proto-ts/src/streams/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/sdk/shared/proto-ts/src/streams"
TEMPLATE="${SCRIPT_DIR}/templates/ts_async_iterable.njk"

mkdir -p "${OUT_DIR}"

if ! command -v node >/dev/null 2>&1; then
    echo "error: node not found. Stream codegen requires Node 18+." >&2
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
    ['VoiceAgent',       'voice_agent',       'VoiceAgentRequest',          'VoiceEvent',                  'Stream',         '../voice_agent_service', '../voice_events'],
    ['LLM',              'llm',               'LLMGenerateRequest',         'LLMStreamEvent',              'Generate',       '../llm_service',         '../llm_service'],
    ['Download',         'download',          'DownloadSubscribeRequest',   'DownloadProgress',            'Subscribe',      '../download_service',    '../download_service'],
    // Generate AsyncIterable wrappers for the remaining
    // 9 server-streaming RPCs so RN and Web consumers can consume them
    // through the same generated pattern as VoiceAgent / LLM / Download.
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
// 'idl/voice_agent_service.proto'. Previously the Nunjucks template
// hard-coded 'idl/<service_lower>_service.proto' which was wrong for 10
// of the 12 tuples below (e.g. VLM lives in vlm_options.proto, not
// vlm_service.proto). Keeping the derivation in this driver lets the
// template stay agnostic of any per-service naming exceptions.
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
echo "✓ shared TS AsyncIterable streams → ${OUT_DIR}"
