#
# RunAnywhere Genie Backend - iOS
#
# This is a stub podspec for the Flutter plugin system.
# Genie NPU backend is Android/Snapdragon only - no iOS binary is provided.
# This podspec exists solely to satisfy Flutter's iOS plugin registration requirements.
#

Pod::Spec.new do |s|
  s.name             = 'runanywhere_genie'
  s.version          = '0.16.0'
  s.summary          = 'RunAnywhere Genie: NPU LLM inference for Flutter (Android/Snapdragon only)'
  s.description      = <<-DESC
Qualcomm Genie NPU backend for RunAnywhere Flutter SDK. Provides LLM text generation
on Snapdragon NPU hardware. This is an Android-only backend; the iOS pod is a stub
for Flutter plugin system compatibility.
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'MIT' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.0'

  # Source files (minimal stub - Genie is Android-only)
  s.source_files = 'Classes/**/*'

  # Flutter dependency
  s.dependency 'Flutter'

  # No vendored_frameworks - Genie has no iOS binary (Android/Snapdragon only)

  # Build settings
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }

  # Mark static framework for proper linking
  s.static_framework = true
end
