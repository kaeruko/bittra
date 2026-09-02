import 'package:bittora/models/bluetooth_models.dart';
import 'package:bittora/screens/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sent notice shows confirmed recipient count', (tester) async {
    final notice = SentNotice(
      id: 'notice-1',
      teaser: 'おすすめ',
      body: 'この本よかった',
      sentAt: DateTime(2026, 9, 2, 12),
      receivedCount: 3,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SentNoticeTile(notice: notice))),
    );

    expect(find.text('受信確認 3人'), findsOneWidget);
  });
}
