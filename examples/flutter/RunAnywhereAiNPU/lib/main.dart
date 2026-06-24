import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

void main() => runApp(const NpuApp());

class NpuApp extends StatefulWidget {
  const NpuApp({super.key});

  @override
  State<NpuApp> createState() => _NpuAppState();
}

class _NpuAppState extends State<NpuApp> {
  bool _booting = true;
  NpuInfo _npu = NpuInfo.unknown;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await RunAnywhere.initialize();
    } catch (_) {
      // SDK init failure still lets the chip-check render.
    }
    final npu = QHexRT.probeNpu();
    var registered = false;
    if (npu.supported) {
      await QHexRT.register();
      registered = true;
    }
    if (mounted) {
      setState(() {
        _npu = npu;
        _registered = registered;
        _booting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RunAnywhere NPU',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: _booting
          ? const _Bootstrapping()
          : HomeScreen(npu: _npu, registered: _registered),
    );
  }
}

class _Bootstrapping extends StatelessWidget {
  const _Bootstrapping();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Detecting NPU…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
