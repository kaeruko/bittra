import 'package:bittora/terms_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('blocks app until current terms are accepted', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      TermsGate(
        preferences: preferences,
        child: const MaterialApp(home: Text('APP CONTENT')),
      ),
    );

    expect(find.text('利用規約 / Terms of Use'), findsOneWidget);
    expect(find.text('APP CONTENT'), findsNothing);

    await tester.tap(find.text('同意してはじめる / Agree and Continue'));
    await tester.pumpAndSettle();

    expect(find.text('APP CONTENT'), findsOneWidget);
    expect(
      preferences.getInt(TermsGate.acceptedTermsVersionKey),
      TermsGate.currentTermsVersion,
    );
  });

  testWidgets('skips terms when current version was already accepted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      TermsGate.acceptedTermsVersionKey: TermsGate.currentTermsVersion,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      TermsGate(
        preferences: preferences,
        child: const MaterialApp(home: Text('APP CONTENT')),
      ),
    );

    expect(find.text('APP CONTENT'), findsOneWidget);
    expect(find.text('利用規約 / Terms of Use'), findsNothing);
  });
}
