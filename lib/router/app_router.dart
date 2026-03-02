import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../screens/stream_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/request_dialog.dart';
import '../screens/detail_screen.dart';
import '../screens/history_screen.dart';
import '../screens/compose_screen.dart';
import '../models/bluetooth_models.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const StreamScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/request',
        pageBuilder: (context, state) {
          final encounter = state.extra as Encounter?;
          return MaterialPage(
            fullscreenDialog: true,
            child: RequestDialog(encounter: encounter),
          );
        },
      ),
      GoRoute(
        path: '/detail/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return DetailScreen(encounterId: id);
        },
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/compose',
        builder: (context, state) => const ComposeScreen(),
      ),
    ],
  );
}
