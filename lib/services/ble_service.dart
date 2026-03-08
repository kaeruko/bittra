import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble_bridge.dart';
import '../models/bluetooth_models.dart';
import '../providers/mock_data_provider.dart';

class BleService {
  final Ref ref;

  BleService(this.ref) {
    _initEventChannel();
  }

  void _initEventChannel() {
    BleBridge.events.listen(
      (event) {
        _handleNativeEvent(event);
      },
      onError: (error) {
        log('BleService: Intercepted error from event channel: $error');
      },
    );
  }

  void _handleNativeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'encounter':
        final peerId = event['peerId'] as String;
        final teaser = event['teaser'] as String;
        final rssi = event['rssi'] as int;

        // Push this data to the Provider (replacing mock with real logic eventually)
        ref
            .read(mockEncountersProvider.notifier)
            .upsertEncounter(peerId: peerId, teaser: teaser, rssi: rssi);
        break;

      case 'status':
        final peerId = event['peerId'] as String;
        final statusStr = event['status'] as String;
        final error = event['error'] as String?;
        // Convert string to enum
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

        // We use peerId (UUID of the peripheral) as the encounterId for mapping
        ref
            .read(mockRequestLogsProvider.notifier)
            .updateRequest(peerId, reqStatus, error: error);
        break;

      case 'body':
        final peerId = event['peerId'] as String;
        final preview = event['preview'] as String?;
        final body = event['body'] as String?;

        if (body != null) {
          ref
              .read(mockRequestLogsProvider.notifier)
              .updateRequest(peerId, RequestStatus.received, body: body);
        }
        break;

      case 'log':
        final tag = event['tag'] as String? ?? '';
        final message = event['message'] as String? ?? '';
        log('[$tag] $message');
        break;

      default:
        log('BleService: Received unknown event type: $type');
    }
  }

  Future<void> startVenueMode(String teaser, String bodyText) async {
    try {
      await BleBridge.setTeaser(teaser);
      await BleBridge.setBody(bodyText);
      await BleBridge.startVenueMode();
    } on PlatformException catch (e) {
      log('Failed to start venue mode: ${e.message}');
    }
  }

  Future<void> startReceiveOnly() async {
    try {
      await BleBridge.startVenueMode();
    } on PlatformException catch (e) {
      log('Failed to start receive-only mode: ${e.message}');
    }
  }

  Future<void> stopVenueMode() async {
    try {
      await BleBridge.stopVenueMode();
    } on PlatformException catch (e) {
      log('Failed to stop venue mode: ${e.message}');
    }
  }

  Future<void> requestFullText(String peerId) async {
    try {
      await BleBridge.requestBody(peerId);
    } on PlatformException catch (e) {
      log('Failed to request full text: ${e.message}');
    }
  }
}

// Provider instance for BleService
final bleServiceProvider = Provider((ref) => BleService(ref));
