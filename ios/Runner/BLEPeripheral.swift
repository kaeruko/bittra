import Foundation
import CoreBluetooth

final class BLEPeripheral: NSObject, CBPeripheralManagerDelegate {

  private var pm: CBPeripheralManager!
  private let log: (String, String) -> Void

  private var reqChar: CBMutableCharacteristic!
  private var chunkChar: CBMutableCharacteristic!
  private var service: CBMutableService!

  private var myTeaser: String = ""
  private var myBody: String = ""

  // 送信キュー
  private var pendingNotifyPackets: [Data] = []
  private var isNotifying: Bool = false
  private var shouldStartWhenPoweredOn: Bool = false
  private var isGattServiceReady: Bool = false
  private var startAdvertisingWhenReady: Bool = false

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

  init(log: @escaping (String, String) -> Void) {
    self.log = log
    super.init()
    self.pm = CBPeripheralManager(delegate: self, queue: nil)
  }

  func setContent(teaser: String, body: String) {
    self.myTeaser = teaser
    self.myBody = body
  }

  func start() {
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
    isNotifying = false
    pm.removeAllServices()
    service = nil
    reqChar = nil
    chunkChar = nil
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

    service = CBMutableService(type: GATTProfile.serviceUUID, primary: true)
    service.characteristics = [reqChar, chunkChar]

    pm.removeAllServices()
    isGattServiceReady = false
    pm.add(service)
    log("PERIPH", "GATT service added")
  }

  private func startAdvertising() {
    let payload = PayloadCodec.encodeAdvert(teaser: myTeaser, nonce: senderId)
    let payloadString = payload.base64EncodedString()

    pm.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [GATTProfile.serviceUUID],
      CBAdvertisementDataLocalNameKey: payloadString
    ])
    log("ADV", "startAdvertising teaser=\(PayloadCodec.normalizeTeaser(myTeaser)) bytes=\(payload.count)")
  }

  // MARK: - CBPeripheralManagerDelegate

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

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    for r in requests {
      guard r.characteristic.uuid == GATTProfile.reqCharUUID else { continue }
      // REQ受信＝即送信
      log("GATT", "REQ received from central")
      // 返信はNotifyなので respond は不要（WriteWithoutResponse）
      sendBodyPreviewThenRest()
    }
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    // 送信バッファが空いたので続行
    flushNotifyQueue()
  }

  // MARK: - Body sending

  private func sendBodyPreviewThenRest() {
    pendingNotifyPackets.removeAll()
    isNotifying = false

    let bytes = Data(myBody.utf8)
    let preview = bytes.prefix(GATTProfile.previewBytes)
    let rest = bytes.dropFirst(GATTProfile.previewBytes)

    // チャンク化（簡易：20B近辺で切る。実際はMTUで調整してOK）
    // iOSはupdateValueが返すfalseで詰まりが見えるので、ここは小さめで安全運転
    let chunkPayloadSize = 140 // 多少大きくてもOK。失敗したらready callbackで再送。
    var seq: UInt16 = 0

    func enqueueChunks(_ data: Data, isLastBlockPotentially: Bool) {
      var offset = 0
      while offset < data.count {
        let end = min(data.count, offset + chunkPayloadSize)
        let slice = data.subdata(in: offset..<end)
        offset = end

        var packet = Data()
        packet.append(UInt8(seq & 0xFF))
        packet.append(UInt8((seq >> 8) & 0xFF))
        packet.append(UInt8(0)) // flags placeholder
        packet.append(slice)
        pendingNotifyPackets.append(packet)
        seq += 1
      }
    }

    enqueueChunks(Data(preview), isLastBlockPotentially: rest.isEmpty)
    enqueueChunks(Data(rest), isLastBlockPotentially: true)

    // Send an explicit final packet even when the body is empty.
    if pendingNotifyPackets.isEmpty {
      pendingNotifyPackets.append(Data([0x00, 0x00, 0x01]))
    }

    // lastフラグを最後のpacketに立てる
    if !pendingNotifyPackets.isEmpty {
      let lastIndex = pendingNotifyPackets.count - 1
      var lastPacket = pendingNotifyPackets[lastIndex]
      lastPacket[2] = 0x01
      pendingNotifyPackets[lastIndex] = lastPacket
    }

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
        // バッファ詰まり：ready callbackで再開
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
