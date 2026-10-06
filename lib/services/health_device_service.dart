import 'package:health/health.dart';

import '../../models/sandy_data.dart';
import 'bluetooth_device_service.dart';

/// Abstraction over the source of vital readings. Implementations pull data
/// from Health Connect, a Bluetooth device, or any future source, and return
/// standardized [VitalReading]s that the rest of the app already understands.
abstract class HealthDeviceService {
  /// Whether this source is available on the current device and authorized.
  Future<bool> isAvailable();

  /// Requests any needed permissions. Returns true if granted.
  Future<bool> requestAuthorization();

  /// Fetches vitals recorded since [since]. Newest last.
  Future<List<VitalReading>> fetchReadings({DateTime? since});
}

/// Reads vitals from Android Health Connect â€” the central store that most
/// modern wearables (Samsung, Xiaomi, Fitbit, Garmin, ...) sync to. This way
/// the app supports any synced device without per-device code.
class HealthConnectService implements HealthDeviceService {
  HealthConnectService({Health? client}) : _client = client ?? Health();

  final Health _client;

  static const _types = [
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.BLOOD_GLUCOSE,
    HealthDataType.HEART_RATE,
    HealthDataType.BLOOD_OXYGEN,
  ];

  @override
  Future<bool> isAvailable() async {
    try {
      return await _client.isHealthConnectAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestAuthorization() async {
    try {
      return await _client.requestAuthorization(_types);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<VitalReading>> fetchReadings({DateTime? since}) async {
    final start = since ??
        DateTime.now().subtract(const Duration(days: 30));
    final end = DateTime.now();

    try {
      final points = await _client.getHealthDataFromTypes(
        types: _types,
        startTime: start,
        endTime: end,
      );
      // FIX: `revokePermissions()` used to be called after every fetch, which
      // silently killed continuous/background syncing â€” every later sync
      // needed the patient to re-grant access. Permissions stay granted so
      // the periodic sync keeps working.
      return _merge(points);
    } catch (_) {
      return const [];
    }
  }

  /// Health Connect stores systolic/diastolic as separate points taken at the
  /// same instant; this merges each pair into one "pressure" reading.
  List<VitalReading> _merge(List<HealthDataPoint> points) {
    final readings = <VitalReading>[];

    // First pass: pair systolic + diastolic that share a timestamp.
    final systolic = <DateTime, double>{};
    final diastolic = <DateTime, double>{};
    for (final p in points) {
      final t = p.dateFrom;
      final num raw = p.value is NumericHealthValue
          ? (p.value as NumericHealthValue).numericValue
          : 0;
      final v = raw.toDouble();
      switch (p.type) {
        case HealthDataType.BLOOD_PRESSURE_SYSTOLIC:
          systolic[t] = v;
          break;
        case HealthDataType.BLOOD_PRESSURE_DIASTOLIC:
          diastolic[t] = v;
          break;
        case HealthDataType.BLOOD_GLUCOSE:
          readings.add(_pointToReading(p, VitalKind.sugar, '${v.toInt()} mg/dL'));
          break;
        case HealthDataType.HEART_RATE:
          readings.add(_pointToReading(p, VitalKind.pulse, '${v.toInt()} bpm'));
          break;
        case HealthDataType.BLOOD_OXYGEN:
          // Health Connect stores SpO2 as a fraction (0.97) or a percentage
          // (97) depending on the writer â€” normalize both to a percentage.
          final pct = v <= 1 ? v * 100 : v;
          readings.add(_pointToReading(
              p, VitalKind.oxygen, '${pct.round()}%'));
          break;
        default:
          break;
      }
    }

    for (final entry in systolic.entries) {
      final sys = entry.value.toInt();
      final dia = (diastolic[entry.key] ?? 0).toInt();
      if (dia > 0) {
        readings.add(VitalReading(
          id: 'hc-bp-${entry.key.millisecondsSinceEpoch}',
          kind: VitalKind.pressure,
          value: '$sys/$dia',
          createdAt: entry.key.toIso8601String(),
          source: VitalSource.healthConnect,
          deviceName: 'Health Connect',
        ));
      }
    }

    readings.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return readings;
  }

  VitalReading _pointToReading(
      HealthDataPoint point, String kind, String value) {
    return VitalReading(
      id: 'hc-$kind-${point.dateFrom.millisecondsSinceEpoch}',
      kind: kind,
      value: value,
      createdAt: point.dateFrom.toIso8601String(),
      source: VitalSource.healthConnect,
      deviceName: 'Health Connect',
    );
  }
}

/// Bluetooth LE implementation backed by [BluetoothDeviceService]: connects
/// to certified meters (blood-pressure monitors, glucose meters, pulse
/// oximeters) using the standard Bluetooth SIG GATT profiles.
class BluetoothHealthService implements HealthDeviceService {
  final BluetoothDeviceService _ble;

  BluetoothHealthService({BluetoothDeviceService? ble})
      : _ble = ble ?? BluetoothDeviceService.instance;

  @override
  Future<bool> isAvailable() => _ble.isAvailable();

  @override
  Future<bool> requestAuthorization() => _ble.requestPermissions();

  @override
  Future<List<VitalReading>> fetchReadings({DateTime? since}) async =>
      const [];
  // Bluetooth meters deliver readings live (GATT notifications) through
  // [BluetoothDeviceService.readings]; there is nothing to "fetch" here.
}
