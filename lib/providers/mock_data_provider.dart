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

    var existingIndex = state.indexWhere((e) => e.dedupeKey == dedupeKey);
    if (existingIndex < 0 && senderId != null) {
      existingIndex = state.indexWhere((e) => e.dedupeKey == '$peerId|$teaser');
    }
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      final gap = previousRawSighting == null
          ? now.difference(existing.lastSeenAt)
          : now.difference(previousRawSighting);
      final isSeparateEncounter = gap >= _separateEncounterGap;

      if (!isSeparateEncounter &&
          now.difference(existing.lastSeenAt) < _screenRefreshInterval) {
        return;
      }

      final updated = existing.copyWith(
        peerId: peerId,
        teaser: teaser,
        dedupeKey: dedupeKey,
        rssi: rssi,
        count: existing.count + (isSeparateEncounter ? 1 : 0),
        lastSeenAt: now,
      );
      final newState = List<Encounter>.from(state);
      newState[existingIndex] = updated;
      newState.sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
      state = newState;
      databaseServiceProvider.upsertEncounter(updated);
    } else {
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
    if (!state.any((e) => e.id == log.id)) {
      state = [log, ...state];
      databaseServiceProvider.upsertRequestLog(log);
    }
  }

  void updateRequest(
    String encounterId,
    RequestStatus status, {
    String? body,
    String? error,
  }) {
    final existingIndex = state.indexWhere((e) => e.encounterId == encounterId);
    if (existingIndex >= 0) {
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
    } else {
      final req = RequestLog(
        id: encounterId,
        encounterId: encounterId,
        status: status,
        requestedAt: DateTime.now(),
        resolvedAt:
            (status == RequestStatus.received ||
                status == RequestStatus.failed ||
                status == RequestStatus.timeout)
            ? DateTime.now()
            : null,
        body: body,
        error: error,
      );
      state = [req, ...state];
      databaseServiceProvider.upsertRequestLog(req);
    }
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
