import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/mock_data_provider.dart';
import '../providers/sent_notice_history_provider.dart';
import '../services/database_service.dart';
import '../services/support_contact.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _showBlockedUsersSheet(
    BuildContext context,
    WidgetRef ref,
    List<String> blockedPeers,
  ) {
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.block, size: 18, color: Colors.grey),
                  SizedBox(width: 8),
                  Text(
                    'ブロック中のユーザー',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...blockedPeers.map(
              (peerId) => ListTile(
                leading: const Icon(Icons.person_off, color: Colors.grey),
                title: Text(
                  peerId,
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: () async {
                    Navigator.of(sheetCtx).pop();
                    await ref
                        .read(blockedPeersProvider.notifier)
                        .unblockPeer(peerId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ブロックを解除しました')),
                      );
                    }
                  },
                  child: const Text('解除'),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openSupport(BuildContext context) async {
    try {
      await SupportContact.openContactEmail();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('メールアプリを開けませんでした: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(mockSettingsProvider);
    final activeVenue = ref.watch(activeVenueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Bluetooth通信'),
            subtitle: Text(
              activeVenue.isBroadcasting
                  ? activeVenue.isSending
                        ? '近くのお知らせを受信し、このお知らせを送信しています'
                        : '近くのお知らせを自動で受信します'
                  : '送受信を停止しています',
            ),
            value: activeVenue.isBroadcasting,
            onChanged: (val) {
              if (val) {
                ref.read(activeVenueProvider.notifier).startReceiveOnly();
              } else {
                ref.read(activeVenueProvider.notifier).stop();
              }
            },
          ),
          SwitchListTile(
            title: const Text('節電モード'),
            subtitle: const Text('履歴を見るときなど'),
            value: settings['powerSave'] ?? false,
            onChanged: (val) {
              ref.read(mockSettingsProvider.notifier).togglePowerSave();
            },
          ),
          const Divider(),
          Consumer(
            builder: (context, ref, _) {
              final blockedPeers = ref.watch(blockedPeersProvider);
              return ListTile(
                leading: const Icon(Icons.block, color: Colors.grey),
                title: const Text('ブロック中のユーザー'),
                trailing: blockedPeers.isEmpty
                    ? const Text('なし', style: TextStyle(color: Colors.grey))
                    : Text(
                        '${blockedPeers.length}人',
                        style: const TextStyle(color: Colors.grey),
                      ),
                onTap: blockedPeers.isEmpty
                    ? null
                    : () => _showBlockedUsersSheet(context, ref, blockedPeers),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.contact_support_outlined),
            title: const Text('運営者へのお問い合わせ'),
            subtitle: const Text(SupportContact.email),
            onTap: () => _openSupport(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('履歴をすべて削除', style: TextStyle(color: Colors.red)),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('履歴の削除'),
                  content: const Text('すべての履歴を削除してもよろしいですか？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('キャンセル'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await databaseServiceProvider.deleteAll();
                        ref.invalidate(mockRequestLogsProvider);
                        ref.invalidate(mockEncountersProvider);
                        ref.invalidate(sentNoticeHistoryProvider);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('履歴を削除しました')),
                          );
                        }
                      },
                      child: const Text(
                        '削除',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
