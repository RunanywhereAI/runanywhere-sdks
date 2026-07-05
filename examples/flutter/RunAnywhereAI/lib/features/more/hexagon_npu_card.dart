import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

/// Slim Hexagon-NPU capability card. NPU models themselves live in the
/// standard model pickers (registered only for the probed arch); this card is
/// the one NPU-specific surface left — it tells the user whether this device
/// runs them.
class HexagonNpuCard extends StatelessWidget {
  const HexagonNpuCard({super.key});

  @override
  Widget build(BuildContext context) {
    final npu = QHexRT.isAvailable ? QHexRT.probeNpu() : NpuCapability();
    final supported = npu.qhexrtSupported;
    final subtitle = supported
        ? '${npu.socModel.isEmpty ? 'Snapdragon' : npu.socModel} · '
              'Hexagon ${npu.archName} — NPU models available'
        : 'Requires Hexagon v75/v79/v81 — NPU models hidden'
              '${npu.socModel.isEmpty ? '' : ' (${npu.socModel})'}';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: AppSpacing.smallMedium,
        ),
        leading: CircleAvatar(
          backgroundColor: (supported ? Colors.green : Colors.grey).withValues(
            alpha: 0.12,
          ),
          foregroundColor: supported ? Colors.green : Colors.grey,
          child: const Icon(Icons.memory),
        ),
        title: Text(
          'Hexagon NPU',
          style: AppTypography.subheadlineSemibold(context),
        ),
        subtitle: Text(subtitle),
        trailing: supported
            ? const Text('Ready', style: TextStyle(color: Colors.green))
            : null,
      ),
    );
  }
}
