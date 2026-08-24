import 'package:url_launcher/url_launcher.dart';

class SupportContact {
  SupportContact._();

  static const String email = 'mail@cloxs.jp';

  static Future<void> openContactEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: const {
        'subject': 'びっとら お問い合わせ',
      },
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw StateError('Could not open mail client for $email');
    }
  }

  static Future<void> openReportEmail({
    required String reason,
    required String peerId,
    required String teaser,
  }) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': 'びっとら 不適切コンテンツ報告',
        'body': [
          '報告理由: $reason',
          '送信元ID: $peerId',
          'おしらせ: $teaser',
          '',
          '必要に応じて補足をご記入のうえ送信してください。',
        ].join('\n'),
      },
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw StateError('Could not open mail client for $email');
    }
  }
}
