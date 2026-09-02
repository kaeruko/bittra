import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private var bleCoordinator: BLECoordinator?
  private var eventSink: FlutterEventSink?

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard let registrar = self.registrar(forPlugin: "BittraBLEPlugin") else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    methodChannel = FlutterMethodChannel(name: "bittra/ble", binaryMessenger: registrar.messenger())
    eventChannel = FlutterEventChannel(name: "bittra/ble_events", binaryMessenger: registrar.messenger())

    bleCoordinator = BLECoordinator()

    methodChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      self?.handleMethodCall(call, result: result)
    }

    eventChannel?.setStreamHandler(self)
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
      guard let args = call.arguments as? [String: Any],
            let noticeId = args["noticeId"] as? String,
            !noticeId.isEmpty else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "noticeId is required", details: nil))
        return
      }
      ble.startVenueMode(noticeId: noticeId)
      result(nil)

    case "startReceiveOnly":
      ble.startReceiveOnly()
      result(nil)

    case "stopVenueMode":
      ble.stopVenueMode()
      result(nil)

    case "setTeaser":
      guard let args = call.arguments as? [String: Any],
            let teaser = args["teaser"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "teaser is required", details: nil))
        return
      }
      ble.setMyTeaser(teaser)
      result(nil)

    case "setBody":
      guard let args = call.arguments as? [String: Any],
            let body = args["body"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "body is required", details: nil))
        return
      }
      ble.setMyBody(body)
      result(nil)

    case "requestBody":
      guard let args = call.arguments as? [String: Any],
            let peerId = args["peerId"] as? String,
            !peerId.isEmpty else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "peerId is required", details: nil))
        return
      }
      ble.requestBody(forPeerId: peerId)
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
    bleCoordinator?.onDeliveryEvent = { [weak self] eventMap in
      self?.eventSink?(eventMap)
    }
    bleCoordinator?.onLogEvent = { [weak self] eventMap in
      self?.eventSink?(eventMap)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}
