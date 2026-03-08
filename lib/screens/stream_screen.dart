import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/mock_data_provider.dart';
import '../models/bluetooth_models.dart';

class StreamScreen extends ConsumerWidget {
  const StreamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allEncounters = ref.watch(mockEncountersProvider);
    final requestLogs = ref.watch(mockRequestLogsProvider);
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
          // 未受信 or 受信後にまた現れた場合は表示
          if (resolvedAt == null) return true;
          return e.lastSeenAt.isAfter(resolvedAt);
        })
        .where((e) => now.difference(e.lastSeenAt).inMinutes < 3)
        .toList();
    final activeVenue = ref.watch(activeVenueProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Very slight gray background
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

class EncounterCard extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
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
