import 'package:flutter/material.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

/// Self-contained NPU (QHexRT) section, reached from More → NPU.
///
/// Hosts its own nested [Navigator] under the standalone NPU theme so the whole
/// section — Home + LLM/VLM/STT/TTS — renders exactly like the dedicated
/// NPU app, without disturbing the host app's screens or theme.
class NpuView extends StatefulWidget {
  const NpuView({super.key});

  @override
  State<NpuView> createState() => _NpuViewState();
}

class _NpuViewState extends State<NpuView> {
  final _navKey = GlobalKey<NavigatorState>();
  late final NpuInfo _npu = QHexRT.probeNpu();
  late final bool _registered = QHexRT.isAvailable;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _navKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Theme(
        data: buildTheme(brightness),
        child: Navigator(
          key: _navKey,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => HomeScreen(npu: _npu, registered: _registered),
            settings: settings,
          ),
        ),
      ),
    );
  }
}
