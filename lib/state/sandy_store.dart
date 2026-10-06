import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';
import '../logic/bee_cell_engine.dart'
    show DoctorMoodAlert, detectRepeatedPostDoseMood;
import '../logic/medication_times.dart';
import '../logic/vital_advice.dart';
import '../models/sandy_data.dart';
import '../services/notification_service.dart';
import '../services/voice_service.dart';
import '../storage/legacy_migrator.dart';
import '../storage/sandy_repository.dart';

class ReminderOutcome {
  final String status; // active | quiet | unsupported | denied | disabled
  final String? identifier;

  /// كل معرّفات الإشعارات المُجدولة لهذه الجرعة (تذكير الموعد + تذكير «اقترب
  /// موعد دوائك») لتُلغى معاً عند التعديل أو الحذف أو تشغيل الوضع الهادئ.
  final List<String> identifiers;

  const ReminderOutcome({
    required this.status,
    this.identifier,
    this.identifiers = const [],
  });

  bool get isActive => status == ReminderStatus.active;
}

/// Port of the RN `SandyProvider` store (lib/sandy-store.tsx) to a
/// ChangeNotifier. Persists the exact same JSON schema under the same key,
/// so data written here round-trips with the legacy app and its backups.
class SandyStore extends ChangeNotifier {
  SandyStore(this._repository);

  final SandyRepository _repository;

  SandyData _data = SandyData.initial;
  bool _loaded = false;
  String _languageTag = 'ar';

  /// true عندما يكون ملف البيانات على الجهاز مشفَّراً ولا يمكن فكّه (مفتاح
  /// التخزين الآمن مفقود): يُنبَّه المستخدم ويمنع التطبيق الكتابة فوق الملف
  /// حتى لا تضيع بياناته (انظر SandyRepository.lastLoadFailed).
  bool dataUnreadable = false;

  /// لغة الواجهة عند الإقلاع — يضبطها `main` من لغة الهاتف عندما تكون غير
  /// العربية، فتُقرأ الترجمة المخزَّنة على الجهاز (أو تُجهَّز مرة واحدة) وتُعرض
  /// مفردات التطبيق بلغة الهاتف. القيمة null (الافتراضي، وكذلك في الاختبارات)
  /// تعني بقاء العربية لغةَ المصدر والعرض.
  String? startupLanguageTag;

  String? _migrationNote;

  SandyData get data => _data;
  bool get loaded => _loaded;
  String get languageTag => _languageTag;
  bool get isRTL => _languageTag.toLowerCase().startsWith('ar');
  String? get migrationNote => _migrationNote;

  PatientProfile get patient => _data.patient;
  List<Medication> get medications => _data.medications;
  List<VitalReading> get vitals => _data.vitals;
  List<JournalEntry> get journals => _data.journals;
  String get lastMood => _data.lastMood;
  List<MedicationDoseEvent> get missedDoseEvents => _data.missedDoseEvents;
  List<MedicationChange> get medicationHistory => _data.medicationHistory;
  List<MedicalAttachment> get medicalAttachments => _data.medicalAttachments;
  List<FoodEntry> get foodEntries => _data.foodEntries;

  /// Emergency contacts and ambulance hotline (see EmergencyScreen).
  List<EmergencyContact> get emergencyContacts => _data.emergencyContacts;
  String get ambulanceNumber => _data.ambulanceNumber;

  String _createId(String prefix) {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rnd =
        (DateTime.now().microsecondsSinceEpoch % 2176782336).toRadixString(36);
    return '$prefix-$ts$rnd';
  }

  /// Loads persisted data, runs the one-time legacy migration and applies
  /// the retention policy. Mirrors the RN restore effect.
  Future<void> init() async {
    try {
      final migrator = LegacyMigrator(_repository);
      final result = await migrator.migrateIfNeeded();
      if (result.performed && result.hasContent) {
        _migrationNote =
            'legacy-imported:${result.medications}meds,${result.vitals}vitals';
      }

      final stored = await _repository.load();
      if (stored != null) {
        _data = stored;
      } else {
        // ملف مشفَّر بلا مفتاح ⇒ لا كتابة (حماية من فقدان البيانات).
        dataUnreadable = _repository.lastLoadFailed;
        await _repository.save(_data);
      }

      await VoiceService.instance.loadPreferences();
      // التطبيق يدعم العربية فقط كواجهة رئيسية. أي قيمة أخرى (لغة الهاتف أو
      // override محفوظ في التخزين) تُهمَل، لأن القاموس الداخلي يُستخدم فقط
      // لترجمة النصوص دون تغيير لغة التطبيق نفسها.
      _languageTag = 'ar';
      // Apply the retention/auto-delete policy on every launch so data older
      // than the configured window is purged from the file as well.
      await _applyRetention(commit: true);
    } catch (_) {
      // A storage/init failure must never leave the app stuck on a loading
      // spinner or crash at startup. Fall back to the in-memory (empty)
      // dataset; the user can still use the app.
      _languageTag = 'ar';
    } finally {
      _loaded = true;
      notifyListeners();
    }
    // معالجة ذاتية بعد جهوز البيانات: إعادة جدولة تذكيرات الأدوية المُفعَّلة
    // (بلا أي نافذة نظام). أي فشل هنا — قنوات إشعارات غائبة في الاختبارات مثلاً
    // — لا يُسقط الإقلاع؛ تُعاد المحاولة في التشغيل التالي.
    try {
      await rescheduleAllReminders();
    } catch (_) {}
  }

  void setLanguageTag(String tag) {
    final normalized = tag.toLowerCase().startsWith('ar') ? 'ar' : 'ar';
    _languageTag = normalized;
    _repository.saveLocaleOverride(normalized).ignore();
    notifyListeners();
  }

  void setLanguageTagNoNotify(String tag) {
    _languageTag = 'ar';
  }

  /// Requests a UI rebuild after background work (e.g. auto-translation)
  /// completes. Safe to call from outside the store.
  void requestRebuild() => notifyListeners();

  /// Applies the retention (auto-delete) policy.
  ///
  /// Only time-series "variable" data is purged when older than the configured
  /// window: vitals, journals, medication history, missed-dose events and food
  /// entries. Static/foundational data (patient profile, current medications,
  /// trusted contact, accessibility, retention setting) is never deleted.
  ///
  /// When [commit] is true the cleaned dataset is written back to the
  /// dedicated storage file. Returns the number of records removed.
  Future<int> _applyRetention({bool commit = false}) async {
    if (_data.dataRetentionDays <= 0) return 0;
    final now = DateTime.now();
    final threshold =
        now.millisecondsSinceEpoch - _data.dataRetentionDays * 86400000;
    bool isOld(String dateStr) {
      final t = DateTime.tryParse(dateStr)?.millisecondsSinceEpoch;
      return t != null && t < threshold;
    }

    final nextVitals = _data.vitals.where((v) => !isOld(v.createdAt)).toList();
    final nextJournals =
        _data.journals.where((j) => !isOld(j.createdAt)).toList();
    final nextHistory =
        _data.medicationHistory.where((h) => !isOld(h.createdAt)).toList();
    final nextEvents =
        _data.missedDoseEvents.where((e) => !isOld(e.createdAt)).toList();
    final nextFood =
        _data.foodEntries.where((f) => !isOld(f.createdAt)).toList();

    final removed = (_data.vitals.length - nextVitals.length) +
        (_data.journals.length - nextJournals.length) +
        (_data.medicationHistory.length - nextHistory.length) +
        (_data.missedDoseEvents.length - nextEvents.length) +
        (_data.foodEntries.length - nextFood.length);

    if (removed > 0) {
      final cleaned = _data.copyWith(
        vitals: nextVitals,
        journals: nextJournals,
        medicationHistory: nextHistory,
        missedDoseEvents: nextEvents,
        foodEntries: nextFood,
      );
      if (commit) {
        await _commit(cleaned);
      } else {
        _data = cleaned;
      }
    }
    return removed;
  }

  Future<void> _commit(SandyData next) async {
    _data = next;
    notifyListeners();
    await _repository.save(next);
  }

  MedicationChange _historyEntry(Medication medication, String action) {
    return MedicationChange(
      id: _createId('med-change'),
      medicationId: medication.id,
      medicationName: medication.name,
      action: action,
      summary:
          '${medication.dose ?? 'جرعة غير محددة'} · ${medication.form ?? 'شكل غير محدد'} · ${getMedicationDoseTimes(medication).join('،')}',
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  /// A short "you have a dose soon" test reminder (~1 minute ahead) that flows
  /// through the exact same alarm channel, sound, vibration, language and
  /// permission checks as the real daily dose reminders — so if the user hears
  /// / sees it, real reminders will work too. Returns the user-facing Arabic
  /// explanation already shown in the dialog (same string either way).
  Future<String> sendOneMinuteTestReminder() async {
    var name = 'دواؤك';
    String language = _languageTag;
    var medicationId = 'test';
    for (final medication in _data.medications) {
      if (medication.reminderEnabled && !medication.asNeeded) {
        name = medication.name;
        medicationId = medication.id;
        break;
      }
    }
    if (_data.medications.isNotEmpty && name == 'دواؤك') {
      name = _data.medications.first.name;
      medicationId = _data.medications.first.id;
      language = _languageTag;
    }
    final outcome = await NotificationService.instance.scheduleTestReminder(
      medicationId: medicationId,
      medicationName: name,
      language: language,
      quietMode: _data.quietMode,
    );
    switch (outcome.status) {
      case ReminderStatus.active:
        return 'تم إرسال إشعار تجريبي — سيصلك خلال دقيقة بصوت وتنبيه. إن لم يصلك، تحقق من صلاحية الإشعارات واستثناء البطارية.';
      case ReminderStatus.quiet:
        return 'الوضع الهادئ مفعّل — أوقفه أولاً ليصلك الإشعار التجريبي.';
      case ReminderStatus.unsupported:
        return 'الإشعارات التجريبية تعمل على أندرويد وآيفون فقط.';
      default:
        return 'تعذّر إرسال الإشعار التجريبي — امنح صلاحية الإشعارات أولاً ثم أعد المحاولة.';
    }
  }

  Future<List<ReminderOutcome>> _scheduleDoseReminders(
    String medicationId,
    String medicationName,
    List<String> times, {
    bool requestPermissions = true,
  }) async {
    if (_data.quietMode) {
      return times
          .map((_) => const ReminderOutcome(status: ReminderStatus.quiet))
          .toList();
    }
    final outcomes = <ReminderOutcome>[];
    for (final time in times) {
      final key = time.replaceAll(':', '');
      final notificationId = '$medicationId-$key';
      // تذكير «اقترب موعد دوائك» قبل الموعد بـ15 دقيقة.
      final preDoseId = '$medicationId-$key-pre';
      final ok = await NotificationService.instance.scheduleDailyReminder(
        notificationId: notificationId,
        medicationId: medicationId,
        medicationName: medicationName,
        time: time,
        language: _languageTag,
        requestPermissions: requestPermissions,
      );
      final preOk = await NotificationService.instance.schedulePreDoseReminder(
        notificationId: preDoseId,
        medicationId: medicationId,
        medicationName: medicationName,
        time: time,
        language: _languageTag,
        requestPermissions: requestPermissions,
      );
      final identifiers = <String>[
        if (ok) notificationId,
        if (preOk) preDoseId,
      ];
      outcomes.add(
        ReminderOutcome(
          // يكفي أن ينجح أحد التذكيرين ليُعدّ الموعد مُذكَّراً.
          status: identifiers.isNotEmpty
              ? ReminderStatus.active
              : ReminderStatus.denied,
          identifier: identifiers.isEmpty ? null : identifiers.first,
          identifiers: identifiers,
        ),
      );
    }
    return outcomes;
  }

  /// معالجة ذاتية: يُعيد جدولة تذكيرات كل الأدوية المُفعَّلة (موعد الجرعة +
  /// «اقترب موعد دوائك») ويحدّث معرّفاتها.
  ///
  /// يُستدعى من [init] عند كل إقلاع، لأن الجدولة تحدث عند الإضافة/التعديل فقط:
  /// من أضاف دواءه قبل منح إذن الإشعارات (أو حين فشل التنبيه الدقيق) يبقى بلا
  /// أي تذكير إلى الأبد بلا هذه الإعادة. كما يُستدعى بعد إصلاح الصلاحيات من
  /// شاشة الإعدادات ([requestPermissions] = true لعرض نافذة المنح).
  Future<void> rescheduleAllReminders({bool requestPermissions = false}) async {
    if (_data.quietMode || _data.medications.isEmpty) return;
    // فحص صامت أولاً: بلا إذن إشعارات لا فائدة من الجدولة (وأي طلب تفاعلي
    // يُظهر نوافذ نظام في كل تشغيل).
    if (!requestPermissions) {
      final enabled = await NotificationService.instance.notificationsEnabled();
      if (!enabled) return;
    }

    final updated = <Medication>[];
    var changed = false;
    for (final medication in _data.medications) {
      if (!medication.reminderEnabled || medication.asNeeded) {
        updated.add(medication);
        continue;
      }
      await _cancelDoseReminders(medication);
      final reminders = await _scheduleDoseReminders(
        medication.id,
        medication.name,
        getMedicationDoseTimes(medication),
        requestPermissions: requestPermissions,
      );
      if (reminders.isEmpty) {
        updated.add(medication);
        continue;
      }
      final first = reminders.first;
      final identifiers = reminders.expand((r) => r.identifiers).toList();
      final status = identifiers.isEmpty ? ReminderStatus.denied : first.status;
      if (identifiers.isEmpty && medication.reminderIdentifiers.isEmpty) {
        // تعذّرت الجدولة (صلاحيات) ولا شيء مخزَّن — نكتفي بتحديث الحالة.
        updated.add(medication.copyWith(reminderStatus: status));
        changed = changed || medication.reminderStatus != status;
        continue;
      }
      updated.add(medication.copyWith(
        reminderIdentifier: first.identifier,
        reminderIdentifiers: identifiers,
        reminderStatus: status,
      ));
      changed = true;
    }
    if (!changed) return;
    await _commit(_data.copyWith(medications: updated));
  }

  Future<void> _cancelDoseReminders(Medication medication) async {
    final identifiers = <String>{
      if (medication.reminderIdentifier != null) medication.reminderIdentifier!,
      ...medication.reminderIdentifiers,
    };
    for (final identifier in identifiers) {
      await NotificationService.instance.cancel(identifier);
    }
  }

  // ---- Public actions (port of the RN store API) ---------------------------

  Future<void> setPatientProfile(PatientProfile profile) {
    return _commit(
      _data.copyWith(
        patient: PatientProfile(
          fullName: profile.fullName.trim(),
          identityNumber: profile.identityNumber.trim(),
          conditionName: profile.conditionName.trim(),
          lockEnabled: profile.lockEnabled,
          doctorNotes: profile.doctorNotes.trim(),
          nextReviewDate: profile.nextReviewDate.trim(),
          updatedAt: DateTime.now().toIso8601String(),
          doctorPhone: profile.doctorPhone.trim(),
          doctorEmail: profile.doctorEmail.trim(),
        ),
      ),
    );
  }

  Future<void> setPatientLock(bool lockEnabled) {
    return _commit(
      _data.copyWith(
        patient: _data.patient.copyWith(
          lockEnabled: lockEnabled,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      ),
    );
  }

  Future<ReminderOutcome> addMedication({
    required String name,
    required String time,
    required String category,
    required bool reminderEnabled,
    String? imageUri,
    String? dose,
    String? form,
    String? startDate,
    String? endDate,
    num? stockRemaining,
    num? stockThreshold,
    bool asNeeded = false,
    List<String>? doseTimes,
    int intervalDays = 1,
  }) async {
    final id = _createId('med');
    final times = normalizeMedicationTimes(
      (doseTimes != null && doseTimes.isNotEmpty) ? doseTimes : [time],
    );
    final primaryTime = times.isNotEmpty ? times.first : time.trim();
    final reminders = reminderEnabled
        ? await _scheduleDoseReminders(id, name.trim(), times)
        : <ReminderOutcome>[];
    final reminder = reminders.isNotEmpty
        ? reminders.first
        : const ReminderOutcome(status: ReminderStatus.disabled);
    final medication = Medication(
      id: id,
      name: name.trim(),
      imageUri: await _repository.persistMedicationImage(imageUri),
      time: primaryTime,
      doseTimes: times,
      category: category,
      dose: dose?.trim(),
      form: form?.trim(),
      startDate: startDate?.trim(),
      endDate: (endDate != null && endDate.trim().isNotEmpty)
          ? endDate.trim()
          : null,
      stockRemaining: stockRemaining,
      stockThreshold: stockThreshold,
      asNeeded: asNeeded,
      intervalDays: intervalDays.clamp(1, 365),
      taken: false,
      updatedAt: DateTime.now().toIso8601String(),
      reminderEnabled: reminderEnabled,
      reminderIdentifier: reminder.identifier,
      reminderIdentifiers: reminders.expand((r) => r.identifiers).toList(),
      reminderStatus: reminder.status,
    );
    await _commit(
      _data.copyWith(
        medications: [..._data.medications, medication],
        medicationHistory: [
          _historyEntry(medication, 'added'),
          ..._data.medicationHistory,
        ].take(40).toList(),
      ),
    );
    return reminder;
  }

  Future<ReminderOutcome> updateMedication(
    String id, {
    required String name,
    required String time,
    required String category,
    required bool reminderEnabled,
    String? imageUri,
    String? dose,
    String? form,
    String? startDate,
    String? endDate,
    num? stockRemaining,
    num? stockThreshold,
    bool asNeeded = false,
    List<String>? doseTimes,
  }) async {
    final current = _data.medications.where((m) => m.id == id).firstOrNull;
    if (current == null) {
      return const ReminderOutcome(status: ReminderStatus.disabled);
    }
    final times = normalizeMedicationTimes(
      (doseTimes != null && doseTimes.isNotEmpty) ? doseTimes : [time],
    );
    final primaryTime = times.isNotEmpty ? times.first : time.trim();
    await _cancelDoseReminders(current);
    final reminders = reminderEnabled
        ? await _scheduleDoseReminders(id, name.trim(), times)
        : <ReminderOutcome>[];
    final reminder = reminders.isNotEmpty
        ? reminders.first
        : const ReminderOutcome(status: ReminderStatus.disabled);
    final persistedImage = await _repository.persistMedicationImage(imageUri);
    final updated = current.copyWith(
      name: name.trim(),
      imageUri: persistedImage,
      time: primaryTime,
      doseTimes: times,
      category: category,
      dose: dose?.trim(),
      form: form?.trim(),
      startDate: startDate?.trim(),
      endDate: (endDate != null && endDate.trim().isNotEmpty)
          ? endDate.trim()
          : null,
      stockRemaining: stockRemaining,
      stockThreshold: stockThreshold,
      asNeeded: asNeeded,
      reminderEnabled: reminderEnabled,
      reminderIdentifier: reminder.identifier,
      reminderIdentifiers: reminders.expand((r) => r.identifiers).toList(),
      reminderStatus: reminder.status,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _commit(
      _data.copyWith(
        medications:
            _data.medications.map((m) => m.id == id ? updated : m).toList(),
        medicationHistory: [
          _historyEntry(updated, 'updated'),
          ..._data.medicationHistory,
        ].take(40).toList(),
      ),
    );
    if (current.imageUri != updated.imageUri) {
      await _repository.removeMedicationImage(current.imageUri);
    }
    return reminder;
  }

  Future<void> toggleMedication(String id) {
    final medication = _data.medications.where((m) => m.id == id).firstOrNull;
    final wasTaken = medication?.taken ?? false;
    // نظام خلية النحل: إلغاء سؤال المزاج المُجدول عند التراجع عن التأكيد.
    if (wasTaken) {
      NotificationService.instance.cancelMoodFollowUp(id);
    }
    final next = _data.medications
        .map((m) => m.id == id
            ? m.copyWith(
                taken: !m.taken, updatedAt: DateTime.now().toIso8601String())
            : m)
        .toList();
    return _commit(_data.copyWith(medications: next));
  }

  Future<void> markMedicationTaken(String id) async {
    final medication = _data.medications.where((m) => m.id == id).firstOrNull;
    if (medication == null || medication.taken) return;
    final event = MedicationDoseEvent(
      id: _createId('taken-dose'),
      medicationId: medication.id,
      medicationName: medication.name,
      type: DoseEventType.taken,
      createdAt: DateTime.now().toIso8601String(),
    );
    await _commit(
      _data.copyWith(
        medications: _data.medications
            .map((m) => m.id == id
                ? m.copyWith(
                    taken: true, updatedAt: DateTime.now().toIso8601String())
                : m)
            .toList(),
        missedDoseEvents: [event, ..._data.missedDoseEvents].take(80).toList(),
      ),
    );
    // نظام خلية النحل: بعد 30-60 دقيقة من التناول نسأل «كيف تشعر الآن؟»
    // لربط أثر الدواء بحالة المريض (الطلب 1 من مواصفة خلية النحل).
    await NotificationService.instance.scheduleMoodFollowUpNotification(
      medicationId: medication.id,
      medicationName: medication.name,
      delay: const Duration(minutes: 45),
    );
  }

  /// نظام خلية النحل: يحفظ إجابة «كيف تشعر الآن؟» على حدث آخر جرعة
  /// متناولة لنفس الدواء، ثم يُبلّغ الطبيب تلقائياً عند بلوغ عتبة
  /// التكرار (3 مرات سلب بعد نفس الدواء خلال 30 يوماً).
  ///
  /// يعيد تنبيه الطبيب إن اكتُشف (وإلا null) ليعرضه المستدعي.
  Future<DoctorMoodAlert?> savePostDoseMood(
    String medicationId,
    String moodKey,
  ) async {
    final index = _data.missedDoseEvents.indexWhere(
        (e) => e.medicationId == medicationId && e.type == DoseEventType.taken);
    if (index < 0) return null;
    final events = [..._data.missedDoseEvents];
    events[index] = events[index].copyWith(postDoseMood: moodKey);
    await _commit(_data.copyWith(missedDoseEvents: events.take(80).toList()));
    // فحص عتبة التكرار فوراً بعد الحفظ (تنبيه فوري عند بلوغ 3 مرات).
    final alert = detectRepeatedPostDoseMood(events.take(80).toList());
    if (alert == null) return null;
    try {
      await NotificationService.instance.showWellbeingNotification(
        title: 'تنبيه لمتابعة الطبيب'.tr,
        body: alert.message.tr,
      );
    } catch (_) {}
    return alert;
  }

  // ---- مغذّيات محرك خلية النحل ----------------------------------------------

  /// مفاتيح مزاج اليوميات (آخر 7 أيام) للتقارير الأسبوعية.
  List<String> get weekJournalMoods {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _data.journals
        .where((j) => DateTime.tryParse(j.createdAt)?.isAfter(cutoff) ?? false)
        .map((j) => j.mood)
        .toList();
  }

  /// أسماء أطعمة آخر 7 أيام (فحص التغذية الأسبوعي).
  List<String> get weekFoodNames {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _data.foodEntries
        .where((f) => DateTime.tryParse(f.createdAt)?.isAfter(cutoff) ?? false)
        .map((f) => f.name)
        .toList();
  }

  /// أسماء أطعمة اليوم (فحص تعارض الدواء-الغذاء اليومي).
  List<String> get todayFoodNames {
    final today = DateTime.now();
    return _data.foodEntries
        .where((f) {
          final d = DateTime.tryParse(f.createdAt);
          return d != null &&
              d.year == today.year &&
              d.month == today.month &&
              d.day == today.day;
        })
        .map((f) => f.name)
        .toList();
  }

  Future<void> removeMedication(String id) async {
    final medication = _data.medications.where((m) => m.id == id).firstOrNull;
    if (medication != null) await _cancelDoseReminders(medication);
    await _commit(
      _data.copyWith(
        medications: _data.medications.where((m) => m.id != id).toList(),
        medicationHistory: medication != null
            ? [
                _historyEntry(medication, 'removed'),
                ..._data.medicationHistory,
              ].take(40).toList()
            : _data.medicationHistory,
      ),
    );
    await _repository.removeMedicationImage(medication?.imageUri);
  }

  Future<void> recordMissedDose(String id, String? reason) async {
    final medication = _data.medications.where((m) => m.id == id).firstOrNull;
    if (medication == null) return;
    final event = MedicationDoseEvent(
      id: _createId('missed-dose'),
      medicationId: medication.id,
      medicationName: medication.name,
      type: DoseEventType.missed,
      reason:
          (reason != null && reason.trim().isNotEmpty) ? reason.trim() : null,
      createdAt: DateTime.now().toIso8601String(),
    );
    await _commit(
      _data.copyWith(
        missedDoseEvents: [event, ..._data.missedDoseEvents].take(80).toList(),
      ),
    );
  }

  Future<bool> repeatMedicationDose(String id) async {
    final medication = _data.medications.where((m) => m.id == id).firstOrNull;
    if (medication == null || !medication.asNeeded) return false;
    final event = MedicationDoseEvent(
      id: _createId('as-needed-dose'),
      medicationId: medication.id,
      medicationName: medication.name,
      type: DoseEventType.asNeeded,
      reason: 'voice-repeat',
      createdAt: DateTime.now().toIso8601String(),
    );
    await _commit(
      _data.copyWith(
        missedDoseEvents: [event, ..._data.missedDoseEvents].take(80).toList(),
      ),
    );
    return true;
  }

  Future<void> snoozeMedication(String medicationId, String name) async {
    await NotificationService.instance.snoozeReminder(
      medicationId: medicationId,
      medicationName: name,
    );
  }

  Future<void> addVital(
    String kind,
    String value, {
    String source = VitalSource.manual,
    String? deviceName,
  }) {
    final reading = VitalReading(
      id: _createId('vital'),
      kind: kind,
      value: value.trim(),
      createdAt: DateTime.now().toIso8601String(),
      source: source,
      deviceName: deviceName,
    );
    _announceVitalAdvice(reading).ignore();
    return _commit(_data.copyWith(vitals: [reading, ..._data.vitals]));
  }

  /// Imports vitals fetched from an external source (Health Connect / Bluetooth),
  /// skipping duplicates that already exist (same id). Returns how many new
  /// readings were added. Readings that turn out abnormal/emergency are
  /// announced (notification + slow speech) once, right after they are stored.
  Future<int> addVitalsImported(List<VitalReading> imported) async {
    if (imported.isEmpty) return 0;
    final existing = _data.vitals.map((v) => v.id).toSet();
    final fresh = imported.where((v) => existing.add(v.id)).toList();
    if (fresh.isEmpty) return 0;
    await _commit(_data.copyWith(vitals: [...fresh, ..._data.vitals]));
    // أخطر نتيجة واحدة فقط في الدفعة الواحدة حتى لا يغرق المستخدم بالتنبيهات.
    _announceWorstVitalAdvice(fresh).ignore();
    return fresh.length;
  }

  /// يعلن نتيجة قراءة واحدة غير مقبولة أو خطرة: إشعار نظام فوري + نطق بطيء.
  ///
  /// القراءات الطبيعية والحدية تُعرض داخل شاشة القياسات فقط — لا إشعار ولا
  /// صوت حتى لا يُزعج المستخدم. كل الفشل مكتوم هنا حتى لا يُسقط الحفظ، وكل
  /// الاستدعاء يتم دون انتظار (`.ignore()`) حتى لا تتأخر عملية الإضافة.
  Future<void> _announceVitalAdvice(VitalReading reading) async {
    final advice = adviseReading(
      reading,
      conditionName: _data.patient.conditionName,
    );
    if (!advice.needsDoctor) return;
    try {
      await NotificationService.instance.showVitalAlertNotification(
        level: advice.level,
        title: advice.title.tr,
        body: advice.spokenText.tr,
      );
    } catch (_) {
      // الإذن غير ممنوح أو الإشعارات معطّلة — يبقى التنبيه داخل الشاشة.
    }
    // نطق فوري بطيء — يعمل والتطبيق مفتوح فقط (TTS لا يعمل من الخلفية)،
    // وصوت الإشعار هو ما يوقظ المريض إذا كان التطبيق مغلقاً.
    await VoiceService.instance
        .speakSlow(advice.spokenText, languageTag: _languageTag)
        .timeout(const Duration(seconds: 10))
        .catchError((_) {});
  }

  /// يعلن أخطر نتيجة واحدة بين دفعة قراءات (الخطر العاجل أولاً، وإلا أول
  /// قراءة غير مقبول) حتى لا يغرق المستخدم بعدة تنبيهات لدفعة واحدة.
  Future<void> _announceWorstVitalAdvice(List<VitalReading> readings) async {
    final candidates = <VitalReading>[];
    for (final reading in readings) {
      final advice = adviseReading(
        reading,
        conditionName: _data.patient.conditionName,
      );
      if (advice.needsDoctor) candidates.add(reading);
    }
    if (candidates.isEmpty) return;
    final chosen = candidates.firstWhere(
      (r) => adviseReading(r, conditionName: _data.patient.conditionName)
          .emergency,
      orElse: () => candidates.first,
    );
    await _announceVitalAdvice(chosen);
  }

  Future<void> addJournal(String mood, String note) {
    final entry = JournalEntry(
      id: _createId('journal'),
      mood: mood,
      note: note.trim(),
      createdAt: DateTime.now().toIso8601String(),
    );
    return _commit(
        _data.copyWith(journals: [entry, ..._data.journals], lastMood: mood));
  }

  /// Logs a food/drink the patient consumed. Newest entries come first.
  /// Adds an emergency contact (family member / caregiver). Duplicate names
  /// are ignored so accidental double-taps don't create copies.
  Future<void> addEmergencyContact(String name, String phone) async {
    final cleanName = name.trim();
    final cleanPhone = phone.replaceAll(RegExp(r'[\s-]'), '');
    if (cleanName.isEmpty || cleanPhone.isEmpty) return;
    final exists = _data.emergencyContacts.any(
      (c) => c.name == cleanName && c.phone == cleanPhone,
    );
    if (exists) return;
    final contact = EmergencyContact(
      id: _createId('ec'),
      name: cleanName,
      phone: cleanPhone,
    );
    await _commit(
      _data.copyWith(
        emergencyContacts: [..._data.emergencyContacts, contact],
      ),
    );
  }

  Future<void> removeEmergencyContact(String id) {
    return _commit(
      _data.copyWith(
        emergencyContacts: _data.emergencyContacts
            .where((c) => c.id != id)
            .toList(growable: false),
      ),
    );
  }

  Future<void> setAmbulanceNumber(String number) {
    final clean = number.replaceAll(RegExp(r'[\s-]'), '');
    return _commit(_data.copyWith(ambulanceNumber: clean));
  }

  Future<void> addFood(String name, String mealType) {
    final entry = FoodEntry(
      id: _createId('food'),
      name: name.trim(),
      mealType: mealType,
      createdAt: DateTime.now().toIso8601String(),
    );
    return _commit(_data.copyWith(foodEntries: [entry, ..._data.foodEntries]));
  }

  Future<bool> removeFood(String id) async {
    final before = _data.foodEntries.length;
    await _commit(
      _data.copyWith(
          foodEntries: _data.foodEntries.where((f) => f.id != id).toList()),
    );
    return _data.foodEntries.length < before;
  }

  Future<void> addMedicalAttachment(String kind, String uri) async {
    final storedUri = await _repository.persistMedicalAttachment(uri);
    final attachment = MedicalAttachment(
      id: _createId('medical-attachment'),
      kind: kind,
      uri: storedUri,
      createdAt: DateTime.now().toIso8601String(),
    );
    await _commit(_data.copyWith(
        medicalAttachments: [attachment, ..._data.medicalAttachments]));
  }

  Future<void> removeMedicalAttachment(String id) async {
    final attachment =
        _data.medicalAttachments.where((a) => a.id == id).firstOrNull;
    await _commit(
      _data.copyWith(
        medicalAttachments:
            _data.medicalAttachments.where((a) => a.id != id).toList(),
      ),
    );
    await _repository.removeMedicalAttachment(attachment?.uri);
  }

  /// الوضع الهادئ: يُلغي كل التذكيرات المُجدولة فعلياً (كانت تستمر بالظهور عند
  /// تشغيله لأن الإلغاء لم يكن يحدث)، وعند إيقافه يُعاد جدولة كل الأدوية
  /// المُفعَّلة مع طلب الصلاحيات إن كانت ناقصة.
  Future<void> setQuietMode(bool quietMode) async {
    if (_data.quietMode == quietMode) return;
    await _commit(_data.copyWith(quietMode: quietMode));
    if (quietMode) {
      for (final medication in _data.medications) {
        await _cancelDoseReminders(medication);
        await NotificationService.instance.cancelMoodFollowUp(medication.id);
      }
      return;
    }
    await rescheduleAllReminders(requestPermissions: true);
  }

  Future<void> setTrustedContact(String url, String name) => _commit(
        _data.copyWith(
          trustedContactUrl: url.trim(),
          trustedContactName: name.trim(),
        ),
      );

  Future<void> setTravelMode(bool travelMode) =>
      _commit(_data.copyWith(travelMode: travelMode));

  /// Sets the retention window (0 = keep forever). When enabled, immediately
  /// purges any time-series data now older than the new window and returns the
  /// number of records removed.
  Future<int> setDataRetentionDays(int days) async {
    final normalized = days < 0 ? 0 : days;
    await _commit(_data.copyWith(dataRetentionDays: normalized));
    return _applyRetention(commit: true);
  }

  Future<void> setAccessibility(AccessibilityPreferences accessibility) =>
      _commit(_data.copyWith(accessibility: accessibility));

  // ---- Backup: identical JSON contract as the RN app's export/import -------

  String exportBackupJson() => jsonEncode(_data.toJson());

  /// Imports an `alk-backup-*.json` file produced by either app build.
  /// Returns the imported record counts.
  Future<LegacyMigrationResult> importBackupJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('backup is not a JSON object');
    }
    final imported = SandyData.fromJson(decoded);
    // طريق الشفاء: إذا كان ملف الجهاز مشفَّراً بمفتاح مفقود فالكتابة موقوفة
    // لحماية البيانات — واستيراد نسخة احتياطية يبدأ ملفاً جديداً بالبيانات
    // المستوردة (بعد تأكيد صريح في شاشة الإعدادات).
    if (dataUnreadable) {
      await _repository.clear();
      dataUnreadable = false;
    }
    final merged = _mergeForImport(imported);
    await _repository.save(merged);
    _data = merged;
    notifyListeners();
    return LegacyMigrationResult(
      performed: true,
      source: 'json-backup',
      medications: imported.medications.length,
      vitals: imported.vitals.length,
      journals: imported.journals.length,
      attachments: imported.medicalAttachments.length,
      doseEvents: imported.missedDoseEvents.length,
      message: 'backup imported successfully',
    );
  }

  SandyData _mergeForImport(SandyData imported) {
    // The chosen backup file is the source of truth; keep the current
    // accessibility prefs and patient identity only when the file has none.
    final patient = imported.patient.fullName.isEmpty &&
            imported.patient.identityNumber.isEmpty
        ? _data.patient
        : imported.patient;
    return SandyData.initial.copyWith(
      patient: patient,
      medications: imported.medications,
      medicationHistory: imported.medicationHistory,
      missedDoseEvents: imported.missedDoseEvents,
      vitals: imported.vitals,
      journals: imported.journals,
      medicalAttachments: imported.medicalAttachments,
      foodEntries: imported.foodEntries,
      quietMode: imported.quietMode,
      accessibility: _data.accessibility,
      trustedContactUrl: imported.trustedContactUrl,
      trustedContactName: imported.trustedContactName,
      travelMode: imported.travelMode,
      dataRetentionDays: imported.dataRetentionDays,
    );
  }

  /// Removes every record (used by "clear all data" in settings).
  Future<void> resetAll() async {
    await _repository.clear();
    _data = SandyData.initial;
    notifyListeners();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
