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

  Future<void> addSentNotice({
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
  }
}
