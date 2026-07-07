#
# RunAnywhere QHexRT Backend - iOS compatibility shim
#
# QHexRT is a private Android/Snapdragon-only Hexagon NPU backend. No iOS binary
# is provided; this podspec only lets Flutter register the package and link the
# example app while keeping the backend unavailable on Apple platforms.
#

Pod::Spec.new do |s|
  s.name             = 'runanywhere_qhexrt'
  s.version          = '0.19.13'
  s.summary          = 'RunAnywhere QHexRT: private Android-only Qualcomm Hexagon NPU backend'
  s.description      = <<-DESC
Private Qualcomm Hexagon NPU (QHexRT) backend for RunAnywhere Flutter SDK.
Android/Snapdragon (v75+) only; the iOS pod provides package registration
metadata on unsupported Apple platforms.
                       DESC
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'MIT' }
  s.author           = { 'RunAnywhere' => 'team@runanywhere.ai' }
  s.source           = { :path => '.' }

  s.ios.deployment_target = '17.0'
  s.swift_version = '5.0'

  s.source_files = 'Classes/**/*'

  s.dependency 'Flutter'
  s.dependency 'runanywhere'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
  }
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
  }
  s.static_framework = true
end
