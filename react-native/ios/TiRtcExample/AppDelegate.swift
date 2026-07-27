import UIKit
import Network
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  private let localNetworkPermissionServiceType = "_tirtc-demo._tcp"
  private let localNetworkPermissionRetryDelaySeconds: TimeInterval = 12.0

  var window: UIWindow?

  var reactNativeDelegate: ReactNativeDelegate?
  var reactNativeFactory: RCTReactNativeFactory?
  private var localNetworkPermissionBrowser: NWBrowser?
  private var localNetworkPermissionResolved = false
  private var localNetworkPermissionRetryScheduled = false

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
      withModuleName: "TiRtcExample",
      in: window,
      launchOptions: launchOptions
    )

    requestLocalNetworkPermissionIfNeeded()

    return true
  }

  func applicationDidBecomeActive(_ application: UIApplication) {
    requestLocalNetworkPermissionIfNeeded()
  }

  private func requestLocalNetworkPermissionIfNeeded() {
    guard !localNetworkPermissionResolved, localNetworkPermissionBrowser == nil else {
      return
    }

    let browser = NWBrowser(
      for: .bonjour(type: localNetworkPermissionServiceType, domain: nil),
      using: .tcp
    )
    browser.stateUpdateHandler = { [weak self] state in
      self?.handleLocalNetworkPermissionBrowserState(state)
    }
    browser.browseResultsChangedHandler = { _, _ in }
    localNetworkPermissionBrowser = browser
    NSLog("[TiRTCRnExample] local network permission preflight started")
    browser.start(queue: .main)
  }

  private func handleLocalNetworkPermissionBrowserState(_ state: NWBrowser.State) {
    switch state {
    case .ready:
      completeLocalNetworkPermissionPreflight(granted: true, reason: "ready")
    case .waiting(let error):
      NSLog("[TiRTCRnExample] local network permission preflight waiting: %@", String(describing: error))
      if isLocalNetworkPolicyDenied(error) {
        completeLocalNetworkPermissionPreflight(granted: false, reason: "policy_denied")
      } else {
        scheduleLocalNetworkPermissionRetry()
      }
    case .failed(let error):
      NSLog("[TiRTCRnExample] local network permission preflight failed: %@", String(describing: error))
      completeLocalNetworkPermissionPreflight(granted: false, reason: "failed")
    default:
      break
    }
  }

  private func completeLocalNetworkPermissionPreflight(granted: Bool, reason: String) {
    NSLog(
      "[TiRTCRnExample] local network permission preflight completed granted=%@ reason=%@",
      granted.description,
      reason
    )
    localNetworkPermissionResolved = true
    localNetworkPermissionRetryScheduled = false
    localNetworkPermissionBrowser?.cancel()
    localNetworkPermissionBrowser = nil
  }

  private func scheduleLocalNetworkPermissionRetry() {
    guard !localNetworkPermissionRetryScheduled else {
      return
    }
    localNetworkPermissionRetryScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + localNetworkPermissionRetryDelaySeconds) { [weak self] in
      guard let self else {
        return
      }
      self.localNetworkPermissionRetryScheduled = false
      self.localNetworkPermissionBrowser?.cancel()
      self.localNetworkPermissionBrowser = nil
      self.requestLocalNetworkPermissionIfNeeded()
    }
  }

  private func isLocalNetworkPolicyDenied(_ error: NWError) -> Bool {
    String(describing: error).localizedCaseInsensitiveContains("PolicyDenied")
  }
}

class ReactNativeDelegate: RCTDefaultReactNativeFactoryDelegate {
  override func sourceURL(for bridge: RCTBridge) -> URL? {
    self.bundleURL()
  }

  override func bundleURL() -> URL? {
#if DEBUG
    RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: "index")
#else
    Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }
}
