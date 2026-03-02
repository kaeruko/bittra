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

String _$mockEncountersHash() => r'0002040ee023ace25363e9f0b4c7c3d00c5ccc37';

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

String _$mockRequestLogsHash() => r'c397da668ec47f9e284bc78e4ef69d15cf61355f';

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

String _$mockSettingsHash() => r'd583ecb131fc6cab2882f5af26fc357fafa43d10';

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
