import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'l10n/app_strings.dart';
import 'logic/medication_times.dart';
import 'screens/home_screen.dart';
import 'screens/medications_screen.dart';
import 'screens/settings_screen.dart';
import 'services/device_sync_service.dart';
import 'services/dictionary_translation_service.dart';
import 'services/lock_state.dart';
import 'services/notification_service.dart';
import 'services/reminder_content.dart';
import 'services/voice_service.dart';
import 'screens/voice_assistant_screen.dart';
import 'state/sandy_store.dart';
import 'storage/sandy_repository.dart';
import 'theme/alk_theme.dart';
import 'widgets/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local timezone for exact daily notifications.
  // Initialized exactly once (guarded): `tzdata.initializeTimeZones()` resets
  // the whole database AND `tz.local` back to UTC, so calling it twice (once
  // here, once from NotificationService during a reminder) would silently shift
  // every already-scheduled alarm by the UTC offset (hours!) and make dose
  // reminders arrive at the wrong time. `log` keeps a startup breadcrumb in
  // `flutter run -v` / logcat to diagnose "no reminder arrived" reports.
  try {
    tzdata.initializeTimeZones();
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
    developer.log('ALK: timezone ready ($name)', name: 'alk.startup');
    // `NotificationService._ensureInitialized` must NOT call
    // `initializeTimeZones()` again afterwards: it would reset `tz.local`
    // to UTC and shift every scheduled dose reminder by the UTC offset
    // (hours off — "the reminder never arrives").
    NotificationService.markTimezonesReady();
  } catch (e) {
    developer.log('ALK: timezone fallback to UTC ($e)', name: 'alk.startup');
    // Fall back to UTC-based scheduling rather than crashing.
  }

  final store = SandyStore(SandyRepository());
  // Warm up notification plumbing in the background (failures are non-fatal).
  NotificationService.instance.ensureInitialized().ignore();

  // ظ„ط؛ط© ط§ظ„ظˆط§ط¬ظ‡ط© طھطھط¨ط¹ ظ„ط؛ط© ط§ظ„ظ‡ط§طھظپ: ط§ظ„ط¹ط±ط¨ظٹط© ظ‡ظٹ ظ„ط؛ط© ط§ظ„ظ…طµط¯ط± ظˆط§ظ„ط¹ط±ط¶طŒ ظˆط¹ظ†ط¯ طھظƒظˆظ† ظ„ط؛ط©
  // ط§ظ„ظ‡ط§طھظپ ط؛ظٹط± ط¹ط±ط¨ظٹط© طھظڈظ‚ط±ط£ طھط±ط¬ظ…ط© ط§ظ„ظ‚ط§ظ…ظˆط³ ط§ظ„ظ…ط®ط²ظژظ‘ظ†ط© ط¹ظ„ظ‰ ط§ظ„ط¬ظ‡ط§ط² ظپظˆط±ط§ظ‹ (ط¨ظ„ط§ ط´ط¨ظƒط©).
  final deviceLanguage = DictionaryTranslationService.deviceLanguageTag();
  // التطبيق يدعم العربية فقط كواجهة رئيسية. تُستخدم ترجمة القاموس داخلياً دون
  // تغيير لغة التطبيق نفسها، لذلك نحتفظ بالواجهة بالعربية في كل الأحوال.
  store.startupLanguageTag = 'ar';
  store.setLanguageTagNoNotify('ar');
  AppStrings.current = 'ar';
  await DictionaryTranslationService.instance.restoreCache(deviceLanguage);

  runApp(AlkApp(store: store));

  // طھط¬ظ‡ظٹط² ظ…ط§ ظٹظ†ظ‚طµ ظ…ظ† طھط±ط¬ظ…ط© ط§ظ„ظ‚ط§ظ…ظˆط³ ظپظٹ ط§ظ„ط®ظ„ظپظٹط© (ظ…ط±ط© ظˆط§ط­ط¯ط© ظ„ظƒظ„ ظ„ط؛ط©) ط«ظ… طھظڈط®ط²ظژظ‘ظ† ط¹ظ„ظ‰
  // ط§ظ„ط¬ظ‡ط§ط²طŒ ظپظ„ط§ طھظڈطھط±ط¬ظ… ط§ظ„ظ…ظپط±ط¯ط§طھ ظ…ط±ط© ط£ط®ط±ظ‰ ظپظٹ ظƒظ„ طھط´ط؛ظٹظ„.
  unawaited(DictionaryTranslationService.instance.start(
    targetLanguage: deviceLanguage,
    onChanged: () => store.requestRebuild(),
  ));
}

class AlkApp extends StatelessWidget {
  final SandyStore store;

  const AlkApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: store,
      // Select only the values that actually affect the app shell (language +
      // direction). The whole tree must NOT rebuild on every data mutation
      // (medication toggles, vitals, journals, ...), only when the language
      // or text direction changes â€” otherwise the app becomes very slow each
      // time the store notifies.
      child: Selector<SandyStore, (String, bool, int)>(
        // ط§ظ„ظ‚ظٹظ… ط§ظ„ظ…ظ†طھظ‚ط§ط© طھط´ظ…ظ„ ط¬ظٹظ„ ظ‚ط§ظ…ظˆط³ ط§ظ„طھط±ط¬ظ…ط©: طھظڈط¹ط§ط¯ ط´ط¬ط±ط© ط§ظ„ظˆط§ط¬ظ‡ط© ظ…ط±ط© ظˆط§ط­ط¯ط©
        // ط¹ظ†ط¯ ط¬ظ‡ظˆط² ط§ظ„طھط±ط¬ظ…ط© ط£ظˆ طھط؛ظٹظ‘ط± ط§ظ„ظ„ط؛ط©طŒ ظ„ط§ ط¹ظ†ط¯ ظƒظ„ طھط¹ط¯ظٹظ„ ط¨ظٹط§ظ†ط§طھ.
        selector: (_, s) =>
            (s.languageTag, s.isRTL, AppStrings.table.generation),
        builder: (context, sel, _) {
          final locale = sel.$1;
          final isRTL = sel.$2;
          final dictionaryGeneration = sel.$3;
          NotificationService.currentLanguageTag = locale;
          // Sync the string-table language so `.tr` extension translates.
          AppStrings.current = locale;
          return MaterialApp(
            // ط§ظ„ظ…ظپطھط§ط­ ظٹطھط¨ط¹ ط§ظ„ظ„ط؛ط© ظˆط¬ظٹظ„ ط§ظ„طھط±ط¬ظ…ط©: طھط؛ظٹظ‘ط±ظ‡ ظٹط¹ظٹط¯ ط¨ظ†ط§ط، ط§ظ„ط´ط¬ط±ط© ظƒط§ظ…ظ„ط©
            // ظ„طھظڈط¹ط±ط¶ ط§ظ„ظ†طµظˆطµ ط§ظ„ظ…طھط±ط¬ظ…ط© ظپظˆط±ط§ظ‹ (ظٹط­ط¯ط« ظ…ط±ط© ظˆط§ط­ط¯ط© ط¹ظ†ط¯ ط¬ظ‡ظˆط² ط§ظ„طھط±ط¬ظ…ط©).
            key: ValueKey<String>('alk-$locale-$dictionaryGeneration'),
            title: 'ALK',
            debugShowCheckedModeBanner: false,
            theme: AlkTheme.light(),
            darkTheme: AlkTheme.dark(),
            themeMode: ThemeMode.system,
            locale: Locale(locale),
            supportedLocales: [
              const Locale('ar'),
              if (locale != 'ar') Locale(locale),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              // قفل التطبيق يلتفّ حول شجرة التنقّل كاملة: أي شاشة مدفوعة
              // (تذكير جرعة، اختصار صوتي، ...) تبقى خلف القفل.
              return Directionality(
                textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
                child: LockGate(
                  store: store,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: const RootGate(),
          );
        },
      ),
    );
  }
}

/// Initializes the store, then shows the lock screen when enabled.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  Timer? _syncTimer;
  Timer? _voiceReminderTimer;
  Timer? _preDoseVoiceTimer;
  bool _startupReminderChecked = false;

  static const _launchChannel = MethodChannel('alk/launch');

  /// ظ…ط±ط¬ط¹ ط§ظ„ظ…ط®ط²ظˆظ† (ظٹظڈظ‚ط±ط£ ظ…ط±ط© ظپظٹ initState ظ„ط£ظ† `context` ظ„ط§ ظٹظڈط³طھط®ط¯ظ… ظپظٹ dispose).
  late final SandyStore _store;

  @override
  void initState() {
    super.initState();
    final store = context.read<SandyStore>();
    _store = store;
    Future<void>.microtask(() => store.init());
    store.addListener(_onStoreChanged);
    // ط¶ط؛ط· ط§ظ„ظ…ط³طھط®ط¯ظ… ط¹ظ„ظ‰ ط¥ط´ط¹ط§ط± طھط°ظƒظٹط± â‡’ ظ†ط·ظ‚ ط§ظ„طھط°ظƒظٹط± ط¨طµظˆطھ ط¹ط§ظ„ظچ ظˆظپطھط­ ط´ط§ط´ط© ط§ظ„ط£ط¯ظˆظٹط©.
    NotificationService.instance.onReminderTap = _handleReminderPayload;
    // قفل التطبيق: عند فتحه يُنفَّذ ما طُلب أثناء القفل (فتح شاشة من تذكير،
    // اختصار صوتي) فلا يتخطى أي مسار القفل.
    AppLockState.instance.addListener(_onLockChanged);
    // Start continuous chronic-disease device monitoring once the store is
    // loaded: Health Connect polling + previously paired Bluetooth meters.
    _syncTimer = Timer(const Duration(seconds: 3), _startDeviceSync);
    // Launch shortcuts: "Hey Google, ط§ظپطھط­ ط§ظ„ظ…ط³ط§ط¹ط¯ ط§ظ„طµظˆطھظٹ ظپظٹ ALK" opens the
    // app directly on the voice-assistant listening screen.
    _launchChannel.setMethodCallHandler((call) {
      if (call.method == 'screen' && call.arguments == 'voice') {
        _openVoiceAssistant();
      }
      return Future.value();
    });
    _launchChannel.invokeMethod<String>('initialScreen').then((screen) {
      if (screen == 'voice') _openVoiceAssistant();
    }).catchError((_) {});
  }

  /// ظƒظ„ طھط؛ظٹظٹط± ظپظٹ ط§ظ„ط¨ظٹط§ظ†ط§طھ (ط¥ط¶ط§ظپط©/طھط¹ط¯ظٹظ„ ط¯ظˆط§ط،طŒ ظˆط¶ط¹ ظ‡ط§ط¯ط¦â€¦) ظٹظڈط¹ظٹط¯ ط¶ط¨ط· ظ…ط¤ظ‚ظ‘طھ ط§ظ„ظ†ط·ظ‚
  /// ط¹ظ„ظ‰ ط£ظ‚ط±ط¨ ظ…ظˆط¹ط¯ ط¬ط±ط¹ط©.
  void _onStoreChanged() {
    if (!mounted) return;
    _scheduleVoiceReminder();
  }

  /// ظٹظ†ط·ظ‚ ط§ظ„طھط°ظƒظٹط± ظپظٹ ظˆظ‚طھظ‡ ط£ظٹط¶ط§ظ‹ ط¹ظ†ط¯ظ…ط§ ظٹظƒظˆظ† ط§ظ„طھط·ط¨ظٹظ‚ ظ…ظپطھظˆط­ط§ظ‹: ظƒط¨ظٹط± ط§ظ„ط³ظ† ظ‚ط¯ ظ„ط§
  /// ظٹظ†ط¸ط± ط¥ظ„ظ‰ ط´ط§ط´ط© ط§ظ„ط¥ط´ط¹ط§ط±ط§طھطŒ ظˆط§ظ„طµظˆطھ ط£ط¶ظ…ظ† ظ„ظ„طھظ†ط¨ظٹظ‡.
  void _scheduleVoiceReminder() {
    _voiceReminderTimer?.cancel();
    _preDoseVoiceTimer?.cancel();
    if (!mounted) return;
    if (!_store.loaded || _store.data.quietMode) return;
    final now = DateTime.now();
    // Speak pre-dose "your dose is near" reminder 15 min before dose time
    // when app is in foreground (complements the background notification).
    final pre = nextPreDoseOccurrence(_store.medications, now);
    if (pre != null) {
      final preDelay = pre.at.difference(now);
      if (!preDelay.isNegative) {
        _preDoseVoiceTimer = Timer(preDelay, () {
          if (!mounted) return;
          final preMessage = localizedPreDoseReminderMessage(
            medicationId: pre.medication.id,
            medicationName: pre.medication.name,
            language: _store.languageTag,
            minutes: NotificationService.preDoseLeadMinutes,
          );
          VoiceService.instance
              .speakSlow(preMessage.spokenText,
                  languageTag: preMessage.languageTag)
              .ignore();
          _scheduleVoiceReminder();
        });
      }
    }
    final upcoming = nextDoseOccurrence(_store.medications, now);
    if (upcoming == null) return;
    var delay = upcoming.at.difference(now);
    if (delay.isNegative) delay = Duration.zero;
    _voiceReminderTimer = Timer(delay, () {
      if (!mounted) return;
      final message = localizedReminderMessage(
        medicationId: upcoming.medication.id,
        medicationName: upcoming.medication.name,
        language: _store.languageTag,
      );
      VoiceService.instance
          .speakSlow(message.spokenText, languageTag: message.languageTag)
          .ignore();
      // Reschedule for the next dose time.
      _scheduleVoiceReminder();
    });
  }

  /// ظ†ط·ظ‚ طھط°ظƒظٹط± ط§ظ„ط¥ط´ط¹ط§ط± (ط¬ط±ط¹ط© ط£ظˆ آ«ط§ظ‚طھط±ط¨ ظ…ظˆط¹ط¯ ط¯ظˆط§ط¦ظƒآ») ظˆظپطھط­ ط´ط§ط´ط© ط§ظ„ط£ط¯ظˆظٹط© ظ„طھط£ظƒظٹط¯
  /// ط§ظ„طھظ†ط§ظˆظ„ ط¨ط¶ط؛ط·ط© ظˆط§ط­ط¯ط©.
  void _handleReminderPayload(String payload) {
    // تنبيه غذائي أو تنبيه قياس حيوي: اقرأ التحذير بصوت بطيء مباشرة.
    if (payload.startsWith('food-alert|') ||
        payload.startsWith('vital-alert|')) {
      final body = payload.split('|').skip(2).join('|');
      if (!mounted || body.isEmpty) return;
      VoiceService.instance
          .speakSlow(body, languageTag: _store.languageTag)
          .ignore();
      return;
    }
    final parsed = ReminderTapPayload.parse(payload);
    if (parsed == null || !mounted) return;
    if (_store.patient.lockEnabled && AppLockState.instance.isLocked) {
      // لا تُفتح أي شاشة قبل المصادقة: يُنفَّذ الطلب بعد فتح القفل.
      AppLockState.instance.requestReminderAfterUnlock(payload);
      return;
    }
    final message = parsed.isPreDose
        ? localizedPreDoseReminderMessage(
            medicationId: parsed.medicationId,
            medicationName: parsed.medicationName,
            language: _store.languageTag,
            minutes: NotificationService.preDoseLeadMinutes,
          )
        : localizedReminderMessage(
            medicationId: parsed.medicationId,
            medicationName: parsed.medicationName,
            language: _store.languageTag,
          );
    VoiceService.instance
        .speakSlow(message.spokenText, languageTag: message.languageTag)
        .ignore();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MedicationsScreen()),
    );
  }

  /// ط¨ط¹ط¯ طھط­ظ…ظٹظ„ ط§ظ„ط¨ظٹط§ظ†ط§طھ: ظ‡ظ„ ط£ظڈط·ظ„ظ‚ ط§ظ„طھط·ط¨ظٹظ‚ ظ…ظ† ط¶ط؛ط· ط¹ظ„ظ‰ ط¥ط´ط¹ط§ط±طں ظˆظ‡ظ„ ط§ظ„طھط°ظƒظٹط±ط§طھ
  /// ظ…ظڈظپط¹ظژظ‘ظ„ط© ظ„ظƒظ† ط§ظ„ط®ظ„ظپظٹط© ظ…ط­ط¬ظˆط¨ط© (طµظ„ط§ط­ظٹط§طھ/ط¨ط·ط§ط±ظٹط©)طں ظˆط¶ط¨ط· ظ…ط¤ظ‚ظ‘طھ ط§ظ„ظ†ط·ظ‚.
  Future<void> _afterFirstLoad() async {
    _scheduleVoiceReminder();
    await _warnIfRemindersBlocked();
    if (!mounted) return;
    if (_store.dataUnreadable) _warnDataUnreadable();
    final payload =
        await NotificationService.instance.launchReminderPayload() ??
            NotificationService.instance.takePendingTapPayload();
    if (payload != null && mounted) _handleReminderPayload(payload);
  }

  /// طھط­ط°ظٹط± ظˆط§ط¶ط­ ط¹ظ†ط¯ظ…ط§ طھظƒظˆظ† ط§ظ„طھط°ظƒظٹط±ط§طھ ظ…ظڈظپط¹ظژظ‘ظ„ط© ظ„ظƒظ† ط§ظ„ظ‡ط§طھظپ ظٹظ…ظ†ط¹ظ‡ط§ ظپظٹ ط§ظ„ط®ظ„ظپظٹط©ط›
  /// ط¨ط¯ظˆظ† ظ‡ط°ظ‡ ط§ظ„ط±ط³ط§ظ„ط© ظٹط¨ظ‚ظ‰ ط§ظ„ظ…ط³طھط®ط¯ظ… ظٹظ†طھط¸ط± ط¥ط´ط¹ط§ط±ط§ظ‹ ظ„ط§ ظٹطµظ„ ظˆظ„ط§ ظٹط¹ط±ظپ ط§ظ„ط³ط¨ط¨.
  Future<void> _warnIfRemindersBlocked() async {
    final hasReminders =
        _store.medications.any((m) => m.reminderEnabled && !m.asNeeded);
    if (!hasReminders || _store.data.quietMode || !mounted) return;
    final canDeliver = await NotificationService.instance
        .canDeliverBackgroundNotifications()
        .catchError((_) => true);
    if (canDeliver || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(
          'طھط°ظƒظٹط±ط§طھ ط§ظ„ط£ط¯ظˆظٹط© ظ‚ط¯ ظ„ط§ طھطµظ„ ظپظٹ ط§ظ„ط®ظ„ظپظٹط© â€” ظ†ط­طھط§ط¬ ط¥ط°ظ† ط§ظ„ط¥ط´ط¹ط§ط±ط§طھ ظˆط§ط³طھط«ظ†ط§ط، ط§ظ„طھط·ط¨ظٹظ‚ ظ…ظ† طھط­ط³ظٹظ† ط§ظ„ط¨ط·ط§ط±ظٹط©'
              .tr,
        ),
        action: SnackBarAction(
          label: 'ط¥طµظ„ط§ط­'.tr,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ),
    );
  }

  /// تنفيذ الطلبات التي طُلبت أثناء القفل فور فتحه: فتح شاشة الدواء بعد ضغط
  /// تذكير، وفتح المساعد الصوتي القادم من اختصار النظام.
  void _onLockChanged() {
    if (!mounted || AppLockState.instance.isLocked) return;
    final payload = AppLockState.instance.takePendingReminderPayload();
    if (payload != null) _handleReminderPayload(payload);
    if (AppLockState.instance.takePendingVoiceAssistant()) {
      _openVoiceAssistant();
    }
  }

  /// تنبيه صريح عند تعذّر فتح ملف البيانات (ملف مشفَّر بمفتاح مفقود): التطبيق
  /// يمنع الكتابة فوق الملف حتى لا تضيع البيانات — والمستخدم يختار بين استيراد
  /// نسخة احتياطية أو البدء من جديد.
  void _warnDataUnreadable() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 15),
        content: Text(
          'تعذّر فتح ملف بياناتك على هذا الجهاز. لن يكتب التطبيق فوقه حتى لا '
                  'تضيع بياناتك — استورد نسخة احتياطية، أو اختر «حذف كل '
                  'البيانات» من الإعدادات للبدء من جديد.'
              .tr,
        ),
      ),
    );
  }

  bool _voiceOpened = false;

  void _startDeviceSync() {
    if (!mounted) return;
    final store = context.read<SandyStore>();
    if (store.loaded) DeviceSyncService.instance.start(store);
  }

  void _openVoiceAssistant() {
    final store = context.read<SandyStore>();
    // أثناء القفل لا يُفتح أي شيء: يُحفظ الطلب ويتنفّذ بعد المصادقة.
    if (store.patient.lockEnabled && AppLockState.instance.isLocked) {
      AppLockState.instance.requestVoiceAssistantAfterUnlock();
      return;
    }
    if (_voiceOpened || !mounted || !store.loaded) {
      // Store still loading â€” retry shortly.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted && context.read<SandyStore>().loaded) {
          _voiceOpened = false;
          _openVoiceAssistant();
        }
      });
      return;
    }
    _voiceOpened = true;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VoiceAssistantScreen()),
    );
  }

  @override
  void dispose() {
    if (NotificationService.instance.onReminderTap == _handleReminderPayload) {
      NotificationService.instance.onReminderTap = null;
    }
    // قراءة المخزن من الحقل (يُضبط في initState) — لا يصح استخدام `context`
    // في dispose: يرمي «Looking up a deactivated widget's ancestor is unsafe»
    // ويُفسد إلغاء المؤقتات التي تليه (فيتسرّب مؤقّت في الاختبارات).
    _store.removeListener(_onStoreChanged);
    AppLockState.instance.removeListener(_onLockChanged);
    _syncTimer?.cancel();
    _voiceReminderTimer?.cancel();
    _preDoseVoiceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    if (!store.loaded) {
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colors.primary),
              const SizedBox(height: 16),
              const Text('ALK'),
            ],
          ),
        ),
      );
    }
    // ط¨ط¹ط¯ ط£ظˆظ„ طھط­ظ…ظٹظ„: ظ†ط·ظ‚ طھط°ظƒظٹط± ط§ظ„ط¥ط´ط¹ط§ط± ط§ظ„ط°ظٹ ط£ط·ظ„ظ‚ ط§ظ„طھط·ط¨ظٹظ‚ (ط¥ظ† ظˆظڈط¬ط¯)طŒ طھط­ط°ظٹط± ظ…ظ†
    // ط­ط¬ط¨ ط§ظ„طھط°ظƒظٹط±ط§طھ ظپظٹ ط§ظ„ط®ظ„ظپظٹط©طŒ ظˆط¶ط¨ط· ظ…ط¤ظ‚ظ‘طھ ط§ظ„ظ†ط·ظ‚ ط¹ظ„ظ‰ ط£ظ‚ط±ط¨ ظ…ظˆط¹ط¯ ط¬ط±ط¹ط©.
    if (!_startupReminderChecked) {
      _startupReminderChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _afterFirstLoad().ignore();
      });
    }
    return const HomeScreen();
  }
}
