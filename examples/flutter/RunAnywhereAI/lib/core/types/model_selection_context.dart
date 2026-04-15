import 'package:runanywhere/core/types/model_types.dart';

enum ModelSelectionContext {
  llm([ModelCategory.language]),
  stt([ModelCategory.speechRecognition]),
  tts([ModelCategory.speechSynthesis]),
  vlm([ModelCategory.multimodal, ModelCategory.vision]),
  embedding([ModelCategory.embedding]);

  const ModelSelectionContext(this.categories);
  final List<ModelCategory> categories;

  String get title => switch (this) {
        llm => 'Select Language Model',
        stt => 'Select STT Model',
        tts => 'Select TTS Model',
        vlm => 'Select Vision Model',
        embedding => 'Select Embedding Model',
      };
}
