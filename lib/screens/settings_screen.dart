import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/backup_service.dart';
import '../screens/emergency_screen.dart';
import 'privacy_screen.dart';
import '../services/voice_service.dart';
import '../services/feedback_service.dart';
import '../services/update_service.dart';
import '../services/deepseek_service.dart';
import '../services/dictionary_translation_service.dart';
import '../services/notification_service.dart';
import '../state/sandy_store.dart';
import '../storage/sandy_repository.dart';
import '../theme/alk_theme.dart';

/// Settings screen — language, reminders, backups and data controls.
/// Port of the settings section of the RN app's More tab.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('الإعدادات'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _VoiceSpeedTile(),
          SizedBox(height: 8),
          _QuietModeTile(),
          SizedBox(height: 8),
          _NotificationsStatusTile(),
          SizedBox(height: 8),
          _AppLockTile(),
          SizedBox(height: 8),
          _DeepSeekTile(),
          SizedBox(height: 8),
          _TranslationTile(),
          SizedBox(height: 8),
          _DataStorageTile(),
          SizedBox(height: 8),
          _PrivacyTile(),
          SizedBox(height: 8),
          _EmergencyTile(),
          SizedBox(height: 8),
          _FeedbackTile(),
          SizedBox(height: 8),
          _BackupTiles(),
          SizedBox(height: 8),
          _UpdateTile(),
          SizedBox(height: 8),
          _ResetTile(),
          SizedBox(height: 24),
          _Disclaimer(),
        ],
      ),
    );
  }
}

class _VoiceSpeedTile extends StatefulWidget {
  const _VoiceSpeedTile();
  @override
  State<_VoiceSpeedTile> createState() => _VoiceSpeedTileState();
}

class _VoiceSpeedTileState extends State<_VoiceSpeedTile> {
  double _rate = 0.52;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await VoiceService.instance.loadPreferences();
    if (!mounted) return;
    setState(() {
      _rate = VoiceService.instance.preferences.rate;
      _loaded = true;
    });
  }

  Future<void> _save(double v) async {
    setState(() => _rate = v);
    final cur = VoiceService.instance.preferences;
    await VoiceService.instance.savePreferences(cur.copyWith(rate: v));
  }

  Future<void> _preview() async {
    final store = context.read<SandyStore>();
    await VoiceService.instance.speak(
        'مرحبا. سأتحدث معك ببطء ووضوح. هل تسمعني جيدا؟'.tr,
        languageTag: store.languageTag,
        slow: true);
  }

  String _label() {
    if (_rate <= 0.42) return 'بطيء جدا'.tr;
    if (_rate <= 0.55) return 'بطيء - مريح لكبار السن'.tr;
    if (_rate <= 0.75) return 'متوسط'.tr;
    return 'سريع'.tr;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('سرعة الصوت'.tr,
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                Text(_label()),
              ],
            ),
            if (_loaded)
              Slider(
                  value: _rate,
                  min: 0.3,
                  max: 1.0,
                  divisions: 14,
                  label: _label(),
                  onChanged: _save),
            Row(
              children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _preview,
                        icon: const Icon(Icons.volume_up),
                        label: Text('جرّب الصوت'.tr))),
              ],
            ),
            Text('القيمة الافتراضية بطيئة 0.52 لتناسب كبار السن.'.tr,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _QuietModeTile extends StatelessWidget {
  const _QuietModeTile();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.do_not_disturb_on_outlined),
        title: Text('الوضع الهادئ'.tr),
        subtitle: Text('تعطيل تذكيرات الأدوية مؤقتًا'.tr),
        value: store.data.quietMode,
        onChanged: (v) => store.setQuietMode(v),
      ),
    );
  }
}

class _AppLockTile extends StatelessWidget {
  const _AppLockTile();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.lock_outline),
        title: Text('قفل التطبيق'.tr),
        subtitle: Text('فتح ببصمة الإصبع أو رمز الجهاز'.tr),
        value: store.patient.lockEnabled,
        onChanged: (v) => store.setPatientLock(v),
      ),
    );
  }
}

/// Allows the user to enter their own DeepSeek API key so the app can use
/// DeepSeek AI chat. The key is stored locally and shown masked.
class _DeepSeekTile extends StatefulWidget {
  const _DeepSeekTile();

  @override
  State<_DeepSeekTile> createState() => _DeepSeekTileState();
}

class _DeepSeekTileState extends State<_DeepSeekTile> {
  @override
  void initState() {
    super.initState();
    DeepSeekService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final service = DeepSeekService.instance;
    final hasKey = service.hasKey;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.smart_toy_outlined),
        title: Text('التسجيل في الذكاء الآلي'.tr),
        subtitle: Text(hasKey
            ? '${'مفعل · المفتاح:'} ${service.maskedKey}'
            : 'أدخل مفتاح DeepSeek الخاص بك ليتحدث التطبيق معك'.tr),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _configure(context),
      ),
    );
  }

  Future<void> _configure(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => _DeepSeekKeyDialog(),
    );
  }
}

class _DeepSeekKeyDialog extends StatefulWidget {
  @override
  State<_DeepSeekKeyDialog> createState() => _DeepSeekKeyDialogState();
}

class _DeepSeekKeyDialogState extends State<_DeepSeekKeyDialog> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await DeepSeekService.instance.saveKey(_controller.text);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final service = DeepSeekService.instance;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('الذكاء الآلي (DeepSeek)'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'سجّل بحساب DeepSeek واحصل على مفتاح API من منصتك، ثم الصقه هنا '
                    'ليستطيع التطبيق التحدث معك عبر الإنترنت. عند غياب المفتاح يعمل '
                    'التطبيق محلياً دون ذكاء آلي.'
                .tr,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            // السرّ لا يُعرض مكشوفاً: يُخفى أثناء الكتابة، ولا يُعبَّأ الحقل
            // بالمفتاح المحفوظ (يظهر الجزء الأخير منه في نص المساعدة).
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            maxLines: 1,
            decoration: InputDecoration(
              labelText: 'مفتاح DeepSeek API'.tr,
              hintText: 'sk-...',
              helperText: service.hasKey
                  ? '${'المفتاح الحالي:'} ${service.maskedKey}'
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'يُخزَّن المفتاح على جهازك فقط ولا يُرسل إلا إلى DeepSeek عند الدردشة.'
                .tr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('إلغاء'.tr),
        ),
        TextButton(
          onPressed: () async {
            await DeepSeekService.instance.saveKey('');
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text('حذف المفتاح'.tr),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('حفظ'.tr),
        ),
      ],
    );
  }
}

/// Lets the user control how long recorded (time-series) data is kept before
/// it is automatically deleted, and shows the storage space currently used.
class _DataStorageTile extends StatefulWidget {
  const _DataStorageTile();

  @override
  State<_DataStorageTile> createState() => _DataStorageTileState();
}

class _DataStorageTileState extends State<_DataStorageTile> {
  static const _options = <int, String>{
    0: 'الاحتفاظ للأبد',
    30: '30 يومًا',
    60: '60 يومًا',
    90: '90 يومًا',
    180: '180 يومًا',
    365: 'سنة (365 يومًا)',
  };

  int? _size;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  Future<void> _refreshSize() async {
    final bytes = await SandyRepository().dataFileSizeBytes();
    if (mounted) setState(() => _size = bytes);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} ${'م.ب'.tr}';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} ${'ك.ب'.tr}';
    }
    return '$bytes ${'بايت'.tr}';
  }

  Future<void> _pickRetention(SandyStore store) async {
    final current = store.data.dataRetentionDays;
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _options.entries
              .map((entry) => ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(entry.value.tr),
                    trailing:
                        entry.key == current ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(context).pop(entry.key),
                  ))
              .toList(),
        ),
      ),
    );
    if (selected == null || selected == current) return;
    setState(() => _busy = true);
    final removed = await store.setDataRetentionDays(selected);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _refreshSize();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        selected == 0
            ? 'تم ضبط الاحتفاظ: للأبد'.tr
            : '${'تم ضبط الاحتفاظ:'} ${_options[selected]!.tr}، ${'حُذف'} $removed ${'سجل قديم'}'
                .tr,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    final days = store.data.dataRetentionDays;
    final label = _options[days] ?? (_options[0]!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: Text('مساحة البيانات والتخزين'.tr),
              subtitle: Text(
                '${'الاحتفاظ:'} ${label.tr}\n'
                '${'المساحة المستخدمة:'} ${_busy ? '…' : (_size == null ? '…' : _formatBytes(_size!))}',
              ),
              isThreeLine: true,
              onTap: _busy ? null : () => _pickRetention(store),
            ),
          ],
        ),
      ),
    );
  }
}

/// أقصى حجم مقبول لملف نسخة احتياطية يُستورَد (5 ميغابايت): ملف أكبر من ذلك
/// ليس نسخة احتياطية واقعية، ويمنع استهلاك الذاكرة/تجميد الواجهة.
const int _maxBackupBytes = 5 * 1024 * 1024;

class _BackupTiles extends StatelessWidget {
  const _BackupTiles();

  @override
  Widget build(BuildContext context) {
    final store = context.read<SandyStore>();
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: Text('تصدير نسخة احتياطية (JSON)'.tr),
            onTap: () async {
              final path = await const BackupService()
                  .exportBackup(store.exportBackupJson());
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(path == null
                      ? 'تعذر تصدير النسخة الاحتياطية'.tr
                      : 'تم إنشاء ملف النسخة الاحتياطية'.tr),
                ));
              }
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: Text('استيراد نسخة احتياطية (JSON)'.tr),
            onTap: () async {
              final raw = await const BackupService().pickAndReadBackup();
              if (raw == null) return;
              // حدّ حجم واقعي: ملف أكبر من ذلك ليس نسخة احتياطية للتطبيق
              // (يمنع تجميد الواجهة/استهلاك الذاكرة من ملف ضخم).
              if (raw.length > _maxBackupBytes) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('ملف النسخة الاحتياطية كبير جداً'.tr),
                  ));
                }
                return;
              }
              if (!context.mounted) return;
              // تأكيد صريح: ملف النسخة الاحتياطية يستبدل بيانات المريض الحالية.
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text('استيراد نسخة احتياطية؟'.tr),
                  content: Text(
                          'سيتم استبدال الأدوية والقياسات واليوميات الحالية ببيانات الملف المختار. لا يمكن التراجع.'
                              .tr),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text('إلغاء'.tr),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text('استيراد'.tr),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              try {
                final result = await store.importBackupJson(raw);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        '${'تم الاستيراد:'} ${result.medications} ${'دواء'}، ${result.vitals} ${'قياس'}'
                            .tr),
                  ));
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('ملف النسخة الاحتياطية غير صالح'.tr),
                  ));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

/// بلاطة فحص التحديثات: تفحص GitHub Releases وتعرض حوار التحديث.
/// قبل ضبط [UpdateService.githubOwner] تعرض رقم النسخة المثبتة فقط.
class _UpdateTile extends StatefulWidget {
  const _UpdateTile();

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  String _current = '…';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    UpdateService().currentVersion().then((v) {
      if (mounted) setState(() => _current = v);
    });
  }

  Future<void> _check() async {
    if (_checking) return;
    if (!UpdateService.isConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${'الإصدار الحالي:'.tr} $_current')),
      );
      return;
    }
    setState(() => _checking = true);
    try {
      await UpdateService.showUpdateDialog(context);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _checking
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.system_update),
        title: Text('فحص التحديثات'.tr),
        subtitle: Text(
          _checking
              ? 'جارٍ التحقق…'.tr
              : '${'الإصدار الحالي:'.tr} $_current\n${'تحقق من وجود إصدار جديد'.tr}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: _checking ? null : _check,
      ),
    );
  }
}


class _ResetTile extends StatelessWidget {
  const _ResetTile();

  @override
  Widget build(BuildContext context) {
    final store = context.read<SandyStore>();
    return Card(
      child: ListTile(
        leading: Icon(Icons.delete_forever,
            color: Theme.of(context).colorScheme.error),
        title: Text('حذف كل البيانات'.tr),
        onTap: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('حذف كل البيانات؟'.tr),
              content: Text(
                  'سيتم حذف الأدوية والقياسات واليوميات نهائيًا. لا يمكن التراجع.'
                      .tr),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('إلغاء'.tr),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('حذف'.tr),
                ),
              ],
            ),
          );
          if (ok == true) await store.resetAll();
        },
      ),
    );
  }
}

/// Lets the user reach the developer on WhatsApp with a pre-filled message.
/// Emergency contacts management — family/caregivers + ambulance hotline.
class _EmergencyTile extends StatelessWidget {
  const _EmergencyTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.emergency, color: Color(0xFFC94F4F)),
        title: Text('الطوارئ'.tr),
        subtitle: Text('أشخاص يُتواصل معهم وقت الخطر ورقم الإسعاف'.tr),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const EmergencyScreen()),
        ),
      ),
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.chat_bubble_outline, color: Colors.green),
        title: Text('واتساب المطور'.tr),
        subtitle: InkWell(
          onTap: () => const FeedbackService().openWhatsApp(),
          child: const Text(
            'https://wa.me/972592055302',
            style: TextStyle(
              color: Color(0xFF1F8A8A),
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFF1F8A8A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => const FeedbackService().openWhatsApp(),
      ),
    );
  }
}

/// Live status of everything required for background dose reminders to fire:
/// the notification permission, exact alarms and battery optimization —
/// with one-tap fixes for each. Reminders silently stop working when any of
/// these is missing (common on Xiaomi/Huawei/Samsung power saving modes).
class _NotificationsStatusTile extends StatefulWidget {
  const _NotificationsStatusTile();

  @override
  State<_NotificationsStatusTile> createState() =>
      _NotificationsStatusTileState();
}

class _NotificationsStatusTileState extends State<_NotificationsStatusTile> {
  bool _loading = true;
  bool _notificationsOn = false;
  bool _batteryExempt = true;
  bool _exactAlarmsOn = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final service = NotificationService.instance;
    final notif = await service.requestPermission().then<bool>(
          (granted) => granted,
          onError: (_) => false,
        );
    final exact = await service.areExactAlarmsAllowed();
    final battery = await service.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _notificationsOn = notif;
      _batteryExempt = battery;
      _exactAlarmsOn = exact;
      _loading = false;
    });
  }

  Future<void> _openDetails() async {
    final service = NotificationService.instance;
    final store = context.read<SandyStore>();
    await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('حالة الإشعارات الخلفية'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusRow(_notificationsOn, 'صلاحية الإشعارات'.tr),
            const SizedBox(height: 8),
            _statusRow(_batteryExempt, 'استثناء من تحسين البطارية'.tr),
            const SizedBox(height: 8),
            _statusRow(_exactAlarmsOn, 'التنبيهات الدقيقة'.tr),
            const SizedBox(height: 12),
            Text(
              'يُذكّرك التطبيق قبل موعد الدواء بربع ساعة («اقترب موعد دوائك») '
                      'وعند الموعد نفسه، واضغط على الإشعار لتسمع التذكير بصوت عالٍ.'
                  .tr,
            ),
            const SizedBox(height: 8),
            Text(
              'لتعمل التذكيرات في الخلفية يجب السماح بالإشعارات واستثناء '
                      'التطبيق من تحسين البطارية (مهم جداً على شاومي وهواوي وسامسونج).'
                  .tr,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await service.requestIgnoreBatteryOptimizations();
              _refresh();
            },
            child: Text('طلب استثناء البطارية'.tr),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              openAppSettings();
            },
            child: Text('فتح إعدادات النظام'.tr),
          ),

          // تنبيه تجريبي خلال ~65 ثانية عبر نفس قناة الجرعات (صوت + اهتزاز +
          // شاشة كاملة) — دليل عملي فوري أن التذكيرات تعمل في الخلفية على هذا
          // الجهاز؛ إن لم يصله المستخدم فالمشكلة في صلاحية ما بالأسفل.
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                final message = await store.sendOneMinuteTestReminder();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    duration: const Duration(seconds: 10),
                  ),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('تعذّر إرسال التنبيه التجريبي — أعد المحاولة'.tr),
                  ),
                );
              }
            },
            icon: const Icon(Icons.notifications_active),
            label: Text('إرسال تنبيه تجريبي الآن'.tr),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('تم'.tr),
          ),
        ],
      ),
    );
    // بعد أي إصلاح للصلاحيات/البطارية: إعادة جدولة كل التذكيرات فوراً حتى
    // لا ينتظر المستخدم تشغيلاً آخر (وهذا ما كان يمنع وصول الإشعار أصلاً).
    if (!mounted) return;
    await store.rescheduleAllReminders(requestPermissions: true);
    if (mounted) _refresh();
  }

  Widget _statusRow(bool ok, String label) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.error,
          color: ok ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text('$label: ${ok ? 'مسموح' : 'غير مسموح'}')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final allOk = _notificationsOn && _batteryExempt && _exactAlarmsOn;
    return Card(
      child: ListTile(
        leading: _loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                allOk ? Icons.notifications_active : Icons.notifications_off,
                color: allOk ? Colors.green : Colors.orange,
              ),
        title: Text('الإشعارات الخلفية'.tr),
        subtitle: Text(_loading
            ? 'جارٍ التحقق…'.tr
            : allOk
                ? 'تعمل — التذكيرات ستصل حتى والتطبيق مغلق'.tr
                : 'يوجد نقص في الصلاحيات — اضغط للإصلاح'.tr),
        trailing: const Icon(Icons.chevron_right),
        onTap: _loading ? null : _openDetails,
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Card(
      // خلفية ناعمة تتبع سطوع الثيم: كانت ثابتة فاتحة فتظهر كمربع أبيض فارغ
      // في الوضع الداكن (نص فاتح على خلفية فاتحة).
      color: AlkPalette.of(context).goldSoft,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'ALK لا يقدم تشخيصًا طبيًا. تواصل مع طبيبك عند وجود عرض مقلق.'.tr,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// بلاطة سياسة الخصوصية — تفتح النص الكامل داخل التطبيق دون إنترنت.
class _PrivacyTile extends StatelessWidget {
  const _PrivacyTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.privacy_tip_outlined),
        title: Text('سياسة الخصوصية'.tr),
        subtitle: Text('بياناتك على جهازك فقط — اقرأ التفاصيل'.tr),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PrivacyPolicyScreen(),
          ),
        ),
      ),
    );
  }
}

/// حالة قاموس مفردات التطبيق: يُترجم مرة واحدة إلى لغة الهاتف ويُخزَّن على
/// الجهاز، فتُعرض الواجهة بلغة الهاتف دون إعادة ترجمة في كل تشغيل.
class _TranslationTile extends StatelessWidget {
  const _TranslationTile();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    final service = DictionaryTranslationService.instance;
    final deviceLanguage = DictionaryTranslationService.deviceLanguageTag();
    final displayLanguage = AppStrings.current;
    final isArabic = displayLanguage.startsWith('ar');
    final String status;
    if (isArabic) {
      status = 'الواجهة بالعربية (لغة المصدر)'.tr;
    } else if (service.running) {
      status =
          'جارٍ تجهيز الترجمة: ${service.translatedCount} من ${service.sourceCount}'
              .tr;
    } else if (service.isComplete) {
      status =
          'الترجمة جاهزة ومخزّنة على الجهاز (${service.translatedCount})'.tr;
    } else if (service.lastError != null) {
      status = 'تعذّر تجهيز ترجمة القاموس — الواجهة بالعربية'.tr;
    } else {
      status = 'لم تُجهَّز الترجمة بعد'.tr;
    }
    final canRetry = !isArabic && !service.running && !service.isComplete;
    final subtitle =
        'الجهاز: $deviceLanguage • الواجهة: $displayLanguage • $status';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.translate),
        title: Text('لغة الواجهة'.tr),
        subtitle: Text(subtitle),
        trailing: canRetry
            ? TextButton(
                onPressed: () =>
                    service.retry(onChanged: () => store.requestRebuild()),
                child: Text('إعادة المحاولة'.tr),
              )
            : null,
      ),
    );
  }
}
