Flutter ⇄ iOSネイティブ（Swift）をつなぐ MethodChannel の雛形を出すね。
ここまで来たら、びっとらは「UIはFlutter、通信はネイティブ」の構成でそのまま作れる。
1) 全体構成（完成形イメージ）
Flutter (UI / 履歴 / 状態管理)
   │
   │ MethodChannel
   ▼
iOS Swift (BLE広告 / スキャン / GATT / 本文送信)
Flutter側は UIとログだけ。
Bluetoothの地雷地帯は全部Swiftに隔離。
2) Flutter 側：MethodChannel 定義
lib/ble_bridge.dart
import 'package:flutter/services.dart';

class BleBridge {
  static const _channel = MethodChannel('bittra/ble');
  static const _events = EventChannel('bittra/ble_events');

  // --- コマンド ---

  static Future<void> startVenueMode() =>
      _channel.invokeMethod('startVenueMode');

  static Future<void> stopVenueMode() =>
      _channel.invokeMethod('stopVenueMode');

  static Future<void> setTeaser(String teaser) =>
      _channel.invokeMethod('setTeaser', {'teaser': teaser});

  static Future<void> setBody(String body) =>
      _channel.invokeMethod('setBody', {'body': body});

  static Future<void> requestBody(String peerId) =>
      _channel.invokeMethod('requestBody', {'peerId': peerId});

  // --- イベント受信 ---

  static Stream<Map<String, dynamic>> get events =>
      _events.receiveBroadcastStream().map(
        (e) => Map<String, dynamic>.from(e),
      );
}
3) Flutter 側：イベントの種類
Swift → Flutter に飛んでくるイベントはこれだけでOK：

{
  "type": "encounter",
  "peerId": "UUID",
  "teaser": "英国片思い",
  "rssi": -55
}
{
  "type": "status",
  "status": "connecting|receivingPreview|completed|timeout|failed"
}
{
  "type": "body",
  "teaser": "英国片思い",
  "body": "本文テキスト..."
}
{
  "type": "log",
  "tag": "GATT",
  "msg": "REQ received"
}
Flutter側は type で振り分けるだけ。
4) iOS 側：MethodChannel ブリッジ
ios/Runner/AppDelegate.swift
import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

  private var ble: BLECoordinator!

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller = window?.rootViewController as! FlutterViewController

    let channel = FlutterMethodChannel(
      name: "bittra/ble",
      binaryMessenger: controller.binaryMessenger
    )

    let events = FlutterEventChannel(
      name: "bittra/ble_events",
      binaryMessenger: controller.binaryMessenger
    )

    ble = BLECoordinator()
    ble.setEventSink { event in
      eventsSink?(event)
    }

    var eventsSink: FlutterEventSink?

    events.setStreamHandler(EventStreamHandler(
      onListen: { sink in eventsSink = sink },
      onCancel: { eventsSink = nil }
    ))

    channel.setMethodCallHandler { call, result in
      switch call.method {

      case "startVenueMode":
        self.ble.startVenueMode()
        result(nil)

      case "stopVenueMode":
        self.ble.stopVenueMode()
        result(nil)

      case "setTeaser":
        let t = (call.arguments as? [String: Any])?["teaser"] as? String ?? ""
        self.ble.setMyTeaser(t)
        result(nil)

      case "setBody":
        let b = (call.arguments as? [String: Any])?["body"] as? String ?? ""
        self.ble.setMyBody(b)
        result(nil)

      case "requestBody":
        let id = (call.arguments as? [String: Any])?["peerId"] as? String ?? ""
        self.ble.requestBodyById(id)
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
5) Swift 側：イベント送信用ヘルパー
BLECoordinator.swift に追加
private var eventSink: (([String: Any]) -> Void)?

func setEventSink(_ sink: @escaping ([String: Any]) -> Void) {
  self.eventSink = sink
}

private func emit(_ event: [String: Any]) {
  eventSink?(event)
}
6) Swift → Flutter へイベント送信
すれ違い検知時
emit([
  "type": "encounter",
  "peerId": peripheral.identifier.uuidString,
  "teaser": teaser,
  "rssi": rssi
])
状態更新
emit([
  "type": "status",
  "status": activeStatusText
])
本文受信
emit([
  "type": "body",
  "teaser": currentTeaser,
  "body": bodyText
])
ログ
emit([
  "type": "log",
  "tag": tag,
  "msg": msg
])
7) Flutter 側：イベント受信例
BleBridge.events.listen((e) {
  switch (e['type']) {
    case 'encounter':
      // ストリームに追加
      break;

    case 'status':
      // UIの状態更新
      break;

    case 'body':
      // 履歴に保存
      break;

    case 'log':
      // ログ表示
      break;
  }
});
