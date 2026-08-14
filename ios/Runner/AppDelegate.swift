import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private var bleCoordinator: BLECoordinator?
  private var eventSink: FlutterEventSink?
  
  // Channels
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard let registrar = self.registrar(forPlugin: "BittraBLEPlugin") else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Store channels in instance properties instead of local variables
    methodChannel = FlutterMethodChannel(name: "bittra/ble", binaryMessenger: registrar.messenger())
    eventChannel = FlutterEventChannel(name: "bittra/ble_events", binaryMessenger: registrar.messenger())
    
    // Initialize BLE Coordinator
    bleCoordinator = BLECoordinator()
    
    // Setup Method Channel
    methodChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      self?.handleMethodCall(call, result: result)
    }
    
    // Setup Event Channel
    eventChannel?.setStreamHandler(self)
    
    // Wire up events from Coordinator to EventSink
    wireUpEvents()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let ble = bleCoordinator else {
      result(FlutterError(code: "UNAVAILABLE", message: "BLE Coordinator not initialized", details: nil))
      return
    }

    switch call.method {
    case "startVenueMode":
      ble.startVenueMode()
      result(nil)

    case "startReceiveOnly":
      ble.startReceiveOnly()
      result(nil)

    case "stopVenueMode":
      ble.stopVenueMode()
      result(nil)

    case "setTeaser":
      let t = (call.arguments as? [String: Any])?["teaser"] as? String ?? ""
      ble.setMyTeaser(t)
      result(nil)

    case "setBody":
      let b = (call.arguments as? [String: Any])?["body"] as? String ?? ""
      ble.setMyBody(b)
      result(nil)

    case "requestBody":
      let id = (call.arguments as? [String: Any])?["peerId"] as? String ?? ""
      ble.requestBody(forPeerId: id)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func wireUpEvents() {
    bleCoordinator?.onEncounterEvent = { [weak self] eventMap in
      self?.eventSink?(eventMap)
    }
    bleCoordinator?.onStatusEvent = { [weak self] eventMap in
      self?.eventSink?(eventMap)
    }
    bleCoordinator?.onBodyEvent = { [weak self] eventMap in
      self?.eventSink?(eventMap)
    }
    bleCoordinator?.onLogEvent = { [weak self] eventMap in
      self?.eventSink?(eventMap)
    }
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}
