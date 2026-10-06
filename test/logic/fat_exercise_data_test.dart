import 'package:flutter_test/flutter_test.dart';
import 'package:alk_flutter/logic/fat_exercise_data.dart';

void main() {
  group('Fat constants (from reference doc)', () {
    test('1 gram saturated fat = 9 calories', () {
      expect(FatConstants.saturatedFatCalPerGram, 9);
    });
    test('daily limit is 10 percent', () {
      expect(FatConstants.saturatedFatDailyLimitPercent, 10);
    });
    test('1 kg body fat ≈ 7700 calories', () {
      expect(FatConstants.kgBodyFatInCalories, 7700);
    });
  });

  group('Saturated fat food database', () {
    test('known high-fat foods return grams', () {
      expect(saturatedFatGramsFor('زبدة'), 7.0);
      expect(saturatedFatGramsFor('برجر'), 6.0);
      expect(saturatedFatGramsFor('دجاج مقلي'), 4.0);
    });
    test('unknown food returns 0', () {
      expect(saturatedFatGramsFor('تفاح'), 0.0);
      expect(saturatedFatGramsFor(''), 0.0);
    });
  });

  group('Total saturated fat calculation', () {
    test('sums grams and calories across foods', () {
      final s = totalSaturatedFatFromFoods(['زبدة', 'برجر']);
      // 7 + 6 = 13 grams → 117 calories
      expect(s.totalGrams, closeTo(13.0, 0.001));
      expect(s.totalCalories, closeTo(117.0, 0.001));
    });
    test('percentage of 10% limit when daily calories provided', () {
      // 2200 daily → limit = 220 cal = 24.4g; eat 12g = 108 cal → ~49%
      final s = totalSaturatedFatFromFoods(['زبدة', 'شاورما'],
          dailyCalories: 2200);
      expect(s.limitCalories, closeTo(220.0, 0.001));
      expect(s.percentageOfLimit, closeTo(108 / 220 * 100, 0.1));
      expect(s.exceedsLimit, isFalse);
    });
    test('flags exceed when over the 10% limit', () {
      final s = totalSaturatedFatFromFoods(
          ['زبدة', 'سمن', 'برجر', 'بيتزا', 'دجاج مقلي'],
          dailyCalories: 1800);
      // 7+7+6+4.5+4 = 28.5g → 256.5 cal; limit = 180
      expect(s.exceedsLimit, isTrue);
    });
  });

  group('Exercise burn compensation', () {
    test('burn time = calories / burn-rate (reference: 2.2 min per gram walking)', () {
      final minutes = exerciseTimeToBurnSatFat(
        saturatedFatGrams: 1,
        exercise: 'مشي عادي (5 كم/س)',
      );
      // 9 cal / 4.0 = 2.25 minutes per gram
      expect(minutes, closeTo(2.25, 0.01));
    });
    test('suggestions ordered fastest first, max 3', () {
      final list = suggestExercisesToBurnSatFat(saturatedFatGrams: 10);
      expect(list.length, 3);
      for (var i = 1; i < list.length; i++) {
        expect(list[i].minutes,
            greaterThanOrEqualTo(list[i - 1].minutes));
      }
    });
    test('lighter patient needs more minutes than 80 kg reference', () {
      final ref = exerciseTimeToBurnSatFat(
          saturatedFatGrams: 10, exercise: 'مشي سريع (6.5 كم/س)');
      final lighter = exerciseTimeToBurnSatFat(
          saturatedFatGrams: 10,
          exercise: 'مشي سريع (6.5 كم/س)',
          patientWeightKg: 60);
      expect(lighter, greaterThan(ref));
    });
    test('unknown exercise returns infinity', () {
      final minutes = exerciseTimeToBurnSatFat(
          saturatedFatGrams: 5, exercise: 'تمرين غير موجود');
      expect(minutes.isInfinite, isTrue);
    });
  });
}