platform :ios, '16.0'

target 'RunAnywhereAI' do
  use_frameworks!

  # Keeping CocoaPods integration with an empty framework
  # This maintains the Pods framework structure without any actual dependencies
  # All real dependencies are managed through Swift Package Manager
  
  # Future CocoaPods dependencies can be added here when needed:
  # TensorFlow Lite (LiteRT) - Currently removed due to App Store Connect submission issues
  # pod 'TensorFlowLiteSwift', '~> 2.17.0'
  # pod 'TensorFlowLiteSwift/Metal', '~> 2.17.0'    # GPU acceleration
  # pod 'TensorFlowLiteSwift/CoreML', '~> 2.17.0'   # Neural Engine support

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
