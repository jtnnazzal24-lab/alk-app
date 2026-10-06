import '../models/sandy_data.dart';

/// Measurement-accuracy policy for automatic readings coming from external
/// devices (Bluetooth meters, Health Connect wearables).
///
/// Home chronic-disease meters always carry a normalized error margin:
///  - Blood-pressure monitors: ±5 mmHg (AAMI/IEC 80601-2-30 allows ±3, plus
///    patient technique error).
///  - Glucose meters: ±15% (ISO 15197:2013 for ≥100 mg/dL).
///  - Pulse meters: ±3 bpm.
///  - Pulse oximeters (SpO2): ±2% (ISO 80601-2-61).
///
/// The policy uses those margins plus physiologically plausible ranges to
/// classify every automatic reading:
///  - [VitalQuality.ok]        — inside the plausible range.
///  - [VitalQuality.check]     — plausible but suspicious (close to the range
///    limits, or far from the recent trend beyond the error margin).
///  - `rejected` (null result) — physiologically impossible; never stored.
abstract final class VitalQualityPolicy {
  /// Plausible ranges per vital kind. Pressure compares systolic/diastolic
  /// separately (the value string is "sys/dia").
  static const _ranges = <String, ({num min, num max})>{
    VitalKind.pressure: (min: 40, max: 260), // systolic bounds
    VitalKind.sugar: (min: 20, max: 600),
    VitalKind.pulse: (min: 30, max: 220),
    VitalKind.oxygen: (min: 50, max: 100),
  };

  static const _diastolicRange = (min: 20, max: 160);

  /// Relative deviation (vs the recent average) beyond which a reading is
  /// flagged for re-check. Chosen above the combined device+technique error.
  static const _deviationThreshold = {
    VitalKind.pressure: 0.25,
    VitalKind.sugar: 0.40,
    VitalKind.pulse: 0.40,
    VitalKind.oxygen: 0.15,
  };

  /// Human-readable accuracy note shown in the UI next to device readings.
  static String uncertaintyNote(String kind) {
    switch (kind) {
      case VitalKind.pressure:
        return 'دقة أجهزة الضغط المنزلية حوالي ±5 mmHg — قد تختلف القراءة عن جهاز العيادة.';
      case VitalKind.sugar:
        return 'دقة أجهزة السكر المنزلية حوالي ±15% وفق ISO 15197.';
      case VitalKind.pulse:
        return 'دقة أجهزة النبض حوالي ±3 نبضة في الدقيقة.';
      case VitalKind.oxygen:
        return 'دقة مقياس الأكسجين حوالي ±2% — الحركة والتدخين تؤثر على القراءة.';
      default:
        return '';
    }
  }

  /// Extracts the primary numeric value from a stored reading string.
  /// For pressure ("120/80") this is the systolic value.
  static double? primaryValue(String kind, String value) {
    final numbers = RegExp(r'\d+(?:\.\d+)?')
        .allMatches(value)
        .map((m) => double.tryParse(m.group(0)!))
        .whereType<double>()
        .toList();
    if (numbers.isEmpty) return null;
    if (kind == VitalKind.pressure) return numbers.first;
    return numbers.first;
  }

  /// Assesses an automatic reading.
  ///
  /// [recentValues] are the primary values of recent same-kind readings
  /// (oldest → newest, may be empty). Returns null when the reading is
  /// physiologically impossible and must be discarded.
  static VitalAssessment? assess({
    required String kind,
    required String value,
    List<double> recentValues = const [],
  }) {
    final primary = primaryValue(kind, value);
    if (primary == null) return null;

    final range = _ranges[kind];
    if (range != null &&
        (primary < range.min || primary > range.max)) {
      return null; // physiologically implausible — reject.
    }

    if (kind == VitalKind.pressure) {
      final dia = _diastolicOf(value);
      if (dia == null || dia < _diastolicRange.min || dia > _diastolicRange.max) {
        return null;
      }
      if (dia >= primary) return null; // diastolic ≥ systolic is impossible.
    }

    final reasons = <String>[];

    // Close to the plausible boundary → suggest a re-check.
    if (range != null) {
      final span = (range.max - range.min).toDouble();
      final margin = span * 0.05;
      if (primary - range.min < margin || range.max - primary < margin) {
        reasons.add('القراءة قريبة من الحدود الحرجة');
      }
    }

    // Far from the recent trend (beyond the error margin) → re-check.
    if (recentValues.length >= 2) {
      final avg =
          recentValues.reduce((a, b) => a + b) / recentValues.length;
      final threshold = _deviationThreshold[kind];
      if (threshold != null && avg > 0) {
        final deviation = (primary - avg).abs() / avg;
        if (deviation > threshold) {
          reasons.add(
              'القراءة منحرفة عن متوسط قياساتك الأخيرة (${avg.round()})');
        }
      }
    }

    if (reasons.isEmpty) {
      return const VitalAssessment(quality: VitalQuality.ok);
    }
    return VitalAssessment(
      quality: VitalQuality.check,
      note: '${reasons.join('، ')}. ${uncertaintyNote(kind)}',
    );
  }

  static double? _diastolicOf(String value) {
    final parts = value.split('/');
    if (parts.length != 2) return null;
    return double.tryParse(parts[1].trim());
  }
}

/// Result of [VitalQualityPolicy.assess].
class VitalAssessment {
  final String quality; // VitalQuality.ok | VitalQuality.check
  final String? note;

  const VitalAssessment({required this.quality, this.note});
}