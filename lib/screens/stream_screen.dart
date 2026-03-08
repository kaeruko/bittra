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
    final receivedIds = requestLogs
        .where((r) => r.status == RequestStatus.received)
        .map((r) => r.encounterId)
        .toSet();

    final now = DateTime.now();
    final encounters = allEncounters
        .where((e) => !receivedIds.contains(e.id))
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
          if (activeVenue.isBroadcasting &&
              activeVenue.teaser != null &&
              activeVenue.teaser!.isNotEmpty)
            Container(
              color: Colors.orange.shade300,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.satellite_alt,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '会場モード ON',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      ref.read(activeVenueProvider.notifier).stop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 32),
                      elevation: 0,
                    ),
                    child: const Text(
                      'スキャン中',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
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
