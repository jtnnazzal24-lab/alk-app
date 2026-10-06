import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/sandy_data.dart';
import '../state/sandy_store.dart';
import '../widgets/speak_button.dart';

/// Medications tab - list of medications with add/toggle/delete actions.
class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({super.key});

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  bool _showAddForm = false;
  final _nameController = TextEditingController();
  final _timeController = TextEditingController(text: '08:00');
  final _doseController = TextEditingController();
  String _category = MedicationCategory.general;
  String? _form;
  int _intervalDays = 1;
  bool _reminderEnabled = true;

  @override
  void dispose() {
    _nameController.dispose();
    _timeController.dispose();
    _doseController.dispose();
    super.dispose();
  }

  Future<void> _saveMedication() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('اكتب اسم الدواء قبل الحفظ'.tr)),
      );
      return;
    }
    final store = context.read<SandyStore>();
    await store.addMedication(
      name: _nameController.text,
      time: _timeController.text,
      category: _category,
      reminderEnabled: _reminderEnabled,
      dose: _doseController.text.trim().isEmpty ? null : _doseController.text,
      form: _form,
      intervalDays: _intervalDays,
    );
    _nameController.clear();
    _timeController.text = '08:00';
    _doseController.clear();
    _category = MedicationCategory.general;
    _form = null;
    _intervalDays = 1;
    _reminderEnabled = true;
    setState(() => _showAddForm = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    final medications = store.medications;

    return Scaffold(
      appBar: AppBar(
        title: Text('أدويتي'.tr),
        actions: [
          IconButton(
            icon: Icon(_showAddForm ? Icons.close : Icons.add),
            onPressed: () => setState(() => _showAddForm = !_showAddForm),
          ),
        ],
      ),
      body: SafeArea(
        // Everything scrolls together — the add form is tall and must never
        // overflow (no yellow stripes) on small screens.
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ReadPageAloud(
              text: 'هذه صفحة أدويتك. سأقرأ لك أسماء الأدوية ومواعيدها ببطء. اضغط زر السماعة بجانب أي دواء لسماعه.'.tr,
              languageTag: context.read<SandyStore>().languageTag,
            ),
            const SizedBox(height: 8),
            if (_showAddForm) ...[
              _buildAddForm(),
              const SizedBox(height: 16),
            ],
            if (medications.isEmpty)
              _buildEmpty()
            else
              for (final med in medications) _buildMedicationCard(med),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.medication_outlined, size: 64),
          const SizedBox(height: 16),
          Text('لا توجد أدوية بعد'.tr),
          Text('أضف دواءً لمتابعة جرعاتك'.tr),
        ],
      ),
    );
  }

  Widget _buildMedicationCard(Medication med) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              med.taken ? Icons.check_circle : Icons.medication,
              color: med.taken ? const Color(0xFF5F8D6E) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    med.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    med.taken ? 'تم التناول ✓'.tr : med.time,
                  ),
                  // Dose / form / disease / frequency summary line.
                  Text(
                    _medicationDetails(med),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                med.taken ? Icons.undo : Icons.check_circle_outline,
                color: med.taken
                    ? const Color(0xFFE07A3F)
                    : const Color(0xFF5F8D6E),
              ),
              tooltip:
                  med.taken ? 'إلغاء تأكيد التناول'.tr : 'تأكيد تناول الجرعة'.tr,
              onPressed: () =>
                  context.read<SandyStore>().toggleMedication(med.id),
            ),
            SpeakButton(
              text: 'دواء ${med.name}. الموعد ${med.time}. ${_medicationDetails(med)}'.tr,
              languageTag: context.read<SandyStore>().languageTag,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  context.read<SandyStore>().removeMedication(med.id),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact summary: "كبسولة • 500 ملغ • سكري • كل يومين".
  String _medicationDetails(Medication med) {
    final frequency = switch (med.intervalDays) {
      1 => 'كل يوم'.tr,
      2 => 'كل يومين'.tr,
      3 => 'كل ٣ أيام'.tr,
      7 => 'كل أسبوع'.tr,
      final n => 'كل $n أيام'.tr,
    };
    return [
      if (med.form != null && med.form!.isNotEmpty) med.form!.tr,
      if (med.dose != null && med.dose!.isNotEmpty) med.dose!,
      if (med.category.isNotEmpty && med.category != MedicationCategory.general)
        med.category.tr,
      frequency,
    ].join(' • ');
  }

  Widget _buildAddForm() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration:
                  InputDecoration(labelText: 'اسم الدواء'.tr),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _doseController,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: 'عيار الجرعة (مثال: 500 ملغ، قرص واحد)'.tr,
              ),
            ),
            const SizedBox(height: 12),
            // Medication form: capsule / pill / liquid / ...
            Text('شكل الدواء'.tr),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in MedicationForm.all)
                  ChoiceChip(
                    label: Text(f.tr),
                    selected: _form == f,
                    onSelected: (_) => setState(() => _form = f),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Time picker for dose time.
            Row(
              children: [
                const Text('${'موعد أخذ الدواء'}: '),
                TextButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time),
                  label: Text(_timeController.text),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Frequency: every day / every other day / every third day.
            Text('التكرار'.tr),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const {
                  1: 'كل يوم',
                  2: 'كل يومين',
                  3: 'كل ٣ أيام',
                  7: 'كل أسبوع',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value.tr),
                    selected: _intervalDays == entry.key,
                    onSelected: (_) =>
                        setState(() => _intervalDays = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Disease category: diabetes / pressure / heart / general.
            Text('الدواء لأي مرض؟'.tr),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in MedicationCategory.all)
                  ChoiceChip(
                    label: Text(c.tr),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Switch(
                  value: _reminderEnabled,
                  onChanged: (v) => setState(() => _reminderEnabled = v),
                ),
                Text('تفعيل التذكير'.tr),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saveMedication,
              child: Text('حفظ'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final parts = _timeController.text.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        _timeController.text =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }
}
