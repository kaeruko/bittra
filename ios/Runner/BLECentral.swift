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

  private static let initialContinuousScanSeconds: Double = 15.0
  private static let steadyScanWindowSeconds: Double = 5.0
  private static let steadyScanPauseSeconds: Double = 10.0

  private var cm: CBCentralManager!
  private let log: (String, String) -> Void

  var onEncounter: ((CBPeripheral, UInt32, String, Int) -> Void)?
  var onStatus: ((RequestStatus, String?) -> Void)?
  var onPreview: ((String) -> Void)?
  var onBody: ((String) -> Void)?

  private var targetPeripheral: CBPeripheral?
  private var reqChar: CBCharacteristic?
  private var chunkChar: CBCharacteristic?
  private var ackChar: CBCharacteristic?

  private var assembler = ChunkAssembler()
  private var timeoutTimer: DispatchSourceTimer?
  private var ackTimeoutTimer: DispatchSourceTimer?
  private var scanPhaseTimer: DispatchSourceTimer?
  private var pendingCompletedBody: String?
  private var retryLeft: Int = 1
  private var shouldScanWhenPoweredOn: Bool = false
  private var scanEnabled: Bool = false
  private var resumeScanAfterRequest: Bool = false

  init(log: @escaping (String, String) -> Void) {
    self.log = log
    super.init()
    self.cm = CBCentralManager(delegate: self, queue: nil)
  }

  func startScan(initialBoost: Bool = true) {
    guard cm.state == .poweredOn else {
      shouldScanWhenPoweredOn = true
      log("CENTRAL", "Bluetooth not poweredOn yet state=\(cm.state.rawValue)")
      return
    }
    guard !scanEnabled else {
      log("SCAN", "already enabled scanning=\(cm.isScanning)")
      return
    }

    scanEnabled = true
    if initialBoost {
      beginHardwareScan()
      scheduleInitialScanEnd()
    } else {
      beginSteadyScanWindow()
    }
  }

  func stopScan() {
    shouldScanWhenPoweredOn = false
    scanEnabled = false
    cancelScanPhaseTimer()
    stopHardwareScan(logMessage: "stopScan")
  }

  private func beginHardwareScan() {
    guard scanEnabled else { return }
    guard cm.state == .poweredOn else {
      shouldScanWhenPoweredOn = true
      return
    }
    guard !cm.isScanning else { return }

    cm.scanForPeripherals(withServices: [GATTProfile.serviceUUID], options: [
      CBCentralManagerScanOptionAllowDuplicatesKey: false
    ])
    log("SCAN", "startScan serviceUUID=\(GATTProfile.serviceUUID.uuidString) duplicates=false")
  }

  private func stopHardwareScan(logMessage: String) {
    if cm.isScanning {
      cm.stopScan()
    }
    log("SCAN", logMessage)
  }

  private func scheduleInitialScanEnd() {
    scheduleScanPhase(after: Self.initialContinuousScanSeconds) { [weak self] in
      guard let self = self, self.scanEnabled else { return }
      self.stopHardwareScan(logMessage: "initial 15s scan complete; pause 10s")
      self.scheduleSteadyScanRestart()
    }
  }

  private func beginSteadyScanWindow() {
    guard scanEnabled else { return }
    beginHardwareScan()
    scheduleScanPhase(after: Self.steadyScanWindowSeconds) { [weak self] in
      guard let self = self, self.scanEnabled else { return }
      self.stopHardwareScan(logMessage: "steady 5s scan complete; pause 10s")
      self.scheduleSteadyScanRestart()
    }
  }

  private func scheduleSteadyScanRestart() {
    scheduleScanPhase(after: Self.steadyScanPauseSeconds) { [weak self] in
      guard let self = self, self.scanEnabled else { return }
      self.beginSteadyScanWindow()
    }
  }

  private func scheduleScanPhase(after seconds: Double, handler: @escaping () -> Void) {
    cancelScanPhaseTimer()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + seconds)
    timer.setEventHandler(handler: handler)
    timer.resume()
    scanPhaseTimer = timer
  }

  private func cancelScanPhaseTimer() {
    scanPhaseTimer?.cancel()
    scanPhaseTimer = nil
  }

  private func suspendScanForRequest() {
    scanEnabled = false
    cancelScanPhaseTimer()
    stopHardwareScan(logMessage: "pause scan for body request")
  }

  func requestBody(peripheral: CBPeripheral) {
    log("CENTRAL", "requestBody called for peerId=\(peripheral.identifier)")
    retryLeft = 1
    targetPeripheral = peripheral
    resumeScanAfterRequest = scanEnabled
    if scanEnabled {
      suspendScanForRequest()
    }
    connect(peripheral)
  }

  private func connect(_ peripheral: CBPeripheral) {
    resetRequestState()
    targetPeripheral?.delegate = self
    onStatus?(.connecting, nil)
    cm.connect(peripheral, options: nil)
    startTimeout(seconds: 3.0)
    log("CENTRAL", "connect start \(peripheral.identifier)")
  }

  private func resetRequestState() {
    stopTimeout()
    stopAckTimeout()
    assembler.reset()
    pendingCompletedBody = nil
    reqChar = nil
    chunkChar = nil
    ackChar = nil
  }

  private func startTimeout(seconds: Double) {
    stopTimeout()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + seconds)
    timer.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.log("CENTRAL", "timeout")
      self.onStatus?(.timeout, nil)
      self.failOrRetry("timeout")
    }
    timer.resume()
    timeoutTimer = timer
  }

  private func stopTimeout() {
    timeoutTimer?.cancel()
    timeoutTimer = nil
  }

  private func startAckTimeout(seconds: Double) {
    stopAckTimeout()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + seconds)
    timer.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.log("CENTRAL", "delivery ACK timeout")
      self.completePendingBody()
    }
    timer.resume()
    ackTimeoutTimer = timer
  }

  private func stopAckTimeout() {
    ackTimeoutTimer?.cancel()
    ackTimeoutTimer = nil
  }

  private func failOrRetry(_ reason: String) {
    stopTimeout()
    stopAckTimeout()
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
      startScan(initialBoost: false)
    }
  }

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

    let decoded: (senderId: UInt32, teaser: String)?
    if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfgData.count > 2 {
      let payload = Data(mfgData.dropFirst(2))
      decoded = PayloadCodec.decodeAdvert(payload)
      log(
        "SCAN",
        "payload source=manufacturer totalBytes=\(mfgData.count) payloadBytes=\(mfgData.count - 2)"
      )
    } else if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
      if let compact = PayloadCodec.decodeLocalName(localName) {
        decoded = compact
        log("SCAN", "payload source=compactLocalName bytes=\(localName.utf8.count)")
      } else if let data = Data(base64Encoded: localName) {
        decoded = PayloadCodec.decodeAdvert(data)
        log("SCAN", "payload source=localName base64Chars=\(localName.count) payloadBytes=\(data.count)")
      } else {
        decoded = nil
        log("SCAN", "skip id=\(peripheral.identifier) unknown localName format: \(localName)")
      }
    } else {
      decoded = nil
      log("SCAN", "skip id=\(peripheral.identifier) no manufacturerData/localName payload")
    }

    guard let decoded = decoded else {
      log("SCAN", "skip id=\(peripheral.identifier) advert decode failed")
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

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error = error {
      log("CENTRAL", "discoverServices error \(error.localizedDescription)")
      return failOrRetry("discover_services")
    }
    guard let services = peripheral.services,
          let service = services.first(where: { $0.uuid == GATTProfile.serviceUUID }) else {
      let found = peripheral.services?.map { $0.uuid.uuidString }.joined(separator: ",") ?? "none"
      log("CENTRAL", "required service missing found=[\(found)]")
      return failOrRetry("no_service")
    }
    log("CENTRAL", "service discovered uuid=\(service.uuid.uuidString)")
    peripheral.discoverCharacteristics(nil, for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let error = error {
      log("CENTRAL", "discoverChars error \(error.localizedDescription)")
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
    ackChar = chars.first(where: { $0.uuid == GATTProfile.ackCharUUID })

    guard let reqChar = reqChar, let chunkChar = chunkChar else {
      log(
        "CENTRAL",
        "required characteristic missing req=\(self.reqChar != nil) chunk=\(self.chunkChar != nil)"
      )
      return failOrRetry("missing_char")
    }

    if ackChar == nil {
      log("CENTRAL", "sender does not support delivery ACK")
    }

    log("CENTRAL", "subscribe chunk=\(chunkChar.uuid.uuidString) req=\(reqChar.uuid.uuidString)")
    onStatus?(.subscribing, nil)
    peripheral.setNotifyValue(true, for: chunkChar)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    if let error = error {
      log("CENTRAL", "notifyState error \(error.localizedDescription)")
      return failOrRetry("notify_fail")
    }
    guard characteristic.uuid == GATTProfile.chunkCharUUID else {
      log("CENTRAL", "ignore notify state for unexpected characteristic=\(characteristic.uuid.uuidString)")
      return
    }

    log("CENTRAL", "notify enabled=\(characteristic.isNotifying) characteristic=\(characteristic.uuid.uuidString)")
    onStatus?(.requesting, nil)
    let req = Data([0x01])
    guard let reqChar = reqChar else {
      return failOrRetry("no_req_char")
    }
    peripheral.writeValue(req, for: reqChar, type: .withoutResponse)
    log("CENTRAL", "REQ sent")
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if let error = error {
      log("CENTRAL", "didUpdateValue error \(error.localizedDescription)")
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
      guard let body = String(data: fullData, encoding: .utf8) else {
        failWithoutRetry("body_invalid_utf8")
        return
      }
      log("CENTRAL", "body completed bytes=\(fullData.count) chars=\(body.count)")
      pendingCompletedBody = body
      sendDeliveryAckOrComplete(peripheral)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic.uuid == GATTProfile.ackCharUUID else { return }
    stopAckTimeout()
    if let error = error {
      log("CENTRAL", "delivery ACK failed error=\(error.localizedDescription)")
    } else {
      log("CENTRAL", "delivery ACK confirmed")
    }
    completePendingBody()
  }

  private func sendDeliveryAckOrComplete(_ peripheral: CBPeripheral) {
    guard let ackChar = ackChar else {
      completePendingBody()
      return
    }
    startAckTimeout(seconds: 2.0)
    peripheral.writeValue(Data([0x02]), for: ackChar, type: .withResponse)
    log("CENTRAL", "delivery ACK sent")
  }

  private func completePendingBody() {
    stopAckTimeout()
    guard let body = pendingCompletedBody else { return }
    pendingCompletedBody = nil
    let preview = String(body.prefix(120))
    onBody?(body)
    onPreview?(preview)
    onStatus?(.completed, nil)
    if let peripheral = targetPeripheral {
      cm.cancelPeripheralConnection(peripheral)
    }
    finishRequest()
  }

  private func failWithoutRetry(_ reason: String) {
    stopTimeout()
    stopAckTimeout()
    log("CENTRAL", "request failed without retry reason=\(reason)")
    onStatus?(.failed, reason)
    if let peripheral = targetPeripheral {
      cm.cancelPeripheralConnection(peripheral)
    }
    finishRequest()
  }
}
