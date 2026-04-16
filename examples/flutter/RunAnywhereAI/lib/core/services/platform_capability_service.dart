import 'dart:io';

class PlatformCapabilityService {
  static const PlatformCapabilityService shared = PlatformCapabilityService._();

  const PlatformCapabilityService._();

  bool get supportsChat => true;
  bool get supportsTools => true;
  bool get supportsStructuredOutput => true;

  bool get supportsVision => !Platform.isWindows;
  bool get supportsSpeechToText => true;
  bool get supportsTextToSpeech => true;
  bool get supportsVoiceAssistant => true;
  bool get supportsRag => !Platform.isWindows;

  String unsupportedMessage(String featureName) =>
      '$featureName is not enabled in the Windows vertical-slice build yet.';
}
