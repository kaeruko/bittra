import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/mock_data_provider.dart';
import '../services/ble_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(mockSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Venue Mode'),
            subtitle: const Text('Enable Bluetooth advertising and scanning'),
            value: settings['venueMode'] ?? false,
            onChanged: (val) {
              ref.read(mockSettingsProvider.notifier).toggleVenueMode();
              if (val) {
                // To fetch teaser/body, we might need a distinct provider or just hardcode for MVP settings click
                ref.read(bleServiceProvider).startVenueMode('Teaser', 'Body text');
              } else {
                ref.read(bleServiceProvider).stopVenueMode();
              }
            },
          ),
          SwitchListTile(
            title: const Text('Power Save Mode'),
            subtitle: const Text('Reduce scanning frequency to save battery'),
            value: settings['powerSave'] ?? false,
            onChanged: (val) {
              ref.read(mockSettingsProvider.notifier).togglePowerSave();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Clear All History', style: TextStyle(color: Colors.red)),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear History'),
                  content: const Text('Are you sure you want to delete all encounter and request history?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('History cleared (mock)')),
                        );
                      },
                      child: const Text('Clear', style: TextStyle(color: Colors.red)),
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

