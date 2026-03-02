## 0) 最小テストアプリのゴール

同一アプリを2台のiPhoneに入れて、両方で会場モードONしたら：

* 互いの **短句（teaser）** をスキャンで発見できる
* タップして接続→ `REQ` を送ると
* 相手が **本文（body）をNotifyでチャンク送信**し
* 受信側で **先頭120Bだけでも**表示できる（可能なら全体も）

---

## 1) プロジェクト構成（SwiftUI + CoreBluetooth）

```
BittraBLETest/
  App/
    BittraBLETestApp.swift
  UI/
    ContentView.swift
    StreamView.swift
    DetailView.swift
    ComposeView.swift
    LogsView.swift
  BLE/
    BLECoordinator.swift
    BLECentral.swift
    BLEPeripheral.swift
    GATTProfile.swift
    PayloadCodec.swift
    ChunkAssembler.swift
  Model/
    Encounter.swift
    RequestState.swift
    LogEvent.swift
```

SwiftUIで最小UI、BLEはCoordinatorで統合。

---

## 2) GATTプロファイル（UUID固定）

`GATTProfile.swift`

* `serviceUUID`: `"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"`
* `reqCharUUID`: `"…REQ…"`（WriteWithoutResponse）
* `chunkCharUUID`: `"…CHUNK…"`（Notify）
* できれば `metaCharUUID`（Read）も後で足せるが、**最小はREQ+CHUNKだけでOK**

---

## 3) 状態機械（ここが肝）

`RequestState.swift`

```swift
enum RequestStatus {
  case idle
  case connecting
  case discovering
  case subscribing
  case requesting
  case receivingPreview   // 冒頭120B到達
  case completed          // 可能なら全文
  case timeout
  case failed(String)
}
```

タイムアウトは **2.0秒**、リトライは **1回だけ**（Central側で）。

---

## 4) モデル

`Encounter.swift`

```swift
struct Encounter: Identifiable, Hashable {
  let id: UUID
  let peerId: UUID          // peripheral.identifier
  let teaser: String
  var rssi: Int
  var firstSeen: Date
  var lastSeen: Date
  var count: Int
}
```

* 集約キーは `peerId + teaser`
* 10分ウィンドウ集約はテストでは軽く（後で本番ロジックへ）

---

## 5) ログ設計（実機で詰まった時に効く）

`LogEvent.swift`

```swift
struct LogEvent: Identifiable {
  let id = UUID()
  let ts: Date
  let tag: String   // "SCAN", "ADV", "CENTRAL", "PERIPH", "GATT"
  let msg: String
}
```

UIに常時出す（LogsView）。

---

## 6) コーデック（広告 payload とチャンク）

### 6-1) 広告 payload

`PayloadCodec.swift`

* `magic = 0x62 0x74`
* `nonce` 2B random
* `len` 1B
* `teaserBytes`（UTF-8, **最大18B推奨**）

関数：

* `encodeAdvert(teaser: String) -> Data`
* `decodeAdvert(data: Data) -> (nonce: UInt16, teaser: String)?`
* `normalizeTeaser(input: String) -> String`

  * trim
  * 制御文字除去
  * NFC
  * **8文字固定**
  * UTF-8で**最大18B**に収まるように安全に切る

### 6-2) 本文チャンク

`ChunkAssembler.swift`

* 送信パケット：

  * `seq: UInt16`（2B）
  * `flags: UInt8`（1B）bit0 = last
  * `payload: Data`

受信側は seq順に連結（順不同が来たら失敗でOK、MVPは粘らない）

---

## 7) Peripheral側（広告＋GATTサーバ）

`BLEPeripheral.swift`（CBPeripheralManagerDelegate）

責務：

* 広告開始/停止（Service UUID + ServiceData）
* GATTサービス公開（REQ write / CHUNK notify）
* CentralからREQを受けたら本文をチャンクにしてnotify送信

重要な実装メモ：

* `chunkChar` は `.notify`
* `reqChar` は `.writeWithoutResponse`
* `updateValue` は **送信バッファが詰まる**ことがあるので、戻り値 false の時は少し待って再送（最小は `peripheralManagerIsReady(toUpdateSubscribers:)` で続行）
* 最初の120B（プレビュー）を優先して送る

送信手順（おすすめ）：

1. 本文UTF-8化
2. `preview = bytes.prefix(120)`
3. `rest = bytes.dropFirst(120)`
4. 先に preview をチャンク送信（lastフラグはrestが空なら立てる）
5. 余裕があれば rest も送る（会場では途中で落ちてもOK）

---

## 8) Central側（スキャン＋接続＋REQ＋受信）

`BLECentral.swift`（CBCentralManagerDelegate, CBPeripheralDelegate）

責務：

* スキャン開始/停止（Service UUIDフィルタ）
* 発見した広告から `Encounter` を生成/更新
* `requestBody(peerId)` が来たら接続フロー開始

接続フロー（最短）：

1. connect
2. discoverServices([serviceUUID])
3. discoverCharacteristics([reqCharUUID, chunkCharUUID])
4. setNotifyValue(true, for: chunkChar)
5. writeValue(REQ, for: reqChar, type: .withoutResponse)
6. didUpdateValueFor chunkChar で受信・組み立て
7. 2秒タイムアウト、失敗なら1回だけやり直し

タイムアウト管理：

* `DispatchSourceTimer` でステートごとに監視
* `receivingPreview` に入ったらタイムアウトを少し伸ばす…は最初いらない（まずは2秒固定で挙動を見る）

---

## 9) Coordinator（Flutterに繋ぐ“前”の統合ポイント）

`BLECoordinator.swift`（ObservableObject）

プロパティ：

* `@Published var encounters: [Encounter]`
* `@Published var statusText: String`
* `@Published var logs: [LogEvent]`
* `@Published var myTeaser: String`
* `@Published var myBody: String`
* `@Published var isVenueModeOn: Bool`
* `@Published var activeRequest: RequestStatus`
* `@Published var receivedPreview: String`
* `@Published var receivedBody: String?`

API：

* `startVenueMode()`: startAdvertise + startScan
* `stopVenueMode()`
* `setTeaser(_:)` / `setBody(_:)`
* `requestFullText(for encounter: Encounter)`

ここが後で MethodChannel の中身にほぼなる。

---

## 10) UI（SwiftUI最小）

### StreamView

* 会場モードON/OFF
* 自分の短句/本文入力（Composeへの導線でもOK）
* Encounterリスト（teaser / rssi / count）
* 行タップで `requestFullText`

### DetailView

* 受信した `preview` と `body`（あれば）
* RequestStatus表示

### LogsView

* ログが時系列で見える（フィルタは要らない）

---

## 11) 最初に実装する順番（最短で詰まる場所を踏む）

1. **Scanだけ**：payload復元してリストに出す
2. **Advertiseだけ**：別端末で見える
3. **Advertise＋Scan同時**：双方ONで双方見える
4. **GATT**：REQ→preview(120B)が受信できる
5. タイムアウト＆リトライ（2秒/1回）

---

## 12) できたらこの1枚で判定できる「合格」基準

* 会場モードON同士で、相手の短句が **数秒以内に必ず見える**
* “全文”押下で、**冒頭プレビューが2秒以内に出る**（成功率が低くてもOK）
* 失敗してもUIが固まらず、ログに原因が残る

---

この次は、上の設計どおりに **各ファイルの「型定義＋主要メソッドの雛形（ほぼコピペで埋められる骨格コード）」**を一気に書くよ。
（Swiftコードをそのまま貼る形になるけど、進めていい？）
了解。じゃあ設計どおりに、**各ファイルの雛形コード**を「コピペで動かし始められる」粒度で出すね。
（UUIDは仮。まずは“2台で動く”確認が目的なので、最小で通す）

---

## 0) 事前準備（Info.plist）

iOSはこれが無いとスキャン/広告で詰まることが多い。

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>近くの端末と短い感想をやり取りするためにBluetoothを使います</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>近くの端末と短い感想をやり取りするためにBluetoothを使います</string>
```

---

## 1) App/BittraBLETestApp.swift

```swift
import SwiftUI

@main
struct BittraBLETestApp: App {
  @StateObject private var ble = BLECoordinator()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(ble)
    }
  }
}
```

---

## 2) UI/ContentView.swift（タブ3つ）

```swift
import SwiftUI

struct ContentView: View {
  var body: some View {
    TabView {
      StreamView()
        .tabItem { Label("すれちがい", systemImage: "dot.radiowaves.left.and.right") }

      ComposeView()
        .tabItem { Label("投稿", systemImage: "square.and.pencil") }

      LogsView()
        .tabItem { Label("ログ", systemImage: "doc.plaintext") }
    }
  }
}
```

---

## 3) UI/StreamView.swift（発見リスト→全文要求）

```swift
import SwiftUI

struct StreamView: View {
  @EnvironmentObject var ble: BLECoordinator

  var body: some View {
    NavigationView {
      List {
        Section {
          Toggle("会場モード", isOn: $ble.isVenueModeOn)
            .onChange(of: ble.isVenueModeOn) { _, on in
              on ? ble.startVenueMode() : ble.stopVenueMode()
            }

          HStack {
            Text("送信短句")
            Spacer()
            Text(ble.myTeaser.isEmpty ? "未設定" : ble.myTeaser)
              .foregroundStyle(.secondary)
          }
        }

        Section("すれちがい") {
          ForEach(ble.encounters) { e in
            Button {
              ble.requestBody(for: e)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(e.teaser).font(.headline)
                  Text("RSSI \(e.rssi)  ×\(e.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("全文")
                  .font(.caption)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(.thinMaterial)
                  .cornerRadius(8)
              }
            }
          }
        }

        Section("受信") {
          VStack(alignment: .leading, spacing: 8) {
            Text("状態: \(ble.activeStatusText)")
              .font(.caption)
              .foregroundStyle(.secondary)

            if !ble.receivedPreview.isEmpty {
              Text(ble.receivedPreview)
                .font(.body)
            }

            if let body = ble.receivedBody {
              Divider()
              Text(body)
                .font(.body)
            }
          }
          .padding(.vertical, 6)
        }
      }
      .navigationTitle("びっとら（テスト）")
    }
  }
}
```

---

## 4) UI/ComposeView.swift（短句8文字固定＋本文）

```swift
import SwiftUI

struct ComposeView: View {
  @EnvironmentObject var ble: BLECoordinator
  @State private var teaserInput: String = ""
  @State private var bodyInput: String = ""

  var body: some View {
    Form {
      Section("短句（8文字固定）") {
        TextField("例：英国片思い", text: $teaserInput)
          .onChange(of: teaserInput) { _, v in
            // UIは8文字固定（表示上）
            if v.count > 8 { teaserInput = String(v.prefix(8)) }
          }

        Text("\(teaserInput.count)/8")
          .font(.caption)
          .foregroundStyle(.secondary)

        Button("短句を適用") {
          ble.setMyTeaser(teaserInput)
        }
        .disabled(teaserInput.isEmpty)
      }

      Section("本文（任意）") {
        TextEditor(text: $bodyInput)
          .frame(minHeight: 140)

        Button("本文を適用") {
          ble.setMyBody(bodyInput)
        }
      }

      Section {
        Button("会場モード ON（送受信開始）") {
          ble.isVenueModeOn = true
          ble.startVenueMode()
        }
        Button("会場モード OFF（停止）") {
          ble.isVenueModeOn = false
          ble.stopVenueMode()
        }
      }
    }
    .onAppear {
      teaserInput = ble.myTeaser
      bodyInput = ble.myBody
    }
    .navigationTitle("投稿")
  }
}
```

---

## 5) UI/LogsView.swift

```swift
import SwiftUI

struct LogsView: View {
  @EnvironmentObject var ble: BLECoordinator

  var body: some View {
    NavigationView {
      List {
        ForEach(ble.logs) { l in
          VStack(alignment: .leading, spacing: 3) {
            Text("[\(l.tag)] \(l.msg)")
              .font(.caption)
            Text(l.ts.formatted(date: .omitted, time: .standard))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("ログ")
      .toolbar {
        Button("消去") { ble.clearLogs() }
      }
    }
  }
}
```

---

## 6) Model/Encounter.swift

```swift
import Foundation

struct Encounter: Identifiable, Hashable {
  let id: UUID
  let peerId: UUID
  let teaser: String
  var rssi: Int
  var firstSeen: Date
  var lastSeen: Date
  var count: Int

  var dedupeKey: String { "\(peerId.uuidString)|\(teaser)" }
}
```

---

## 7) Model/LogEvent.swift

```swift
import Foundation

struct LogEvent: Identifiable {
  let id = UUID()
  let ts: Date
  let tag: String
  let msg: String
}
```

---

## 8) Model/RequestState.swift

```swift
import Foundation

enum RequestStatus: Equatable {
  case idle
  case connecting
  case discovering
  case subscribing
  case requesting
  case receivingPreview
  case completed
  case timeout
  case failed(String)
}
```

---

## 9) BLE/GATTProfile.swift（UUIDをここで固定）

```swift
import Foundation
import CoreBluetooth

enum GATTProfile {
  // 適当に生成したUUIDに置換してOK（iOS/Androidで揃える）
  static let serviceUUID = CBUUID(string: "9E2A0001-4B5A-4F5E-9A9D-1B7A00000001")
  static let reqCharUUID = CBUUID(string: "9E2A0002-4B5A-4F5E-9A9D-1B7A00000002")
  static let chunkCharUUID = CBUUID(string: "9E2A0003-4B5A-4F5E-9A9D-1B7A00000003")

  static let magic: UInt16 = 0x6274 // "bt"
  static let maxTeaserUTF8Bytes: Int = 18
  static let previewBytes: Int = 120
}
```

---

## 10) BLE/PayloadCodec.swift（8文字固定＋UTF-8バイト上限で安全に切る）

```swift
import Foundation

enum PayloadCodec {

  static func normalizeTeaser(_ input: String) -> String {
    // 1) trim
    var s = input.trimmingCharacters(in: .whitespacesAndNewlines)

    // 2) 制御文字を除去
    s.removeAll { ch in
      ch.unicodeScalars.contains { $0.properties.isControl }
    }

    // 3) NFC
    s = s.precomposedStringWithCanonicalMapping

    // 4) UI的に8文字固定
    if s.count > 8 { s = String(s.prefix(8)) }

    // 5) UTF-8バイトで安全に切る（最大18B）
    s = clipUTF8ToMaxBytes(s, maxBytes: GATTProfile.maxTeaserUTF8Bytes)
    return s
  }

  static func encodeAdvert(teaser: String, nonce: UInt16) -> Data {
    let t = normalizeTeaser(teaser)
    let teaserBytes = Data(t.utf8)

    var data = Data()
    // magic (2B) little-endian
    data.append(UInt8(GATTProfile.magic & 0xFF))
    data.append(UInt8((GATTProfile.magic >> 8) & 0xFF))
    // nonce (2B) little-endian
    data.append(UInt8(nonce & 0xFF))
    data.append(UInt8((nonce >> 8) & 0xFF))
    // len (1B)
    data.append(UInt8(min(255, teaserBytes.count)))
    // teaser
    data.append(teaserBytes)
    return data
  }

  static func decodeAdvert(_ data: Data) -> (nonce: UInt16, teaser: String)? {
    if data.count < 5 { return nil }
    let m0 = UInt16(data[0])
    let m1 = UInt16(data[1]) << 8
    let magic = m0 | m1
    guard magic == GATTProfile.magic else { return nil }

    let n0 = UInt16(data[2])
    let n1 = UInt16(data[3]) << 8
    let nonce = n0 | n1

    let len = Int(data[4])
    guard data.count >= 5 + len else { return nil }

    let teaserBytes = data.subdata(in: 5..<(5 + len))
    let teaser = String(data: teaserBytes, encoding: .utf8) ?? ""
    return (nonce, teaser)
  }

  // UTF-8を壊さず maxBytes 以内に切る
  private static func clipUTF8ToMaxBytes(_ s: String, maxBytes: Int) -> String {
    var out = ""
    var used = 0
    for ch in s {
      let b = String(ch).utf8.count
      if used + b > maxBytes { break }
      out.append(ch)
      used += b
    }
    return out
  }
}
```

---

## 11) BLE/ChunkAssembler.swift（冒頭120B到達で preview 完了）

```swift
import Foundation

final class ChunkAssembler {
  private var chunks: [UInt16: Data] = [:]
  private var receivedBytes: Int = 0
  private var lastSeq: UInt16?
  private let previewTarget: Int

  init(previewTarget: Int = GATTProfile.previewBytes) {
    self.previewTarget = previewTarget
  }

  func reset() {
    chunks.removeAll()
    receivedBytes = 0
    lastSeq = nil
  }

  // returns: (previewReady, completed, fullData)
  func addChunk(seq: UInt16, flags: UInt8, payload: Data) -> (Bool, Bool, Data?) {
    if chunks[seq] == nil {
      chunks[seq] = payload
      receivedBytes += payload.count
    }
    if (flags & 0x01) != 0 {
      lastSeq = seq
    }

    let previewReady = receivedBytes >= previewTarget

    // 完了判定：0..lastSeqが全部揃ってる
    if let last = lastSeq {
      for i in 0...last {
        if chunks[i] == nil { return (previewReady, false, nil) }
      }
      var data = Data()
      for i in 0...last { data.append(chunks[i]!) }
      return (previewReady, true, data)
    }
    return (previewReady, false, nil)
  }
}
```

---

## 12) BLE/BLEPeripheral.swift（広告＋GATTサーバ）

```swift
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
    guard pm.state == .poweredOn else {
      log("PERIPH", "Bluetooth not poweredOn yet")
      return
    }
    setupGATTIfNeeded()
    startAdvertising()
  }

  func stop() {
    pm.stopAdvertising()
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
    pm.add(service)
    log("PERIPH", "GATT service added")
  }

  private func startAdvertising() {
    let nonce = UInt16.random(in: 0...UInt16.max)
    let payload = PayloadCodec.encodeAdvert(teaser: myTeaser, nonce: nonce)

    pm.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [GATTProfile.serviceUUID],
      CBAdver3nP5oFahNL86vESFrkKjmuupsQa1mPzN7: [GATTProfile.serviceUUID: payload]
    ])
    log("ADV", "startAdvertising teaser=\(PayloadCodec.normalizeTeaser(myTeaser)) bytes=\(payload.count)")
  }

  // MARK: - CBPeripheralManagerDelegate

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    log("PERIPH", "state=\(peripheral.state.rawValue)")
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

    // lastフラグを最後のpacketに立てる
    if !pendingNotifyPackets.isEmpty {
      pendingNotifyPackets[pendingNotifyPackets.count - 1][2] = 0x01
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
```

---

## 13) BLE/BLECentral.swift（スキャン＋接続＋REQ＋受信）

```swift
import Foundation
import CoreBluetooth

final class BLECentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

  private var cm: CBCentralManager!
  private let log: (String, String) -> Void

  // 発見データ
  var onEncounter: ((UUID, String, Int) -> Void)?

  // 本文受信
  var onStatus: ((RequestStatus) -> Void)?
  var onPreview: ((String) -> Void)?
  var onBody: ((String) -> Void)?

  private var targetPeripheral: CBPeripheral?
  private var reqChar: CBCharacteristic?
  private var chunkChar: CBCharacteristic?

  private var assembler = ChunkAssembler()
  private var timeoutTimer: DispatchSourceTimer?
  private var retryLeft: Int = 1

  init(log: @escaping (String, String) -> Void) {
    self.log = log
    super.init()
    self.cm = CBCentralManager(delegate: self, queue: nil)
  }

  func startScan() {
    guard cm.state == .poweredOn else {
      log("CENTRAL", "Bluetooth not poweredOn yet")
      return
    }
    cm.scanForPeripherals(withServices: [GATTProfile.serviceUUID], options: [
      CBCentralManagerScanOptionAllowDuplicatesKey: true
    ])
    log("SCAN", "startScan")
  }

  func stopScan() {
    cm.stopScan()
    log("SCAN", "stopScan")
  }

  func requestBody(peerId: UUID) {
    // 既に発見済みの peripheral を CBCentralManager が保持してないので、
    // 実運用では Encounter に CBPeripheral を保持するか、discovery時にキャッシュする。
    // テストでは「最後に見つけた peripheral」を使う形にして簡略化するのが早い。
    log("CENTRAL", "requestBody called for peerId=\(peerId)")
    // ここは Coordinator 側で peerId→peripheral を引いて connect(peer) する設計にする
  }

  func connect(_ peripheral: CBPeripheral) {
    resetRequestState()
    retryLeft = 1
    targetPeripheral = peripheral
    targetPeripheral?.delegate = self
    onStatus?(.connecting)
    cm.connect(peripheral, options: nil)
    startTimeout(seconds: 2.0)
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
      guard let self else { return }
      self.log("CENTRAL", "timeout")
      self.onStatus?(.timeout)
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
      onStatus?(.failed(reason))
      if let p = targetPeripheral {
        cm.cancelPeripheralConnection(p)
      }
      stopTimeout()
    }
  }

  // MARK: - CBCentralManagerDelegate

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    log("CENTRAL", "state=\(central.state.rawValue)")
  }

  func centralManager(_ central: CBCentralManager,
                      didDiscover peripheral: CBPeripheral,
                      advertisementData: [String : Any],
                      rssi RSSI: NSNumber) {
    guard let sd = advertisementData[CBAdverQuMHtpwbtsTXsRMArUQeWyGrRu7gwbZs2] as? [CBUUID: Data],
          let payload = sd[GATTProfile.serviceUUID],
          let decoded = PayloadCodec.decodeAdvert(payload) else { return }

    onEncounter?(peripheral.identifier, decoded.teaser, RSSI.intValue)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    log("CENTRAL", "didConnect")
    onStatus?(.discovering)
    peripheral.discoverServices([GATTProfile.serviceUUID])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    log("CENTRAL", "didFailToConnect \(error?.localizedDescription ?? "-")")
    failOrRetry("connect_failed")
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    log("CENTRAL", "didDisconnect \(error?.localizedDescription ?? "-")")
    // 途中切断は会場では普通に起きるので、ここでは Coordinator 側で扱う
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

    guard let reqChar, let chunkChar else { return failOrRetry("missing_char") }

    onStatus?(.subscribing)
    peripheral.setNotifyValue(true, for: chunkChar)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    if let e = error {
      log("CENTRAL", "notifyState error \(e.localizedDescription)")
      return failOrRetry("notify_fail")
    }
    guard characteristic.uuid == GATTProfile.chunkCharUUID else { return }

    onStatus?(.requesting)
    // REQ：今回は中身空でOK（「全文ください」）
    let req = Data([0x01])
    if let reqChar {
      peripheral.writeValue(req, for: reqChar, type: .withoutResponse)
      log("CENTRAL", "REQ sent")
      // タイムアウトは維持（2秒）
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
      onStatus?(.receivingPreview)
      // 受信済みの分だけテキスト化して見せる（簡易）
      // 完全な順序保証がないので、MVPでは previewReady を優先
      // （本番は0..nを揃えてからにしてもOK）
      // ここでは fullData が無い場合、今ある分を適当に連結して表示しない
    }

    if completed, let fullData {
      stopTimeout()
      let s = String(data: fullData, encoding: .utf8) ?? ""
      onBody?(s)
      onStatus?(.completed)
      cm.cancelPeripheralConnection(peripheral)
    }
  }
}
```

> ここ、previewの出し方は「順序が揃ってない可能性がある」ので、**最初は completed が取れたときだけ本文表示**にしておくと安定する。
> “冒頭だけでも”をやりたいなら、`ChunkAssembler` を「0から連続で揃った分だけ」をpreviewとして出す実装に変えるのが堅い（必要ならすぐ出す）。

---

## 14) BLE/BLECoordinator.swift（両方を束ねる）

```swift
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
    central.onEncounter = { [weak self] peerId, teaser, rssi in
      guard let self else { return }
      self.upsertEncounter(peerId: peerId, teaser: teaser, rssi: rssi)
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

    // “peerIdからperipheralを引く”が必要。
    // CoreBluetoothはdidDiscoverでCBPeripheralが渡るが、上の BLECentral は peerIdだけ上げてる。
    // なので最初は BLECentral を拡張して didDiscover の CBPeripheral もCoordinatorに渡してキャッシュするのが正解。
    addLog("APP", "requestBody teaser=\(e.teaser) peerId=\(e.peerId)")
    // TODO: cacheが入ったら central.connect(peripheral) を呼ぶ
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
```

### 重要：いまのCoordinatorは「接続」だけ未配線

CoreBluetoothの `didDiscover peripheral: CBPeripheral` が必要なので、次の小改修を入れる。

---

## 15) “接続できるようにする”最小改修（2ヶ所だけ）

### (A) BLECentral の onEncounter を peripheral も渡す

`BLECentral.swift` の定義をこう変える：

```swift
var onEncounter: ((CBPeripheral, String, Int) -> Void)?
```

そして `didDiscover` で：

```swift
onEncounter?(peripheral, decoded.teaser, RSSI.intValue)
```

### (B) Coordinator で peripheral をキャッシュして接続

`BLECoordinator.init()` をこう：

```swift
central.onEncounter = { [weak self] peripheral, teaser, rssi in
  guard let self else { return }
  self.peripheralCache[peripheral.identifier] = peripheral
  self.upsertEncounter(peerId: peripheral.identifier, teaser: teaser, rssi: rssi)
}
```

`requestBody(for:)` で：

```swift
guard let p = peripheralCache[e.peerId] else {
  addLog("APP", "no cached peripheral (wait a bit and try again)")
  return
}
central.connect(p)
```

これで **タップ→接続→REQ→本文受信** まで一気に通せる。

---