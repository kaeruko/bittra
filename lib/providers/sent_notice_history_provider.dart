import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/bluetooth_models.dart';
import '../services/database_service.dart';

final sentNoticeHistoryProvider =
    NotifierProvider<SentNoticeHistoryNotifier, List<SentNotice>>(
      SentNoticeHistoryNotifier.new,
    );

class SentNoticeHistoryNotifier extends Notifier<List<SentNotice>> {
  static final Uuid _uuid = Uuid();
  late Future<void> _loadFuture;

  @override
  List<SentNotice> build() {
    _loadFuture = _loadFromDb();
    return const [];
  }

  Future<void> _loadFromDb() async {
    final notices = await databaseServiceProvider.loadSentNotices();
    state = notices;
  }

  Future<SentNotice> addSentNotice({
    required String teaser,
    required String body,
  }) async {
    await _loadFuture;

    final notice = SentNotice(
      id: _uuid.v4(),
      teaser: teaser,
      body: body,
      sentAt: DateTime.now(),
    );

    await databaseServiceProvider.insertSentNotice(notice);
    state = [notice, ...state];
    return notice;
  }

  Future<void> updateReceivedCount({
    required String noticeId,
    required int receivedCount,
  }) async {
    if (receivedCount < 0) {
      throw ArgumentError.value(
        receivedCount,
        'receivedCount',
        'must be zero or greater',
      );
    }

    await _loadFuture;
    final index = state.indexWhere((notice) => notice.id == noticeId);
    if (index < 0) {
      throw StateError('Sent notice not found for delivery receipt: $noticeId');
    }

    final current = state[index];
    if (receivedCount < current.receivedCount) {
      throw StateError(
        'Delivery receipt count regressed for $noticeId: '
        '${current.receivedCount} -> $receivedCount',
      );
    }
    if (receivedCount == current.receivedCount) {
      return;
    }

    await databaseServiceProvider.updateSentNoticeReceivedCount(
      noticeId,
      receivedCount,
    );

    final updatedState = List<SentNotice>.from(state);
    updatedState[index] = current.copyWith(receivedCount: receivedCount);
    state = updatedState;
  }
}
