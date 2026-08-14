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
      if (urlMatch != null) {
        final url = urlMatch.group(0)!;
        body = _BodyWithWebView(text: text, url: url);
      } else {
        body = text.isEmpty
            ? const Center(child: Text('本文はありません'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: SelectableText(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('本文')),
      body: body,
    );
  }
}

class _BodyWithWebView extends StatefulWidget {
  final String text;
  final String url;

  const _BodyWithWebView({required this.text, required this.url});

  @override
  State<_BodyWithWebView> createState() => _BodyWithWebViewState();
}

class _BodyWithWebViewState extends State<_BodyWithWebView> {
  late final WebViewController _controller;
  bool _showText = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final isOnlyUrl = widget.text.trim() == widget.url.trim();

    if (isOnlyUrl) {
      return WebViewWidget(controller: _controller);
    }

    return Column(
      children: [
        if (_showText)
          Container(
            color: Colors.grey.shade100,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            child: Text(widget.text, style: const TextStyle(fontSize: 14)),
          ),
        TextButton(
          onPressed: () => setState(() => _showText = !_showText),
          child: Text(_showText ? 'テキストを隠す' : 'テキストを表示'),
        ),
        Expanded(child: WebViewWidget(controller: _controller)),
      ],
    );
  }
}
