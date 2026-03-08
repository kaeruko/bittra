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
    final encounters = ref.watch(mockEncountersProvider);
    final receivedLogs = logs
        .where((l) => l.status == RequestStatus.received)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('受信履歴')),
      body: receivedLogs.isEmpty
          ? const Center(child: Text('受信済みのお知らせはありません。'))
          : ListView.builder(
              itemCount: receivedLogs.length,
              itemBuilder: (context, index) {
                final log = receivedLogs[index];
                final encounter = encounters
                    .where((e) => e.id == log.encounterId)
                    .firstOrNull;
                return ReceivedNoticeTile(log: log, teaser: encounter?.teaser);
              },
            ),
    );
  }
}

class ReceivedNoticeTile extends StatelessWidget {
  final RequestLog log;
  final String? teaser;
  const ReceivedNoticeTile({super.key, required this.log, this.teaser});

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('MM/dd HH:mm');
    final bodyPreview = log.body != null && log.body!.isNotEmpty
        ? log.body!.replaceAll('\n', ' ')
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 1,
      child: InkWell(
        onTap: () => context.push('/detail/${log.encounterId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  Text(
                    format.format(log.resolvedAt ?? log.requestedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (teaser != null)
                Text(teaser!, style: Theme.of(context).textTheme.titleMedium),
              if (bodyPreview != null) ...[
                const SizedBox(height: 4),
                Text(
                  bodyPreview,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
