#!/usr/bin/env bash
# Static functional smoke preflight for the native iOS sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${APP_ROOT}"

echo "==> Checking Swift SDK call coverage"
grep -R -E "RunAnywhere\.(initialize|registerModel|downloadModel|loadModel|generateStream|generate\(|transcribe|speak|processImage|processImageStream|detectVoiceActivity|getStorageInfo|clearCache|cleanTempFiles|cancelGeneration|listModels|initializeVoiceAgent|streamVoiceAgent|ragCreatePipeline|ragIngest|ragQuery)" \
    RunAnywhereAI >/dev/null

grep -R -E "Voice|Pipeline|RAG|rag|cancelGeneration" RunAnywhereAI >/dev/null

echo "==> Checking exact Parakeet CTC transform catalog policy"
catalog_source="RunAnywhereAI/Core/Services/ModelCatalogBootstrap.swift"
catalog_literals=(
    "sherpa-nemo-parakeet-ctc-1.1b-int8"
    "3ca664a2f106622d599052b4e4ecee5fdfc7e2e5"
    "a16056c0a0d8df38c7b57cb019062df116e9e565203c6f25d6ea0c0c1122c84d"
    "62f73c17a5301c048c7273cf24ef1cd0c3621d3625c5415fbafe5633d7bf2f98"
    "ed16e1a4e3a3aa379138c0b1888e5d49f993c9d512b2be4d46e90a87afd54921"
    "filename: \"tokens.txt\""
    "memoryRequirement: 2_000_000_000"
    "downloadSize: 1_110_024_519"
)
for literal in "${catalog_literals[@]}"; do
    grep -F -- "${literal}" "${catalog_source}" >/dev/null
done

metadata_hex="$({
    sed -n '/let metadataPayload: \[UInt8\] = \[/,/^[[:space:]]*\]/p' "${catalog_source}" |
        grep -Eo '0x[0-9a-f]{2}' |
        sed 's/^0x//' |
        tr -d '\n'
} || true)"
expected_metadata_hex="72120a0a766f6361625f73697a6512043130323572170a1273756273616d706c696e675f666163746f72120138721d0a0e6e6f726d616c697a655f74797065120b7065725f66656174757265"
test "${metadata_hex}" = "${expected_metadata_hex}"

if [ "${RUN_BUILD_GATES:-0}" = "1" ]; then
    echo "==> Running full iOS verify gates"
    "${SCRIPT_DIR}/verify.sh"
fi

echo "iOS smoke preflight complete"
