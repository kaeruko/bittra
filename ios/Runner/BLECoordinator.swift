import Foundation
import CoreBluetooth

@MainActor
final class BLECoordinator: NSObject {

  // Event callbacks to Flutter
  var onEncounterEvent: (([String: Any]) -> Void)?
  var onStatusEvent: (([String: Any]) -> Void)?
  var onBodyEvent: (([String: Any]) -> Void)?
  var onLogEvent: (([String: Any]) -> Void)?

  var myTeaser: String = ""
  var myBody: String = ""

  private lazy var peripheral = BLEPeripheral(log: self.addLog)
  private lazy var central = BLECentral(log: self.addLog)

  // peerId -> CBPeripheral キャッシュ（最小）
  private var peripheralCache: [UUID: CBPeripheral] = [:]

  override init() {
    super.init()
    
    central.onEncounter = { [weak self] peripheral, senderId, teaser, rssi in
      guard let self = self else { return }
      guard !teaser.isEmpty else { return }
      self.peripheralCache[peripheral.identifier] = peripheral
      self.onEncounterEvent?([
        "type": "encounter",
        "peerId": peripheral.identifier.uuidString,
        "senderId": Int(senderId),
        "teaser": teaser,
        "rssi": rssi
      ])
    }

    central.onStatus = { [weak self] st, errorStr in
      guard let self = self else { return }
      // The current implementation of central has the targetPeripheral
      // To bubble this back up accurately we iterate cache
      // MVP simplistic approach: Just use latest peerId being requested.
      // Alternatively, pass peerId back from onStatus in Central.
      // Let's modify Central slightly strictly for Flutter bridge.
    }

    central.onBody = { [weak self] body in
      guard let self = self else { return }
      // This will be piped down in requestBody with proper context.
    }
  }

  func setMyTeaser(_ teaser: String) {
    myTeaser = PayloadCodec.normalizeTeaser(teaser)
    peripheral.setContent(teaser: myTeaser, body: myBody)
    addLog("APP", "set teaser=\(myTeaser)")
  }

  func setMyBody(_ body: String) {
    myBody = body
    peripheral.setContent(teaser: myTeaser, body: myBody)
    addLog("APP", "set body bytes=\(Data(myBody.utf8).count)")
  }

  func startVenueMode() {
    guard !myTeaser.isEmpty else {
      startReceiveOnly()
      return
    }
    peripheral.setContent(teaser: myTeaser, body: myBody)
    peripheral.start()
    central.startScan()
    addLog("APP", "venue ON")
  }

  func startReceiveOnly() {
    peripheral.stop()
    central.startScan()
    addLog("APP", "receive-only ON")
  }

  func stopVenueMode() {
    central.stopScan()
    peripheral.stop()
    addLog("APP", "venue OFF")
  }

  func requestBody(forPeerId peerIdString: String) {
    guard let uuid = UUID(uuidString: peerIdString), let p = peripheralCache[uuid] else {
      addLog("APP", "no cached peripheral (wait a bit and try again)")
      onStatusEvent?([
        "type": "status",
        "peerId": peerIdString,
        "status": RequestStatus.failed.rawValue,
        "error": "Peripheral not cached yet."
      ])
      return
    }

    addLog("APP", "requestBody peerId=\(p.identifier)")
    
    // Inject peerId context directly for callbacks
    central.onStatus = { [weak self] st, err in
      self?.onStatusEvent?([
        "type": "status",
        "peerId": peerIdString,
        "status": st.rawValue,
        "error": err ?? ""
      ])
    }
    
    central.onPreview = { [weak self] preview in
        // In this implementation preview stream comes separate or prepends
        // We'll leave it as a log or ignore for flutter simple MVP if full body is received anyway.
        self?.onBodyEvent?([
            "type": "body",
            "peerId": peerIdString,
            "preview": preview,
        ])
    }

    central.onBody = { [weak self] body in
      self?.onBodyEvent?([
        "type": "body",
        "peerId": peerIdString,
        "preview": String(body.prefix(80)),
        "body": body
      ])
    }

    central.requestBody(peripheral: p)
  }

  func addLog(_ tag: String, _ msg: String) {
    onLogEvent?([
      "type": "log",
      "tag": tag,
      "message": msg
    ])
  }
}
