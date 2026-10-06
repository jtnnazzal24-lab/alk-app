import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sandy_data.dart';

// ---- Standard Bluetooth SIG GATT medical services ---------------------------
// Every certified chronic-disease meter implements these well-known profiles,
// so one parser set supports any compliant device (Omron, A&D, Accu-Chek,
// Beurer, iHealth, Wellion, ...).

/// Blood Pressure service (0x1810) — measurement char 0x2A35 (notify).
final Guid svcBloodPressure = Guid('00001810-0000-1000-8000-00805f9b34fb');
final Guid chrBloodPressureMeasurement =
    Guid('00002a35-0000-1000-8000-00805f9b34fb');

/// Glucose service (0x1808) — measurement char 0x2A18 (notify).
final Guid svcGlucose = Guid('00001808-0000-1000-8000-00805f9b34fb');
final Guid chrGlucoseMeasurement =
    Guid('00002a18-0000-1000-8000-00805f9b34fb');

/// Heart Rate service (0x180D) — measurement char 0x2A37 (notify).
final Guid svcHeartRate = Guid('0000180d-0000-1000-8000-00805f9b34fb');
final Guid chrHeartRateMeasurement =
    Guid('00002a37-0000-1000-8000-00805f9b34fb');

/// Pulse Oximeter service (0x1822) — spot-check char 0x2A5E (indicate).
final Guid svcPulseOximeter = Guid('00001822-0000-1000-8000-00805f9b34fb');
final Guid chrPlxSpotCheck = Guid('00002a5e-0000-1000-8000-00805f9b34fb');

List<Guid> get medicalServiceUuids =>
    [svcBloodPressure, svcGlucose, svcHeartRate, svcPulseOximeter];

// ---- IEEE-11073 16-bit SFLOAT (used by all the profiles above) --------------

/// Decodes a Bluetooth SIG IEEE-11073 16-bit SFLOAT. Returns null for the
/// reserved values (NaN / NRes / ±Inf) so bad frames never become readings.
double? decodeSfloat(int raw) {
  // Reserved special values per the SIG specification.
  if (raw == 0x07FF ||
      raw == 0x0800 ||
      raw == 0x07FE ||
      raw == 0x0801 ||
      raw == 0x0802) {
    return null;
  }
  int mantissa = raw & 0x0FFF;
  int exponent = (raw >> 12) & 0x0F;
  if (mantissa >= 0x0800) mantissa -= 0x1000; // 12-bit two's complement.
  if (exponent >= 0x08) exponent -= 0x10; // 4-bit two's complement.
  return mantissa * math.pow(10, exponent).toDouble();
}

int _u16(List<int> d, int i) => d[i] | (d[i + 1] << 8);

// ---- Profile-specific measurement parsers (pure, unit-tested) ---------------

class BleBloodPressure {
  final int systolicMmHg;
  final int diastolicMmHg;
  final int? pulseBpm;

  const BleBloodPressure({
    required this.systolicMmHg,
    required this.diastolicMmHg,
    this.pulseBpm,
  });
}

/// Parses the Blood Pressure Measurement characteristic (0x2A35).
BleBloodPressure? parseBloodPressureMeasurement(List<int> data) {
  if (data.length < 7) return null;
  final flags = data[0];
  final usesKpa = flags & 0x01 != 0;

  final sys = decodeSfloat(_u16(data, 1));
  final dia = decodeSfloat(_u16(data, 3));
  if (sys == null || dia == null) return null;

  // Skip MAP (sfloat at offset 5) and the optional timestamp (7 bytes).
  var offset = 7;
  if (flags & 0x02 != 0) offset += 7;

  int? pulse;
  if (flags & 0x04 != 0 && data.length >= offset + 2) {
    final rawPulse = decodeSfloat(_u16(data, offset));
    if (rawPulse != null) pulse = rawPulse.round();
  }

  final factor = usesKpa ? 7.50062 : 1.0;
  return BleBloodPressure(
    systolicMmHg: (sys * factor).round(),
    diastolicMmHg: (dia * factor).round(),
    pulseBpm: pulse,
  );
}

class BleGlucose {
  final int mgDl;
  const BleGlucose({required this.mgDl});
}

/// Parses the Glucose Measurement characteristic (0x2A18) and normalizes the
/// concentration to mg/dL regardless of the device's unit flag.
BleGlucose? parseGlucoseMeasurement(List<int> data) {
  if (data.length < 12) return null;
  final flags = data[0];
  final usesMolL = flags & 0x01 != 0;

  // Sequence (2 bytes) at 1..2, base time (7 bytes) at 3..9.
  var offset = 10;
  if (flags & 0x04 != 0) offset += 2; // time offset present
  if (data.length < offset + 2) return null;

  final concentration = decodeSfloat(_u16(data, offset));
  if (concentration == null || concentration < 0) return null;

  // kg/L × 100000 → mg/dL ; mol/L × 18015.6 → mg/dL (glucose, C6H12O6).
  final mgDl = usesMolL ? concentration * 18015.6 : concentration * 100000;
  return BleGlucose(mgDl: mgDl.round());
}

class BleHeartRate {
  final int bpm;
  const BleHeartRate({required this.bpm});
}

/// Parses the Heart Rate Measurement characteristic (0x2A37).
BleHeartRate? parseHeartRateMeasurement(List<int> data) {
  if (data.length < 2) return null;
  final flags = data[0];
  final bpm = flags & 0x01 != 0 ? _u16(data, 1) : data[1];
  if (bpm <= 0) return null;
  return BleHeartRate(bpm: bpm);
}

class BlePulseOximeter {
  final int spo2Percent;
  final int pulseBpm;
  const BlePulseOximeter({required this.spo2Percent, required this.pulseBpm});
}

/// Parses the PLX Spot-Check Measurement characteristic (0x2A5E).
BlePulseOximeter? parsePlxSpotCheck(List<int> data) {
  if (data.length < 5) return null;
  final spo2 = decodeSfloat(_u16(data, 1));
  final pulse = decodeSfloat(_u16(data, 3));
  if (spo2 == null || pulse == null || spo2 <= 0 || pulse <= 0) return null;
  return BlePulseOximeter(
    spo2Percent: spo2.round(),
    pulseBpm: pulse.round(),
  );
}

// ---- Connection management --------------------------------------------------

/// A discoverable certified medical meter.
class MedicalBleDevice {
  final String remoteId;
  final String name;
  final List<String> kinds; // VitalKinds the device can measure.

  const MedicalBleDevice({
    required this.remoteId,
    required this.name,
    required this.kinds,
  });
}

/// Live Bluetooth LE connection to certified chronic-disease meters.
///
/// Devices push every new measurement over GATT notifications, so once
/// connected the patient never enters a number manually: the meter measures,
/// the app receives, validates (quality policy upstream) and stores.
class BluetoothDeviceService {
  BluetoothDeviceService._();

  static final BluetoothDeviceService instance = BluetoothDeviceService._();

  static const _prefsKey = 'alk-ble-medical-devices';

  final _connections = <String, _BleConnection>{};

  /// Broadcast stream of readings arriving from every connected device.
  final _readings = StreamController<VitalReading>.broadcast();
  Stream<VitalReading> get readings => _readings.stream;

  List<String> get connectedIds => _connections.keys.toList();

  /// Whether Bluetooth LE is usable right now. Returns false (instead of
  /// throwing) on unsupported platforms and in unit tests.
  Future<bool> isAvailable() async {
    try {
      final state = await FlutterBluePlus.adapterState.firstWhere(
        (s) => s != BluetoothAdapterState.turningOn,
        orElse: () => BluetoothAdapterState.unknown,
      );
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  /// Requests the Bluetooth permissions required on Android 12+.
  Future<bool> requestPermissions() async {
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      return statuses.values.every((s) => s.isGranted || s.isLimited);
    } catch (_) {
      return false;
    }
  }

  /// Scans for devices advertising one of the standard medical services.
  /// Results are de-duplicated by id.
  Future<List<MedicalBleDevice>> scanForMedicalDevices({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!await isAvailable()) return const [];
    final found = <String, MedicalBleDevice>{};
    StreamSubscription<List<ScanResult>>? sub;
    try {
      sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final kinds = <String>[];
          for (final uuid in r.advertisementData.serviceUuids) {
            if (uuid == svcBloodPressure) kinds.add(VitalKind.pressure);
            if (uuid == svcGlucose) kinds.add(VitalKind.sugar);
            if (uuid == svcHeartRate) kinds.add(VitalKind.pulse);
            if (uuid == svcPulseOximeter) kinds.add(VitalKind.oxygen);
          }
          if (kinds.isEmpty) continue;
          final id = r.device.remoteId.str;
          final advName = r.advertisementData.advName;
          found[id] = MedicalBleDevice(
            remoteId: id,
            name: (advName.isNotEmpty ? advName : r.device.platformName)
                .trim(),
            kinds: kinds,
          );
        }
      });
      await FlutterBluePlus.startScan(
        withServices: medicalServiceUuids,
        timeout: timeout,
      );
    } catch (_) {
      // Scanning failed (no adapter, permissions...) — return what we got.
    } finally {
      await sub?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    return found.values.toList();
  }

  /// Connects to [remoteId] with auto-reconnect and subscribes to its
  /// measurement notifications. Incoming readings are emitted on [readings].
  Future<bool> connect({
    required String remoteId,
    required String deviceName,
  }) async {
    if (_connections.containsKey(remoteId)) return true;
    try {
      final device = BluetoothDevice.fromId(remoteId);
      // autoConnect: the OS keeps re-establishing the link in the background,
      // which is what makes continuous measurement work across dropouts.
      await device.connect(
        timeout: const Duration(seconds: 20),
        autoConnect: true,
      );
      final services = await device.discoverServices();

      final handlers = <_CharHandler>[];
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          _CharHandler? handler;
          if (service.uuid == svcBloodPressure &&
              characteristic.uuid == chrBloodPressureMeasurement) {
            handler = _CharHandler(
              characteristic: characteristic,
              parse: (d) => _bpReading(d, deviceName),
            );
          } else if (service.uuid == svcGlucose &&
              characteristic.uuid == chrGlucoseMeasurement) {
            handler = _CharHandler(
              characteristic: characteristic,
              parse: (d) => _glucoseReading(d, deviceName),
            );
          } else if (service.uuid == svcHeartRate &&
              characteristic.uuid == chrHeartRateMeasurement) {
            handler = _CharHandler(
              characteristic: characteristic,
              parse: (d) => _heartRateReading(d, deviceName),
            );
          } else if (service.uuid == svcPulseOximeter &&
              characteristic.uuid == chrPlxSpotCheck) {
            handler = _CharHandler(
              characteristic: characteristic,
              parse: (d) => _pulseOxReading(d, deviceName),
            );
          }
          if (handler != null) handlers.add(handler);
        }
      }
      if (handlers.isEmpty) {
        // Not a standard medical meter after all.
        await device.disconnect();
        return false;
      }

      final subs = <StreamSubscription<void>>[];
      for (final handler in handlers) {
        await handler.characteristic.setNotifyValue(true);
        subs.add(handler.characteristic.onValueReceived.listen((data) {
          final reading = handler.parse(data);
          if (reading != null) _readings.add(reading);
        }));
      }

      // Clean up bookkeeping when the link dies.
      subs.add(device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _teardown(remoteId);
        }
      }));

      _connections[remoteId] =
          _BleConnection(device: device, subscriptions: subs);
      await _saveDevice(remoteId, deviceName);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect(String remoteId) async {
    final connection = _connections.remove(remoteId);
    try {
      await connection?.device.disconnect();
    } catch (_) {}
  }

  /// Reconnects every previously paired device (used on app start so
  /// continuous measurement resumes without any patient action).
  Future<void> connectSavedDevices() async {
    final saved = await savedDevices();
    for (final entry in saved.entries) {
      if (!_connections.containsKey(entry.key)) {
        await connect(remoteId: entry.key, deviceName: entry.value);
      }
    }
  }

  /// Saved device ids → names (SharedPreferences).
  Future<Map<String, String>> savedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey) ?? const <String>[];
      return {
        for (final item in raw)
          if (item.contains('|'))
            item.split('|').first: item.split('|').skip(1).join('|'),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> _saveDevice(String remoteId, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await savedDevices();
      saved[remoteId] = name;
      await prefs.setStringList(
        _prefsKey,
        saved.entries.map((e) => '${e.key}|${e.value}').toList(),
      );
    } catch (_) {}
  }

  void _teardown(String remoteId) {
    final connection = _connections.remove(remoteId);
    for (final sub
        in connection?.subscriptions ?? const <StreamSubscription<void>>[]) {
      sub.cancel();
    }
  }

  // ---- Reading builders ----------------------------------------------------

  VitalReading? _bpReading(List<int> data, String deviceName) {
    final bp = parseBloodPressureMeasurement(data);
    if (bp == null) return null;
    return VitalReading(
      id: 'ble-bp-$deviceName-${DateTime.now().millisecondsSinceEpoch}',
      kind: VitalKind.pressure,
      value: '${bp.systolicMmHg}/${bp.diastolicMmHg}',
      createdAt: DateTime.now().toIso8601String(),
      source: VitalSource.bluetooth,
      deviceName: deviceName,
    );
  }

  VitalReading? _glucoseReading(List<int> data, String deviceName) {
    final glucose = parseGlucoseMeasurement(data);
    if (glucose == null) return null;
    return VitalReading(
      id: 'ble-sugar-$deviceName-${DateTime.now().millisecondsSinceEpoch}',
      kind: VitalKind.sugar,
      value: '${glucose.mgDl} mg/dL',
      createdAt: DateTime.now().toIso8601String(),
      source: VitalSource.bluetooth,
      deviceName: deviceName,
    );
  }

  VitalReading? _heartRateReading(List<int> data, String deviceName) {
    final hr = parseHeartRateMeasurement(data);
    if (hr == null) return null;
    return VitalReading(
      id: 'ble-pulse-$deviceName-${DateTime.now().millisecondsSinceEpoch}',
      kind: VitalKind.pulse,
      value: '${hr.bpm} bpm',
      createdAt: DateTime.now().toIso8601String(),
      source: VitalSource.bluetooth,
      deviceName: deviceName,
    );
  }

  VitalReading? _pulseOxReading(List<int> data, String deviceName) {
    final plx = parsePlxSpotCheck(data);
    if (plx == null) return null;
    return VitalReading(
      id: 'ble-spo2-$deviceName-${DateTime.now().millisecondsSinceEpoch}',
      kind: VitalKind.oxygen,
      value: '${plx.spo2Percent}% — ${plx.pulseBpm} bpm',
      createdAt: DateTime.now().toIso8601String(),
      source: VitalSource.bluetooth,
      deviceName: deviceName,
    );
  }
}

class _CharHandler {
  final BluetoothCharacteristic characteristic;
  final VitalReading? Function(List<int> data) parse;

  const _CharHandler({required this.characteristic, required this.parse});
}

class _BleConnection {
  final BluetoothDevice device;
  final List<StreamSubscription<void>> subscriptions;

  const _BleConnection({required this.device, required this.subscriptions});
}