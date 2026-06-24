/// Curated NPU (QHexRT) model catalog.
///
/// Source of truth: the npu-tagged repo `runanywhere/genie-npu-models` on
/// Hugging Face (tags: qualcomm, genie, npu, snapdragon) — Snapdragon Hexagon
/// NPU LLM bundles (w4a16/w8a16, Snapdragon 8 Elite / 8 Elite Gen5). The NPU
/// Models screen lists exactly these, not the generic SDK registry.
const _hf = 'https://huggingface.co/runanywhere/genie-npu-models/resolve/main';

class NpuModel {
  const NpuModel({
    required this.id,
    required this.name,
    required this.detail,
    required this.sizeBytes,
    required this.url,
  });

  final String id;
  final String name;

  /// Short spec line: params · quant · target SoC.
  final String detail;
  final int sizeBytes;
  final String url;
}

const npuModels = <NpuModel>[
  NpuModel(
    id: 'llama3.2-1b-instruct-genie-w4a16-8elite-gen5',
    name: 'Llama 3.2 1B Instruct',
    detail: '1B · w4a16 · 8 Elite Gen5',
    sizeBytes: 1373507483,
    url: '$_hf/llama3.2-1b-instruct-genie-w4a16-8elite-gen5.tar.gz',
  ),
  NpuModel(
    id: 'llama3.2-1b-instruct-genie-w4a16-8elite',
    name: 'Llama 3.2 1B Instruct',
    detail: '1B · w4a16 · 8 Elite',
    sizeBytes: 1369601674,
    url: '$_hf/llama3.2-1b-instruct-genie-w4a16-8elite.tar.gz',
  ),
  NpuModel(
    id: 'qwen3-4b-genie-w4a16-8elite-gen5',
    name: 'Qwen3 4B',
    detail: '4B · w4a16 · 8 Elite Gen5',
    sizeBytes: 2538981899,
    url: '$_hf/qwen3-4b-genie-w4a16-8elite-gen5.tar.gz',
  ),
  NpuModel(
    id: 'qwen2.5-7b-instruct-genie-w8a16-8elite',
    name: 'Qwen2.5 7B Instruct',
    detail: '7B · w8a16 · 8 Elite',
    sizeBytes: 4184248574,
    url: '$_hf/qwen2.5-7b-instruct-genie-w8a16-8elite.tar.gz',
  ),
  NpuModel(
    id: 'sea-lion3.5-8b-instruct-genie-w4a16-8elite-gen5',
    name: 'SEA-LION 3.5 8B Instruct',
    detail: '8B · w4a16 · 8 Elite Gen5',
    sizeBytes: 4724747321,
    url: '$_hf/sea-lion3.5-8b-instruct-genie-w4a16-8elite-gen5.tar.gz',
  ),
  NpuModel(
    id: 'sea-lion3.5-8b-instruct-genie-w4a16-8elite',
    name: 'SEA-LION 3.5 8B Instruct',
    detail: '8B · w4a16 · 8 Elite',
    sizeBytes: 4722492367,
    url: '$_hf/sea-lion3.5-8b-instruct-genie-w4a16-8elite.tar.gz',
  ),
];

String formatBytes(int bytes) {
  if (bytes >= 1000000000) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  if (bytes >= 1000000) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  return '$bytes B';
}
