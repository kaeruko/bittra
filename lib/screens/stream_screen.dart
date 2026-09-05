import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/mock_data_provider.dart';
import '../models/bluetooth_models.dart';
import '../services/support_contact.dart';

class StreamScreen extends ConsumerStatefulWidget {
  final DateTime Function()? now;

  const StreamScreen({super.key, this.now});

  @override
  ConsumerState<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends ConsumerState<StreamScreen> {
  static const _encounterRetention = Duration(minutes: 3);
  static const _refreshInterval = Duration(seconds: 1);
  static const _accent = Color(0xFFD946EF);
  static const _headerGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFD946EF), Color(0xFFFF7A00)],
  );

  late DateTime _now;
  late final Timer _refreshTimer;

  DateTime _currentTime() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _now = _currentTime();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!mounted) {
        return;
      }
      setState(() => _now = _currentTime());
    });
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allEncounters = ref.watch(mockEncountersProvider);
    final requestLogs = ref.watch(mockRequestLogsProvider);
    final blockedPeers = ref.watch(blockedPeersProvider);

    final receivedMap = Map.fromEntries(
      requestLogs
          .where(
            (r) => r.status == RequestStatus.received && r.resolvedAt != null,
          )
          .map((r) => MapEntry(r.encounterId, r.resolvedAt!)),
    );

    final encounters = allEncounters
        .where((e) {
          final resolvedAt = receivedMap[e.id];
          if (resolvedAt == null) return true;
          return e.lastSeenAt.isAfter(resolvedAt);
        })
        .where(
          (e) => _now.difference(e.lastSeenAt) < _encounterRetention,
        )
        .where((e) => !blockedPeers.contains(e.peerId))
        .toList();
    final activeVenue = ref.watch(activeVenueProvider);
    final isSending =
        activeVenue.isSending &&
        (activeVenue.teaser?.trim().isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9FC),
      appBar: AppBar(
        toolbarHeight: 64,
        elevation: 0,
        backgroundColor: const Color(0xFFD946EF),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: const Text(
          'びっとら',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: 0.4,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: _headerGradient),
        ),
        actions: [
          IconButton(
            tooltip: '設定',
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (activeVenue.isBroadcasting)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(gradient: _headerGradient),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bluetooth_searching_rounded,
                          color: Colors.white,
                          size: 17,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            '会場モード ON',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const _HeaderStatusPill(label: 'スキャン中'),
                        const SizedBox(width: 6),
                        _HeaderPillButton(
                          label: '停止',
                          onPressed: () {
                            ref.read(activeVenueProvider.notifier).stop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('会場モードを停止しました')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  if (isSending) ...[
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.campaign_rounded,
                            color: _accent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'お知らせ送信中',
                                  style: TextStyle(
                                    color: _accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  activeVenue.teaser!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF172033),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _HeaderPillButton(
                            label: '送信停止',
                            onPressed: () {
                              ref
                                  .read(activeVenueProvider.notifier)
                                  .startReceiveOnly();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('お知らせの送信を停止しました'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: encounters.isEmpty
                ? const Center(
                    child: Text(
                      'からっぽ',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    itemCount: encounters.length,
                    itemBuilder: (context, index) {
                      final encounter = encounters[index];
                      return EncounterCard(encounter: encounter);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStatusPill extends StatelessWidget {
  final String label;

  const _HeaderStatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: _StreamScreenState._accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _HeaderPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _HeaderPillButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD946EF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class EncounterCard extends ConsumerWidget {
  final Encounter encounter;
  const EncounterCard({super.key, required this.encounter});

  String _getTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inMinutes == 0) return 'いま受信';
    if (difference.inHours == 0) return '${difference.inMinutes}分前';
    if (difference.inDays == 0) return '${difference.inHours}時間前';
    return '${difference.inDays}日前';
  }

  void _showActionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text(
                'このユーザーをブロック（ミュート）する',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _showBlockConfirmDialog(context, ref);
              },
            ),
            ListTile(
              leading: Icon(Icons.report_outlined, color: Colors.grey.shade600),
              title: const Text('不適切なコンテンツとして報告する'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _showReportDialog(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showBlockConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('ユーザーをブロック'),
        content: const Text('本当にブロックしますか？\n解除は設定から行えます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await ref
                  .read(blockedPeersProvider.notifier)
                  .blockPeer(encounter.peerId);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('ユーザーをブロックしました')));
              }
            },
            child: const Text('ブロック', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    String? selectedReason;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('報告する'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('報告理由を選択してください'),
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: selectedReason,
                onChanged: (val) => setState(() => selectedReason = val),
                child: Column(
                  children: ['スパム', '不適切な表現', '嫌がらせ・ハラスメント', 'その他']
                      .map(
                        (reason) => RadioListTile<String>(
                          title: Text(reason),
                          value: reason,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '「報告メールを作成」を押すとメールアプリが開きます。内容を確認して送信してください。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () async {
                      final reason = selectedReason!;
                      Navigator.of(dialogCtx).pop();
                      try {
                        await SupportContact.openReportEmail(
                          reason: reason,
                          peerId: encounter.peerId,
                          teaser: encounter.teaser,
                        );
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('メールアプリを開けませんでした: $error')),
                          );
                        }
                      }
                    },
              child: const Text('報告メールを作成'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const accentGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFF7A00), Color(0xFFD946EF)],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3DDEC)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD946EF).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/request', extra: encounter),
          onLongPress: () => _showActionSheet(context, ref),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(
                  width: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: accentGradient),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                encounter.teaser,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF172033),
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '${_getTimeAgo(encounter.lastSeenAt)}・×${encounter.count}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCEBFC),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 10,
                          ),
                          child: const Text(
                            '全文',
                            style: TextStyle(
                              color: Color(0xFFD946EF),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
