import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble_bridge.dart';
import '../models/bluetooth_models.dart';
import '../providers/mock_data_provider.dart';
import '../providers/sent_notice_history_provider.dart';

class BleService {
  final Ref ref;

  BleService(this.ref) {
    _initEventChannel();
  }

  void _initEventChannel() {
    BleBridge.events.listen(
      (event) async {
        await _handleNativeEvent(event);
      },
      onError: (error) {
        // ignore: avoid_print
        print('[BITTRA-BLE][FLUTTER] event channel error: $error');
        log('BleService: Intercepted error from event channel: $error');
      },
    );
  }

  Future<void> _handleNativeEvent(Map<String, dynamic> event) async {
    final type = event['type'] as String?;
    switch (type) {
      case 'encounter':
        final peerId = event['peerId'] as String;
        final senderId = (event['senderId'] as num?)?.toInt();
        final teaser = event['teaser'] as String;
        final rssi = event['rssi'] as int;

        // ignore: avoid_print
        print(
          '[BITTRA-BLE][ENCOUNTER] peerId=$peerId senderId=$senderId teaser=$teaser rssi=$rssi',
        );
        ref
            .read(mockEncountersProvider.notifier)
            .upsertEncounter(
              peerId: peerId,
              senderId: senderId,
              teaser: teaser,
              rssi: rssi,
            );
        break;

      case 'status':
        final peerId = event['peerId'] as String;
        final statusStr = event['status'] as String;
        final error = event['error'] as String?;
        // ignore: avoid_print
        print(
          '[BITTRA-BLE][STATUS] peerId=$peerId status=$statusStr error=${error ?? ''}',
        );
        RequestStatus reqStatus = RequestStatus.requested;
        switch (statusStr) {
          case 'connecting':
          case 'discovering':
          case 'subscribing':
          case 'requesting':
          case 'receivingPreview':
            reqStatus = RequestStatus.requested;
            break;
          case 'completed':
            reqStatus = RequestStatus.received;
            break;
          case 'timeout':
            reqStatus = RequestStatus.timeout;
            break;
          case 'failed':
            reqStatus = RequestStatus.failed;
            break;
        }

        ref
            .read(mockRequestLogsProvider.notifier)
            .updateRequest(peerId, reqStatus, error: error);
        break;

      case 'body':
        final peerId = event['peerId'] as String;
        final preview = event['preview'] as String?;
        final body = event['body'] as String?;
        // ignore: avoid_print
        print(
          '[BITTRA-BLE][BODY] peerId=$peerId previewChars=${preview?.length ?? 0} bodyChars=${body?.length ?? 0}',
        );

        if (body != null) {
          ref
              .read(mockRequestLogsProvider.notifier)
              .updateRequest(peerId, RequestStatus.received, body: body);
        }
        break;

      case 'delivery':
        final noticeId = event['noticeId'];
        final countValue = event['count'];
        if (noticeId is! String || noticeId.isEmpty || countValue is! num) {
          throw StateError('Invalid delivery event: $event');
        }
        final count = countValue.toInt();
        if (count < 0 || countValue != count) {
          throw StateError('Invalid delivery count: $event');
        }

        // ignore: avoid_print
        print('[BITTRA-BLE][DELIVERY] noticeId=$noticeId count=$count');
        await ref
            .read(sentNoticeHistoryProvider.notifier)
            .updateReceivedCount(noticeId: noticeId, receivedCount: count);
        break;

      case 'log':
        final tag = event['tag'] as String? ?? '';
        final message = event['message'] as String? ?? '';
        // `print` is intentional here so BLE diagnostics are always visible in
        // the terminal used for `flutter run` on a physical iOS device.
        // ignore: avoid_print
        print('[BITTRA-BLE][$tag] $message');
        log('[$tag] $message');
        break;

      default:
        // ignore: avoid_print
        print('[BITTRA-BLE][FLUTTER] unknown event type=$type event=$event');
        log('BleService: Received unknown event type: $type');
    }
  }

  Future<void> startVenueMode(
    String noticeId,
    String teaser,
    String bodyText,
  ) async {
    if (noticeId.isEmpty) {
      throw ArgumentError.value(noticeId, 'noticeId', 'must not be empty');
    }
    await BleBridge.setTeaser(teaser);
    await BleBridge.setBody(bodyText);
    await BleBridge.startVenueMode(noticeId);
  }

  Future<void> startReceiveOnly() async {
    try {
      await BleBridge.startReceiveOnly();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[BITTRA-BLE][FLUTTER] startReceiveOnly failed: ${e.message}');
      log('Failed to start receive-only mode: ${e.message}');
    }
  }

  Future<void> stopVenueMode() async {
    try {
      await BleBridge.stopVenueMode();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[BITTRA-BLE][FLUTTER] stopVenueMode failed: ${e.message}');
      log('Failed to stop venue mode: ${e.message}');
    }
  }

  Future<void> requestFullText(String peerId) async {
    try {
      await BleBridge.requestBody(peerId);
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[BITTRA-BLE][FLUTTER] requestFullText failed: ${e.message}');
      log('Failed to request full text: ${e.message}');
    }
  }
}

final bleServiceProvider = Provider((ref) => BleService(ref));
