import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/bluetooth_models.dart';
import '../services/ble_service.dart';

part 'mock_data_provider.g.dart';

@riverpod
class MockEncounters extends _$MockEncounters {
  @override
  List<Encounter> build() {
    return [];
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
        // Optional: you can update rssi if needed
      );
      final newState = List<Encounter>.from(state);
      newState[existingIndex] = updated;
      
      // Sort to bring most recently seen to the top
      newState.sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
      state = newState;
    } else {
      final newEnc = Encounter(
        id: peerId, // using peerId as ID for simplicity
        peerId: peerId,
        teaser: teaser,
        receivedAt: now,
        dedupeKey: dedupeKey,
        lastSeenAt: now,
        count: 1,
      );
      state = [newEnc, ...state];
    }
  }

  void addEncounter(Encounter enc) {
    state = [enc, ...state];
  }
}

@riverpod
class MockRequestLogs extends _$MockRequestLogs {
  @override
  List<RequestLog> build() {
    return [];
  }

  void addRequest(RequestLog log) {
    // Prevent duplicates
    if (!state.any((e) => e.id == log.id)) {
      state = [log, ...state];
    }
  }

  void updateRequest(String encounterId, RequestStatus status, {String? body, String? error}) {
    // If request doesn't exist yet, create it. Usually happens if native triggers an update without frontend asking first or if we use peerId as encounterId
    final existingIndex = state.indexWhere((e) => e.encounterId == encounterId);
    if (existingIndex >= 0) {
      final newState = List<RequestLog>.from(state);
      final req = newState[existingIndex];
      newState[existingIndex] = req.copyWith(
        status: status,
        resolvedAt: (status == RequestStatus.received || status == RequestStatus.failed || status == RequestStatus.timeout) ? DateTime.now() : null,
        body: body ?? req.body,
        error: error ?? req.error,
      );
      state = newState;
    } else {
      // Create new
      final req = RequestLog(
        id: encounterId, // simplified
        encounterId: encounterId,
        status: status,
        requestedAt: DateTime.now(),
        resolvedAt: (status == RequestStatus.received || status == RequestStatus.failed || status == RequestStatus.timeout) ? DateTime.now() : null,
        body: body,
        error: error,
      );
       state = [req, ...state];
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

  void stop() {
    state = state.copyWith(isBroadcasting: false);
    ref.read(bleServiceProvider).stopVenueMode();
  }
}
