import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/vital_quality.dart';
import '../models/sandy_data.dart';
import '../state/sandy_store.dart';
import 'bluetooth_device_service.dart';
import 'health_device_service.dart';

/// Keeps chronic-disease measurements flowing into the app automatically:
///
///  - Health Connect (every synced wearable) is polled on a fixed interval —
///    readings appear without any patient action.
///  - Previously paired Bluetooth meters are re-connected on start and push
///    each new measurement live over GATT notifications.
///
/// Every automatic reading passes through [VitalQualityPolicy] before it is
/// stored: physiologically impossible values are dropped, and plausible-but-
/// suspicious ones are stored flagged with `quality: check` so the UI can
/// warn about the device error margin.
class DeviceSyncService {
  DeviceSyncService._();

  static final DeviceSyncService instance = DeviceSyncService._();

  static const _syncInterval = Duration(minutes: 10);

  final HealthConnectService _healthConnect = HealthConnectService();
  final BluetoothDeviceService _ble = BluetoothDeviceService.instance;

  SandyStore? _store;
  Timer? _timer;
  StreamSubscription<VitalReading>? _bleSub;
  bool _started = false;

  /// Live stream of readings arriving from connected Bluetooth meters
  /// (before quality filtering) — the UI can use it for instant feedback.
  Stream<VitalReading> get bleReadings => _ble.readings;

  /// Starts continuous monitoring (idempotent). Safe to call on every app
  /// launch; failures never propagate to the caller.
  Future<void> start(SandyStore store) async {
    _store = store;
    if (_started) return;
    _started = true;

    // Listen to live Bluetooth meter readings.
    _bleSub = _ble.readings.listen((reading) {
      _import([reading]);
    });

    // Resume connections to previously paired meters in the background.
    unawaited(_ble.connectSavedDevices());

    // Immediate first pull + periodic Health Connect polling.
    unawaited(syncHealthConnectNow());
    _timer = Timer.periodic(_syncInterval, (_) {
      unawaited(syncHealthConnectNow());
    });
  }

  /// Pulls new readings from Health Connect (if the patient already granted
  /// access) and imports them. Returns how many readings were stored.
  Future<int> syncHealthConnectNow() async {
    try {
      final readings = await _healthConnect.fetchReadings(
        since: DateTime.now().subtract(const Duration(hours: 24)),
      );
      return _import(readings);
    } catch (_) {
      // Not authorized / not available — the patient can still sync manually
      // from the vitals screen which shows the permission dialog.
      return 0;
    }
  }

  /// Connects a newly paired meter (called from the pairing dialog). The
  /// device keeps pushing readings; each one is validated then stored.
  Future<bool> connectMeter({
    required String remoteId,
    required String deviceName,
  }) async {
    if (!await _ble.requestPermissions()) return false;
    return _ble.connect(remoteId: remoteId, deviceName: deviceName);
  }

  Future<void> disconnectMeter(String remoteId) =>
      _ble.disconnect(remoteId);

  /// Quality-filters and stores automatic readings. Returns how many were
  /// actually stored (impossible values are dropped silently).
  Future<int> _import(List<VitalReading> readings) async {
    final store = _store;
    if (store == null || readings.isEmpty) return 0;

    final accepted = <VitalReading>[];
    for (final reading in readings) {
      final assessment = VitalQualityPolicy.assess(
        kind: reading.kind,
        value: reading.value,
        recentValues: _recentValues(store, reading.kind),
      );
      if (assessment == null) {
        debugPrint('Dropped implausible ${reading.kind} reading: '
            '${reading.value}');
        continue;
      }
      accepted.add(reading.copyWith(
        quality: assessment.quality,
        deviceName: reading.deviceName ?? reading.source,
      ));
    }
    return store.addVitalsImported(accepted);
  }

  /// Primary values of the latest same-kind readings (oldest → newest),
  /// used by the quality policy to detect suspicious deviations.
  List<double> _recentValues(SandyStore store, String kind) {
    final values = store.vitals
        .where((v) => v.kind == kind)
        .take(5)
        .map((v) => VitalQualityPolicy.primaryValue(kind, v.value))
        .whereType<double>()
        .toList();
    return values.reversed.toList(); // oldest → newest
  }

  void dispose() {
    _timer?.cancel();
    _bleSub?.cancel();
    _started = false;
  }
}