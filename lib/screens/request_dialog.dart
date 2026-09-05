import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../providers/mock_data_provider.dart';
import '../models/bluetooth_models.dart';
import '../services/ble_service.dart';

class RequestDialog extends ConsumerWidget {
  final Encounter? encounter;

  const RequestDialog({super.key, this.encounter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('全文をリクエスト')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.download_rounded, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              if (encounter != null)
                Text(
                  '「${encounter!.teaser}」の全文をリクエストしますか？',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 16),
              const Text(
                'BLE経由で送信者に接続し、全文をダウンロードします。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton(
                    onPressed: () => context.pop(),
                    child: const Text('キャンセル'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (encounter == null) return;

                      final requestId = const Uuid().v4();
                      final peerId = encounter!.peerId;
                      final log = RequestLog(
                        id: requestId,
                        encounterId: peerId,
                        encounterKey: encounter!.dedupeKey,
                        teaser: encounter!.teaser,
                        status: RequestStatus.requested,
                        requestedAt: DateTime.now(),
                      );
                      ref
                          .read(mockRequestLogsProvider.notifier)
                          .addRequest(log);

                      ref.read(bleServiceProvider).requestFullText(
                            peerId: peerId,
                            requestId: requestId,
                          );

                      // Detail/history identity is the immutable request log ID,
                      // not the BLE peer ID which can be reused by later notices.
                      context.pushReplacement('/detail/$requestId');
                    },
                    child: const Text('リクエスト'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
