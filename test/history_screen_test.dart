import 'package:bittora/models/bluetooth_models.dart';
import 'package:bittora/screens/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('受信履歴は受信時点のタイトルと本文をセットで表示する', (tester) async {
    final log = RequestLog(
      id: 'request-1',
      encounterId: 'peer-current',
      teaser: 'わんわん',
      status: RequestStatus.received,
      requestedAt: DateTime(2026, 9, 5, 10, 42),
      resolvedAt: DateTime(2026, 9, 5, 10, 42),
      body: 'もふー',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReceivedNoticeTile(log: log)),
      ),
    );

    expect(find.text('わんわん'), findsOneWidget);
    expect(find.text('もふー'), findsOneWidget);
  });
}
