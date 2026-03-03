import Foundation
import SwiftUI
import CoreBluetooth

@MainActor
final class BLECoordinator: ObservableObject {

  @Published var encounters: [Encounter] = []
  @Published var logs: [LogEvent] = []

  @Published var isVenueModeOn: Bool = false

  @Published var myTeaser: String = ""
  @Published var myBody: String = ""

  @Published var activeStatus: RequestStatus = .idle
  @Published var receivedPreview: String = ""
  @Published var receivedBody: String? = nil

  var activeStatusText: String {
    switch activeStatus {
    case .idle: return "idle"
    case .connecting: return "connecting"
    case .discovering: return "discovering"
    case .subscribing: return "subscribing"
    case .requesting: return "requesting"
    case .receivingPreview: return "receivingPreview"
    case .completed: return "completed"
    case .timeout: return "timeout"
    case .failed(let s): return "failed(\(s))"
    }
  }

  private lazy var peripheral = BLEPeripheral(log: self.addLog)
  private lazy var central = BLECentral(log: self.addLog)

  // peerId -> CBPeripheral キャッシュ（最小）
  private var peripheralCache: [UUID: CBPeripheral] = [:]

  init() {
    central.onEncounter = { [weak self] peripheral, teaser, rssi in
      guard let self else { return }
      self.peripheralCache[peripheral.identifier] = peripheral
      self.upsertEncounter(peerId: peripheral.identifier, teaser: teaser, rssi: rssi)
    }

    central.onStatus = { [weak self] st in
      self?.activeStatus = st
    }

    central.onBody = { [weak self] body in
      guard let self else { return }
      self.receivedBody = body
      self.receivedPreview = String(body.prefix(80))
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
    peripheral.setContent(teaser: myTeaser, body: myBody)
    peripheral.start()
    central.startScan()
    addLog("APP", "venue ON")
  }

  func stopVenueMode() {
    central.stopScan()
    peripheral.stop()
    addLog("APP", "venue OFF")
  }

  func requestBody(for e: Encounter) {
    receivedPreview = ""
    receivedBody = nil
    activeStatus = .idle

    addLog("APP", "requestBody teaser=\(e.teaser) peerId=\(e.peerId)")
    guard let p = peripheralCache[e.peerId] else {
      addLog("APP", "no cached peripheral (wait a bit and try again)")
      return
    }
    central.connect(p)
  }

  private func upsertEncounter(peerId: UUID, teaser: String, rssi: Int) {
    let now = Date()
    let key = "\(peerId.uuidString)|\(teaser)"
    if let idx = encounters.firstIndex(where: { $0.dedupeKey == key }) {
      encounters[idx].lastSeen = now
      encounters[idx].count += 1
      encounters[idx].rssi = rssi
    } else {
      encounters.insert(
        Encounter(id: UUID(), peerId: peerId, teaser: teaser, rssi: rssi, firstSeen: now, lastSeen: now, count: 1),
        at: 0
      )
    }
  }

  func addLog(_ tag: String, _ msg: String) {
    logs.insert(LogEvent(ts: Date(), tag: tag, msg: msg), at: 0)
  }

  func clearLogs() {
    logs.removeAll()
  }
}
