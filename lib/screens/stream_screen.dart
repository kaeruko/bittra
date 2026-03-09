import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/mock_data_provider.dart';
import '../models/bluetooth_models.dart';

class StreamScreen extends ConsumerWidget {
  const StreamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allEncounters = ref.watch(mockEncountersProvider);
    final requestLogs = ref.watch(mockRequestLogsProvider);
    final blockedPeers = ref.watch(blockedPeersProvider);

    // 受信済みのencounterIdとその受信日時のマップ
    final receivedMap = Map.fromEntries(
      requestLogs
          .where((r) => r.status == RequestStatus.received && r.resolvedAt != null)
          .map((r) => MapEntry(r.encounterId, r.resolvedAt!)),
    );

    final now = DateTime.now();
    final encounters = allEncounters
        .where((e) {
          final resolvedAt = receivedMap[e.id];
          if (resolvedAt == null) return true;
          return e.lastSeenAt.isAfter(resolvedAt);
        })
        .where((e) => now.difference(e.lastSeenAt).inMinutes < 3)
        .where((e) => !blockedPeers.contains(e.peerId)) // ブロック済みを除外
        .toList();
    final activeVenue = ref.watch(activeVenueProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'びっとら',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (activeVenue.isBroadcasting)
            Container(
              color: Colors.orange.shade50,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.satellite_alt, color: Colors.orange, size: 14),
                      const SizedBox(width: 4),
                      const Text(
                        '自分のおしらせ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => context.push('/compose'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('編集', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => ref.read(activeVenueProvider.notifier).stop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('停止', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  if (activeVenue.teaser != null && activeVenue.teaser!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12, top: 2),
                      child: Text(
                        activeVenue.teaser!,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12, top: 2),
                      child: Text(
                        '受信のみ',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ),
                  Divider(height: 1, color: Colors.orange.shade200),
                ],
              ),
            ),
          Expanded(
            child: encounters.isEmpty
                ? const Center(child: Text('からっぽ'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: encounters.length,
                    itemBuilder: (context, index) {
                      final encounter = encounters[index];
                      return EncounterCard(encounter: encounter);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class EncounterCard extends ConsumerWidget {
  final Encounter encounter;
  const EncounterCard({super.key, required this.encounter});

  String _getTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inMinutes == 0) return 'いま';
    if (difference.inHours == 0) return '${difference.inMinutes}分前';
    if (difference.inDays == 0) return '${difference.inHours}時間前';
    return '${difference.inDays}日前';
  }

  void _showActionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text(
                'このユーザーをブロック（ミュート）する',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _showBlockConfirmDialog(context, ref);
              },
            ),
            ListTile(
              leading: Icon(Icons.report_outlined, color: Colors.grey.shade600),
              title: const Text('不適切なコンテンツとして報告する'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _showReportDialog(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showBlockConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('ユーザーをブロック'),
        content: const Text('本当にブロックしますか？\n解除は設定から行えます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await ref.read(blockedPeersProvider.notifier).blockPeer(encounter.peerId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ユーザーをブロックしました')),
                );
              }
            },
            child: const Text('ブロック', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    String? selectedReason;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('報告する'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('報告理由を選択してください'),
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: selectedReason,
                onChanged: (val) => setState(() => selectedReason = val),
                child: Column(
                  children: ['スパム', '不適切な表現', '嫌がらせ・ハラスメント', 'その他']
                      .map((reason) => RadioListTile<String>(
                            title: Text(reason),
                            value: reason,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () async {
                      Navigator.of(dialogCtx).pop();
                      // ダミー送信処理（P2Pのためネットワーク送信なし）
                      await Future.delayed(const Duration(seconds: 1));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('報告を受け付けました。ご協力ありがとうございます。'),
                          ),
                        );
                      }
                    },
              child: const Text('送信'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: () => context.push('/request', extra: encounter),
        onLongPress: () => _showActionSheet(context, ref),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      encounter.teaser,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_getTimeAgo(encounter.receivedAt)}・×${encounter.count}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: const Text(
                  '全文',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
