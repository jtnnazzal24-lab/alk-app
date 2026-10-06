/// شاشة «الرعاية الذكية»: تنبيهات التفاعلات والأنماط والمخزون والفحوصات،
/// بطاقة الطوارئ، زر «أنا بخير»، التقرير العائلي، ووضع رمضان.
///
/// تنفيذ بنود وثيقة التطوير 1، 2، 3، 5، 15 و16.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../logic/care_alerts.dart';
import '../logic/drug_interactions.dart';
import '../logic/pattern_detector.dart';
import '../logic/ramadan_plan.dart';
import '../services/family_share_service.dart';
import '../state/sandy_store.dart';
import '../theme/alk_theme.dart';

/// تنبيه موحّد من أي مصدر (تفاعلات / أنماط / مخزون / فحوصات).
class UnifiedAlert {
  const UnifiedAlert({
    required this.severity,
    required this.title,
    required this.detail,
  });

  final String severity;
  final String title;
  final String detail;
}

class SmartCareScreen extends StatefulWidget {
  const SmartCareScreen({super.key});

  @override
  State<SmartCareScreen> createState() => _SmartCareScreenState();
}

class _SmartCareScreenState extends State<SmartCareScreen> {
  static const _prefix = 'alk.checkup.';
  static const _familyShare = FamilyShareService();

  Map<String, String> _done = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadDone();
  }

  Future<void> _loadDone() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_prefix)) {
        map[key.substring(_prefix.length)] = prefs.getString(key) ?? '';
      }
    }
    if (!mounted) return;
    setState(() => _done = map);
  }

  Future<void> _markCheckup(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;
    await prefs.setString('$_prefix$id', today);
    await _loadDone();
  }

  /// جمع التنبيهات من كل المصادر في قائمة واحدة مرتّبة.
  List<UnifiedAlert> _alerts(SandyStore store) {
    final out = <UnifiedAlert>[
      for (final a in stockAlerts(store.medications))
        UnifiedAlert(severity: a.severity, title: a.title, detail: a.detail),
      for (final a in expiryAlerts(store.medications))
        UnifiedAlert(severity: a.severity, title: a.title, detail: a.detail),
      for (final a in dueCheckups(
        condition: store.patient.conditionName,
        lastDone: _done,
      ))
        UnifiedAlert(severity: a.severity, title: a.title, detail: a.detail),
      for (final a in findDrugInteractions(
        medications: store.medications,
        condition: store.patient.conditionName,
        foods: store.weekFoodNames,
      ))
        UnifiedAlert(severity: a.severity, title: a.title, detail: a.detail),
      for (final p in detectVitalPatterns(store.vitals))
        UnifiedAlert(severity: p.severity, title: p.title, detail: p.detail),
    ];
    out.sort((a, b) {
      int rank(String s) => s == 'high' ? 0 : (s == 'medium' ? 1 : 2);
      final r = rank(a.severity).compareTo(rank(b.severity));
      return r != 0 ? r : a.title.compareTo(b.title);
    });
    return out;
  }

  Future<void> _shareIamFine() async {
    final store = context.read<SandyStore>();
    final text = _familyShare.buildIamFineMessage(store).tr;
    final contacts = store.emergencyContacts;
    if (contacts.isNotEmpty) {
      final ok = await _familyShare.sendViaWhatsApp(contacts.first.phone, text);
      if (ok || !mounted) return;
    }
    await _familyShare.shareText(text);
  }

  Future<void> _shareCard() async {
    final store = context.read<SandyStore>();
    await _familyShare.shareText(
      _familyShare.buildEmergencyCard(store).tr,
      subject: 'بطاقة طوارئ — ALK'.tr,
    );
  }

  Future<void> _shareReport() async {
    final store = context.read<SandyStore>();
    await _familyShare.shareText(
      _familyShare.buildFamilyReport(store).tr,
      subject: 'تقرير العائلة — ALK'.tr,
    );
  }

  void _showRamadanPlan() {
    final store = context.read<SandyStore>();
    final tips = buildRamadanPlan(medications: store.medications);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (sheetContext, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'وضع رمضان الذكي'.tr,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'اقتراحات حسب أدويتك — لا تغيّر أي جرعة دون طبيبك.'.tr,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final t in tips)
              Card(
                child: ListTile(
                  leading: Icon(
                    t.severity == 'high'
                        ? Icons.warning_amber_rounded
                        : Icons.lightbulb_outline,
                    color: t.severity == 'high' ? Colors.red.shade700 : null,
                  ),
                  title: Text(t.title.tr),
                  subtitle: Text(t.detail.tr),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    final alerts = _alerts(store);
    final outline = Theme.of(context).colorScheme.outline;

    return Scaffold(
      appBar: AppBar(title: Text('الرعاية الذكية'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AlkPalette.of(context).goldSoft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _shareIamFine,
                    icon: const Icon(Icons.favorite),
                    label: Text('أنا بخير اليوم'.tr),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'زر واحد يطمئن عائلتك: يرسل رسالة واتساب جاهزة بوضعك اليوم.'
                        .tr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.emergency,
                  title: 'بطاقة الطوارئ'.tr,
                  subtitle: 'فصيلة الدم والأدوية والحساسيات'.tr,
                  onTap: _shareCard,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionCard(
                  icon: Icons.family_restroom,
                  title: 'تقرير العائلة'.tr,
                  subtitle: 'ملخص بضغطة واحدة'.tr,
                  onTap: _shareReport,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ActionCard(
            icon: Icons.self_improvement,
            title: 'وضع رمضان الذكي'.tr,
            subtitle: 'خطة سحور وإفطار حسب أدويتك'.tr,
            onTap: _showRamadanPlan,
          ),
          const SizedBox(height: 16),
          Text(
            'التنبيهات الذكية'.tr,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '$alerts.length تنبيه — تفاعلات وأنماط ومخزون وفحوصات'.tr,
            style: TextStyle(fontSize: 13, color: outline),
          ),
          const SizedBox(height: 8),
          if (alerts.isEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text('لا توجد تنبيهات الآن'.tr),
                subtitle: Text('كل شيء تحت السيطرة — أحسنت!'.tr),
              ),
            )
          else
            for (final a in alerts) _AlertTile(alert: a),
          const SizedBox(height: 16),
          Text(
            'الفحوصات الدورية'.tr,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'اضغط «تم» بعد كل فحص ليُحسب موعده القادم تلقائياً.'.tr,
            style: TextStyle(fontSize: 13, color: outline),
          ),
          const SizedBox(height: 8),
          for (final item in standardCheckups(store.patient.conditionName))
            _CheckupTile(
              item: item,
              doneOn: _done[item.id],
              onDone: () => _markCheckup(item.id),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// بطاقة إجراء صغيرة (بطاقة الطوارئ / التقرير / رمضان).
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// سطر تنبيه واحد بلون حسب الخطورة.
class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final UnifiedAlert alert;

  Color get _color {
    switch (alert.severity) {
      case 'high':
        return Colors.red.shade700;
      case 'medium':
        return Colors.orange.shade800;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.priority_high, color: _color),
        title: Text(alert.title.tr),
        subtitle: Text(alert.detail.tr),
      ),
    );
  }
}

/// فحص دوري مع زر «تم» يسجّل تاريخ الإنجاز.
class _CheckupTile extends StatelessWidget {
  const _CheckupTile({
    required this.item,
    required this.doneOn,
    required this.onDone,
  });

  final CheckupItem item;
  final String? doneOn;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final done = (doneOn ?? '').isNotEmpty;
    return Card(
      child: ListTile(
        leading: Icon(
          done ? Icons.check_circle_outline : Icons.event_available_outlined,
          color: done ? Colors.green : null,
        ),
        title: Text(item.title.tr),
        subtitle: Text(
          done ? '${item.detail.tr} — آخر فحص: $doneOn'.tr : item.detail.tr,
        ),
        trailing: done
            ? null
            : TextButton(
                onPressed: onDone,
                child: Text('تم'.tr),
              ),
      ),
    );
  }
}


