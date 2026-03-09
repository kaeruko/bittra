// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mock_data_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MockEncounters)
final mockEncountersProvider = MockEncountersProvider._();

final class MockEncountersProvider
    extends $NotifierProvider<MockEncounters, List<Encounter>> {
  MockEncountersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mockEncountersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mockEncountersHash();

  @$internal
  @override
  MockEncounters create() => MockEncounters();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Encounter> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Encounter>>(value),
    );
  }
}

String _$mockEncountersHash() => r'ef1feaf3641921931ae835e5c4a7f1598a503473';

abstract class _$MockEncounters extends $Notifier<List<Encounter>> {
  List<Encounter> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<Encounter>, List<Encounter>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<Encounter>, List<Encounter>>,
              List<Encounter>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(MockRequestLogs)
final mockRequestLogsProvider = MockRequestLogsProvider._();

final class MockRequestLogsProvider
    extends $NotifierProvider<MockRequestLogs, List<RequestLog>> {
  MockRequestLogsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mockRequestLogsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mockRequestLogsHash();

  @$internal
  @override
  MockRequestLogs create() => MockRequestLogs();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<RequestLog> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<RequestLog>>(value),
    );
  }
}

String _$mockRequestLogsHash() => r'33357afa7b523fbe3e4743defbb3ed2aa55b5022';

abstract class _$MockRequestLogs extends $Notifier<List<RequestLog>> {
  List<RequestLog> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<RequestLog>, List<RequestLog>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<RequestLog>, List<RequestLog>>,
              List<RequestLog>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(BlockedPeers)
final blockedPeersProvider = BlockedPeersProvider._();

final class BlockedPeersProvider
    extends $NotifierProvider<BlockedPeers, List<String>> {
  BlockedPeersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'blockedPeersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$blockedPeersHash();

  @$internal
  @override
  BlockedPeers create() => BlockedPeers();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$blockedPeersHash() => r'b1a2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0';

abstract class _$BlockedPeers extends $Notifier<List<String>> {
  List<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<String>, List<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<String>, List<String>>,
              List<String>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(MockSettings)
final mockSettingsProvider = MockSettingsProvider._();

final class MockSettingsProvider
    extends $NotifierProvider<MockSettings, Map<String, bool>> {
  MockSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mockSettingsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mockSettingsHash();

  @$internal
  @override
  MockSettings create() => MockSettings();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, bool> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, bool>>(value),
    );
  }
}

String _$mockSettingsHash() => r'770328d9e8f406d8013dd835269ec32f4f09c33e';

abstract class _$MockSettings extends $Notifier<Map<String, bool>> {
  Map<String, bool> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Map<String, bool>, Map<String, bool>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, bool>, Map<String, bool>>,
              Map<String, bool>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(ActiveVenue)
final activeVenueProvider = ActiveVenueProvider._();

final class ActiveVenueProvider
    extends $NotifierProvider<ActiveVenue, VenueState> {
  ActiveVenueProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeVenueProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeVenueHash();

  @$internal
  @override
  ActiveVenue create() => ActiveVenue();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VenueState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VenueState>(value),
    );
  }
}

String _$activeVenueHash() => r'd3bb87577b6acb758dd27ccb33d42d019993044f';

abstract class _$ActiveVenue extends $Notifier<VenueState> {
  VenueState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<VenueState, VenueState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VenueState, VenueState>,
              VenueState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
