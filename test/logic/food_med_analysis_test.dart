import 'package:flutter_test/flutter_test.dart';
import 'package:alk_flutter/logic/food_med_analysis.dart';
import 'package:alk_flutter/models/sandy_data.dart';

Medication med(String name, String time, String cat) {
  return Medication(id: 'm-$name', name: name, time: time, category: cat, taken: false, updatedAt: '', reminderEnabled: false);
}

FoodEntry food(String name, String meal) {
  return FoodEntry(id: 'f-$name-$meal', name: name, mealType: meal, createdAt: DateTime.now().toIso8601String());
}

void main() {
  test('breakfast conflict with diabetes med is high risk with portion + alternative', () {
    final m = [med('جلوكوفاج', '08:00', MedicationCategory.diabetes)];
    final a = analyzeMealWithMeds(mealType: FoodMealType.breakfast, foods: ['خبز أبيض'], morningMeds: m);
    expect(a.risk, MealRisk.high);
    expect(a.items.single.amountAdvice, isNotEmpty);
    expect(a.items.single.alternative, isNotEmpty);
  });
  test('lunch and dinner graded lower than breakfast', () {
    final m = [med('كونكور', '08:00', MedicationCategory.pressure)];
    final lunch = analyzeMealWithMeds(mealType: FoodMealType.lunch, foods: ['مخلل'], morningMeds: m);
    expect(lunch.risk, MealRisk.medium);
  });
  test('day map covers three meals', () {
    final m = [med('دواء', '08:00', MedicationCategory.general)];
    final map = analyzeDayMealsWithMeds(entries: [food('مخلل', FoodMealType.breakfast)], medications: m);
    expect(map.keys, containsAll([FoodMealType.breakfast, FoodMealType.lunch, FoodMealType.dinner]));
  });
}
