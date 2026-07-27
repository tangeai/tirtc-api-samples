import AVFoundation
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.isOpaque = true
    self.backgroundColor = NSColor(
      calibratedRed: 1.0,
      green: 0.9725,
      blue: 0.9098,
      alpha: 1.0
    )

    if let screen = NSScreen.main {
      let screenRect = screen.visibleFrame
      let aspectRatio: CGFloat = 19.5 / 9.0
      let windowHeight = min(screenRect.height * 0.82, 900)
      let windowWidth = windowHeight / aspectRatio
      let originX = screenRect.midX - (windowWidth / 2)
      let originY = screenRect.midY - (windowHeight / 2)
      let frame = NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight)
      self.setFrame(frame, display: true)
      self.minSize = NSSize(width: windowWidth, height: windowHeight)
      self.maxSize = NSSize(width: windowWidth, height: windowHeight)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerPreferencesChannel(binaryMessenger: flutterViewController.engine.binaryMessenger)
    registerPermissionsChannel(binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func registerPermissionsChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "tirtc_example/permissions",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "checkMicrophonePermission":
        result(self.capturePermissionGranted(for: .audio))
      case "requestMicrophonePermission":
        self.requestCaptureAccessIfNeeded(for: .audio, result: result)
      case "requestLocalNetworkPermission":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func registerPreferencesChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "tirtc_example/preferences",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "putPreferencesInt":
        guard let (key, value) = self.intArguments(
          call.arguments,
          valueKey: "value",
          result: result
        ) else {
          return
        }
        UserDefaults.standard.set(value, forKey: key)
        result(nil)
      case "getPreferencesInt":
        guard let (key, defaultValue) = self.intArguments(
          call.arguments,
          valueKey: "defaultValue",
          result: result
        ) else {
          return
        }
        if UserDefaults.standard.object(forKey: key) == nil {
          result(defaultValue)
          return
        }
        result(UserDefaults.standard.integer(forKey: key))
      case "putPreferencesString":
        guard let (key, value) = self.stringArguments(
          call.arguments,
          valueKey: "value",
          result: result
        ) else {
          return
        }
        UserDefaults.standard.set(value, forKey: key)
        result(nil)
      case "getPreferencesString":
        guard let (key, defaultValue) = self.stringArguments(
          call.arguments,
          valueKey: "defaultValue",
          result: result
        ) else {
          return
        }
        result(UserDefaults.standard.string(forKey: key) ?? defaultValue)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func intArguments(
    _ rawArguments: Any?,
    valueKey: String,
    result: FlutterResult
  ) -> (String, Int)? {
    guard let arguments = rawArguments as? [String: Any],
          let key = arguments["key"] as? String,
          key.hasPrefix("tirtc_example."),
          let value = arguments[valueKey] as? Int else {
      result(FlutterError(
        code: "INVALID_ARGUMENT",
        message: "key and \(valueKey) are required",
        details: nil
      ))
      return nil
    }
    return (key, value)
  }

  private func stringArguments(
    _ rawArguments: Any?,
    valueKey: String,
    result: FlutterResult
  ) -> (String, String)? {
    guard let arguments = rawArguments as? [String: Any],
          let key = arguments["key"] as? String,
          key.hasPrefix("tirtc_example."),
          let value = arguments[valueKey] as? String else {
      result(FlutterError(
        code: "INVALID_ARGUMENT",
        message: "key and \(valueKey) are required",
        details: nil
      ))
      return nil
    }
    return (key, value)
  }

  private func capturePermissionGranted(for mediaType: AVMediaType) -> Bool {
    AVCaptureDevice.authorizationStatus(for: mediaType) == .authorized
  }

  private func requestCaptureAccessIfNeeded(for mediaType: AVMediaType, result: @escaping FlutterResult) {
    resolveCaptureAccess(for: mediaType) { granted in
      result(granted)
    }
  }

  private func resolveCaptureAccess(
    for mediaType: AVMediaType,
    completion: @escaping (Bool) -> Void
  ) {
    switch AVCaptureDevice.authorizationStatus(for: mediaType) {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: mediaType) { granted in
        DispatchQueue.main.async {
          completion(granted)
        }
      }
    case .denied, .restricted:
      completion(false)
    @unknown default:
      completion(false)
    }
  }
}
