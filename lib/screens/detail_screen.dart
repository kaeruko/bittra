import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/mock_data_provider.dart';
import '../models/bluetooth_models.dart';

class DetailScreen extends ConsumerWidget {
  final String encounterId;

  const DetailScreen({super.key, required this.encounterId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(mockRequestLogsProvider);
    final log = logs.where((l) => l.encounterId == encounterId).firstOrNull;

    Widget body;
    if (log == null) {
      body = const Center(child: Text('見つかりません'));
    } else if (log.status == RequestStatus.requested) {
      body = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('ダウンロード中...'),
          ],
        ),
      );
    } else if (log.status == RequestStatus.failed ||
        log.status == RequestStatus.timeout) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'エラー: ${log.error ?? "タイムアウトなどの理由で失敗しました"}',
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ),
      );
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: SelectableText(
          log.body ?? '',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('本文')),
      body: body,
    );
  }
}
