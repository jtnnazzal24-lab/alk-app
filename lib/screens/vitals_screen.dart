import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/vital_advice.dart';
import '../logic/vital_quality.dart';
import '../l10n/app_strings.dart';
import '../models/sandy_data.dart';
import '../services/bluetooth_device_service.dart';
import '../services/device_sync_service.dart';
import '../services/health_device_service.dart';
import '../state/sandy_store.dart';
import '../widgets/speak_button.dart';
import 'nutrition_screen.dart';

/// لون موحّد لكل مستوى نتيجة تفسير (نفس المعنى في كل الشاشات).
Color vitalLevelColor(String level) {
  switch (level) {
    case VitalLevel.normal:
      return const Color(0xFF2E7D32); // أخضر
    case VitalLevel.borderline:
      return const Color(0xFFE08A00); // برتقالي
    case VitalLevel.abnormal:
      return const Color(0xFFC62828); // أحمر
    case VitalLevel.emergency:
      return const Color(0xFF8E0000); // أحمر غامق
    default:
      return Colors.grey;
  }
}

/// أيقونة النتيجة المقابلة للمستوى.
IconData vitalLevelIcon(String level) {
  switch (level) {
    case VitalLevel.normal:
      return Icons.check_circle_outline;
    case VitalLevel.borderline:
      return Icons.info_outline;
    case VitalLevel.abnormal:
      return Icons.warning_amber_rounded;
    case VitalLevel.emergency:
      return Icons.local_hospital_outlined;
    default:
      return Icons.help_outline;
  }
}

/// Vitals tab — record and view blood pressure, sugar, pulse and SpO2
/// readings. Supports manual entry, Health Connect sync (wearables) and live
/// Bluetooth LE meters (continuous chronic-disease monitoring).
class VitalsScreen extends StatefulWidget {
  const VitalsScreen({super.key});

  @override
  State<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends State<VitalsScreen> {
  String _kind = VitalKind.pressure;
  final _valueController = TextEditingController();
  bool _syncing = false;
  StreamSubscription<VitalReading>? _bleSub;

  /// سياق قياس السكر عند الإدخال اليدوي (صائم / بعد الأكل / عشوائي) —
  /// يُحفظ كنص مع القيمة ليبقى مخطط JSON موحّداً مع تطبيق React Native.
  String _sugarContext = SugarContext.random;

  @override
  void initState() {
    super.initState();
    // Instant interpretation when a connected meter pushes a new measurement.
    // النطق والإشعار يُديرهما المخزن بعد قبول القراءة وحفظها
    // (انظر SandyStore._announceVitalAdvice) فلا يتكرر الصوت هنا.
    _bleSub =
        DeviceSyncService.instance.bleReadings.listen(_onDeviceReading);
  }

  /// يعرض نتيجة القراءة القادمة من الجهاز: مرفوضة/غير صالحة بالرمادي، أو
  /// مفسَّرة بلونها (طبيعي/انتبه/غير مقبول/خطر عاجل).
  void _onDeviceReading(VitalReading reading) {
    if (!mounted) return;
    if (VitalQualityPolicy.assess(kind: reading.kind, value: reading.value) ==
        null) {
      // قيمة فيزيائياً مستحيلة — تُرفض قبل الحفظ فلا تُعرض كتوصية طبية.
      _showRawSnackBar(
        'قراءة غير صالحة من الجهاز (${_getLabelFor(reading.kind)}): '
        '${reading.value} — تم تجاهلها وإعادة القياس',
        color: vitalLevelColor(VitalLevel.unknown),
      );
      return;
    }
    final store = context.read<SandyStore>();
    final advice = adviseVital(
      kind: reading.kind,
      value: reading.value,
      conditionName: store.patient.conditionName,
    );
    _showAdviceSnackBar(advice, prefix: 'قياس جديد من الجهاز');
  }

  /// سنك بار ملوّن يعرض نتيجة مفسَّرة (اللون حسب مستوى الخطورة).
  void _showAdviceSnackBar(VitalAdvice advice, {required String prefix}) {
    final text = advice.level == VitalLevel.normal ||
            advice.level == VitalLevel.unknown
        ? '$prefix: ${vitalKindLabel(advice.kind)} ${advice.value} — '
            '${advice.title}'
        : '$prefix. ${advice.spokenText}';
    _showRawSnackBar(
      text,
      color: vitalLevelColor(advice.level),
      seconds: advice.level == VitalLevel.normal ? 4 : 8,
    );
  }

  void _showRawSnackBar(String text, {required Color color, int seconds = 5}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      content: Text(
        text.tr,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      duration: Duration(seconds: seconds),
    ));
  }

  @override
  void dispose() {
    _valueController.dispose();
    _bleSub?.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _valueController.text.trim();
    if (raw.isEmpty) return;
    final store = context.read<SandyStore>();
    // السكر يُحفظ مع سياقه («98 صائم» / «160 بعد الأكل») ليُفسَّر بالعتبة
    // الصحيحة، وأرقام بقية القياسات تبقى كما كتبها المستخدم.
    final value = _kind == VitalKind.sugar
        ? '$raw${SugarContext.suffix(_sugarContext)}'
        : raw;
    await store.addVital(_kind, value);
    _valueController.clear();
    if (!mounted) return;
    _showAdviceSnackBar(
      adviseVital(
        kind: _kind,
        value: value,
        conditionName: store.patient.conditionName,
      ),
      prefix: 'تم حفظ القراءة',
    );
  }

  Future<void> _syncFromHealthConnect() async {
    final service = HealthConnectService();
    final store = context.read<SandyStore>();

    final granted = await service.requestAuthorization();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('لم يُمنح الإذن للوصول إلى Health Connect'.tr),
      ));
      return;
    }

    setState(() => _syncing = true);
    final readings = await service.fetchReadings();
    final added = await store.addVitalsImported(readings);
    if (!mounted) return;
    setState(() => _syncing = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(added == 0
          ? 'لا توجد قراءات جديدة'.tr
          : 'تمت إضافة $added قراءة من جهازك'.tr),
    ));
  }

  /// تسمية نوع القياس بالعربية (موحّدة مع `vitalKindLabel`).
  String _getLabelFor(String kind) => vitalKindLabel(kind).tr;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    final theme = Theme.of(context);
    final vitals = store.vitals;

    return Scaffold(
      appBar: AppBar(
        title: Text('القياسات'.tr),
        actions: [
          SpeakButton(
            text: 'هذه صفحة القياسات. سجل ضغطك أو سكرك أو نبضك هنا. سأقرأ لك النتيجة ببطء ووضوح.'.tr,
            languageTag: store.languageTag,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // رأس قابل للتمرير: استمارة الإدخال + بطاقة النتيجة + بطاقات
          // الأجهزة، ثم قائمة القياسات (lazy) تحته — يمنع أي فيض طولي.
          SliverToBoxAdapter(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _kindButton('ضغط'.tr, 'pressure'),
                      const SizedBox(width: 8),
                      _kindButton('سكر'.tr, 'sugar'),
                      const SizedBox(width: 8),
                      _kindButton('نبض'.tr, 'pulse'),
                      const SizedBox(width: 8),
                      _kindButton('أكسجين'.tr, 'spo2'),
                    ],
                  ),
                  if (_kind == VitalKind.sugar) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'قبل القياس:'.tr,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        for (final ctx in [
                          SugarContext.random,
                          SugarContext.fasting,
                          SugarContext.afterMeal,
                        ])
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 6),
                            child: ChoiceChip(
                              label: Text(SugarContext.label(ctx).tr),
                              selected: _sugarContext == ctx,
                              onSelected: (_) =>
                                  setState(() => _sugarContext = ctx),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      'الصائم يُقيَّم بعتبة أقل من العشوائي — اختر ما يناسب قياسك.'
                          .tr,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _valueController,
                    decoration: InputDecoration(labelText: 'القيمة'.tr),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: Text('حفظ القراءة'.tr),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _syncing ? null : _syncFromHealthConnect,
                      icon: _syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text('مزامنة من جهازي'.tr),
                    ),
                  ),
                ],
              ),
            ),
          ),
                const _LatestResultsCard(),
                const _DevicesCard(),
              ],
            ),
          ),
          if (vitals.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('لا توجد قراءات بعد'.tr)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(
                  left: 16, right: 16, bottom: 24),
              sliver: SliverList.builder(
                itemCount: vitals.length,
                itemBuilder: (context, index) {
                      final v = vitals[index];
                      final flagged = v.quality == VitalQuality.check;
                      final advice = adviseReading(
                        v,
                        conditionName: store.patient.conditionName,
                      );
                      final color = vitalLevelColor(advice.level);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            vitalLevelIcon(advice.level),
                            color: color,
                          ),
                          title: Text(
                            '${_getLabelFor(v.kind)} — '
                            '${VitalLevel.label(advice.level).tr}',
                            style: TextStyle(color: color),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                flagged
                                    ? '${VitalSource.label(v.source)} — '
                                        '${'تحتاج تدقيقاً'.tr}'
                                    : VitalSource.label(v.source),
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                advice.title.tr,
                                style: TextStyle(
                                    color: color,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          trailing: Text(v.value,
                              style: theme.textTheme.titleMedium),
                          onLongPress: () => _showReadingInfo(v),
                        ),
                      );
                    },
                  ),
              ),
        ],
      ),
    );
  }

  void _showReadingInfo(VitalReading v) {
    final store = context.read<SandyStore>();
    final advice =
        adviseReading(v, conditionName: store.patient.conditionName);
    final color = vitalLevelColor(advice.level);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            '${_getLabelFor(v.kind)} — ${VitalLevel.label(advice.level).tr}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('القيمة: ${v.value}'.tr),
            const SizedBox(height: 8),
            Text('المصدر: ${VitalSource.label(v.source)}'.tr),
            if (v.deviceName != null) Text('الجهاز: ${v.deviceName}'.tr),
            const SizedBox(height: 8),
            Text(advice.title.tr,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(advice.message.tr),
            if (advice.conditionNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(advice.conditionNote.tr,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Text(VitalQualityPolicy.uncertaintyNote(v.kind).tr),
            const SizedBox(height: 8),
            Text(
              'إرشاد تثقيفي فقط — لا يغني عن استشارة طبيبك ولا يحل محل التشخيص.'
                  .tr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          SpeakButton(
            text: advice.spokenText,
            languageTag: store.languageTag,
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('تم'.tr),
          ),
        ],
      ),
    );
  }

  Widget _kindButton(String label, String kind) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () => setState(() => _kind = kind),
        style: OutlinedButton.styleFrom(
          backgroundColor: _kind == kind
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
        ),
        child: Text(label),
      ),
    );
  }
}

/// بطاقة «نتيجة قياساتك»: أحدث قياس من كل نوع مفسَّر بلونه، وتوجيه مفصّل
/// (رسالة + تمارين + أغذية + زر اتصال بالطبيب) لأسوأ نتيجة بينها.
class _LatestResultsCard extends StatelessWidget {
  const _LatestResultsCard();

  /// ترتيب الخطورة (الأعلى أسوأ).
  static const _rank = <String, int>{
    VitalLevel.normal: 0,
    VitalLevel.unknown: 1,
    VitalLevel.borderline: 2,
    VitalLevel.abnormal: 3,
    VitalLevel.emergency: 4,
  };

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    final theme = Theme.of(context);
    final advices = latestVitalAdvices(
      store.vitals,
      conditionName: store.patient.conditionName,
    );
    if (advices.isEmpty) return const SizedBox.shrink();

    var worst = advices.first;
    for (final a in advices) {
      if (_rank[a.level]! > _rank[worst.level]!) worst = a;
    }

    // نص مضغوط يُقرأ ببطء: سطر لكل قياس + تفصيل أسوأ نتيجة.
    final spoken = StringBuffer('نتيجة قياساتك. ');
    for (final a in advices) {
      spoken.write('${vitalKindLabel(a.kind)} ${a.value}: ${a.title}. ');
    }
    if (worst.level != VitalLevel.normal) spoken.write(worst.spokenText);

    final hasDoctor = store.patient.doctorPhone.trim().isNotEmpty;
    final callLabel = worst.emergency
        ? 'اتصل بالإسعاف الآن'.tr
        : hasDoctor
            ? 'اتصل بطبيبك'.tr
            : 'اتصل بجهة الطوارئ'.tr;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite_outline,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('نتيجة قياساتك'.tr,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                SpeakButton(
                  text: spoken.toString().tr,
                  languageTag: store.languageTag,
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final a in advices) _ResultRow(advice: a),
            if (worst.level != VitalLevel.normal) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: vitalLevelColor(worst.level).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${vitalKindLabel(worst.kind)} ${worst.value}: '
                          '${worst.title}'
                          .tr,
                      style: TextStyle(
                        color: vitalLevelColor(worst.level),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(worst.message.tr),
                    if (worst.conditionNote.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(worst.conditionNote.tr,
                          style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (worst.exercises.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('تمارين مقترحة لك:'.tr,
                    style: theme.textTheme.titleSmall),
                for (final e in worst.exercises)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_walk, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text(e.tr)),
                      ],
                    ),
                  ),
              ],
              if (worst.foods.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('أغذية تساعدك على التحسين:'.tr,
                    style: theme.textTheme.titleSmall),
                for (final f in worst.foods)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.restaurant_menu, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text(f.tr)),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const NutritionScreen()),
                  ),
                  icon: const Icon(Icons.menu_book),
                  label: Text('افتح نصائح التغذية'.tr),
                ),
              ],
              if (worst.needsDoctor) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: vitalLevelColor(worst.level),
                    ),
                    onPressed: () => _dialPhone(
                      context,
                      dialNumberFor(store, emergency: worst.emergency),
                    ),
                    icon: const Icon(Icons.phone),
                    label: Text(callLabel),
                  ),
                ),
                if (worst.emergency && hasDoctor)
                  TextButton.icon(
                    onPressed: () => _dialPhone(
                        context, store.patient.doctorPhone),
                    icon: const Icon(Icons.medical_services_outlined),
                    label: Text('اتصل بطبيبك'.tr),
                  ),
              ],
            ],
            const SizedBox(height: 10),
            Text(
              'إرشاد تثقيفي فقط من مرجع عام — لا يغني عن استشارة طبيبك ولا '
                  'يحل محل التشخيص.'
                  .tr,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// صف واحد في بطاقة النتيجة: الأيقونة + النوع + القيمة + شارة المستوى.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.advice});

  final VitalAdvice advice;

  @override
  Widget build(BuildContext context) {
    final color = vitalLevelColor(advice.level);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(vitalLevelIcon(advice.level), color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(vitalKindLabel(advice.kind).tr)),
          Text(advice.value,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              VitalLevel.label(advice.level).tr,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// الرقم المناسب للاتصال حسب شدة النتيجة: مع الخطر العاجل يُقدَّم رقم
/// الإسعاف ثم جهة الطوارئ ثم رقم الطبيب؛ وعند القراءة غير المقبولة يبدأ
/// برقم طبيبه إن وُجد. '' = لا يوجد رقم محفوظ (يظهر تنبيه عند الضغط).
String dialNumberFor(SandyStore store, {required bool emergency}) {
  final doctor = store.patient.doctorPhone.trim();
  final ambulance = store.ambulanceNumber.trim();
  final contact = store.emergencyContacts.isEmpty
      ? ''
      : store.emergencyContacts.first.phone.trim();
  final order = emergency
      ? [ambulance, contact, doctor]
      : [doctor, contact, ambulance];
  for (final phone in order) {
    if (phone.isNotEmpty) return phone;
  }
  return '';
}

/// يفتح تطبيق الهاتف لطلب [phone]؛ إن غاب الرقم يعرض تنبيه بإضافة رقم
/// الطوارئ من شاشة الطوارئ.
Future<void> _dialPhone(BuildContext context, String phone) async {
  if (phone.trim().isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'لا يوجد رقم محفوظ — أضف رقم الطوارئ أو رقم طبيبك أولاً.'.tr,
        ),
      ));
    }
    return;
  }
  try {
    final ok = await launchUrl(
      Uri(scheme: 'tel', path: phone.trim()),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) throw StateError('dial failed');
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذر فتح الاتصال على هذا الهاتف'.tr),
      ));
    }
  }
}

/// "My measuring devices" card — scan, pair and manage certified Bluetooth
/// meters. Once paired, the app reconnects automatically on every launch and
/// stores each pushed measurement without any patient input.
class _DevicesCard extends StatefulWidget {
  const _DevicesCard();

  @override
  State<_DevicesCard> createState() => _DevicesCardState();
}

class _DevicesCardState extends State<_DevicesCard> {
  bool _scanning = false;
  Map<String, String> _paired = const {};

  @override
  void initState() {
    super.initState();
    _refreshPaired();
  }

  Future<void> _refreshPaired() async {
    final paired = await BluetoothDeviceService.instance.savedDevices();
    if (!mounted) return;
    setState(() => _paired = paired);
  }

  Future<void> _scanAndPair() async {
    final sync = DeviceSyncService.instance;
    final granted = await BluetoothDeviceService.instance.requestPermissions();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('لم تُمنح صلاحيات البلوتوث — لا يمكن البحث عن الأجهزة'.tr),
      ));
      return;
    }

    setState(() => _scanning = true);
    final devices = await BluetoothDeviceService.instance
        .scanForMedicalDevices(timeout: const Duration(seconds: 10));
    if (!mounted) return;
    setState(() => _scanning = false);

    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'لم يُعثر على أجهزة قياس قريبة. شغّل جهاز القياس وضع قربه من الهاتف ثم أعد المحاولة'.tr),
      ));
      return;
    }

    // Let the patient pick one of the detected meters.
    final selected = await showModalBottomSheet<MedicalBleDevice>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('الأجهزة التي تم العثور عليها'.tr,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final device in devices)
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: Text(device.name.isEmpty
                    ? 'جهاز قياس (${device.kinds.join('، ')})'.tr
                    : device.name),
                subtitle:
                    Text('يقيس: ${device.kinds.map(_kindLabel).join('، ')}'.tr),
                trailing: const Icon(Icons.link),
                onTap: () => Navigator.of(sheetContext).pop(device),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;

    final ok = await sync.connectMeter(
      remoteId: selected.remoteId,
      deviceName: selected.name,
    );
    await _refreshPaired();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'تم ربط الجهاز — سيتم استقبال قياساته تلقائياً'.tr
          : 'تعذر الاتصال بالجهاز — تأكد أنه قريب ويعمل'.tr),
    ));
  }

  String _kindLabel(String kind) => vitalKindLabel(kind).tr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = BluetoothDeviceService.instance.connectedIds;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices_other, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('أجهزة القياس المتصلة'.tr,
                      style:
                          const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'اربط جهاز الضغط أو السكر أو الأكسجين وسيسجل التطبيق قياساته تلقائياً دون تدخل منك.'.tr,
              style: theme.textTheme.bodySmall,
            ),
            for (final entry in _paired.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  connected.contains(entry.key)
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: connected.contains(entry.key) ? Colors.green : null,
                ),
                title: Text(entry.value.isEmpty ? 'جهاز مقترن'.tr : entry.value),
                subtitle: Text(connected.contains(entry.key)
                    ? 'متصل — يستقبل القياسات الآن'.tr
                    : 'غير متصل حالياً'.tr),
                trailing: IconButton(
                  icon: const Icon(Icons.link_off),
                  tooltip: 'فصل الجهاز'.tr,
                  onPressed: () async {
                    await DeviceSyncService.instance
                        .disconnectMeter(entry.key);
                    await _refreshPaired();
                  },
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _scanning ? null : _scanAndPair,
                icon: _scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_scanning
                    ? 'جارٍ البحث عن الأجهزة…'.tr
                    : 'ربط جهاز قياس جديد'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
