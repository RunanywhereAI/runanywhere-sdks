import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  var reactNativeDelegate: ReactNativeDelegate?
  var reactNativeFactory: RCTReactNativeFactory?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let delegate = ReactNativeDelegate()
    let factory = RCTReactNativeFactory(delegate: delegate)
    delegate.dependencyProvider = RCTAppDependencyProvider()

    reactNativeDelegate = delegate
    reactNativeFactory = factory

    window = UIWindow(frame: UIScreen.main.bounds)

    factory.startReactNative(
      withModuleName: "RunAnywhereAI",
      in: window,
      launchOptions: launchOptions
    )

    return true
  }
}

class ReactNativeDelegate: RCTDefaultReactNativeFactoryDelegate {
  override func sourceURL(for bridge: RCTBridge) -> URL? {
    self.bundleURL()
  }

  override func bundleURL() -> URL? {
#if DEBUG
    let provider = RCTBundleURLProvider.sharedSettings()
    if let bundleURL = provider.jsBundleURL(forBundleRoot: "index") {
      return bundleURL
    }

    let jsLocation = provider.jsLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
    let packagerHost = (jsLocation?.isEmpty == false) ? jsLocation! : "localhost:8081"
    return RCTBundleURLProvider.jsBundleURL(
      forBundleRoot: "index",
      packagerHost: packagerHost,
      packagerScheme: provider.packagerScheme,
      enableDev: provider.enableDev,
      enableMinification: provider.enableMinification,
      inlineSourceMap: provider.inlineSourceMap,
      modulesOnly: false,
      runModule: true
    )
#else
    Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }

  // CRITICAL: Disable bridgeless mode for Nitrogen/NitroModules compatibility
  override func bridgelessEnabled() -> Bool {
    return false
  }
}
