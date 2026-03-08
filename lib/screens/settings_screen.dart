import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/mock_data_provider.dart';
import '../services/database_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(mockSettingsProvider);
    final activeVenue = ref.watch(activeVenueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('送受信を有効にする'),
            subtitle: const Text('Bluetoothでの送受信を有効にします'),
            value: activeVenue.isBroadcasting,
            onChanged: (val) {
              if (val) {
                if (activeVenue.teaser != null &&
                    activeVenue.teaser!.isNotEmpty) {
                  ref
                      .read(activeVenueProvider.notifier)
                      .start(activeVenue.teaser!, activeVenue.body ?? '');
                } else {
                  ref.read(activeVenueProvider.notifier).startReceiveOnly();
                  context.go('/');
                }
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
