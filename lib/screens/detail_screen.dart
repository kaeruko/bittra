import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/mock_data_provider.dart';
import '../models/bluetooth_models.dart';

final _urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);

class DetailScreen extends ConsumerWidget {
  final String encounterId;

  const DetailScreen({super.key, required this.encounterId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(mockRequestLogsProvider);
    final log = logs.where((l) => l.encounterId == encounterId).firstOrNull;

    Widget body;
    if (log == null) {
      body = const Center(child: Text('見つかりません'));
    } else if (log.status == RequestStatus.requested) {
      body = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('ダウンロード中...'),
          ],
        ),
      );
    } else if (log.status == RequestStatus.failed ||
        log.status == RequestStatus.timeout) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'エラー: ${log.error ?? "タイムアウトなどの理由で失敗しました"}',
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ),
      );
    } else {
      final text = log.body ?? '';
      final urlMatch = _urlRegex.firstMatch(text);
      body = text.isEmpty
          ? const Center(child: Text('本文はありません'))
          : _ReceivedBody(text: text, url: urlMatch?.group(0));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('本文')),
      body: body,
    );
  }
}

class _ReceivedBody extends StatelessWidget {
  final String text;
  final String? url;

  const _ReceivedBody({required this.text, this.url});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(text, style: Theme.of(context).textTheme.bodyLarge),
          if (url != null) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _WebViewScreen(url: url!),
                  ),
                );
              },
              icon: const Icon(Icons.open_in_browser),
              label: const Text('リンクを開く'),
            ),
          ],
        ],
      ),
    );
  }
}

class _WebViewScreen extends StatefulWidget {
  final String url;

  const _WebViewScreen({required this.url});

  @override
  State<_WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<_WebViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('リンク')),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
        ],
      ),
    );
  }
}
