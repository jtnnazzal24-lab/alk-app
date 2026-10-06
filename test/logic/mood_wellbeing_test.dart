import 'package:flutter_test/flutter_test.dart';
import 'package:alk_flutter/logic/mood_wellbeing.dart';

void main() {
  test('sad mood gives calming exercise + uplifting music with a reason', () {
    final r = wellbeingForMood('حزين');
    expect(r.exerciseTitle, contains('تنفس'));
    expect(r.exerciseSteps, contains('شهيق'));
    expect(r.musicTitle, isNotEmpty);
    expect(r.musicReason, contains('لأنها'));
    expect(r.musicQuery, isNotEmpty);
  });
  test('tired mood gives energy routine', () {
    final r = wellbeingForMood('متعب');
    expect(r.exerciseSteps, contains('تنفس'));
  });
  test('calm mood gives maintenance routine', () {
    final r = wellbeingForMood('مرتاح');
    expect(r.tip, isNotEmpty);
  });
}
