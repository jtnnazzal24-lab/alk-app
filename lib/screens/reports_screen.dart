import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/doctor_report_service.dart';
import '../l10n/app_strings.dart';
import '../state/sandy_store.dart';
import '../theme/alk_theme.dart';

/// Reports tab - summary of adherence and vitals with export option.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  static const _reportService = DoctorReportService();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    final theme = Theme.of(context);
    final medications = store.medications;
    final vitals = store.vitals;
    final journals = store.journals;

    final taken = medications.where((m) => m.taken).length;
    final rate = medications.isEmpty ? 0 : (taken / medications.length * 100).round();

    return Scaffold(
      appBar: AppBar(title: Text('التقارير'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Adherence summary
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('التزام الأدوية اليوم'.tr,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('$rate%',
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
                    Text('$taken من ${medications.length} جرعات مؤكدة'.tr),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Last vitals
            Text('آخر القياسات'.tr, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (vitals.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(child: Text('لا توجد قراءات مسجلة'.tr)),
                ),
              )
            else
              ...vitals.take(5).map((v) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(v.kind),
                      trailing: Text(v.value,
                          style: theme.textTheme.titleMedium),
                    ),
                  )),

            const SizedBox(height: 16),
            // Journal count
            Card(
              child: ListTile(
                title: Text('المذكرات المحفوظة'.tr),
                trailing: Text('${journals.length}',
                    style: theme.textTheme.titleLarge),
              ),
            ),

            const SizedBox(height: 24),
            const _SendToDoctorCard(reportService: _reportService),
            const SizedBox(height: 24),

            // Disclaimer
            Card(
              // خلفية إرشادية تتبع سطوع الثيم (بدل مربع أبيض فارغ في الوضع الداكن).
              color: AlkPalette.of(context).goldSoft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'هذا التقرير ملخص تنظيمي لبيانات أدخلتها بنفسك، ولا يفسر القياسات أو يقدم تشخيصًا.'.tr,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Send report to the treating doctor" card with WhatsApp / email / share
/// actions and inline doctor-contact editing.
class _SendToDoctorCard extends StatelessWidget {
  const _SendToDoctorCard({required this.reportService});

  final DoctorReportService reportService;

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens the doctor-contact editor. Returns:
  /// true  = saved with usable contact info,
  /// false = saved but still incomplete,
  /// null  = dialog dismissed without saving.
  Future<bool?> _editDoctorContact(BuildContext context, SandyStore store) {
    final phoneCtrl = TextEditingController(text: store.patient.doctorPhone);
    final emailCtrl = TextEditingController(text: store.patient.doctorEmail);

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('بيانات الطبيب المعالج'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'رقم واتساب الطبيب (بصيغة دولية)'.tr,
                  hintText: '972591234567',
                  prefixIcon: const Icon(Icons.chat_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'البريد الإلكتروني للطبيب'.tr,
                  hintText: 'doctor@example.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text('إلغاء'.tr),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save_outlined),
            label: Text('حفظ'.tr),
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);
              await store.setPatientProfile(
                store.patient.copyWith(
                  doctorPhone: phoneCtrl.text,
                  doctorEmail: emailCtrl.text,
                ),
              );
              final ok = DoctorReportService.normalizePhone(phoneCtrl.text)
                      .isNotEmpty ||
                  emailCtrl.text.trim().contains('@');
              navigator.pop(ok);
            },
          ),
        ],
      ),
    );
  }

  /// Ensures the doctor's contact info for [channelLabel] exists; shows the
  /// inline editor when missing. Returns true when ready to send.
  Future<bool> _ensureDoctorContact(
    BuildContext context,
    SandyStore store, {
    required String channelLabel,
  }) async {
    final patient = store.patient;
    final hasPhone =
        DoctorReportService.normalizePhone(patient.doctorPhone).isNotEmpty;
    final hasEmail = patient.doctorEmail.trim().contains('@');
    if (channelLabel == 'واتساب' ? hasPhone : hasEmail) return true;

    final saved = await _editDoctorContact(context, store);
    if (saved == null) return false; // dismissed — cancel silently
    if (saved) return true;
    if (context.mounted) {
      _showMessage(context, 'أدخل بيانات الطبيب المعالج أولاً'.tr);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.send_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'إرسال التقرير إلى الطبيب المعالج'.tr,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'سيُرسل ملخص الالتزام بالأدوية وآخر القياسات والجرعات الفائتة.'.tr,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.chat_outlined, size: 20),
                    label: Text('واتساب'.tr),
                    onPressed: () => _sendViaWhatsApp(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.email_outlined, size: 20),
                    label: Text('بريد إلكتروني'.tr),
                    onPressed: () => _sendViaEmail(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.ios_share, size: 20),
                    label: Text('مشاركة عبر تطبيق آخر'.tr),
                    onPressed: () async {
                      final store = context.read<SandyStore>();
                      await reportService
                          .shareReport(reportService.buildReportText(store));
                    },
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    label: Text('تعديل بيانات الطبيب'.tr),
                    onPressed: () async {
                      final store = context.read<SandyStore>();
                      await _editDoctorContact(context, store);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendViaWhatsApp(BuildContext context) async {
    final store = context.read<SandyStore>();
    if (!await _ensureDoctorContact(context, store, channelLabel: 'واتساب')) {
      return;
    }
    final report = reportService.buildReportText(store);
    final sent = await reportService.sendViaWhatsApp(
        store.patient.doctorPhone, report);
    if (!context.mounted) return;
    _showMessage(
      context,
      sent
          ? 'تم فتح واتساب لإرسال التقرير للطبيب'.tr
          : 'تعذر فتح واتساب — تأكد من تثبيته ومن رقم الطبيب'.tr,
    );
  }

  Future<void> _sendViaEmail(BuildContext context) async {
    final store = context.read<SandyStore>();
    if (!await _ensureDoctorContact(context, store, channelLabel: 'بريد')) {
      return;
    }
    final report = reportService.buildReportText(store);
    final sent =
        await reportService.sendViaEmail(store.patient.doctorEmail, report);
    if (!context.mounted) return;
    _showMessage(
      context,
      sent
          ? 'تم فتح تطبيق البريد لإرسال التقرير للطبيب'.tr
          : 'تعذر فتح تطبيق البريد — تأكد من بريد الطبيب'.tr,
    );
  }
}
