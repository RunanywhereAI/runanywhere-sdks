import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/runanywhere_protos.dart' as ra;

import '../widgets.dart';

/// Vision (VLM) screen. Two modes:
///  • Static — pick an image from the gallery and describe it once.
///  • Live   — open the camera and caption a frame every few seconds.
///
/// QHexRT VLM streaming yields zero tokens, so both paths use the non-streaming
/// [RunAnywhere.vlm.processImage] with a file-path image (the lowest-overhead
/// form: the bundle's preprocessor reads the JPEG straight off disk).
class VlmScreen extends StatefulWidget {
  const VlmScreen({super.key});

  @override
  State<VlmScreen> createState() => _VlmScreenState();
}

enum _Mode { static_, live }

class _VlmScreenState extends State<VlmScreen> {
  final _controller = TextEditingController(text: 'Describe this image.');
  _Mode _mode = _Mode.static_;

  // Static mode.
  Uint8List? _imageBytes;
  String? _imagePath;

  // Live mode.
  CameraController? _camera;
  Timer? _loop;
  bool _liveBusy = false;

  String _output = '';
  bool _running = false;
  String? _error;
  String _tps = '—';

  @override
  void dispose() {
    _loop?.cancel();
    _camera?.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x != null) {
      final bytes = await x.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imagePath = x.path;
      });
    }
  }

  Future<void> _process() async {
    final path = _imagePath;
    if (path == null) return;
    setState(() {
      _output = '';
      _error = null;
      _running = true;
    });
    try {
      final result = await RunAnywhere.vlm.processImage(
        ra.VLMImage(filePath: path),
        prompt: _controller.text,
        options: ra.VLMGenerationOptions(maxTokens: 200),
      );
      if (!mounted) return;
      setState(() {
        _output = result.text;
        _tps = result.tokensPerSecond.toStringAsFixed(1);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // ---- Live mode ----

  Future<void> _enterLive() async {
    setState(() {
      _mode = _Mode.live;
      _error = null;
      _output = '';
    });
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _error = 'Camera permission denied');
      return;
    }
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
      _loop = Timer.periodic(const Duration(milliseconds: 2500), (_) => _captionFrame());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _exitLive() async {
    _loop?.cancel();
    _loop = null;
    final cam = _camera;
    _camera = null;
    await cam?.dispose();
    if (mounted) {
      setState(() {
        _mode = _Mode.static_;
        _liveBusy = false;
      });
    }
  }

  Future<void> _captionFrame() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || _liveBusy) return;
    _liveBusy = true;
    try {
      final shot = await cam.takePicture();
      final result = await RunAnywhere.vlm.processImage(
        ra.VLMImage(filePath: shot.path),
        prompt: _controller.text,
        options: ra.VLMGenerationOptions(maxTokens: 120),
      );
      if (!mounted) return;
      setState(() {
        _output = result.text;
        _tps = result.tokensPerSecond.toStringAsFixed(1);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _liveBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Vision')),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.static_, label: Text('Image'), icon: Icon(Icons.image)),
                ButtonSegment(value: _Mode.live, label: Text('Live'), icon: Icon(Icons.videocam)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                final next = s.first;
                if (next == _Mode.live) {
                  _enterLive();
                } else {
                  _exitLive();
                }
              },
            ),
            const SizedBox(height: 16),
            if (_mode == _Mode.static_)
              ..._staticBody(cs)
            else
              ..._liveBody(cs),
            const SizedBox(height: 16),
            MetricStrip([('tokens/s', _tps), ('mode', _mode == _Mode.live ? 'live' : 'static')]),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: _mode == _Mode.live ? 'Live caption' : 'Result',
              child: Text(
                _output.isEmpty
                    ? (_running || _liveBusy
                        ? '…'
                        : _mode == _Mode.live
                            ? 'Point the camera at a scene.'
                            : 'Pick an image and describe it.')
                    : _output,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _output.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _staticBody(ColorScheme cs) => [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _running ? null : _pick,
            child: Text(_imageBytes == null ? 'Pick an image' : 'Change image'),
          ),
        ),
        if (_imageBytes != null) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_imageBytes!, height: 200, width: double.infinity, fit: BoxFit.cover),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          enabled: !_running,
          decoration: const InputDecoration(labelText: 'Prompt', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (_running || _imageBytes == null) ? null : _process,
            child: Text(_running ? 'Processing…' : 'Describe'),
          ),
        ),
      ];

  List<Widget> _liveBody(ColorScheme cs) {
    final cam = _camera;
    return [
      if (cam != null && cam.value.isInitialized)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: cam.value.aspectRatio,
            child: CameraPreview(cam),
          ),
        )
      else
        Container(
          height: 200,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('Starting camera…', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      const SizedBox(height: 16),
      TextField(
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Prompt', border: OutlineInputBorder()),
      ),
    ];
  }
}
