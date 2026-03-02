import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/mock_data_provider.dart';

class DetailScreen extends ConsumerWidget {
  final String encounterId;

  const DetailScreen({super.key, required this.encounterId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Find the log that matches encounterId and is received
    final logs = ref.watch(mockRequestLogsProvider);
    final log = logs.where(
      (l) => l.encounterId == encounterId && l.body != null
    ).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Full Text')),
      body: log == null
          ? const Center(child: Text('No text available.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: SelectableText(
                log.body ?? '',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
    );
  }
}

