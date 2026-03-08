import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/mock_data_provider.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _teaserController = TextEditingController();
  final _bodyController = TextEditingController();

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

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final teaser = _teaserController.text;
      final body = _bodyController.text;

      ref.read(activeVenueProvider.notifier).start(teaser, body);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('おしらせを流しました')));
      context.go('/');
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
            TextFormField(
              controller: _teaserController,
              decoration: const InputDecoration(
                labelText: 'おしらせ',
                border: OutlineInputBorder(),
                helperText: 'びっとらを持ってる周りの人に届きます',
              ),
              maxLength: 8,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'おしらせを入力してください';
                }
                if (value.length > 8) {
                  return 'おしらせは8文字以内で入力してください';
                }
                return null;
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
                return null;
              },
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.podcasts),
              label: const Text('おしらせ！'),
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
