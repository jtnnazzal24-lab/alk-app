import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:alk_flutter/models/sandy_data.dart';
import 'package:alk_flutter/services/health_device_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VitalSource labels', () {
    test('returns Arabic labels', () {
      expect(VitalSource.label(VitalSource.manual), 'يدوي');
      expect(VitalSource.label(VitalSource.healthConnect), 'Health Connect');
      expect(VitalSource.label(VitalSource.bluetooth), 'بلوتوث');
      expect(VitalSource.label('unknown'), 'يدوي');
    });
  });

  group('HealthConnectService', () {
    test('isAvailable returns false when the platform errors', () async {
      final service = HealthConnectService(client: _FakeHealth(available: false));
      expect(await service.isAvailable(), isFalse);
    });

    test('fetchReadings returns empty list on error', () async {
      final service = HealthConnectService(client: _FakeHealth(available: true));
      final result = await service.fetchReadings();
      expect(result, isEmpty);
    });
  });

  group('BluetoothHealthService placeholder', () {
    test('is not available and returns no readings', () async {
      final service = BluetoothHealthService();
      expect(await service.isAvailable(), isFalse);
      expect(await service.fetchReadings(), isEmpty);
    });
  });
}

/// Minimal fake that satisfies just enough of the Health surface used by
/// [HealthConnectService] to exercise the error paths without a real device.
class _FakeHealth extends Health {
  _FakeHealth({required this.available});

  final bool available;

  @override
  Future<bool> isHealthConnectAvailable() async => available;

  @override
  Future<bool> requestAuthorization(List<HealthDataType> types,
      {List<HealthDataAccess>? permissions}) async =>
      false;

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async =>
      const [];
}