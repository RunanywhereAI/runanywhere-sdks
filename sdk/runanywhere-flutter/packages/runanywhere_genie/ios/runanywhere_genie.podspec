#
# RunAnywhere Genie Backend - iOS (stub)
#
# Genie NPU backend is Android/Snapdragon only — no iOS binary is provided.
# This podspec exists solely to satisfy Flutter's iOS plugin registration
# requirements so the example app can link the Dart package.
#

Pod::Spec.new do |s|
  s.name             = 'runanywhere_genie'
  s.version          = '0.16.0'
  s.summary          = 'RunAnywhere Genie: NPU LLM inference for Flutter (Android/Snapdragon only)'
  s.description      = <<-DESC
Qualcomm Genie NPU backend for RunAnywhere Flutter SDK. Provides LLM text
generation on Snapdragon NPU hardware. This is an Android-only backend; the
iOS pod is a stub for Flutter plugin system compatibility.
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'MIT' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  s.ios.deployment_target = '15.1'
  s.swift_version = '5.0'

  s.source_files = 'Classes/**/*'

  s.dependency 'Flutter'

  # No vendored_frameworks — Genie has no iOS binary.

  # Match the x86_64 exclusion used by sibling plugins so the whole dependency
  # graph stays consistent on Intel simulators.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
  }

  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
  }

  s.static_framework = true
end
