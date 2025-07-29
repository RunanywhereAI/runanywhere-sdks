platform :ios, '16.0'

target 'RunAnywhereAI' do
  use_frameworks!
  
  # TensorFlow Lite (LiteRT) - Only available via CocoaPods
  pod 'TensorFlowLiteSwift', '~> 2.17.0'
  pod 'TensorFlowLiteSwift/Metal', '~> 2.17.0'    # GPU acceleration
  pod 'TensorFlowLiteSwift/CoreML', '~> 2.17.0'   # Neural Engine support
  
  # ZIP handling moved to Swift Package Manager
  # pod 'ZIPFoundation', '~> 0.9.19'
  
  # PicoLLM - Proprietary SDK (Check actual pod name)
  # pod 'PicovoiceSDK', '~> 3.0.0'  # Correct Picovoice pod name
  
  # Alternative MLC-LLM if SPM version doesn't work
  # pod 'MLCSwift', '~> 0.2.0'
end

target 'RunAnywhereAITests' do
  inherit! :search_paths
end

target 'RunAnywhereAIUITests' do
  inherit! :search_paths
end