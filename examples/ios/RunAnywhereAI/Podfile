# Support both iOS and macOS platforms
platform :ios, '16.0'
# platform :osx, '13.0'  # Uncomment for macOS support

# Use abstract target to share pods between platforms
abstract_target 'RunAnywhereAICommon' do
  use_frameworks!

  # Currently all dependencies are commented out
  # When re-enabling dependencies, ensure they support both iOS and macOS
  
  # TensorFlow Lite (LiteRT) - REMOVED due to App Store Connect submission issues
  # pod 'TensorFlowLiteSwift', '~> 2.17.0'
  # pod 'TensorFlowLiteSwift/Metal', '~> 2.17.0'    # GPU acceleration
  # pod 'TensorFlowLiteSwift/CoreML', '~> 2.17.0'   # Neural Engine support

  # ZIP handling - REMOVED: Already available via Swift Package Manager
  # pod 'ZIPFoundation', '~> 0.9.19'

  # PicoLLM - Proprietary SDK (Check actual pod name)
  # pod 'PicovoiceSDK', '~> 3.0.0'  # Correct Picovoice pod name

  # Alternative MLC-LLM if SPM version doesn't work
  # pod 'MLCSwift', '~> 0.2.0'

  target 'RunAnywhereAI' do
    # App specific pods (if any)
  end
end

target 'RunAnywhereAITests' do
  inherit! :search_paths
end

target 'RunAnywhereAIUITests' do
  inherit! :search_paths
end
