import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/mock_data_provider.dart';
import '../models/bluetooth_models.dart';
import '../services/ble_service.dart';

class RequestDialog extends ConsumerWidget {
  final Encounter? encounter;

  const RequestDialog({super.key, this.encounter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Full Text')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.download_rounded, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              if (encounter != null) Text(
                'Request full text for "${encounter!.teaser}"?',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'This will attempt to connect to the sender via BLE and download the full text.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (encounter == null) return;
                      
                      final log = RequestLog(
                        id: encounter!.peerId,
                        encounterId: encounter!.peerId,
                        status: RequestStatus.requested,
                        requestedAt: DateTime.now(),
                      );
                      ref.read(mockRequestLogsProvider.notifier).addRequest(log);
                      
                      // Call Native BLE
                      ref.read(bleServiceProvider).requestFullText(encounter!.peerId);
                      
                      // Navigate to history 
                      context.pushReplacement('/history');
                    },
                    child: const Text('Request'),
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


