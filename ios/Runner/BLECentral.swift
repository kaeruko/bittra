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
  var onEncounter: ((CBPeripheral, UInt32, String, Int) -> Void)?

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
  private var resumeScanAfterRequest: Bool = false

  init(log: @escaping (String, String) -> Void) {
    self.log = log
    super.init()
    self.cm = CBCentralManager(delegate: self, queue: nil)
  }

  func startScan() {
    guard cm.state == .poweredOn else {
      shouldScanWhenPoweredOn = true
      log("CENTRAL", "Bluetooth not poweredOn yet state=\(cm.state.rawValue)")
      return
    }
    if cm.isScanning {
      log("SCAN", "already scanning")
      return
    }
    cm.scanForPeripherals(withServices: [GATTProfile.serviceUUID], options: [
      CBCentralManagerScanOptionAllowDuplicatesKey: true
    ])
    log("SCAN", "startScan serviceUUID=\(GATTProfile.serviceUUID.uuidString)")
  }

  func stopScan() {
    shouldScanWhenPoweredOn = false
    cm.stopScan()
    log("SCAN", "stopScan")
  }

  func requestBody(peripheral: CBPeripheral) {
    log("CENTRAL", "requestBody called for peerId=\(peripheral.identifier)")
    retryLeft = 1
    targetPeripheral = peripheral
    resumeScanAfterRequest = cm.isScanning
    if cm.isScanning {
      cm.stopScan()
      log("SCAN", "pause scan for body request")
    }
    connect(peripheral)
  }

  private func connect(_ peripheral: CBPeripheral) {
    resetRequestState()
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
    stopTimeout()
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
      finishRequest()
    }
  }

  private func finishRequest() {
    targetPeripheral = nil
    if resumeScanAfterRequest {
      resumeScanAfterRequest = false
      startScan()
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
    let keys = advertisementData.keys.sorted().joined(separator: ",")
    let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "-"
    log(
      "SCAN",
      "didDiscover id=\(peripheral.identifier) rssi=\(RSSI) name=\(advertisedName) keys=[\(keys)]"
    )

    // Android peripheral: payload in manufacturer specific data (skip 2-byte company ID)
    // iOS peripheral: payload in localName (base64-encoded, CoreBluetooth limitation)
    let payload: Data?
    if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfgData.count > 2 {
      payload = Data(mfgData.dropFirst(2))
      log(
        "SCAN",
        "payload source=manufacturer totalBytes=\(mfgData.count) payloadBytes=\(mfgData.count - 2)"
      )
    } else if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
      if let data = Data(base64Encoded: localName) {
        payload = data
        log("SCAN", "payload source=localName base64Chars=\(localName.count) payloadBytes=\(data.count)")
      } else {
        payload = nil
        log("SCAN", "skip id=\(peripheral.identifier) localName is not valid base64: \(localName)")
      }
    } else {
      payload = nil
      log("SCAN", "skip id=\(peripheral.identifier) no manufacturerData/localName payload")
    }

    guard let payload = payload else { return }
    guard let decoded = PayloadCodec.decodeAdvert(payload) else {
      let prefix = payload.base64EncodedString().prefix(32)
      log("SCAN", "skip id=\(peripheral.identifier) advert decode failed bytes=\(payload.count) b64prefix=\(prefix)")
      return
    }
    guard !decoded.teaser.isEmpty else {
      log("SCAN", "skip id=\(peripheral.identifier) decoded teaser is empty senderId=\(decoded.senderId)")
      return
    }

    log(
      "SCAN",
      "encounter id=\(peripheral.identifier) senderId=\(decoded.senderId) teaser=\(decoded.teaser) rssi=\(RSSI.intValue)"
    )
    onEncounter?(peripheral, decoded.senderId, decoded.teaser, RSSI.intValue)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    log("CENTRAL", "didConnect id=\(peripheral.identifier)")
    onStatus?(.discovering, nil)
    peripheral.discoverServices([GATTProfile.serviceUUID])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    log("CENTRAL", "didFailToConnect id=\(peripheral.identifier) error=\(error?.localizedDescription ?? "-")")
    failOrRetry("connect_failed")
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    log("CENTRAL", "didDisconnect id=\(peripheral.identifier) error=\(error?.localizedDescription ?? "-")")
  }

  // MARK: - CBPeripheralDelegate

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let e = error {
      log("CENTRAL", "discoverServices error \(e.localizedDescription)")
      return failOrRetry("discover_services")
    }
    guard let services = peripheral.services,
          let s = services.first(where: { $0.uuid == GATTProfile.serviceUUID }) else {
      let found = peripheral.services?.map { $0.uuid.uuidString }.joined(separator: ",") ?? "none"
      log("CENTRAL", "required service missing found=[\(found)]")
      return failOrRetry("no_service")
    }
    log("CENTRAL", "service discovered uuid=\(s.uuid.uuidString)")
    peripheral.discoverCharacteristics([GATTProfile.reqCharUUID, GATTProfile.chunkCharUUID], for: s)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let e = error {
      log("CENTRAL", "discoverChars error \(e.localizedDescription)")
      return failOrRetry("discover_chars")
    }
    guard let chars = service.characteristics else {
      log("CENTRAL", "no characteristics returned")
      return failOrRetry("no_chars")
    }
    let found = chars.map { $0.uuid.uuidString }.joined(separator: ",")
    log("CENTRAL", "characteristics discovered [\(found)]")

    reqChar = chars.first(where: { $0.uuid == GATTProfile.reqCharUUID })
    chunkChar = chars.first(where: { $0.uuid == GATTProfile.chunkCharUUID })

    guard let reqChar = reqChar, let chunkChar = chunkChar else {
      log(
        "CENTRAL",
        "required characteristic missing req=\(self.reqChar != nil) chunk=\(self.chunkChar != nil)"
      )
      return failOrRetry("missing_char")
    }

    log("CENTRAL", "subscribe chunk=\(chunkChar.uuid.uuidString) req=\(reqChar.uuid.uuidString)")
    onStatus?(.subscribing, nil)
    peripheral.setNotifyValue(true, for: chunkChar)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    if let e = error {
      log("CENTRAL", "notifyState error \(e.localizedDescription)")
      return failOrRetry("notify_fail")
    }
    guard characteristic.uuid == GATTProfile.chunkCharUUID else {
      log("CENTRAL", "ignore notify state for unexpected characteristic=\(characteristic.uuid.uuidString)")
      return
    }

    log("CENTRAL", "notify enabled=\(characteristic.isNotifying) characteristic=\(characteristic.uuid.uuidString)")
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
    guard characteristic.uuid == GATTProfile.chunkCharUUID else {
      log("CENTRAL", "ignore value for unexpected characteristic=\(characteristic.uuid.uuidString)")
      return
    }
    guard let value = characteristic.value else {
      log("CENTRAL", "chunk update has nil value")
      return
    }
    guard value.count >= 3 else {
      log("CENTRAL", "chunk too short bytes=\(value.count)")
      return
    }

    let seq = UInt16(value[0]) | (UInt16(value[1]) << 8)
    let flags = value[2]
    let payload = value.subdata(in: 3..<value.count)
    log("CENTRAL", "chunk seq=\(seq) flags=0x\(String(flags, radix: 16)) payloadBytes=\(payload.count)")

    let (previewReady, completed, fullData) = assembler.addChunk(seq: seq, flags: flags, payload: payload)

    if previewReady {
      log("CENTRAL", "preview ready")
      onStatus?(.receivingPreview, nil)
    }

    if completed, let fullData = fullData {
      stopTimeout()
      let s = String(data: fullData, encoding: .utf8) ?? ""
      let preview = String(s.prefix(120))
      log("CENTRAL", "body completed bytes=\(fullData.count) chars=\(s.count)")
      onBody?(s)
      onPreview?(preview)
      onStatus?(.completed, nil)
      cm.cancelPeripheralConnection(peripheral)
      finishRequest()
    }
  }
}
