/// Data models for ALK.
///
/// CRITICAL: the JSON field names in this file MUST stay identical to the
/// React Native app's schema (lib/sandy-store.tsx). The same JSON blob
/// (AsyncStorage key `sandy-health-local-v1`) is read/written by both apps so
/// that migrating from the RN build to this Flutter build never loses data.
library;

import '../l10n/app_strings.dart';

/// reminderStatus strings — must match the RN values exactly.
class ReminderStatus {
  static const active = 'active';
  static const quiet = 'quiet';
  static const unsupported = 'unsupported';
  static const denied = 'denied';
  static const disabled = 'disabled';
}

class MedicationCategory {
  static const general = 'عام';
  static const heart = 'قلب';
  static const diabetes = 'سكري';
  static const pressure = 'ضغط';

  /// All categories shown in the add-medication form.
  static const all = [general, diabetes, pressure, heart];
}

/// Medication physical forms shown in the add-medication form.
class MedicationForm {
  static const tablet = 'حبة';
  static const capsule = 'كبسولة';
  static const liquid = 'سائل';
  static const syrup = 'شراب';
  static const injection = 'إبرة';
  static const patch = 'لصقة';
  static const drops = 'قطرة';

  static const all = [tablet, capsule, liquid, syrup, injection, patch, drops];
}

class VitalKind {
  static const pressure = 'pressure';
  static const sugar = 'sugar';
  static const pulse = 'pulse';
  static const oxygen = 'spo2';

  static const all = [pressure, sugar, pulse, oxygen];
}

/// Measurement quality flags for automatic (device) readings. Stored on the
/// reading itself so the UI can warn about values that deserve a re-check.
class VitalQuality {
  static const ok = 'ok';
  static const check = 'check';

  /// Arabic label for the quality flag.
  static String label(String quality) {
    switch (quality) {
      case check:
        return 'تحتاج تدقيقاً'.tr;
      case ok:
        return 'سليمة'.tr;
      default:
        return '';
    }
  }
}

/// Where a vital reading originated from.
class VitalSource {
  static const manual = 'manual';
  static const healthConnect = 'health_connect';
  static const bluetooth = 'bluetooth';

  /// Arabic label for display.
  static String label(String source) {
    switch (source) {
      case healthConnect:
        return 'Health Connect';
      case bluetooth:
        return 'بلوتوث'.tr;
      case manual:
      default:
        return 'يدوي'.tr;
    }
  }
}

class AttachmentKind {
  static const prescription = 'prescription';
  static const lab = 'lab';
}

/// A person to call in an emergency (family member, caregiver...).
class EmergencyContact {
  final String id;
  final String name;
  final String phone;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone};
}

class DoseEventType {
  static const taken = 'taken';
  static const missed = 'missed';
  static const asNeeded = 'as-needed';
}

class MedicationChangeAction {
  static const added = 'added';
  static const updated = 'updated';
  static const removed = 'removed';
}

class Medication {
  final String id;
  final String name;
  final String? imageUri;
  final String time;
  final String category;
  final String? dose;
  final String? form;
  final String? startDate;
  final String? endDate;
  final List<String> doseTimes;
  final bool taken;
  final String updatedAt;
  final bool reminderEnabled;
  final String? reminderIdentifier;
  final List<String> reminderIdentifiers;
  final String reminderStatus;
  final num? stockRemaining;
  final num? stockThreshold;
  final bool asNeeded;

  /// How often the dose repeats, in days (1 = every day, 2 = every other
  /// day, 3 = every third day, ...).
  final int intervalDays;

  const Medication({
    required this.id,
    required this.name,
    this.imageUri,
    required this.time,
    required this.category,
    this.dose,
    this.form,
    this.startDate,
    this.endDate,
    this.doseTimes = const [],
    required this.taken,
    required this.updatedAt,
    required this.reminderEnabled,
    this.reminderIdentifier,
    this.reminderIdentifiers = const [],
    this.reminderStatus = ReminderStatus.disabled,
    this.stockRemaining,
    this.stockThreshold,
    this.asNeeded = false,
    this.intervalDays = 1,
  });

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      imageUri: json['imageUri'] as String?,
      time: (json['time'] as String?) ?? '00:00',
      category: (json['category'] as String?) ?? MedicationCategory.general,
      dose: json['dose'] as String?,
      form: json['form'] as String?,
      startDate: json['startDate'] as String?,
      endDate: json['endDate'] as String?,
      doseTimes: ((json['doseTimes'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
      taken: (json['taken'] as bool?) ?? false,
      updatedAt: (json['updatedAt'] as String?) ?? '',
      reminderEnabled: (json['reminderEnabled'] as bool?) ?? false,
      reminderIdentifier: json['reminderIdentifier'] as String?,
      reminderIdentifiers:
          ((json['reminderIdentifiers'] as List<dynamic>?) ?? const [])
              .whereType<String>()
              .toList(growable: false),
      reminderStatus:
          (json['reminderStatus'] as String?) ?? ReminderStatus.disabled,
      stockRemaining: _numOrNull(json['stockRemaining']),
      stockThreshold: _numOrNull(json['stockThreshold']),
      asNeeded: (json['asNeeded'] as bool?) ?? false,
      intervalDays:
          ((json['intervalDays'] as num?) ?? 1).toInt().clamp(1, 365),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (imageUri != null) 'imageUri': imageUri,
        'time': time,
        'category': category,
        if (dose != null) 'dose': dose,
        if (form != null) 'form': form,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        'doseTimes': doseTimes,
        'taken': taken,
        'updatedAt': updatedAt,
        'reminderEnabled': reminderEnabled,
        if (reminderIdentifier != null) 'reminderIdentifier': reminderIdentifier,
        'reminderIdentifiers': reminderIdentifiers,
        'reminderStatus': reminderStatus,
        if (stockRemaining != null) 'stockRemaining': stockRemaining,
        if (stockThreshold != null) 'stockThreshold': stockThreshold,
        'asNeeded': asNeeded,
        'intervalDays': intervalDays,
      };

  Medication copyWith({
    String? name,
    String? imageUri,
    bool clearImageUri = false,
    String? time,
    String? category,
    String? dose,
    String? form,
    String? startDate,
    String? endDate,
    List<String>? doseTimes,
    bool? taken,
    String? updatedAt,
    bool? reminderEnabled,
    String? reminderIdentifier,
    bool clearReminderIdentifier = false,
    List<String>? reminderIdentifiers,
    String? reminderStatus,
    num? stockRemaining,
    num? stockThreshold,
    bool? asNeeded,
    int? intervalDays,
  }) {
    return Medication(
      id: id,
      name: name ?? this.name,
      imageUri: clearImageUri ? null : (imageUri ?? this.imageUri),
      time: time ?? this.time,
      category: category ?? this.category,
      dose: dose ?? this.dose,
      form: form ?? this.form,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      doseTimes: doseTimes ?? this.doseTimes,
      taken: taken ?? this.taken,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderIdentifier: clearReminderIdentifier
          ? null
          : (reminderIdentifier ?? this.reminderIdentifier),
      reminderIdentifiers: reminderIdentifiers ?? this.reminderIdentifiers,
      reminderStatus: reminderStatus ?? this.reminderStatus,
      stockRemaining: stockRemaining ?? this.stockRemaining,
      stockThreshold: stockThreshold ?? this.stockThreshold,
      asNeeded: asNeeded ?? this.asNeeded,
      intervalDays: intervalDays ?? this.intervalDays,
    );
  }
}

class MedicationChange {
  final String id;
  final String medicationId;
  final String medicationName;
  final String action; // added | updated | removed
  final String summary;
  final String createdAt;

  const MedicationChange({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.action,
    required this.summary,
    required this.createdAt,
  });

  factory MedicationChange.fromJson(Map<String, dynamic> json) {
    return MedicationChange(
      id: (json['id'] as String?) ?? '',
      medicationId: (json['medicationId'] as String?) ?? '',
      medicationName: (json['medicationName'] as String?) ?? '',
      action: (json['action'] as String?) ?? MedicationChangeAction.updated,
      summary: (json['summary'] as String?) ?? '',
      createdAt: (json['createdAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicationId': medicationId,
        'medicationName': medicationName,
        'action': action,
        'summary': summary,
        'createdAt': createdAt,
      };
}

class PatientProfile {
  final String fullName;
  final String identityNumber;
  final String conditionName;
  final bool lockEnabled;
  final String doctorNotes;
  final String nextReviewDate;
  final String updatedAt;

  /// Treating doctor's WhatsApp phone number (international format, digits
  /// only, no `+` — e.g. `972592055302`). Used to send health reports.
  final String doctorPhone;

  /// Treating doctor's email address. Used to send health reports.
  final String doctorEmail;

  /// Blood group (e.g. `A+`, `O-`) — read from the emergency card.
  final String bloodType;

  /// Known allergies / intolerances, free text (comma separated).
  final String allergies;

  const PatientProfile({
    required this.fullName,
    required this.identityNumber,
    required this.conditionName,
    this.lockEnabled = false,
    this.doctorNotes = '',
    this.nextReviewDate = '',
    this.updatedAt = '',
    this.doctorPhone = '',
    this.doctorEmail = '',
    this.bloodType = '',
    this.allergies = '',
  });

  static const PatientProfile initial = PatientProfile(
    fullName: '',
    identityNumber: '',
    conditionName: '',
  );

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    return PatientProfile(
      fullName: (json['fullName'] as String?) ?? '',
      identityNumber: (json['identityNumber'] as String?) ?? '',
      conditionName: (json['conditionName'] as String?) ?? '',
      lockEnabled: (json['lockEnabled'] as bool?) ?? false,
      doctorNotes: (json['doctorNotes'] as String?) ?? '',
      nextReviewDate: (json['nextReviewDate'] as String?) ?? '',
      updatedAt: (json['updatedAt'] as String?) ?? '',
      doctorPhone: (json['doctorPhone'] as String?) ?? '',
      doctorEmail: (json['doctorEmail'] as String?) ?? '',
      bloodType: (json['bloodType'] as String?) ?? '',
      allergies: (json['allergies'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'identityNumber': identityNumber,
        'conditionName': conditionName,
        'lockEnabled': lockEnabled,
        'doctorNotes': doctorNotes,
        'nextReviewDate': nextReviewDate,
        'updatedAt': updatedAt,
        'doctorPhone': doctorPhone,
        'doctorEmail': doctorEmail,
        'bloodType': bloodType,
        'allergies': allergies,
      };

  PatientProfile copyWith({
    String? fullName,
    String? identityNumber,
    String? conditionName,
    bool? lockEnabled,
    String? doctorNotes,
    String? nextReviewDate,
    String? updatedAt,
    String? doctorPhone,
    String? doctorEmail,
    String? bloodType,
    String? allergies,
  }) {
    return PatientProfile(
      fullName: fullName ?? this.fullName,
      identityNumber: identityNumber ?? this.identityNumber,
      conditionName: conditionName ?? this.conditionName,
      lockEnabled: lockEnabled ?? this.lockEnabled,
      doctorNotes: doctorNotes ?? this.doctorNotes,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      updatedAt: updatedAt ?? this.updatedAt,
      doctorPhone: doctorPhone ?? this.doctorPhone,
      doctorEmail: doctorEmail ?? this.doctorEmail,
      bloodType: bloodType ?? this.bloodType,
      allergies: allergies ?? this.allergies,
    );
  }
}

class MedicationDoseEvent {
  final String id;
  final String medicationId;
  final String medicationName;
  final String type; // taken | missed | as-needed
  final String? reason;
  final String createdAt;

  /// الحالة المزاجية بعد الجرعة (نظام خلية النحل): يُسأل المستخدم بعد
  /// 30-60 دقيقة من تأكيد التناول. اختياري وغير مخزَّن إلا عند الإجابة،
  /// وبأسماء قيم عربية موحّدة مع مفاتيح المزاج في القاموس
  /// (ممتاز/جيد/لا بأس/تعبان/متوتر).
  final String? postDoseMood;

  const MedicationDoseEvent({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.type,
    this.reason,
    this.postDoseMood,
    required this.createdAt,
  });

  factory MedicationDoseEvent.fromJson(Map<String, dynamic> json) {
    return MedicationDoseEvent(
      id: (json['id'] as String?) ?? '',
      medicationId: (json['medicationId'] as String?) ?? '',
      medicationName: (json['medicationName'] as String?) ?? '',
      type: (json['type'] as String?) ?? DoseEventType.missed,
      reason: json['reason'] as String?,
      postDoseMood: json['postDoseMood'] as String?,
      createdAt: (json['createdAt'] as String?) ?? '',
    );
  }

  /// نسخة معدَّلة (لتحديث المزاج بعد الجرعة دون تغيير بقية الحقول).
  MedicationDoseEvent copyWith({
    String? type,
    String? reason,
    String? postDoseMood,
  }) {
    return MedicationDoseEvent(
      id: id,
      medicationId: medicationId,
      medicationName: medicationName,
      type: type ?? this.type,
      reason: reason ?? this.reason,
      postDoseMood: postDoseMood ?? this.postDoseMood,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicationId': medicationId,
        'medicationName': medicationName,
        'type': type,
        if (reason != null) 'reason': reason,
        if (postDoseMood != null) 'postDoseMood': postDoseMood,
        'createdAt': createdAt,
      };
}

class AccessibilityPreferences {
  final String fontScale; // "default" | "large"
  final bool highContrast;

  const AccessibilityPreferences({
    this.fontScale = 'default',
    this.highContrast = false,
  });

  factory AccessibilityPreferences.fromJson(Map<String, dynamic> json) {
    return AccessibilityPreferences(
      fontScale: (json['fontScale'] as String?) ?? 'default',
      highContrast: (json['highContrast'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'fontScale': fontScale,
        'highContrast': highContrast,
      };

  bool get isLarge => fontScale == 'large';
}

class VitalReading {
  final String id;
  final String kind; // pressure | sugar | pulse | spo2
  final String value;
  final String createdAt;
  final String source; // manual | health_connect | bluetooth
  final String? deviceName;

  /// Quality flag assigned by the automatic-measurement pipeline
  /// (see VitalQualityPolicy). Empty for manual entries.
  final String quality;

  const VitalReading({
    required this.id,
    required this.kind,
    required this.value,
    required this.createdAt,
    this.source = VitalSource.manual,
    this.deviceName,
    this.quality = '',
  });

  factory VitalReading.fromJson(Map<String, dynamic> json) {
    return VitalReading(
      id: (json['id'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? VitalKind.pulse,
      value: (json['value'] as String?) ?? '',
      createdAt: (json['createdAt'] as String?) ?? '',
      source: (json['source'] as String?) ?? VitalSource.manual,
      deviceName: json['deviceName'] as String?,
      quality: (json['quality'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'value': value,
        'createdAt': createdAt,
        'source': source,
        if (deviceName != null) 'deviceName': deviceName,
        if (quality.isNotEmpty) 'quality': quality,
      };

  /// Human-friendly value for list tiles and reports.
  String get displayValue => value;

  VitalReading copyWith({String? source, String? deviceName, String? quality}) {
    return VitalReading(
      id: id,
      kind: kind,
      value: value,
      createdAt: createdAt,
      source: source ?? this.source,
      deviceName: deviceName ?? this.deviceName,
      quality: quality ?? this.quality,
    );
  }
}

class JournalEntry {
  final String id;
  final String mood;
  final String note;
  final String createdAt;

  const JournalEntry({
    required this.id,
    required this.mood,
    required this.note,
    required this.createdAt,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      id: (json['id'] as String?) ?? '',
      mood: (json['mood'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      createdAt: (json['createdAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mood': mood,
        'note': note,
        'createdAt': createdAt,
      };
}

class MedicalAttachment {
  final String id;
  final String kind; // prescription | lab
  final String uri;
  final String createdAt;

  const MedicalAttachment({
    required this.id,
    required this.kind,
    required this.uri,
    required this.createdAt,
  });

  factory MedicalAttachment.fromJson(Map<String, dynamic> json) {
    return MedicalAttachment(
      id: (json['id'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? AttachmentKind.prescription,
      uri: (json['uri'] as String?) ?? '',
      createdAt: (json['createdAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'uri': uri,
        'createdAt': createdAt,
      };
}

/// Meal-type labels used by the nutrition tracker.
class FoodMealType {
  static const breakfast = 'فطور';
  static const lunch = 'غداء';
  static const dinner = 'عشاء';
  static const snack = 'وجبة خفيفة';

  static const all = [breakfast, lunch, dinner, snack];
}

/// A single food/drink the patient logged in the nutrition tracker.
///
/// The impact of the food on sugar/pressure/heart is derived at display time
/// from the built-in food knowledge base (see `logic/food_advice.dart`), so
/// the stored record stays simple and schema-stable.
class FoodEntry {
  final String id;
  final String name;
  final String mealType; // فطور | غداء | عشاء | وجبة خفيفة
  final String createdAt;

  const FoodEntry({
    required this.id,
    required this.name,
    required this.mealType,
    required this.createdAt,
  });

  factory FoodEntry.fromJson(Map<String, dynamic> json) {
    return FoodEntry(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      mealType:
          (json['mealType'] as String?) ?? FoodMealType.breakfast,
      createdAt: (json['createdAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mealType': mealType,
        'createdAt': createdAt,
      };

  FoodEntry copyWith({String? name, String? mealType}) {
    return FoodEntry(
      id: id,
      name: name ?? this.name,
      mealType: mealType ?? this.mealType,
      createdAt: createdAt,
    );
  }
}

/// The complete local dataset — mirrors `SandyData` in the RN app exactly.
class SandyData {
  final PatientProfile patient;
  final List<Medication> medications;
  final List<MedicationChange> medicationHistory;
  final List<MedicationDoseEvent> missedDoseEvents;
  final List<VitalReading> vitals;
  final List<JournalEntry> journals;
  final List<MedicalAttachment> medicalAttachments;
  final List<FoodEntry> foodEntries;
  final bool quietMode;
  final AccessibilityPreferences accessibility;
  final String trustedContactUrl;
  final String trustedContactName;
  final bool travelMode;
  final int dataRetentionDays; // 0 means keep forever; default 30

  /// آخر مزاج سجّله المستخدم — يُظهره تطبيق العافية حتى لو فُتح منفصلاً.
  final String lastMood;

  /// Emergency contacts (family/caregivers) callable by voice command.
  final List<EmergencyContact> emergencyContacts;

  /// Ambulance hotline (editable; region-dependent).
  final String ambulanceNumber;

  const SandyData({
    required this.patient,
    required this.medications,
    required this.medicationHistory,
    required this.missedDoseEvents,
    required this.vitals,
    required this.journals,
    required this.medicalAttachments,
    required this.foodEntries,
    required this.quietMode,
    required this.accessibility,
    required this.trustedContactUrl,
    required this.trustedContactName,
    required this.travelMode,
    required this.dataRetentionDays,
    this.lastMood = '',
    this.emergencyContacts = const [],
    this.ambulanceNumber = '101',
  });

  static const SandyData initial = SandyData(
    patient: PatientProfile(
      fullName: '',
      identityNumber: '',
      conditionName: '',
    ),
    medications: [],
    medicationHistory: [],
    missedDoseEvents: [],
    vitals: [],
    journals: [],
    medicalAttachments: [],
    foodEntries: [],
    quietMode: false,
    accessibility: AccessibilityPreferences(),
    trustedContactUrl: '',
    trustedContactName: '',
    travelMode: false,
    dataRetentionDays: 30,
  );

  /// Tolerant parse mirroring the RN restore path (missing fields fall back
  /// to defaults; medications get defensive normalizing of new fields).
  factory SandyData.fromJson(Map<String, dynamic> json) {
    return SandyData(
      patient: json['patient'] is Map<String, dynamic>
          ? PatientProfile.fromJson(json['patient'] as Map<String, dynamic>)
          : SandyData.initial.patient,
      medications: ((json['medications'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Medication.fromJson)
          .toList(),
      medicationHistory:
          ((json['medicationHistory'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(MedicationChange.fromJson)
              .toList(),
      missedDoseEvents:
          ((json['missedDoseEvents'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(MedicationDoseEvent.fromJson)
              .toList(),
      vitals: ((json['vitals'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VitalReading.fromJson)
          .toList(),
      journals: ((json['journals'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(JournalEntry.fromJson)
          .toList(),
      medicalAttachments:
          ((json['medicalAttachments'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(MedicalAttachment.fromJson)
              .toList(),
      foodEntries: ((json['foodEntries'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FoodEntry.fromJson)
          .toList(),
      quietMode: (json['quietMode'] as bool?) ?? false,
      accessibility: json['accessibility'] is Map<String, dynamic>
          ? AccessibilityPreferences.fromJson(
              json['accessibility'] as Map<String, dynamic>)
          : SandyData.initial.accessibility,
      trustedContactUrl: (json['trustedContactUrl'] as String?) ?? '',
      trustedContactName: (json['trustedContactName'] as String?) ?? '',
      travelMode: (json['travelMode'] as bool?) ?? false,
      dataRetentionDays: (json['dataRetentionDays'] as num?)?.toInt() ?? 30,
      lastMood: (json['lastMood'] as String?) ?? '',
      emergencyContacts:
          ((json['emergencyContacts'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(EmergencyContact.fromJson)
              .toList(),
      ambulanceNumber:
          (json['ambulanceNumber'] as String?)?.isNotEmpty == true
              ? json['ambulanceNumber'] as String
              : '101',
    );
  }

  Map<String, dynamic> toJson() => {
        'patient': patient.toJson(),
        'medications': medications.map((m) => m.toJson()).toList(),
        'medicationHistory': medicationHistory.map((m) => m.toJson()).toList(),
        'missedDoseEvents': missedDoseEvents.map((m) => m.toJson()).toList(),
        'vitals': vitals.map((v) => v.toJson()).toList(),
        'journals': journals.map((j) => j.toJson()).toList(),
        'medicalAttachments':
            medicalAttachments.map((m) => m.toJson()).toList(),
        'foodEntries': foodEntries.map((f) => f.toJson()).toList(),
        'quietMode': quietMode,
        'accessibility': accessibility.toJson(),
        'trustedContactUrl': trustedContactUrl,
        'trustedContactName': trustedContactName,
        'travelMode': travelMode,
        'dataRetentionDays': dataRetentionDays,
        'lastMood': lastMood,
        'emergencyContacts': emergencyContacts.map((c) => c.toJson()).toList(),
        'ambulanceNumber': ambulanceNumber,
      };

  SandyData copyWith({
    PatientProfile? patient,
    List<Medication>? medications,
    List<MedicationChange>? medicationHistory,
    List<MedicationDoseEvent>? missedDoseEvents,
    List<VitalReading>? vitals,
    List<JournalEntry>? journals,
    List<MedicalAttachment>? medicalAttachments,
    List<FoodEntry>? foodEntries,
    bool? quietMode,
    AccessibilityPreferences? accessibility,
    String? trustedContactUrl,
    String? trustedContactName,
    bool? travelMode,
    int? dataRetentionDays,
    String? lastMood,
    List<EmergencyContact>? emergencyContacts,
    String? ambulanceNumber,
  }) {
    return SandyData(
      patient: patient ?? this.patient,
      medications: medications ?? this.medications,
      medicationHistory: medicationHistory ?? this.medicationHistory,
      missedDoseEvents: missedDoseEvents ?? this.missedDoseEvents,
      vitals: vitals ?? this.vitals,
      journals: journals ?? this.journals,
      medicalAttachments: medicalAttachments ?? this.medicalAttachments,
      foodEntries: foodEntries ?? this.foodEntries,
      quietMode: quietMode ?? this.quietMode,
      accessibility: accessibility ?? this.accessibility,
      trustedContactUrl: trustedContactUrl ?? this.trustedContactUrl,
      trustedContactName: trustedContactName ?? this.trustedContactName,
      travelMode: travelMode ?? this.travelMode,
      dataRetentionDays: dataRetentionDays ?? this.dataRetentionDays,
      lastMood: lastMood ?? this.lastMood,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
      ambulanceNumber: ambulanceNumber ?? this.ambulanceNumber,
    );
  }
}

num? _numOrNull(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}



