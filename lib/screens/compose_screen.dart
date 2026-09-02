import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/mock_data_provider.dart';
import '../providers/sent_notice_history_provider.dart';
import '../services/content_moderation.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _teaserController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final venue = ref.read(activeVenueProvider);
      if (venue.isBroadcasting) {
        if (venue.teaser != null) _teaserController.text = venue.teaser!;
        if (venue.body != null) _bodyController.text = venue.body!;
      }
    });
  }

  @override
  void dispose() {
    _teaserController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) {
      return;
    }

    final teaser = _teaserController.text;
    final body = _bodyController.text;

    setState(() => _isSubmitting = true);
    try {
      final notice = await ref
          .read(sentNoticeHistoryProvider.notifier)
          .addSentNotice(teaser: teaser, body: body);

      await ref
          .read(activeVenueProvider.notifier)
          .start(notice.id, teaser, body);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('おしらせを流しました')));
      context.go('/');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('おしらせする'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            const Text(
              '不適切な表現や嫌がらせを目的とした投稿は禁止されています。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _teaserController,
              decoration: const InputDecoration(
                labelText: 'おしらせ',
                border: OutlineInputBorder(),
                helperText: 'びっとらを持ってる周りの人に届きます',
              ),
              maxLength: 8,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'おしらせを入力してください';
                }
                if (value.length > 8) {
                  return 'おしらせは8文字以内で入力してください（現在${value.length}文字）';
                }
                return ContentModeration.validate(value);
              },
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: '詳しい内容',
                border: OutlineInputBorder(),
                helperText: 'リクエストされると送信されます',
                alignLabelWithHint: true,
              ),
              maxLength: 300,
              maxLines: 8,
              validator: (value) {
                if (value != null && value.length > 300) {
                  return '本文は300文字以内で入力してください';
                }
                return ContentModeration.validate(value);
              },
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.podcasts),
              label: Text(_isSubmitting ? '保存中…' : 'おしらせ！'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
