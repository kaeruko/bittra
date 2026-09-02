import 'package:flutter/services.dart';

class BleBridge {
  static const _channel = MethodChannel('bittra/ble');
  static const _events = EventChannel('bittra/ble_events');

  // --- コマンド ---

  static Future<void> startVenueMode(String noticeId) =>
      _channel.invokeMethod('startVenueMode', {'noticeId': noticeId});

  static Future<void> startReceiveOnly() =>
      _channel.invokeMethod('startReceiveOnly');

  static Future<void> stopVenueMode() => _channel.invokeMethod('stopVenueMode');

  static Future<void> setTeaser(String teaser) =>
      _channel.invokeMethod('setTeaser', {'teaser': teaser});

  static Future<void> setBody(String body) =>
      _channel.invokeMethod('setBody', {'body': body});

  static Future<void> requestBody(String peerId) =>
      _channel.invokeMethod('requestBody', {'peerId': peerId});

  // --- イベント受信 ---

  static Stream<Map<String, dynamic>> get events =>
      _events.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e));
}
