platform :ios, '16.0'

target 'RunAnywhereAI' do
  use_frameworks!
  
  # TensorFlow Lite (LiteRT) - Use latest available version
  pod 'TensorFlowLiteSwift'
  
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