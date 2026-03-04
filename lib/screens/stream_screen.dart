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
    final encounters = ref.watch(mockEncountersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bittora - Stream'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: encounters.isEmpty
          ? const Center(child: Text('No encounters yet.'))
          : ListView.builder(
              itemCount: encounters.length,
              itemBuilder: (context, index) {
                final encounter = encounters[index];
                return EncounterCard(encounter: encounter);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/compose'),
        tooltip: 'Post new teaser',
        child: const Icon(Icons.edit),
      ),
    );
  }
}

class EncounterCard extends StatelessWidget {
  final Encounter encounter;
  const EncounterCard({super.key, required this.encounter});

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('HH:mm');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 1,
      child: InkWell(
        onTap: () => context.push('/request', extra: encounter),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${encounter.count} times',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    format.format(encounter.receivedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                encounter.teaser,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                   Text(
                    'ID: ${encounter.id}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey),
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

