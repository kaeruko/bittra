import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bluetooth_models.dart';
import '../services/ble_service.dart';
import '../services/database_service.dart';

part 'mock_data_provider.g.dart';

@riverpod
class MockEncounters extends _$MockEncounters {
  @override
  List<Encounter> build() {
    _loadFromDb();
    return [];
  }

  Future<void> _loadFromDb() async {
    final encounters = await databaseServiceProvider.loadEncounters();
    try { state = encounters; } catch (_) {}
  }

  void upsertEncounter({
    required String peerId,
    required String teaser,
    required int rssi,
  }) {
    final dedupeKey = '$peerId|$teaser';
    final now = DateTime.now();

    final existingIndex = state.indexWhere((e) => e.dedupeKey == dedupeKey);
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      final updated = existing.copyWith(
        count: existing.count + 1,
        lastSeenAt: now,
      );
      final newState = List<Encounter>.from(state);
      newState[existingIndex] = updated;
      newState.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
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
    try { state = logs; } catch (_) {}
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

// ブロック済みピアID管理
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
    try { state = list; } catch (_) {}
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

// Dummy Settings
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
  final String? teaser;
  final String? body;

  const VenueState({required this.isBroadcasting, this.teaser, this.body});

  VenueState copyWith({bool? isBroadcasting, String? teaser, String? body}) {
    return VenueState(
      isBroadcasting: isBroadcasting ?? this.isBroadcasting,
      teaser: teaser ?? this.teaser,
      body: body ?? this.body,
    );
  }
}

@riverpod
class ActiveVenue extends _$ActiveVenue {
  static const _keyBroadcasting = 'venue_broadcasting';
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
    final wasBroadcasting = prefs.getBool(_keyBroadcasting) ?? false;

    try { state; } catch (_) { return; }

    if (wasBroadcasting && teaser != null && teaser.isNotEmpty) {
      state = VenueState(isBroadcasting: true, teaser: teaser, body: body);
      ref.read(bleServiceProvider).startVenueMode(teaser, body);
    } else if (wasBroadcasting) {
      state = state.copyWith(isBroadcasting: true);
      ref.read(bleServiceProvider).startReceiveOnly();
    }
  }

  Future<void> _save(VenueState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBroadcasting, s.isBroadcasting);
    if (s.teaser != null) await prefs.setString(_keyTeaser, s.teaser!);
    if (s.body != null) await prefs.setString(_keyBody, s.body!);
  }

  void start(String teaser, String body) {
    state = VenueState(isBroadcasting: true, teaser: teaser, body: body);
    _save(state);
    ref.read(bleServiceProvider).startVenueMode(teaser, body);
  }

  void startReceiveOnly() {
    state = state.copyWith(isBroadcasting: true);
    _save(state);
    ref.read(bleServiceProvider).startReceiveOnly();
  }

  void stop() {
    state = state.copyWith(isBroadcasting: false);
    _save(state);
    ref.read(bleServiceProvider).stopVenueMode();
  }
}
