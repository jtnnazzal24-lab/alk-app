import 'package:flutter_test/flutter_test.dart';
import 'package:alk_flutter/logic/fat_exercise_advice.dart';
import 'package:alk_flutter/models/sandy_data.dart';

void main() {
  group('Chronic-condition advice', () {
    test('diabetes condition gives tailored advice + preferred exercises', () {
      final a = adviceForFoods(
        foods: ['زبدة', 'برجر'],
        conditionName: 'سكري النوع الثاني',
      );
      expect(a.conditionAdvice, contains('أنسولين'));
      expect(a.suggestions, isNotEmpty);
      // جميع الاقتراحات من قائمة التمارين المفضلة للسكري.
      final pool = preferredExercisesFor('سكري النوع الثاني');
      for (final s in a.suggestions) {
        expect(pool, contains(s.exercise));
      }
    });
    test('heart condition picks heart-safe exercises', () {
      final a = adviceForFoods(foods: ['سمن'], conditionName: 'ضعف قلب');
      final names = a.suggestions.map((s) => s.exercise).join('، ');
      expect(names.contains('ملاكمة'), isFalse);
      expect(names.contains('رفع الأثقال'), isFalse);
    });
    test('unknown condition falls back to general advice', () {
      final a = adviceForFoods(foods: ['برجر'], conditionName: 'زكام');
      expect(a.conditionAdvice, kGeneralFatAdvice);
    });
  });

  group('Overeating compensation levels', () {
    test('over level triggers after exceeding the 10% limit', () {
      final a = adviceForFoods(
        foods: ['زبدة', 'سمن', 'برجر', 'بيتزا', 'دجاج مقلي'],
        dailyCalories: 1800,
      );
      expect(a.level, FatAdviceLevel.over);
      expect(a.suggestions, isNotEmpty);
      final text = adviceSummaryText(a);
      expect(text, contains('أفرطت'));
      expect(text, contains('دقيقة'));
    });
    test('warn level near the limit', () {
      // 2200 daily → limit ≈ 24.4g; eat ~18.5g (زبدة 7 + برجر 6 + شاورما 5.5 تقريب)
      final a = adviceForFoods(foods: ['زبدة', 'برجر', 'شاورما']);
      expect(
        [FatAdviceLevel.warn, FatAdviceLevel.over].contains(a.level),
        isTrue,
      );
    });
    test('ok level for small amounts', () {
      final a = adviceForFoods(foods: ['خبز أبيض']);
      expect(a.level, FatAdviceLevel.ok);
      final text = adviceSummaryText(a);
      expect(text, contains('ضمن الحد'));
    });
    test('none level when no known fat foods', () {
      final a = adviceForFoods(foods: ['تفاح', 'سلطة خضار']);
      expect(a.level, FatAdviceLevel.none);
      expect(a.suggestions, isEmpty);
    });
  });

  group('Day-level advice', () {
    test('adviceForDay reads patient condition and foods', () {
      const data = SandyData(
        patient: PatientProfile(
          fullName: 'أبو أحمد',
          identityNumber: '123',
          conditionName: 'سكري',
        ),
        medications: [],
        medicationHistory: [],
        missedDoseEvents: [],
        vitals: [],
        journals: [],
        medicalAttachments: [],
        foodEntries: [
          FoodEntry(id: 'f1', name: 'برجر', mealType: 'غداء', createdAt: ''),
        ],
        quietMode: false,
        accessibility: AccessibilityPreferences(),
        trustedContactUrl: '',
        trustedContactName: '',
        travelMode: false,
        dataRetentionDays: 30,
      );
      final a = adviceForDay(data: data);
      expect(a.summary.totalGrams, closeTo(6.0, 0.001));
      expect(a.conditionAdvice, contains('أنسولين'));
    });
  });
}