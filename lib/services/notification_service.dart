import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/app_strings.dart';
import 'reminder_content.dart';

/// Reminder outcome statuses — identical strings to the RN `ReminderStatus`.
class ReminderOutcome {
  final String status; // active | quiet | unsupported | denied | disabled
  final String? identifier;

  const ReminderOutcome({required this.status, this.identifier});

  const ReminderOutcome.disabled() : this(status: 'disabled');

  bool get isActive => status == 'active';
}

const int _snoozeSeed = 0x5E005E;

/// حمولة إشعار تذكير مفكوكة: تُستخدم لفتح شاشة الأدوية ونطق التذكير بصوت
/// عالٍ عند ضغط المستخدم على الإشعار (كبير السن قد لا يقرأ الإشعار).
class ReminderTapPayload {
  const ReminderTapPayload({
    required this.isPreDose,
    required this.medicationId,
    required this.medicationName,
    required this.languageTag,
    required this.variant,
  });

  /// true لتذكير «اقترب موعد دوائك»، false لتذكير موعد الجرعة نفسه.
  final bool isPreDose;
  final String medicationId;
  final String medicationName;
  final String languageTag;
  final int variant;

  /// صيغتا الحمولة:
  /// جرعة:    `medId|name|lang|variant`
  /// ما قبل:  `predose|medId|name|lang|variant`
  static ReminderTapPayload? parse(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    final parts = payload.split('|');
    final isPreDose = parts.first == 'predose';
    final offset = isPreDose ? 1 : 0;
    // نحتاج: [الاسم، وسم اللغة، عداد التباين] على الأقل بعد المعرّف.
    if (parts.length < offset + 4) return null;
    final medicationId = parts[offset];
    final name = parts[offset + 1];
    if (medicationId.isEmpty || name.isEmpty) return null;
    return ReminderTapPayload(
      isPreDose: isPreDose,
      medicationId: medicationId,
      medicationName: name,
      languageTag: parts[offset + 2],
      variant: int.tryParse(parts[offset + 3]) ?? 0,
    );
  }
}

final AndroidNotificationDetails _medicationAndroidDetails =
    AndroidNotificationDetails(
  'medication-reminders-system',
  'ALK medication reminders',
  channelDescription: 'Daily dose reminders',
  importance: Importance.max,
  priority: Priority.max,
  category: AndroidNotificationCategory.alarm,
  visibility: NotificationVisibility.private,
  ticker: 'ALK',
  // Full-screen-style head-up alert: pops over the screen with the default
  // alarm sound (audible "take your medicine" style ring + vibration) instead
  // of a silent tray entry that an elderly user might never notice.
  fullScreenIntent: true,
  vibrationPattern: Int64List.fromList([0, 500, 250, 500, 250, 500]),
  enableVibration: true,
  playSound: true,
  ledColor: const Color(0xFF1F8A8A),
  ledOnMs: 1000,
  ledOffMs: 500,
  color: const Color(0xFF1F8A8A),
);

final NotificationDetails _medicationDetails = NotificationDetails(
  android: _medicationAndroidDetails,
  iOS: const DarwinNotificationDetails(),
);

/// Port of `lib/medication-reminders.ts` (expo-notifications →
/// flutter_local_notifications). Schedules exact daily dose alarms on Android
/// with the same channel IDs as the RN build.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Current language tag for notification content localization.
  static String currentLanguageTag = 'en';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _configured = false;

  /// Whether the tz database was initialized (exactly once per process).
  ///
  /// Static on purpose: `_ensureInitialized` may be called on different
  /// `NotificationService` instances (tests, store, main) — the guard must
  /// still hold, because `initializeTimeZones()` resets `tz.local` to UTC.
  static bool _timezonesReady = false;

  /// Called by `main()` after it initializes the tz database + pins the
  /// device location, so `_ensureInitialized` must NOT call
  /// `initializeTimeZones()` again (it would reset `tz.local` to UTC and
  /// shift every scheduled dose reminder by the UTC offset — hours off,
  /// "never arrives").
  static void markTimezonesReady() => _timezonesReady = true;

  /// Test-only: resets the tz guard so each test starts from a clean slate.
  @visibleForTesting
  static void resetTimezonesForTest() => _timezonesReady = false;

  /// ليد التذكير الاستباقي («اقترب موعد دوائك») قبل موعد الجرعة بالدقائق.
  ///
  /// كبير السن يحتاج وقتاً للتحضير: كأس ماء، فتح العلبة، الجلوس… فتصل الرسالة
  /// قبل الموعد لا بعده فقط.
  static const int preDoseLeadMinutes = 15;

  /// يُستدعى عند ضغط المستخدم على إشعار تذكير (جرعة أو «اقترب موعد» أو
  /// تنبيه غذائي) بحمولته، لتفتح الواجهة الشاشة المناسبة وتنطق بصوت عالٍ.
  void Function(String payload)? onReminderTap;

  String? _pendingTapPayload;

  /// الحمولة التي ضُغطت قبل جهوز الواجهة (يأخذها المستدعي مرة واحدة).
  String? takePendingTapPayload() {
    final payload = _pendingTapPayload;
    _pendingTapPayload = null;
    return payload;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final handler = onReminderTap;
    if (handler == null) {
      _pendingTapPayload = payload;
      return;
    }
    handler(payload);
  }

  /// إن أُطلق التطبيق من ضغط على إشعار تذكير (التطبيق كان مغلقاً) يعيد
  /// حمولته، وإلا null. تُستدعى بعد تحميل البيانات.
  Future<String?> launchReminderPayload() async {
    try {
      await _ensureInitialized();
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return details?.notificationResponse?.payload;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_configured) return;
    // Guarded exactly-once: `initializeTimeZones()` rebuilds the whole tz
    // database and resets `tz.local` to UTC. `main()` already initializes it
    // and pins the device location (`setLocalLocation`), so re-initializing
    // here would silently move that location back to UTC and shift every
    // scheduled dose reminder by the UTC offset (hours off, "never arrives").
    if (!_timezonesReady) {
      tzdata.initializeTimeZones();
      _timezonesReady = true;
    }
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(const AndroidNotificationChannel(
        'medication-reminders-system',
        'ALK medication reminders',
        description: 'Daily dose reminders',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ));
      await android.createNotificationChannel(const AndroidNotificationChannel(
        'wellbeing-reminders-system',
        'ALK wellbeing reminders',
        description: 'Daily wellbeing nudges',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ));
      await android.createNotificationChannel(const AndroidNotificationChannel(
        'food-alerts-system',
        'ALK food alerts',
        description: 'Level 1 (over limit) and level 2 (near limit) food alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ));
      // Android 13+ runtime permission.
      await android.requestNotificationsPermission();
      // Android 14+ exact-alarm permission (best effort).
      try {
        await android.requestExactAlarmsPermission();
      } catch (_) {
        // Older Android versions throw here; exact alarms are implicit.
      }
    }
    _configured = true;
  }

  /// Requests notification permission; returns true when granted.
  ///
  /// FIX: previously this returned `false` whenever notifications were
  /// disabled without ever showing the Android 13+ runtime dialog, which made
  /// background dose reminders silently never get scheduled. Now the dialog
  /// is requested explicitly and the grant state is re-checked afterwards.
  Future<bool> requestPermission() async {
    try {
      return await _requestPermission();
    } catch (_) {
      // قنوات المنصة غائبة (بيئة الاختبار مثلاً) — لا نُسقط أي شيء بسببها.
      return false;
    }
  }

  Future<bool> _requestPermission() async {
    await _ensureInitialized();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      var enabled = await android.areNotificationsEnabled();
      if (enabled != true) {
        // Android 13+: triggers the POST_NOTIFICATIONS system dialog.
        try {
          await android.requestNotificationsPermission();
        } catch (_) {
          // Best effort — re-checked below.
        }
        enabled = await android.areNotificationsEnabled();
      }
      if (enabled != true) return false;
      try {
        await android.requestExactAlarmsPermission();
      } catch (_) {
        // Ignore on Android < 12 where the API is unavailable.
      }
      return true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: false,
        sound: true,
      );
      return granted ?? false;
    }
    return true;
  }

  Future<bool> _notificationsEnabled() async {
    await _ensureInitialized();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        return await android.areNotificationsEnabled() == true;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Resolves the safest schedule mode for this device.
  ///
  /// FIX: on Android 14+ `exactAllowWhileIdle` throws when the user has not
  /// granted the exact-alarm permission, which used to fail the whole
  /// `zonedSchedule` call (caught upstream as `denied`) so **no** reminder was
  /// scheduled at all. Now we fall back to inexact alarms, which still fire in
  /// the background — just with a small timing window.
  Future<AndroidScheduleMode> _resolveScheduleMode() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      final canExact = await android.canScheduleExactNotifications();
      if (canExact == true) {
        return AndroidScheduleMode.exactAllowWhileIdle;
      }
    } catch (_) {
      // API unavailable (< Android 12): exact alarms are implicit there.
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Whether scheduled alarms can survive the app being in the background:
  /// notifications allowed AND the app exempted from battery optimization.
  Future<bool> canDeliverBackgroundNotifications() async {
    if (!await _notificationsEnabled()) return false;
    return isIgnoringBatteryOptimizations();
  }

  /// Whether exact alarms are currently allowed (Android 12+). Shown in the
  /// settings status dialog; `false` means dose reminders may fire with a
  /// small delay (inexact-alarm fallback) instead of at the exact minute.
  Future<bool> areExactAlarmsAllowed() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    try {
      return await android.canScheduleExactNotifications() == true;
    } catch (_) {
      // API unavailable (< Android 12): exact alarms are implicit there.
      return true;
    }
  }


  /// Whether the OS has exempted the app from battery optimization. On many
  /// devices (Xiaomi, Huawei, Oppo...) battery optimization silently kills
  /// scheduled alarms while the app is in the background or killed.
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (_) {
      // Unsupported platform or permission plugin missing — assume true so
      // the reminder flow is never blocked.
      return true;
    }
  }

  /// Opens the system dialog asking the user to exempt the app from battery
  /// optimization so background dose reminders keep firing. Returns true when
  /// the app is (or became) exempt.
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (_) {
      return await isIgnoringBatteryOptimizations();
    }
  }

  ({int hour, int minute})? parseDailyTime(String time) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }

  /// Convenience wrapper used by [SandyStore]: schedules the daily dose
  /// reminder for [time] (`HH:mm`) and returns true when it is active.
  Future<bool> scheduleDailyReminder({
    required String notificationId,
    required String medicationId,
    required String medicationName,
    required String time,
    String? language,
    bool quietMode = false,
    bool requestPermissions = true,
  }) async {
    final outcome = await scheduleDailyDoseReminder(
      id: notificationId,
      medicationId: medicationId,
      name: medicationName,
      time: time,
      language: language ?? currentLanguageTag,
      quietMode: quietMode,
      requestPermissions: requestPermissions,
    );
    return outcome.isActive;
  }

  /// هل الإشعارات مسموحة الآن؟ فحص صامت (بلا أي نافذة نظام) يُستخدم عند
  /// إعادة الجدولة الصامتة بعد الإقلاع.
  Future<bool> notificationsEnabled() => _notificationsEnabled();

  /// Schedules a daily dose reminder; returns a [ReminderOutcome] with the
  /// same status vocabulary as the RN build.
  ///
  /// [requestPermissions] = false يتخطى طلب الصلاحيات التفاعلي (نافذة النظام
  /// وطلب التنبيهات الدقيقة) — يُستخدم عند إعادة الجدولة تلقائياً بعد الإقلاع
  /// حتى لا تظهر نوافذ نظام في كل تشغيل.
  Future<ReminderOutcome> scheduleDailyDoseReminder({
    required String id,
    required String medicationId,
    required String name,
    required String time,
    required String language,
    required bool quietMode,
    bool requestPermissions = true,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return const ReminderOutcome(status: 'unsupported');
    }
    if (quietMode) return const ReminderOutcome(status: 'quiet');
    final clock = parseDailyTime(time);
    if (clock == null) return const ReminderOutcome(status: 'denied');
    if (requestPermissions && !await requestPermission()) {
      return const ReminderOutcome(status: 'denied');
    }
    if (!await _notificationsEnabled()) {
      return const ReminderOutcome(status: 'denied');
    }

    final message = localizedReminderMessage(
      medicationId: medicationId,
      medicationName: name,
      language: language,
    );
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      clock.hour,
      clock.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    try {
      await _plugin.zonedSchedule(
        id.hashCode & 0x7fffffff,
        message.title,
        message.body,
        scheduled,
        _medicationDetails,
        payload:
            '$medicationId|$name|${message.languageTag}|${message.variant}',
        androidScheduleMode: await _resolveScheduleMode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return ReminderOutcome(status: 'active', identifier: id);
    } catch (_) {
      return const ReminderOutcome(status: 'denied');
    }
  }

  /// Convenience wrapper used by [SandyStore]: schedules the daily
  /// "your dose is near" head-up reminder (dose time minus [leadMinutes])
  /// and returns true when it is active.
  Future<bool> schedulePreDoseReminder({
    required String notificationId,
    required String medicationId,
    required String medicationName,
    required String time,
    String? language,
    bool quietMode = false,
    int leadMinutes = preDoseLeadMinutes,
    bool requestPermissions = true,
  }) async {
    final outcome = await scheduleDailyPreDoseReminder(
      id: notificationId,
      medicationId: medicationId,
      name: medicationName,
      time: time,
      language: language ?? currentLanguageTag,
      quietMode: quietMode,
      leadMinutes: leadMinutes,
      requestPermissions: requestPermissions,
    );
    return outcome.isActive;
  }

  /// وقت تذكير ما قبل الجرعة: موعد الجرعة (`hour:minute`) ناقص [leadMinutes]،
  /// وإن كان قد مضى اليوم فالغد. دالة نقية قابلة للاختبار بلا منصة.
  static tz.TZDateTime nextPreDoseOccurrence({
    required tz.TZDateTime now,
    required int hour,
    required int minute,
    required int leadMinutes,
  }) {
    var occurrence = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).subtract(Duration(minutes: leadMinutes));
    final doseToday = occurrence.add(Duration(minutes: leadMinutes));
    if (!doseToday.isAfter(now)) {
      // الغد: يُبنى بالتاريخ (لا بمدة 24 ساعة) ليبقى صحيحاً عبر التوقيت الصيفي.
      occurrence = tz.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      ).subtract(Duration(minutes: leadMinutes));
    }
    return occurrence;
  }

  /// يُجدول تذكيراً يومياً قبل موعد الجرعة («اقترب موعد دوائك») بـ[leadMinutes]
  /// دقيقة، مع تكرار يومي في نفس الدقيقة.
  Future<ReminderOutcome> scheduleDailyPreDoseReminder({
    required String id,
    required String medicationId,
    required String name,
    required String time,
    required String language,
    required bool quietMode,
    int leadMinutes = preDoseLeadMinutes,
    bool requestPermissions = true,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return const ReminderOutcome(status: 'unsupported');
    }
    if (quietMode) return const ReminderOutcome(status: 'quiet');
    final clock = parseDailyTime(time);
    if (clock == null) return const ReminderOutcome(status: 'denied');
    if (requestPermissions && !await requestPermission()) {
      return const ReminderOutcome(status: 'denied');
    }
    if (!await _notificationsEnabled()) {
      return const ReminderOutcome(status: 'denied');
    }

    final message = localizedPreDoseReminderMessage(
      medicationId: medicationId,
      medicationName: name,
      language: language,
      minutes: leadMinutes,
    );
    final nowTz = tz.TZDateTime.now(tz.local);
    var scheduled = nextPreDoseOccurrence(
      now: nowTz,
      hour: clock.hour,
      minute: clock.minute,
      leadMinutes: leadMinutes,
    );
    final payload =
        'predose|$medicationId|$name|${message.languageTag}|${message.variant}';
    try {
      if (!scheduled.isAfter(nowTz)) {
        // Inside the reminder window (between the heads-up moment and the
        // dose time): a past date cannot be scheduled (the plugin throws
        // ArgumentError), so fire an immediate nudge with the REAL minutes
        // left and start the daily repetition from tomorrow so the user
        // never loses the daily heads-up going forward.
        final doseToday = scheduled.add(Duration(minutes: leadMinutes));
        final minutesLeft = doseToday.difference(nowTz).inMinutes;
        final urgent = localizedPreDoseReminderMessage(
          medicationId: medicationId,
          medicationName: name,
          language: language,
          minutes: minutesLeft <= 0 ? 1 : minutesLeft,
        );
        await _plugin.show(
          id.hashCode & 0x7fffffff,
          urgent.title,
          urgent.body,
          _medicationDetails,
          payload: payload,
        );
        scheduled = nextPreDoseOccurrence(
          now: doseToday.add(const Duration(minutes: 1)),
          hour: clock.hour,
          minute: clock.minute,
          leadMinutes: leadMinutes,
        );
      }
      await _plugin.zonedSchedule(
        id.hashCode & 0x7fffffff,
        message.title,
        message.body,
        scheduled,
        _medicationDetails,
        payload: payload,
        androidScheduleMode: await _resolveScheduleMode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return ReminderOutcome(status: 'active', identifier: id);
    } catch (_) {
      return const ReminderOutcome(status: 'denied');
    }
  }

  /// One-shot "is it working?" probe (~65s ahead) through the SAME alarm
  /// channel/sound/vibration as the daily dose reminders. One-shot on
  /// purpose: it proves the background path (permission + exact alarm +
  /// channel) without leaving a stray repeating alarm behind.
  Future<ReminderOutcome> scheduleTestReminder({
    required String medicationId,
    required String medicationName,
    required String language,
    required bool quietMode,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return const ReminderOutcome(status: 'unsupported');
    }
    if (quietMode) return const ReminderOutcome(status: 'quiet');
    if (!await requestPermission()) {
      return const ReminderOutcome(status: 'denied');
    }
    if (!await _notificationsEnabled()) {
      return const ReminderOutcome(status: 'denied');
    }
    final message = localizedReminderMessage(
      medicationId: medicationId,
      medicationName: medicationName,
      language: language,
    );
    try {
      await _plugin.zonedSchedule(
        ('test-$medicationId-${DateTime.now().millisecondsSinceEpoch}')
                .hashCode &
            0x7fffffff,
        message.title,
        message.body,
        tz.TZDateTime.now(tz.local).add(const Duration(seconds: 65)),
        _medicationDetails,
        payload:
            '$medicationId|$medicationName|${message.languageTag}|${message.variant}',
        androidScheduleMode: await _resolveScheduleMode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return const ReminderOutcome(status: 'active', identifier: 'test');
    } catch (_) {
      return const ReminderOutcome(status: 'denied');
    }
  }

  /// One-shot snooze (15 minutes) — mirrors `snoozeMedicationReminder`.
  Future<ReminderOutcome> snoozeReminder({
    required String medicationId,
    required String medicationName,
    String language = 'en',
  }) async {
    if (!await requestPermission()) {
      return const ReminderOutcome(status: 'denied');
    }
    final message = localizedReminderMessage(
      medicationId: medicationId,
      medicationName: medicationName,
      language: language,
    );
    try {
      await _plugin.zonedSchedule(
        (medicationId.hashCode ^ _snoozeSeed) & 0x7fffffff,
        message.title,
        message.body,
        tz.TZDateTime.now(tz.local).add(const Duration(minutes: 15)),
        _medicationDetails,
        payload:
            '$medicationId|$medicationName|${message.languageTag}|${message.variant}',
        androidScheduleMode: await _resolveScheduleMode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return ReminderOutcome(
          status: 'active', identifier: medicationId);
    } catch (_) {
      return const ReminderOutcome(status: 'denied');
    }
  }

  /// يُجدول إشعار سؤال الحالة المزاجية بعد الجرعة (نظام خلية النحل).
  ///
  /// يُستدعى من `SandyStore.markMedicationTaken` بعد تأكيد التناول بـ
  /// 30-60 دقيقة تأخير (الافتراضي 45 دقيقة). إشعار واحد بلا تكرار؛ وإذا
  /// أُلغي التأكيد يُلغى الإشعار معه عبر [cancelMoodFollowUp].
  Future<void> scheduleMoodFollowUpNotification({
    required String medicationId,
    required String medicationName,
    Duration delay = const Duration(minutes: 45),
  }) async {
    if (!await requestPermission()) return;
    try {
      await _plugin.zonedSchedule(
        (medicationId.hashCode ^ 0xBEECE11) & 0x7fffffff,
        'كيف تشعر الآن؟'.tr,
        'بعد دواء $medicationName — شاركنا حالتك لمتابعة أثر الدواء'.tr,
        tz.TZDateTime.now(tz.local).add(delay),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'mood-followup-system',
            'ALK mood follow-up',
            channelDescription: 'How do you feel after your dose?',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: 'mood-followup|$medicationId',
        androidScheduleMode: await _resolveScheduleMode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // تعذّرت الجدولة (صلاحيات) — يبقى السؤال متاحاً من شاشة خلية النحل.
    }
  }

  /// يلغي إشعار السؤال المُجدول (عند إلغاء تأكيد التناول مثلاً).
  Future<void> cancelMoodFollowUp(String medicationId) async {
    try {
      await _plugin.cancel((medicationId.hashCode ^ 0xBEECE11) & 0x7fffffff);
    } catch (_) {}
  }

  /// يعرض إشعاراً فورياً لسؤال المستخدم عن حالته المزاجية بعد الجرعة
  /// (نظام خلية النحل). لا مواعيد ولا تكرار — إشعار واحد عند الحاجة.
  Future<void> showMoodFollowUpNotification({
    required String medicationName,
  }) async {
    await _ensureInitialized();
    await _plugin.show(
      'mood-followup-${DateTime.now().millisecondsSinceEpoch}'.hashCode &
          0x7fffffff,
      'كيف تشعر الآن؟'.tr,
      'بعد دواء $medicationName — شاركنا حالتك لمتابعة أثر الدواء'.tr,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'mood-followup-system',
          'ALK mood follow-up',
          channelDescription: 'How do you feel after your dose?',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Shows an immediate wellbeing nudge.
  Future<void> showWellbeingNotification({
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    await _plugin.show(
      'wellbeing-${DateTime.now().millisecondsSinceEpoch}'.hashCode &
          0x7fffffff,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'wellbeing-reminders-system',
          'ALK wellbeing reminders',
          channelDescription: 'Daily wellbeing nudges',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// إشعار فوري صوتي (نظام + نطق عند التطبيق المفتوح) لمستويي الطعام:
  /// المستوى الأول `over` (تجاوز الحد) والمستوى الثاني `warn` (قريب من الحد).
  ///
  /// [level] تكون `over` أو `warn`. الضغط على الإشعار ينطق التحذير
  /// بصوت بطيء عبر `_handleReminderPayload` في `main` — أما الإشعار نفسه فيصدر صوت
  /// النظام (قناة `food-alerts-system` بأعلى أهمية + اهتزاز) حتى لو كان
  /// التطبيق مغلقاً، لأن TTS لا يعمل في الخلفية.
  Future<void> showFoodAlertNotification({
    required String level,
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    final id = 'food-$level-${DateTime.now().millisecondsSinceEpoch}'.hashCode &
        0x7fffffff;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'food-alerts-system',
          'ALK food alerts',
          channelDescription:
              'Level 1 (over limit) and level 2 (near limit) food alerts',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.private,
          playSound: true,
          enableVibration: true,
          vibrationPattern: level == 'over'
              ? Int64List.fromList(const [0, 600, 250, 600, 250, 600])
              : Int64List.fromList(const [0, 400, 250, 400]),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'food-alert|$level|$body',
    );
  }

  /// إشعار فوري لنتيجة قياس حيوي غير مقبول أو خطر (انظر `vital_advice.dart`).
  ///
  /// [level] تكون `abnormal` (غير مقبول — راجع الطبيب) أو `emergency` (خطر
  /// عاجل — اتصل بالإسعاف). ضغط المستخدم على الإشعار ينطق النص ببطء عبر
  /// `_handleReminderPayload` في `main.dart`؛ أما صوت الإشعار نفسه فيصدر من
  /// قناة النظام (عالية الأهمية + اهتزاز) حتى لو كان التطبيق مغلقاً، لأن TTS
  /// لا يعمل في الخلفية.
  Future<void> showVitalAlertNotification({
    required String level,
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    final id =
        'vital-$level-${DateTime.now().millisecondsSinceEpoch}'.hashCode &
            0x7fffffff;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'vital-alerts-system',
          'ALK vital alerts',
          channelDescription: 'Abnormal / emergency vital-sign readings',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.private,
          playSound: true,
          enableVibration: true,
          vibrationPattern: level == 'emergency'
              ? Int64List.fromList(const [0, 600, 250, 600, 250, 600])
              : Int64List.fromList(const [0, 400, 250, 400]),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'vital-alert|$level|$body',
    );
  }


  Future<void> cancel(String identifier) async {
    try {
      await _plugin.cancel(identifier.hashCode & 0x7fffffff);
    } catch (_) {
      // Cancellation is best-effort.
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  /// Public wrapper to initialize the notification service.
  Future<void> ensureInitialized() => _ensureInitialized();
}
