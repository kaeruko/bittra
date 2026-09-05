import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TermsGate extends StatefulWidget {
  static const int currentTermsVersion = 1;
  static const String acceptedTermsVersionKey = 'accepted_terms_version';

  final SharedPreferences preferences;
  final Widget child;

  const TermsGate({
    super.key,
    required this.preferences,
    required this.child,
  });

  @override
  State<TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends State<TermsGate> {
  late bool _accepted;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _accepted =
        widget.preferences.getInt(TermsGate.acceptedTermsVersionKey) ==
        TermsGate.currentTermsVersion;
  }

  Future<void> _accept() async {
    if (_saving) return;

    setState(() => _saving = true);
    final saved = await widget.preferences.setInt(
      TermsGate.acceptedTermsVersionKey,
      TermsGate.currentTermsVersion,
    );
    if (!saved) {
      throw StateError('Failed to persist Terms of Use acceptance.');
    }
    if (!mounted) return;

    setState(() {
      _accepted = true;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted) {
      return widget.child;
    }

    return MaterialApp(
      title: 'びっとら 利用規約',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('利用規約 / Terms of Use')),
        body: SafeArea(
          child: Column(
            children: [
              const Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: _TermsText(),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                child: FilledButton(
                  onPressed: _saving ? null : _accept,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _saving
                        ? '保存中…'
                        : '同意してはじめる / Agree and Continue',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsText extends StatelessWidget {
  const _TermsText();

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'びっとらを利用するには、以下の利用規約への同意が必要です。\n'
          'You must agree to these Terms of Use before using Bittra.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Text('1. お知らせ内容 / User-Generated Content', style: titleStyle),
        const SizedBox(height: 8),
        const Text(
          'びっとらでは、近くの利用者が作成したおしらせをBluetooth経由で受信できます。'
          'お知らせの送信者は、自分が送信する内容について責任を負います。\n\n'
          'Bittra can receive notices created by nearby users via Bluetooth. '
          'Users are responsible for the content they transmit.',
        ),
        const SizedBox(height: 20),
        Text('2. 不適切な行為の禁止 / Zero Tolerance Policy', style: titleStyle),
        const SizedBox(height: 8),
        const Text(
          'わいせつ・暴力的・差別的・違法な内容、脅迫、嫌がらせ、いじめ、スパム、'
          'その他の不適切なコンテンツや abusive behavior は一切許容しません。'
          '他の利用者を害する目的で本サービスを使用してはいけません。\n\n'
          'We have zero tolerance for objectionable content or abusive users. '
          'Obscene, violent, discriminatory, illegal, threatening, harassing, bullying, '
          'or spam content is prohibited. The service must not be used to harm other users.',
        ),
        const SizedBox(height: 20),
        Text('3. 報告 / Reporting', style: titleStyle),
        const SizedBox(height: 8),
        const Text(
          '不適切なおしらせを見つけた場合は、そのおしらせを長押しし、'
          '「不適切なコンテンツとして報告する」から運営者へ報告できます。\n\n'
          'If you encounter objectionable content, long-press the notice and select '
          '“Report inappropriate content” to report it to the operator.',
        ),
        const SizedBox(height: 20),
        Text('4. ブロック / Blocking', style: titleStyle),
        const SizedBox(height: 8),
        const Text(
          '不快な利用者は、おしらせを長押しして「このユーザーをブロック（ミュート）する」'
          'を選ぶことでブロックできます。ブロックした利用者のおしらせは表示されません。\n\n'
          'You can block an abusive user by long-pressing their notice and selecting '
          '“Block this user.” Notices from blocked users will no longer be displayed.',
        ),
        const SizedBox(height: 20),
        Text('5. 違反報告への対応 / Moderation Response', style: titleStyle),
        const SizedBox(height: 8),
        const Text(
          '運営者は不適切なコンテンツの報告を24時間以内に確認し、違反が確認された場合は、'
          '該当コンテンツの排除および違反利用者への利用停止措置を行います。\n\n'
          'The operator reviews reports of objectionable content within 24 hours. '
          'When a violation is confirmed, the offending content will be removed and '
          'the abusive user will be ejected from the service.',
        ),
        const SizedBox(height: 20),
        Text('6. 同意 / Agreement', style: titleStyle),
        const SizedBox(height: 8),
        const Text(
          '「同意してはじめる / Agree and Continue」を押すことで、この利用規約に同意します。\n\n'
          'By tapping “Agree and Continue,” you agree to these Terms of Use.',
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
