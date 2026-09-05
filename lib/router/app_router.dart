import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../screens/stream_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/request_dialog.dart';
import '../screens/detail_screen.dart';
import '../screens/history_screen.dart';
import '../screens/compose_screen.dart';
import '../screens/main_scaffold.dart';
import '../models/bluetooth_models.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return MainScaffold(child: child);
        },
        routes: [
          GoRoute(path: '/', builder: (context, state) => const StreamScreen()),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: '/compose',
            builder: (context, state) => const ComposeScreen(),
          ),
          GoRoute(
            path: '/detail/:id',
            builder: (context, state) {
              final requestId = state.pathParameters['id']!;
              return DetailScreen(requestId: requestId);
            },
          ),
        ],
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
    ],
  );
}
