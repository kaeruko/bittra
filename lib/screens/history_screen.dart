import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/mock_data_provider.dart';
import '../providers/sent_notice_history_provider.dart';
import '../models/bluetooth_models.dart';
import '../services/database_service.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  Future<void> _deleteAllHistory(BuildContext context, WidgetRef ref) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('履歴の削除'),
        content: const Text('受信履歴と送信履歴をすべて削除してもよろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) {
      return;
    }

    await databaseServiceProvider.deleteAll();
    ref.invalidate(mockRequestLogsProvider);
    ref.invalidate(mockEncountersProvider);
    ref.invalidate(sentNoticeHistoryProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('履歴を削除しました')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(mockRequestLogsProvider);
    final sentNotices = ref.watch(sentNoticeHistoryProvider);
    final receivedLogs = logs
        .where((l) => l.status == RequestStatus.received)
        .toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('履歴'),
          actions: [
            IconButton(
              tooltip: '履歴をすべて削除',
              onPressed: logs.isEmpty && sentNotices.isEmpty
                  ? null
                  : () => _deleteAllHistory(context, ref),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '受信'),
              Tab(text: '送信'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReceivedHistoryList(logs: receivedLogs),
            _SentHistoryList(notices: sentNotices),
          ],
        ),
      ),
    );
  }
}

class _ReceivedHistoryList extends StatelessWidget {
  final List<RequestLog> logs;

  const _ReceivedHistoryList({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(child: Text('受信済みのお知らせはありません。'));
    }

    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) => ReceivedNoticeTile(log: logs[index]),
    );
  }
}

class _SentHistoryList extends StatelessWidget {
  final List<SentNotice> notices;

  const _SentHistoryList({required this.notices});

  @override
  Widget build(BuildContext context) {
    if (notices.isEmpty) {
      return const Center(child: Text('送信したお知らせはありません。'));
    }

    return ListView.builder(
      itemCount: notices.length,
      itemBuilder: (context, index) => SentNoticeTile(notice: notices[index]),
    );
  }
}

class ReceivedNoticeTile extends StatelessWidget {
  final RequestLog log;
  const ReceivedNoticeTile({super.key, required this.log});

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
        onTap: () => context.push('/detail/${log.id}'),
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
              if (log.teaser != null && log.teaser!.isNotEmpty)
                Text(
                  log.teaser!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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

class SentNoticeTile extends StatelessWidget {
  final SentNotice notice;

  const SentNoticeTile({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('MM/dd HH:mm');
    final bodyPreview = notice.body.isNotEmpty
        ? notice.body.replaceAll('\n', ' ')
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(Icons.upload_rounded, size: 18),
                Text(
                  format.format(notice.sentAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(notice.teaser, style: Theme.of(context).textTheme.titleMedium),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '受信確認 ${notice.receivedCount}人',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
