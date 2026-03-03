import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bittora/router/app_router.dart';
import 'package:bittora/services/ble_service.dart';

void main() {
  runApp(
    const ProviderScope(
      child: BittoraApp(),
    ),
  );
}

class BittoraApp extends ConsumerWidget {
  const BittoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize BLE Event Listener
    ref.listen(bleServiceProvider, (_, __) {});

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Bittora',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
