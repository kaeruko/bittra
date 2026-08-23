import 'package:bittora/models/bluetooth_models.dart';
import 'package:bittora/providers/mock_data_provider.dart';
import 'package:bittora/screens/stream_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stopped notice disappears after the retention period', (
    tester,
  ) async {
    final firstSeenAt = DateTime(2026, 8, 23, 12);
    var now = firstSeenAt;
    final encounter = Encounter(
      id: 'peer-1',
      peerId: 'peer-1',
      teaser: 'テスト通知',
      receivedAt: firstSeenAt,
      dedupeKey: 'sender:1',
      lastSeenAt: firstSeenAt,
      rssi: -50,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mockEncountersProvider.overrideWithValue([encounter]),
          mockRequestLogsProvider.overrideWithValue(const []),
          blockedPeersProvider.overrideWithValue(const []),
          activeVenueProvider.overrideWithValue(
            const VenueState(isBroadcasting: false),
          ),
        ],
        child: MaterialApp(home: StreamScreen(now: () => now)),
      ),
    );

    expect(find.text('テスト通知'), findsOneWidget);

    now = firstSeenAt.add(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('テスト通知'), findsNothing);
    expect(find.text('からっぽ'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
