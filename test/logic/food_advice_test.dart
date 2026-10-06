import 'package:flutter_test/flutter_test.dart';
import 'package:alk_flutter/logic/food_advice.dart';

void main() {
  group('Food knowledge base', () {
    test('detects sugar-raising foods', () {
      final concerns = analyzeFood('خبز أبيض');
      expect(concerns.any((c) => c.kind == FoodImpactKind.sugar), isTrue);
    });

    test('detects blood-pressure foods', () {
      final concerns = analyzeFood('مخلل');
      expect(concerns.any((c) => c.kind == FoodImpactKind.pressure), isTrue);
    });

    test('detects heart-health foods', () {
      final concerns = analyzeFood('دجاج مقلي');
      expect(concerns.any((c) => c.kind == FoodImpactKind.heart), isTrue);
    });

    test('fast food affects sugar, pressure and heart', () {
      final analysis = analyzeFoodEntry('برجر وسوبر ماركت');
      expect(analysis.affects(FoodImpactKind.sugar), isTrue);
      expect(analysis.affects(FoodImpactKind.pressure), isTrue);
      expect(analysis.affects(FoodImpactKind.heart), isTrue);
    });

    test('returns empty for unknown or empty names', () {
      expect(analyzeFood(''), isEmpty);
      expect(analyzeFood('تفاح'), isEmpty);
      expect(analyzeFood('سلطة خضار'), isEmpty);
    });

    test('provides advice text for every match', () {
      final concerns = analyzeFood('بيتزا');
      expect(concerns, isNotEmpty);
      for (final c in concerns) {
        expect(c.advice, isNotEmpty);
        expect(FoodImpactKind.label(c.kind), isNotEmpty);
      }
    });
  });
}