import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bittora/providers/mock_data_provider.dart';
import 'package:bittora/router/app_router.dart';
import 'package:bittora/services/ble_service.dart';
import 'package:bittora/terms_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();

  runApp(
    TermsGate(
      preferences: preferences,
      child: const ProviderScope(child: BittoraApp()),
    ),
  );
}

class BittoraApp extends ConsumerWidget {
  const BittoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize BLE event handling and the persisted receive setting only
    // after the user has accepted the Terms of Use.
    ref.listen(bleServiceProvider, (_, __) {});
    ref.listen(activeVenueProvider, (_, __) {});

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Bittora',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
