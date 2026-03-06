import Foundation
import CoreBluetooth

enum RequestStatus: String {
  case idle
  case connecting
  case discovering
  case subscribing
  case requesting
  case receivingPreview
  case completed
  case timeout
  case failed
}

final class BLECentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

  private var cm: CBCentralManager!
  private let log: (String, String) -> Void

  // 発見データ: UUID(peerId), Teaser, RSSI, CBPeripheral
  var onEncounter: ((CBPeripheral, String, Int) -> Void)?

  // 本文受信
  var onStatus: ((RequestStatus, String?) -> Void)?
  var onPreview: ((String) -> Void)?
  var onBody: ((String) -> Void)?

  private var targetPeripheral: CBPeripheral?
  private var reqChar: CBCharacteristic?
  private var chunkChar: CBCharacteristic?

  private var assembler = ChunkAssembler()
  private var timeoutTimer: DispatchSourceTimer?
  private var retryLeft: Int = 1
  private var shouldScanWhenPoweredOn: Bool = false

  init(log: @escaping (String, String) -> Void) {
    self.log = log
    super.init()
    self.cm = CBCentralManager(delegate: self, queue: nil)
  }

  func startScan() {
    guard cm.state == .poweredOn else {
      shouldScanWhenPoweredOn = true
      log("CENTRAL", "Bluetooth not poweredOn yet")
      return
    }
    cm.scanForPeripherals(withServices: [GATTProfile.serviceUUID], options: [
      CBCentralManagerScanOptionAllowDuplicatesKey: true
    ])
    log("SCAN", "startScan")
  }

  func stopScan() {
    shouldScanWhenPoweredOn = false
    cm.stopScan()
    log("SCAN", "stopScan")
  }

  func requestBody(peripheral: CBPeripheral) {
    log("CENTRAL", "requestBody called for peerId=\(peripheral.identifier)")
    connect(peripheral)
  }

  private func connect(_ peripheral: CBPeripheral) {
    resetRequestState()
    retryLeft = 1
    targetPeripheral = peripheral
    targetPeripheral?.delegate = self
    onStatus?(.connecting, nil)
    cm.connect(peripheral, options: nil)
    startTimeout(seconds: 3.0) // Timeout is 3.0 specified in docs
    log("CENTRAL", "connect start \(peripheral.identifier)")
  }

  private func resetRequestState() {
    stopTimeout()
    assembler.reset()
    reqChar = nil
    chunkChar = nil
  }

  private func startTimeout(seconds: Double) {
    stopTimeout()
    let t = DispatchSource.makeTimerSource(queue: .main)
    t.schedule(deadline: .now() + seconds)
    t.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.log("CENTRAL", "timeout")
      self.onStatus?(.timeout, nil)
      self.failOrRetry("timeout")
    }
    t.resume()
    timeoutTimer = t
  }

  private func stopTimeout() {
    timeoutTimer?.cancel()
    timeoutTimer = nil
  }

  private func failOrRetry(_ reason: String) {
    if retryLeft > 0, let p = targetPeripheral {
      retryLeft -= 1
      log("CENTRAL", "retry \(retryLeft) reason=\(reason)")
      cm.cancelPeripheralConnection(p)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        self.connect(p)
      }
    } else {
      onStatus?(.failed, reason)
      if let p = targetPeripheral {
        cm.cancelPeripheralConnection(p)
      }
      stopTimeout()
    }
  }

  // MARK: - CBCentralManagerDelegate

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    log("CENTRAL", "state=\(central.state.rawValue)")
    if central.state == .poweredOn && shouldScanWhenPoweredOn {
      log("CENTRAL", "Bluetooth is now poweredOn, starting delayed scan")
      shouldScanWhenPoweredOn = false
      startScan()
    }
  }

  func centralManager(_ central: CBCentralManager,
                      didDiscover peripheral: CBPeripheral,
                      advertisementData: [String : Any],
                      rssi RSSI: NSNumber) {
    guard let serviceDataDict = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
          let payload = serviceDataDict[GATTProfile.serviceUUID],
          let decoded = PayloadCodec.decodeAdvert(payload) else { return }

    onEncounter?(peripheral, decoded.teaser, RSSI.intValue)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    log("CENTRAL", "didConnect")
    onStatus?(.discovering, nil)
    peripheral.discoverServices([GATTProfile.serviceUUID])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    log("CENTRAL", "didFailToConnect \(error?.localizedDescription ?? "-")")
    failOrRetry("connect_failed")
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    log("CENTRAL", "didDisconnect \(error?.localizedDescription ?? "-")")
  }

  // MARK: - CBPeripheralDelegate

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let e = error {
      log("CENTRAL", "discoverServices error \(e.localizedDescription)")
      return failOrRetry("discover_services")
    }
    guard let services = peripheral.services,
          let s = services.first(where: { $0.uuid == GATTProfile.serviceUUID }) else {
      return failOrRetry("no_service")
    }
    peripheral.discoverCharacteristics([GATTProfile.reqCharUUID, GATTProfile.chunkCharUUID], for: s)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let e = error {
      log("CENTRAL", "discoverChars error \(e.localizedDescription)")
      return failOrRetry("discover_chars")
    }
    guard let chars = service.characteristics else { return failOrRetry("no_chars") }
    reqChar = chars.first(where: { $0.uuid == GATTProfile.reqCharUUID })
    chunkChar = chars.first(where: { $0.uuid == GATTProfile.chunkCharUUID })

    guard let reqChar = reqChar, let chunkChar = chunkChar else { return failOrRetry("missing_char") }

    onStatus?(.subscribing, nil)
    peripheral.setNotifyValue(true, for: chunkChar)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    if let e = error {
      log("CENTRAL", "notifyState error \(e.localizedDescription)")
      return failOrRetry("notify_fail")
    }
    guard characteristic.uuid == GATTProfile.chunkCharUUID else { return }

    onStatus?(.requesting, nil)
    // REQ：空リクエスト
    let req = Data([0x01])
    if let reqChar = reqChar {
      peripheral.writeValue(req, for: reqChar, type: .withoutResponse)
      log("CENTRAL", "REQ sent")
    } else {
      failOrRetry("no_req_char")
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if let e = error {
      log("CENTRAL", "didUpdateValue error \(e.localizedDescription)")
      return
    }
    guard characteristic.uuid == GATTProfile.chunkCharUUID,
          let value = characteristic.value,
          value.count >= 3 else { return }

    let seq = UInt16(value[0]) | (UInt16(value[1]) << 8)
    let flags = value[2]
    let payload = value.subdata(in: 3..<value.count)

    let (previewReady, completed, fullData) = assembler.addChunk(seq: seq, flags: flags, payload: payload)

    if previewReady {
      onStatus?(.receivingPreview, nil)
    }

    if completed, let fullData = fullData {
      stopTimeout()
      let s = String(data: fullData, encoding: .utf8) ?? ""
      let preview = String(s.prefix(120))
      onBody?(s)
      onPreview?(preview)
      onStatus?(.completed, nil)
      cm.cancelPeripheralConnection(peripheral)
    }
  }
}
