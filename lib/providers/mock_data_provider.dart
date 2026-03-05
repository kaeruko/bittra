import 'package:riverpod_annotation/riverpod_annotation.dart';
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
    state = encounters;
  }

  void upsertEncounter({required String peerId, required String teaser, required int rssi}) {
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
    state = logs;
  }

  void addRequest(RequestLog log) {
    if (!state.any((e) => e.id == log.id)) {
      state = [log, ...state];
      databaseServiceProvider.upsertRequestLog(log);
    }
  }

  void updateRequest(String encounterId, RequestStatus status, {String? body, String? error}) {
    final existingIndex = state.indexWhere((e) => e.encounterId == encounterId);
    if (existingIndex >= 0) {
      final newState = List<RequestLog>.from(state);
      final req = newState[existingIndex];
      final updated = req.copyWith(
        status: status,
        resolvedAt: (status == RequestStatus.received || status == RequestStatus.failed || status == RequestStatus.timeout) ? DateTime.now() : null,
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
        resolvedAt: (status == RequestStatus.received || status == RequestStatus.failed || status == RequestStatus.timeout) ? DateTime.now() : null,
        body: body,
        error: error,
      );
      state = [req, ...state];
      databaseServiceProvider.upsertRequestLog(req);
    }
  }
}

// Dummy Settings
@riverpod
class MockSettings extends _$MockSettings {
  @override
  Map<String, bool> build() {
    return {
      'powerSave': false,
    };
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

  const VenueState({
    required this.isBroadcasting,
    this.teaser,
    this.body,
  });

  VenueState copyWith({
    bool? isBroadcasting,
    String? teaser,
    String? body,
  }) {
    return VenueState(
      isBroadcasting: isBroadcasting ?? this.isBroadcasting,
      teaser: teaser ?? this.teaser,
      body: body ?? this.body,
    );
  }
}

@riverpod
class ActiveVenue extends _$ActiveVenue {
  @override
  VenueState build() {
    return const VenueState(isBroadcasting: false);
  }

  void start(String teaser, String body) {
    state = VenueState(isBroadcasting: true, teaser: teaser, body: body);
    ref.read(bleServiceProvider).startVenueMode(teaser, body);
  }

  void startReceiveOnly() {
    state = state.copyWith(isBroadcasting: true);
    ref.read(bleServiceProvider).startReceiveOnly();
  }

  void stop() {
    state = state.copyWith(isBroadcasting: false);
    ref.read(bleServiceProvider).stopVenueMode();
  }
}
