  import 'package:flutter_test/flutter_test.dart';
import 'package:alk_flutter/logic/voice_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alk_flutter/state/sandy_store.dart';
import 'package:alk_flutter/storage/sandy_repository.dart';

import '../helpers/platform_secrets.dart';

void main() {
  // لا قنوات منصّة للتخزين الآمن في اختبارات الوحدة (التشفير يُختبر مستقلاً).
  setUpAll(disableSecureStorageInTests);
  tearDownAll(restoreSecureStorageAfterTests);

  test('emergency contacts and ambulance persist', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SandyStore(SandyRepository());
    await store.init();
    await store.setAmbulanceNumber('997');
    await store.addEmergencyContact('أحمد', '0592055302');
    await store.addEmergencyContact('أحمد', '0592055302'); // duplicate ignored
    expect(store.ambulanceNumber, '997');
    expect(store.emergencyContacts.length, 1);
    expect(store.emergencyContacts.first.name, 'أحمد');
    await store.removeEmergencyContact(store.emergencyContacts.first.id);
    expect(store.emergencyContacts, isEmpty);
  });

  test('voice intents: emergency and call contact', () {
    expect(parseVoiceIntent('طوارئ'), isA<VoiceCallAmbulance>());
    final call = parseVoiceIntent('اتصل بـ أحمد');
    expect(call, isA<VoiceCallContact>());
    expect((call as VoiceCallContact).name, 'أحمد');
  });

  group('SandyStore Tests', () {
    late SandyStore store;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      store = SandyStore(SandyRepository());
    });

    test('Initial state has empty data', () {
      expect(store.medications, isEmpty);
      expect(store.vitals, isEmpty);
      expect(store.journals, isEmpty);
      expect(store.loaded, false);
    });

    test('Default language is Arabic', () {
      expect(store.languageTag, 'ar');
      expect(store.isRTL, true);
    });

    test('Arabic is the only language — saved override ignored on init',
        () async {
      SharedPreferences.setMockInitialValues({
        SandyRepository.localeOverrideKey: 'en',
      });
      final reloaded = SandyStore(SandyRepository());
      await reloaded.init();
      expect(reloaded.languageTag, 'ar');
      expect(reloaded.isRTL, true);
    });

    test('addFood adds a food entry and persists it', () async {
      await store.addFood('مخلل', 'عشاء');
      expect(store.foodEntries.length, 1);
      expect(store.foodEntries.first.name, 'مخلل');
      expect(store.foodEntries.first.mealType, 'عشاء');

      // regain the same data from storage
      final reloaded = await SandyRepository().load();
      expect(reloaded!.foodEntries.length, 1);
      expect(reloaded.foodEntries.first.name, 'مخلل');
    });

    test('removeFood removes the entry', () async {
      await store.addFood('برجر', 'غداء');
      final id = store.foodEntries.first.id;
      final removed = await store.removeFood(id);
      expect(removed, isTrue);
      expect(store.foodEntries, isEmpty);
    });

    test('default retention window is 30 days', () {
      expect(store.data.dataRetentionDays, 30);
    });

    test('retention sweep deletes old records and keeps recent ones',
        () async {
      final now = DateTime.now();
      final oldDate =
          now.subtract(const Duration(days: 90)).toIso8601String();
      final recentDate = now.toIso8601String();
      SharedPreferences.setMockInitialValues({
        SandyRepository.mainKey: '{"vitals":['
            '{"id":"v-old","kind":"sugar","value":"200","createdAt":"$oldDate"},'
            '{"id":"v-recent","kind":"sugar","value":"110","createdAt":"$recentDate"}'
            '],"dataRetentionDays":30}',
      });

      final seeded = SandyStore(SandyRepository());
      await seeded.init();

      // The 90-day-old reading is auto-deleted; the fresh one survives.
      expect(seeded.vitals.any((v) => v.id == 'v-old'), isFalse);
      expect(seeded.vitals.any((v) => v.id == 'v-recent'), isTrue);
    });

    test('retention "keep forever" (0) deletes nothing', () async {
      final oldDate = DateTime.now()
          .subtract(const Duration(days: 400))
          .toIso8601String();
      SharedPreferences.setMockInitialValues({
        SandyRepository.mainKey: '{"vitals":['
            '{"id":"v-ancient","kind":"pulse","value":"70","createdAt":"$oldDate"}'
            '],"dataRetentionDays":0}',
      });

      final seeded = SandyStore(SandyRepository());
      await seeded.init();
      expect(seeded.vitals.any((v) => v.id == 'v-ancient'), isTrue);
    });
  });
}
