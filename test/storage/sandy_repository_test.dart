import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alk_flutter/models/sandy_data.dart';
import 'package:alk_flutter/storage/data_cipher.dart';
import 'package:alk_flutter/storage/sandy_repository.dart';

import '../helpers/platform_secrets.dart';

void main() {
  group('SandyRepository storage', () {
    setUpAll(disableSecureStorageInTests);
    tearDownAll(restoreSecureStorageAfterTests);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DataCipher.forceDisabled = true;
      DataCipher.instance.resetForTesting();
    });

    tearDown(() => DataCipher.instance.resetForTesting());

    test('data round-trips transparently (prefs fallback in unit env)',
        () async {
      // In a plain unit-test environment path_provider is unavailable, so the
      // repository transparently falls back to SharedPreferences and the user
      // keeps their data without knowing where it lives.
      final repo = SandyRepository();
      final data = SandyData.initial.copyWith(
        dataRetentionDays: 30,
        foodEntries: [
          FoodEntry(
            id: 'f1',
            name: 'تفاح',
            mealType: FoodMealType.breakfast,
            createdAt: DateTime.now().toIso8601String(),
          ),
        ],
      );

      await repo.save(data);
      final loaded = await repo.load();

      expect(loaded, isNotNull);
      expect(loaded!.dataRetentionDays, 30);
      expect(loaded.foodEntries.length, 1);
      expect(loaded.foodEntries.first.name, 'تفاح');
    });

    test('forcePrefsMode uses SharedPreferences and never touches the file',
        () async {
      SandyRepository.forcePrefsMode = true;
      final repo = SandyRepository();
      final data = SandyData.initial.copyWith(dataRetentionDays: 15);

      await repo.save(data);
      final loaded = await repo.load();

      expect(loaded, isNotNull);
      expect(loaded!.dataRetentionDays, 15);
      final file = await repo.debugDataFile();
      expect(file, isNotNull);
      expect(file!.existsSync(), isFalse);
      SandyRepository.forcePrefsMode = false;
    });

    test('clear removes the stored dataset in prefs fallback', () async {
      final repo = SandyRepository();
      await repo.save(SandyData.initial.copyWith(dataRetentionDays: 9));
      expect((await repo.load())!.dataRetentionDays, 9);
      await repo.clear();
      expect(await repo.load(), isNull);
    });

    // ── تشفير البيانات على الجهاز + حماية من فقدانها ────────────────────────
    group('تشفير البيانات وحماية الكتابة', () {
      setUp(() async {
        DataCipher.forceDisabled = false;
        DataCipher.instance.resetForTesting();
      });

      test('البيانات تُخزَّن مشفَّرة ولا تظهر بيانات المريض نصاً', () async {
        await DataCipher.instance.useKeyForTesting(List<int>.filled(32, 33));
        await SandyRepository().save(
          SandyData.initial.copyWith(dataRetentionDays: 12),
        );

        final raw = (await SharedPreferences.getInstance())
            .getString(SandyRepository.mainKey);

        expect(raw, isNotNull);
        expect(DataCipher.isEncrypted(raw!), isTrue);
        expect(raw.contains('dataRetentionDays'), isFalse);
      });

      test('البيانات المشفَّرة تُقرأ كاملة بالمفتاح نفسه', () async {
        await DataCipher.instance.useKeyForTesting(List<int>.filled(32, 44));
        await SandyRepository()
            .save(SandyData.initial.copyWith(dataRetentionDays: 17));

        final loaded = await SandyRepository().load();

        expect(loaded, isNotNull);
        expect(loaded!.dataRetentionDays, 17);
      });

      test('مفتاح مفقود: لا قراءة ولا كتابة فوق البيانات (لا فقدان)',
          () async {
        await DataCipher.instance.useKeyForTesting(List<int>.filled(32, 11));
        await SandyRepository()
            .save(SandyData.initial.copyWith(dataRetentionDays: 21));
        final original = (await SharedPreferences.getInstance())
            .getString(SandyRepository.mainKey);

        // كأن مفتاح Keystore فُقد بعد نقل الجهاز أو استعادة نسخة نظام.
        DataCipher.instance.resetForTesting();
        await DataCipher.instance.useKeyForTesting(List<int>.filled(32, 22));

        final repo = SandyRepository();
        expect(await repo.load(), isNull);
        expect(repo.lastLoadFailed, isTrue);

        // محاولة حفظ (كالتي يقوم بها التطبيق عند الإقلاع) يجب ألا تمس البيانات.
        await repo.save(SandyData.initial.copyWith(dataRetentionDays: 1));
        expect(
          (await SharedPreferences.getInstance())
              .getString(SandyRepository.mainKey),
          original,
        );
      });

      test('حذف كل البيانات يُلغي الحظر ويسمح ببداية جديدة', () async {
        await DataCipher.instance.useKeyForTesting(List<int>.filled(32, 55));
        await SandyRepository().save(SandyData.initial);
        DataCipher.instance.resetForTesting();
        await DataCipher.instance.useKeyForTesting(List<int>.filled(32, 66));

        final repo = SandyRepository();
        await repo.load();
        expect(repo.lastLoadFailed, isTrue);

        await repo.clear();
        expect(repo.lastLoadFailed, isFalse);
        await repo.save(SandyData.initial.copyWith(dataRetentionDays: 3));
        expect(
          (await SandyRepository().load())!.dataRetentionDays,
          3,
        );
      });
    });
  });
}
