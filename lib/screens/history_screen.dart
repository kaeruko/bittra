import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/mock_data_provider.dart';
import '../models/bluetooth_models.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(mockRequestLogsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('リクエスト履歴')),
      body: logs.isEmpty
          ? const Center(child: Text('履歴がありません。'))
          : ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return RequestLogTile(log: log);
              },
            ),
    );
  }
}

class RequestLogTile extends StatelessWidget {
  final RequestLog log;
  const RequestLogTile({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('MM/dd HH:mm:ss');
    
    IconData statusIcon;
    Color statusColor;
    switch (log.status) {
      case RequestStatus.requested:
        statusIcon = Icons.hourglass_empty;
        statusColor = Colors.orange;
        break;
      case RequestStatus.received:
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
        break;
      case RequestStatus.failed:
      case RequestStatus.timeout:
        statusIcon = Icons.error_outline;
        statusColor = Colors.red;
        break;
    }

    return ListTile(
      leading: Icon(statusIcon, color: statusColor),
      title: Text('Encounter: ${log.encounterId}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('リクエスト日時: ${format.format(log.requestedAt)}'),
          if (log.error != null) Text('エラー: ${log.error}', style: const TextStyle(color: Colors.red)),
        ],
      ),
      trailing: log.status == RequestStatus.received
          ? IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
              onPressed: () => context.push('/detail/${log.encounterId}'),
            )
          : null,
      onTap: log.status == RequestStatus.received
          ? () => context.push('/detail/${log.encounterId}')
          : null,
    );
  }
}

