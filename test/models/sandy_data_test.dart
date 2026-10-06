import 'package:flutter_test/flutter_test.dart';
import 'package:alk_flutter/models/sandy_data.dart';


void main() {
  test('medication intervalDays serializes and deserializes', () {
    const med = Medication(
      id: 'm1',
      name: 'أسبيرين',
      time: '08:00',
      category: MedicationCategory.heart,
      dose: '100 ملغ',
      form: MedicationForm.tablet,
      intervalDays: 2,
      taken: false,
      reminderEnabled: false,
      updatedAt: '2026-01-01T00:00:00Z',
    );
    final restored = Medication.fromJson(med.toJson());
    expect(restored.intervalDays, 2);
    expect(restored.dose, '100 ملغ');
    expect(restored.form, 'حبة');
    // Legacy data without the field defaults to every day.
    final legacy = Medication.fromJson({'id': 'm2', 'name': 'x'});
    expect(legacy.intervalDays, 1);
  });


  group('SandyData Model Tests', () {
    test('Medication creates with required fields', () {
      const med = Medication(
        id: 'test-1',
        name: 'أسبرين',
        time: '08:00',
        category: 'قلب',
        taken: false,
        updatedAt: '2024-01-01T00:00:00.000Z',
        reminderEnabled: true,
      );

      expect(med.id, 'test-1');
      expect(med.name, 'أسبرين');
      expect(med.time, '08:00');
      expect(med.category, 'قلب');
      expect(med.taken, false);
      expect(med.reminderEnabled, true);
    });

    test('VitalReading creates with correct values', () {
      const vital = VitalReading(
        id: 'vital-1',
        kind: 'pressure',
        value: '120/80',
        createdAt: '2024-01-01T00:00:00.000Z',
      );

      expect(vital.kind, 'pressure');
      expect(vital.value, '120/80');
      expect(vital.displayValue, '120/80');
    });

    test('JournalEntry creates with mood and note', () {
      const entry = JournalEntry(
        id: 'journal-1',
        mood: 'مرتاح',
        note: 'يوم جيد',
        createdAt: '2024-01-01T00:00:00.000Z',
      );

      expect(entry.mood, 'مرتاح');
      expect(entry.note, 'يوم جيد');
    });

    test('PatientProfile has default values', () {
      const patient = PatientProfile.initial;

      expect(patient.fullName, '');
      expect(patient.identityNumber, '');
      expect(patient.lockEnabled, false);
    });

    test('FoodEntry serializes and deserializes', () {
      const entry = FoodEntry(
        id: 'food-1',
        name: 'أرز أبيض',
        mealType: FoodMealType.lunch,
        createdAt: '2024-01-01T00:00:00.000Z',
      );

      final json = entry.toJson();
      expect(json['id'], 'food-1');
      expect(json['name'], 'أرز أبيض');
      expect(json['mealType'], 'غداء');

      final restored = FoodEntry.fromJson(json);
      expect(restored.id, 'food-1');
      expect(restored.name, 'أرز أبيض');
      expect(restored.mealType, FoodMealType.lunch);
    });

    test('VitalReading carries source and device name', () {
      const reading = VitalReading(
        id: 'v1',
        kind: 'sugar',
        value: '120',
        createdAt: '2024-01-01T00:00:00.000Z',
        source: VitalSource.healthConnect,
        deviceName: 'Galaxy Watch',
      );

      expect(reading.source, VitalSource.healthConnect);
      expect(reading.deviceName, 'Galaxy Watch');

      final json = reading.toJson();
      expect(json['source'], VitalSource.healthConnect);
      expect(json['deviceName'], 'Galaxy Watch');

      final restored = VitalReading.fromJson(json);
      expect(restored.source, VitalSource.healthConnect);
      expect(restored.deviceName, 'Galaxy Watch');
    });

    test('VitalReading defaults to manual source', () {
      const reading = VitalReading(
        id: 'v2',
        kind: 'pulse',
        value: '72',
        createdAt: '2024-01-01T00:00:00.000Z',
      );
      expect(reading.source, VitalSource.manual);
      expect(reading.deviceName, isNull);
    });
  });
}
