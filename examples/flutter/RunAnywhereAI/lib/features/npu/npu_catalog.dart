/// NPU (QHexRT) model catalog — Google-Drive-hosted ZIP bundles.
///
/// Each model is a .zip archive on Google Drive. The Models screen registers it
/// as a ZIP archive (DIRECTORY_BASED) and the SDK downloads + extracts it into
/// the standard model dir, then loads it like any other model.
///
/// To wire a model: paste its Google Drive FILE ID into [driveId] (the long id
/// from the share link `https://drive.google.com/file/d/<FILE_ID>/view`). An
/// empty [driveId] renders the row as "link pending" with Download disabled.
enum NpuModality { llm, vlm }

class NpuModel {
  const NpuModel({
    required this.id,
    required this.name,
    required this.detail,
    required this.modality,
    this.driveId = '',
    this.sizeBytes,
  });

  final String id;
  final String name;

  /// Short spec line: modality · params · target arch.
  final String detail;
  final NpuModality modality;

  /// Google Drive file id of the .zip bundle; '' until the link is provided.
  final String driveId;
  final int? sizeBytes;
}

const npuModels = <NpuModel>[
  NpuModel(
    id: 'llama3_2_1b_hnpu',
    name: 'Llama 3.2 1B (HNPU)',
    detail: 'LLM · 1B · Hexagon v79 / v81',
    modality: NpuModality.llm,
    driveId: '', // TODO: paste Google Drive file id for llama3_2_1b_HNPU.zip
  ),
  NpuModel(
    id: 'qwen3_vl_hnpu',
    name: 'Qwen3-VL (HNPU)',
    detail: 'VLM · Hexagon v79 / v81',
    modality: NpuModality.vlm,
    driveId: '', // TODO: paste Google Drive file id for qwen3_vl_HNPU.zip
  ),
];

/// Direct-download URL for a Google Drive file id. Uses the usercontent host
/// with `confirm=t` so large files skip the virus-scan HTML interstitial and
/// stream the bytes.
String driveZipUrl(String driveId) =>
    'https://drive.usercontent.google.com/download?id=$driveId&export=download&confirm=t';

String formatBytes(int bytes) {
  if (bytes >= 1000000000) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  if (bytes >= 1000000) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  return '$bytes B';
}
