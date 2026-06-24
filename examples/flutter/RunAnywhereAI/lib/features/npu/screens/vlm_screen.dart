import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/runanywhere_protos.dart' as ra;

import '../widgets.dart';

class VlmScreen extends StatefulWidget {
  const VlmScreen({super.key});

  @override
  State<VlmScreen> createState() => _VlmScreenState();
}

class _VlmScreenState extends State<VlmScreen> {
  final _controller = TextEditingController(text: 'Describe this image.');
  Uint8List? _imageBytes;
  String _output = '';
  bool _running = false;
  String? _error;
  String _tps = '—';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x != null) {
      final bytes = await x.readAsBytes();
      setState(() => _imageBytes = bytes);
    }
  }

  Future<void> _process() async {
    final bytes = _imageBytes;
    if (bytes == null) return;
    setState(() {
      _output = '';
      _error = null;
      _running = true;
    });
    try {
      final image = ra.VLMImage(encoded: bytes, format: ra.VLMImageFormat.VLM_IMAGE_FORMAT_JPEG);
      final result = await RunAnywhere.vlm.processImage(
        image,
        prompt: _controller.text,
        options: ra.VLMGenerationOptions(maxTokens: 200),
      );
      setState(() {
        _output = result.text;
        _tps = result.tokensPerSecond.toStringAsFixed(1);
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
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
            const SizedBox(height: 16),
            MetricStrip([('tokens/s', _tps), ('image', _imageBytes != null ? 'loaded' : '—')]),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: 'Result',
              child: Text(
                _output.isEmpty ? (_running ? '…' : 'Pick an image and describe it.') : _output,
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
}
