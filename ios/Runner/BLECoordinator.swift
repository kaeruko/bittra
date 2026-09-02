import Foundation
import CoreBluetooth

@MainActor
final class BLECoordinator: NSObject {

  var onEncounterEvent: (([String: Any]) -> Void)?
  var onStatusEvent: (([String: Any]) -> Void)?
  var onBodyEvent: (([String: Any]) -> Void)?
  var onDeliveryEvent: (([String: Any]) -> Void)?
  var onLogEvent: (([String: Any]) -> Void)?

  var myTeaser: String = ""
  var myBody: String = ""

  private lazy var peripheral = BLEPeripheral(
    log: self.addLog,
    onDeliveryReceipt: { [weak self] noticeId, count in
      self?.onDeliveryEvent?([
        "type": "delivery",
        "noticeId": noticeId,
        "count": count
      ])
    }
  )
  private lazy var central = BLECentral(log: self.addLog)

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

    central.onStatus = { [weak self] _, _ in
      guard self != nil else { return }
    }

    central.onBody = { [weak self] _ in
      guard self != nil else { return }
    }
  }

  func setMyTeaser(_ teaser: String) {
    myTeaser = PayloadCodec.normalizeTeaser(teaser)
    addLog("APP", "set teaser=\(myTeaser)")
  }

  func setMyBody(_ body: String) {
    myBody = body
    addLog("APP", "set body bytes=\(Data(myBody.utf8).count)")
  }

  func startVenueMode(noticeId: String) {
    precondition(!noticeId.isEmpty, "noticeId must not be empty")
    guard !myTeaser.isEmpty else {
      startReceiveOnly()
      return
    }
    peripheral.setContent(noticeId: noticeId, teaser: myTeaser, body: myBody)
    peripheral.start()
    central.startScan()
    addLog("APP", "venue ON noticeId=\(noticeId)")
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

    central.onStatus = { [weak self] st, err in
      self?.onStatusEvent?([
        "type": "status",
        "peerId": peerIdString,
        "status": st.rawValue,
        "error": err ?? ""
      ])
    }

    central.onPreview = { [weak self] preview in
      self?.onBodyEvent?([
        "type": "body",
        "peerId": peerIdString,
        "preview": preview
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
    print("[BITTRA-BLE][\(tag)] \(msg)")
    onLogEvent?([
      "type": "log",
      "tag": tag,
      "message": msg
    ])
  }
}
