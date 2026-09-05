import Foundation
import CoreBluetooth

final class BLEPeripheral: NSObject, CBPeripheralManagerDelegate {

  private var pm: CBPeripheralManager!
  private let log: (String, String) -> Void
  private let onDeliveryReceipt: (String, Int) -> Void

  private var reqChar: CBMutableCharacteristic!
  private var chunkChar: CBMutableCharacteristic!
  private var ackChar: CBMutableCharacteristic!
  private var service: CBMutableService!

  private var myNoticeId: String = ""
  private var myTeaser: String = ""
  private var myBody: String = ""

  private var pendingNotifyPackets: [Data] = []
  private var isNotifying: Bool = false
  private var shouldStartWhenPoweredOn: Bool = false
  private var isGattServiceReady: Bool = false
  private var startAdvertisingWhenReady: Bool = false

  private var pendingNoticeByCentral: [UUID: String] = [:]
  private var acknowledgedCentralsByNotice: [String: Set<UUID>] = [:]

  private lazy var senderId: UInt16 = {
    let defaults = UserDefaults.standard
    let key = "bittra_ble_sender_id"
    if defaults.object(forKey: key) != nil {
      return UInt16(truncatingIfNeeded: defaults.integer(forKey: key))
    }
    let generated = UInt16.random(in: 1...UInt16.max)
    defaults.set(Int(generated), forKey: key)
    return generated
  }()

  init(
    log: @escaping (String, String) -> Void,
    onDeliveryReceipt: @escaping (String, Int) -> Void
  ) {
    self.log = log
    self.onDeliveryReceipt = onDeliveryReceipt
    super.init()
    self.pm = CBPeripheralManager(delegate: self, queue: nil)
  }

  func setContent(noticeId: String, teaser: String, body: String) {
    precondition(!noticeId.isEmpty, "noticeId must not be empty")
    myNoticeId = noticeId
    myTeaser = teaser
    myBody = body
  }

  func start() {
    precondition(!myNoticeId.isEmpty, "Cannot start advertising without noticeId")
    guard !PayloadCodec.normalizeTeaser(myTeaser).isEmpty else {
      stop()
      log("PERIPH", "skip empty teaser advertisement")
      return
    }
    guard pm.state == .poweredOn else {
      shouldStartWhenPoweredOn = true
      log("PERIPH", "Bluetooth not poweredOn yet")
      return
    }
    if pm.isAdvertising {
      pm.stopAdvertising()
    }
    setupGATTIfNeeded()
    if isGattServiceReady {
      startAdvertising()
    } else {
      startAdvertisingWhenReady = true
    }
  }

  func stop() {
    shouldStartWhenPoweredOn = false
    startAdvertisingWhenReady = false
    pm.stopAdvertising()
    pendingNotifyPackets.removeAll()
    pendingNoticeByCentral.removeAll()
    isNotifying = false
    pm.removeAllServices()
    service = nil
    reqChar = nil
    chunkChar = nil
    ackChar = nil
    isGattServiceReady = false
    log("PERIPH", "stopAdvertising")
  }

  private func setupGATTIfNeeded() {
    if service != nil { return }

    reqChar = CBMutableCharacteristic(
      type: GATTProfile.reqCharUUID,
      properties: [.writeWithoutResponse],
      value: nil,
      permissions: [.writeable]
    )

    chunkChar = CBMutableCharacteristic(
      type: GATTProfile.chunkCharUUID,
      properties: [.notify],
      value: nil,
      permissions: []
    )

    ackChar = CBMutableCharacteristic(
      type: GATTProfile.ackCharUUID,
      properties: [.write],
      value: nil,
      permissions: [.writeable]
    )

    service = CBMutableService(type: GATTProfile.serviceUUID, primary: true)
    service.characteristics = [reqChar, chunkChar, ackChar]

    pm.removeAllServices()
    isGattServiceReady = false
    pm.add(service)
    log("PERIPH", "GATT service added")
  }

  private func startAdvertising() {
    let localName = PayloadCodec.encodeLocalName(teaser: myTeaser, senderId: senderId)

    pm.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [GATTProfile.serviceUUID],
      CBAdvertisementDataLocalNameKey: localName
    ])
    log(
      "ADV",
      "startAdvertising requested teaser=\(PayloadCodec.normalizeTeaser(myTeaser)) localNameBytes=\(localName.utf8.count)"
    )
  }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    log("PERIPH", "state=\(peripheral.state.rawValue)")
    if peripheral.state == .poweredOn && shouldStartWhenPoweredOn {
      log("PERIPH", "Bluetooth is now poweredOn, starting delayed broadcast")
      shouldStartWhenPoweredOn = false
      start()
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager,
                         didAdd service: CBService,
                         error: Error?) {
    guard self.service != nil, service === self.service else { return }
    isGattServiceReady = error == nil
    log("PERIPH", "GATT service ready error=\(error?.localizedDescription ?? "-")")
    if isGattServiceReady && startAdvertisingWhenReady {
      startAdvertisingWhenReady = false
      startAdvertising()
    }
  }

  func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager,
                                             error: Error?) {
    if let error = error {
      log("ADV", "startAdvertising failed error=\(error.localizedDescription)")
    } else {
      log("ADV", "startAdvertising success")
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    for request in requests {
      if request.characteristic.uuid == GATTProfile.reqCharUUID {
        guard request.value == Data([0x01]) else {
          log("GATT", "invalid REQ payload")
          continue
        }
        precondition(!myNoticeId.isEmpty, "REQ received without active noticeId")
        pendingNoticeByCentral[request.central.identifier] = myNoticeId
        log("GATT", "REQ received from central noticeId=\(myNoticeId)")
        sendBodyPreviewThenRest()
        continue
      }

      if request.characteristic.uuid == GATTProfile.ackCharUUID {
        guard request.value == Data([0x02]) else {
          log("GATT", "invalid ACK payload")
          pm.respond(to: request, withResult: .requestNotSupported)
          continue
        }
        guard let noticeId = pendingNoticeByCentral.removeValue(forKey: request.central.identifier) else {
          log("GATT", "ACK without pending body central=\(request.central.identifier)")
          pm.respond(to: request, withResult: .unlikelyError)
          continue
        }

        var acknowledged = acknowledgedCentralsByNotice[noticeId, default: []]
        let inserted = acknowledged.insert(request.central.identifier).inserted
        acknowledgedCentralsByNotice[noticeId] = acknowledged
        pm.respond(to: request, withResult: .success)

        if inserted {
          log("GATT", "delivery ACK noticeId=\(noticeId) count=\(acknowledged.count)")
          onDeliveryReceipt(noticeId, acknowledged.count)
        }
      }
    }
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    flushNotifyQueue()
  }

  private func sendBodyPreviewThenRest() {
    pendingNotifyPackets.removeAll()
    isNotifying = false

    let bytes = Data(myBody.utf8)
    let preview = bytes.prefix(GATTProfile.previewBytes)
    let rest = bytes.dropFirst(GATTProfile.previewBytes)

    // Keep each notification within the default ATT payload budget.
    // The packet header uses 3 bytes (seq 2B + flags 1B), leaving 17 bytes
    // for body data when the characteristic value budget is 20 bytes.
    let chunkPayloadSize = 17
    var seq: UInt16 = 0

    func enqueueChunks(_ data: Data) {
      var offset = 0
      while offset < data.count {
        let end = min(data.count, offset + chunkPayloadSize)
        let slice = data.subdata(in: offset..<end)
        offset = end

        var packet = Data()
        packet.append(UInt8(seq & 0xFF))
        packet.append(UInt8((seq >> 8) & 0xFF))
        packet.append(UInt8(0))
        packet.append(slice)
        pendingNotifyPackets.append(packet)
        seq += 1
      }
    }

    enqueueChunks(Data(preview))
    enqueueChunks(Data(rest))

    if pendingNotifyPackets.isEmpty {
      pendingNotifyPackets.append(Data([0x00, 0x00, 0x01]))
    }

    let lastIndex = pendingNotifyPackets.count - 1
    var lastPacket = pendingNotifyPackets[lastIndex]
    lastPacket[2] = 0x01
    pendingNotifyPackets[lastIndex] = lastPacket

    log("GATT", "enqueue notify packets=\(pendingNotifyPackets.count) bodyBytes=\(bytes.count)")
    flushNotifyQueue()
  }

  private func flushNotifyQueue() {
    guard !isNotifying else { return }
    isNotifying = true

    while !pendingNotifyPackets.isEmpty {
      let packet = pendingNotifyPackets[0]
      let ok = pm.updateValue(packet, for: chunkChar, onSubscribedCentrals: nil)
      if !ok {
        log("GATT", "updateValue blocked; wait ready")
        isNotifying = false
        return
      }
      pendingNotifyPackets.removeFirst()
    }
    log("GATT", "notify complete")
    isNotifying = false
  }
}
