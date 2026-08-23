import 'package:bittora/models/bluetooth_models.dart';
import 'package:bittora/providers/mock_data_provider.dart';
import 'package:bittora/screens/detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  Widget detailWithBody(String body) {
    final log = RequestLog(
      id: 'request-1',
      encounterId: 'peer-1',
      status: RequestStatus.received,
      requestedAt: DateTime(2026, 8, 23, 16),
      body: body,
    );

    return ProviderScope(
      overrides: [
        mockRequestLogsProvider.overrideWithValue([log]),
      ],
      child: const MaterialApp(home: DetailScreen(encounterId: 'peer-1')),
    );
  }

  testWidgets('URLを含む本文を隠さずリンクボタンを表示する', (tester) async {
    const body = '詳細はこちらです。\nhttps://example.com';

    await tester.pumpWidget(detailWithBody(body));

    expect(find.text(body), findsOneWidget);
    expect(find.text('リンクを開く'), findsOneWidget);
    expect(find.text('テキストを表示'), findsNothing);
    expect(find.byType(WebViewWidget), findsNothing);
  });

  testWidgets('URLのない本文にはリンクボタンを表示しない', (tester) async {
    const body = 'URLを含まない本文です。';

    await tester.pumpWidget(detailWithBody(body));

    expect(find.text(body), findsOneWidget);
    expect(find.text('リンクを開く'), findsNothing);
  });

  testWidgets('URLだけの本文でもWebViewを自動表示しない', (tester) async {
    const body = 'https://example.com';

    await tester.pumpWidget(detailWithBody(body));

    expect(find.text(body), findsOneWidget);
    expect(find.text('リンクを開く'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
  });
}
