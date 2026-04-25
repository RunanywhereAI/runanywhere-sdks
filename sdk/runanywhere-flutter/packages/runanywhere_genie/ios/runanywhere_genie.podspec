#
# RunAnywhere Genie Backend - iOS compatibility shim
#
# Genie is an experimental Android/Snapdragon-only backend shell. Functional
# routing requires Qualcomm Genie SDK-backed native ops. No iOS binary is
# provided; this podspec only lets Flutter register the package and link the
# example app while keeping the backend unavailable on Apple platforms.
#

Pod::Spec.new do |s|
  s.name             = 'runanywhere_genie'
  s.version          = '0.16.0'
  s.summary          = 'RunAnywhere Genie: experimental Android-only Qualcomm Genie backend shell'
  s.description      = <<-DESC
Experimental Qualcomm Genie backend shell for RunAnywhere Flutter SDK. LLM
routing is disabled by default and requires Android/Snapdragon hardware plus
native ops built with the Qualcomm Genie SDK. The iOS pod only provides package
registration metadata on unsupported Apple platforms.
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
