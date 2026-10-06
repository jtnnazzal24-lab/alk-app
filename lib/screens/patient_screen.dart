import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/sandy_store.dart';
import '../l10n/app_strings.dart';

/// Patient profile screen — identity, condition and doctor notes.
/// Port of the RN app's `patient.tsx`.
class PatientScreen extends StatefulWidget {
  const PatientScreen({super.key});

  @override
  State<PatientScreen> createState() => _PatientScreenState();
}

class _PatientScreenState extends State<PatientScreen> {
  late final TextEditingController _name;
  late final TextEditingController _identity;
  late final TextEditingController _condition;
  late final TextEditingController _doctorNotes;
  late final TextEditingController _reviewDate;
  late final TextEditingController _doctorPhone;
  late final TextEditingController _doctorEmail;
  late final TextEditingController _bloodType;
  late final TextEditingController _allergies;

  @override
  void initState() {
    super.initState();
    final p = context.read<SandyStore>().patient;
    _name = TextEditingController(text: p.fullName);
    _identity = TextEditingController(text: p.identityNumber);
    _condition = TextEditingController(text: p.conditionName);
    _doctorNotes = TextEditingController(text: p.doctorNotes);
    _reviewDate = TextEditingController(text: p.nextReviewDate);
    _doctorPhone = TextEditingController(text: p.doctorPhone);
    _doctorEmail = TextEditingController(text: p.doctorEmail);
    _bloodType = TextEditingController(text: p.bloodType);
    _allergies = TextEditingController(text: p.allergies);
  }

  @override
  void dispose() {
    _name.dispose();
    _identity.dispose();
    _condition.dispose();
    _doctorNotes.dispose();
    _reviewDate.dispose();
    _doctorPhone.dispose();
    _doctorEmail.dispose();
    _bloodType.dispose();
    _allergies.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.read<SandyStore>();
    await store.setPatientProfile(
      store.patient.copyWith(
        fullName: _name.text,
        identityNumber: _identity.text,
        conditionName: _condition.text,
        doctorNotes: _doctorNotes.text,
        nextReviewDate: _reviewDate.text,
        doctorPhone: _doctorPhone.text,
        doctorEmail: _doctorEmail.text,
        bloodType: _bloodType.text,
        allergies: _allergies.text,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ الملف الشخصي'.tr)),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    return Scaffold(
      appBar: AppBar(title: Text('ملف المريض'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'الاسم الكامل'.tr,
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _identity,
              decoration: InputDecoration(
                labelText: 'رقم الهوية'.tr,
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _condition,
              decoration: InputDecoration(
                labelText: 'اسم الحالة المرضية'.tr,
                prefixIcon: const Icon(Icons.medical_information_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bloodType,
              decoration: InputDecoration(
                labelText: 'فصيلة الدم'.tr,
                hintText: 'مثال: A+ أو O-'.tr,
                prefixIcon: const Icon(Icons.bloodtype_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _allergies,
              decoration: InputDecoration(
                labelText: 'الحساسيات'.tr,
                hintText: 'مثال: بنسلين، مكسرات'.tr,
                prefixIcon: const Icon(Icons.rule_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _doctorNotes,
              decoration: InputDecoration(
                labelText: 'ملاحظات الطبيب'.tr,
                prefixIcon: const Icon(Icons.sticky_note_2_outlined),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reviewDate,
              decoration: InputDecoration(
                labelText: 'موعد المراجعة القادم'.tr,
                prefixIcon: const Icon(Icons.event_outlined),
              ),
              readOnly: true,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null) {
                  _reviewDate.text =
                      picked.toIso8601String().split('T').first;
                }
              },
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'الطبيب المعالج (لإرسال التقارير)'.tr,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _doctorPhone,
              decoration: InputDecoration(
                labelText: 'رقم واتساب الطبيب (بصيغة دولية)'.tr,
                hintText: 'مثال: 972591234567'.tr,
                prefixIcon: const Icon(Icons.chat_outlined),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _doctorEmail,
              decoration: InputDecoration(
                labelText: 'البريد الإلكتروني للطبيب'.tr,
                hintText: 'doctor@example.com',
                prefixIcon: const Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.lock_outline),
                title: Text('قفل التطبيق'.tr),
                value: store.patient.lockEnabled,
                onChanged: (v) => store.setPatientLock(v),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: Text('حفظ'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
