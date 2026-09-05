import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bluetooth_models.dart';
import '../services/ble_service.dart';
import '../services/database_service.dart';

part 'mock_data_provider.g.dart';

@riverpod
class MockEncounters extends _$MockEncounters {
  static const _separateEncounterGap = Duration(seconds: 30);
  static const _screenRefreshInterval = Duration(seconds: 2);
  final Map<String, DateTime> _lastRawSightings = {};

  @override
  List<Encounter> build() {
    _loadFromDb();
    return [];
  }

  Future<void> _loadFromDb() async {
    final encounters = await databaseServiceProvider.loadEncounters();
    try {
      state = encounters;
    } catch (_) {}
  }

  void upsertEncounter({
    required String peerId,
    int? senderId,
    required String teaser,
    required int rssi,
  }) {
    final dedupeKey = senderId == null ? '$peerId|$teaser' : 'sender:$senderId';
    final now = DateTime.now();
    final previousRawSighting = _lastRawSightings[dedupeKey];
    _lastRawSightings[dedupeKey] = now;

    final matchingIndices = <int>[];
    for (var index = 0; index < state.length; index++) {
      final encounter = state[index];
      final sameStableSender = encounter.dedupeKey == dedupeKey;
      final sameLegacyPeer =
          senderId != null &&
          !encounter.dedupeKey.startsWith('sender:') &&
          encounter.peerId == peerId;
      if (sameStableSender || sameLegacyPeer) {
        matchingIndices.add(index);
      }
    }

    if (matchingIndices.isNotEmpty) {
      final exactSenderIndices = matchingIndices
          .where((index) => state[index].dedupeKey == dedupeKey)
          .toList();
      final canonicalPool = exactSenderIndices.isNotEmpty
          ? exactSenderIndices
          : matchingIndices;
      var canonicalIndex = canonicalPool.first;
      for (final index in canonicalPool.skip(1)) {
        if (state[index].lastSeenAt.isAfter(state[canonicalIndex].lastSeenAt)) {
          canonicalIndex = index;
        }
      }

      var latestLastSeenAt = state[matchingIndices.first].lastSeenAt;
      var earliestReceivedAt = state[matchingIndices.first].receivedAt;
      var maxCount = state[matchingIndices.first].count;
      for (final index in matchingIndices.skip(1)) {
        final encounter = state[index];
        if (encounter.lastSeenAt.isAfter(latestLastSeenAt)) {
          latestLastSeenAt = encounter.lastSeenAt;
        }
        if (encounter.receivedAt.isBefore(earliestReceivedAt)) {
          earliestReceivedAt = encounter.receivedAt;
        }
        if (encounter.count > maxCount) {
          maxCount = encounter.count;
        }
      }

      final gap = previousRawSighting == null
          ? now.difference(latestLastSeenAt)
          : now.difference(previousRawSighting);
      final isSeparateEncounter = gap >= _separateEncounterGap;
      final hasDuplicates = matchingIndices.length > 1;

      if (!hasDuplicates &&
          !isSeparateEncounter &&
          now.difference(latestLastSeenAt) < _screenRefreshInterval) {
        return;
      }

      final canonical = state[canonicalIndex];
      final updated = canonical.copyWith(
        peerId: peerId,
        teaser: teaser,
        receivedAt: earliestReceivedAt,
        dedupeKey: dedupeKey,
        rssi: rssi,
        count: maxCount + (isSeparateEncounter ? 1 : 0),
        lastSeenAt: now,
      );

      final duplicateIds = matchingIndices
          .where((index) => index != canonicalIndex)
          .map((index) => state[index].id)
          .where((id) => id != updated.id)
          .toSet()
          .toList();

      final matchingIndexSet = matchingIndices.toSet();
      final newState = <Encounter>[
        updated,
        for (var index = 0; index < state.length; index++)
          if (!matchingIndexSet.contains(index)) state[index],
      ]..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
      state = newState;

      databaseServiceProvider.replaceEncounterAndDeleteDuplicates(
        updated,
        duplicateIds: duplicateIds,
      );
      return;
    }

    final newEnc = Encounter(
      id: peerId,
      peerId: peerId,
      teaser: teaser,
      receivedAt: now,
      dedupeKey: dedupeKey,
      lastSeenAt: now,
      count: 1,
      rssi: rssi,
    );
    state = [newEnc, ...state];
    databaseServiceProvider.upsertEncounter(newEnc);
  }

  void addEncounter(Encounter enc) {
    state = [enc, ...state];
    databaseServiceProvider.upsertEncounter(enc);
  }
}

@riverpod
class MockRequestLogs extends _$MockRequestLogs {
  @override
  List<RequestLog> build() {
    _loadFromDb();
    return [];
  }

  Future<void> _loadFromDb() async {
    final logs = await databaseServiceProvider.loadRequestLogs();
    try {
      state = logs;
    } catch (_) {}
  }

  void addRequest(RequestLog log) {
    if (state.any((e) => e.id == log.id)) {
      throw StateError('Duplicate request log id: ${log.id}');
    }
    state = [log, ...state];
    databaseServiceProvider.upsertRequestLog(log);
  }

  void updateRequest(
    String requestId,
    RequestStatus status, {
    String? body,
    String? error,
  }) {
    final existingIndex = state.indexWhere((e) => e.id == requestId);
    if (existingIndex < 0) {
      throw StateError('Request log not found: requestId=$requestId');
    }

    final newState = List<RequestLog>.from(state);
    final req = newState[existingIndex];
    final updated = req.copyWith(
      status: status,
      resolvedAt:
          (status == RequestStatus.received ||
              status == RequestStatus.failed ||
              status == RequestStatus.timeout)
          ? DateTime.now()
          : null,
      body: body ?? req.body,
      error: error ?? req.error,
    );
    newState[existingIndex] = updated;
    state = newState;
    databaseServiceProvider.upsertRequestLog(updated);
  }
}

@riverpod
class BlockedPeers extends _$BlockedPeers {
  static const _key = 'blocked_peers';

  @override
  List<String> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    try {
      state = list;
    } catch (_) {}
  }

  Future<void> blockPeer(String peerId) async {
    if (state.contains(peerId)) return;
    final newState = [...state, peerId];
    state = newState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, newState);
  }

  Future<void> unblockPeer(String peerId) async {
    final newState = state.where((id) => id != peerId).toList();
    state = newState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, newState);
  }
}

@riverpod
class MockSettings extends _$MockSettings {
  @override
  Map<String, bool> build() {
    return {'powerSave': false};
  }

  void togglePowerSave() {
    final current = state['powerSave'] ?? false;
    state = {...state, 'powerSave': !current};
  }
}

class VenueState {
  final bool isBroadcasting;
  final bool isSending;
  final String? teaser;
  final String? body;

  const VenueState({
    required this.isBroadcasting,
    this.isSending = false,
    this.teaser,
    this.body,
  });

  VenueState copyWith({
    bool? isBroadcasting,
    bool? isSending,
    String? teaser,
    String? body,
  }) {
    return VenueState(
      isBroadcasting: isBroadcasting ?? this.isBroadcasting,
      isSending: isSending ?? this.isSending,
      teaser: teaser ?? this.teaser,
      body: body ?? this.body,
    );
  }
}

@riverpod
class ActiveVenue extends _$ActiveVenue {
  static const _keyBluetoothEnabled = 'bluetooth_enabled';
  static const _keySending = 'venue_sending';
  static const _keyTeaser = 'venue_teaser';
  static const _keyBody = 'venue_body';

  @override
  VenueState build() {
    _loadAndRestore();
    return const VenueState(isBroadcasting: false);
  }

  Future<void> _loadAndRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final teaser = prefs.getString(_keyTeaser);
    final body = prefs.getString(_keyBody) ?? '';
    final bluetoothEnabled = prefs.getBool(_keyBluetoothEnabled) ?? true;

    try {
      state;
    } catch (_) {
      return;
    }

    if (!bluetoothEnabled) {
      state = VenueState(
        isBroadcasting: false,
        teaser: teaser,
        body: body,
      );
      return;
    }

    state = VenueState(
      isBroadcasting: true,
      isSending: false,
      teaser: teaser,
      body: body,
    );
    await prefs.setBool(_keyBluetoothEnabled, true);
    await prefs.setBool(_keySending, false);
    await ref.read(bleServiceProvider).startReceiveOnly();
  }

  Future<void> _save(VenueState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBluetoothEnabled, s.isBroadcasting);
    await prefs.setBool(_keySending, s.isSending);
    if (s.teaser != null) await prefs.setString(_keyTeaser, s.teaser!);
    if (s.body != null) await prefs.setString(_keyBody, s.body!);
  }

  Future<void> start(String noticeId, String teaser, String body) async {
    await ref.read(bleServiceProvider).startVenueMode(noticeId, teaser, body);
    state = VenueState(
      isBroadcasting: true,
      isSending: true,
      teaser: teaser,
      body: body,
    );
    await _save(state);
  }

  void startReceiveOnly() {
    state = VenueState(
      isBroadcasting: true,
      teaser: state.teaser,
      body: state.body,
    );
    _save(state);
    ref.read(bleServiceProvider).startReceiveOnly();
  }

  void stop() {
    state = VenueState(
      isBroadcasting: false,
      teaser: state.teaser,
      body: state.body,
    );
    _save(state);
    ref.read(bleServiceProvider).stopVenueMode();
  }
}
