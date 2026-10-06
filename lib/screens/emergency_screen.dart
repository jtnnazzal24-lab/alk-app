import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/sandy_store.dart';
import '../l10n/app_strings.dart';

/// Emergency settings — manage the people to call when the patient is losing
/// control, and the ambulance hotline.
class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ambulanceController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ambulanceController.dispose();
    super.dispose();
  }

  Future<void> _addContact() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('اكتب الاسم ورقم الهاتف'.tr)),
      );
      return;
    }
    await context.read<SandyStore>().addEmergencyContact(name, phone);
    _nameController.clear();
    _phoneController.clear();
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت إضافة $name إلى قائمة الطوارئ'.tr)),
      );
    }
  }

  Future<void> _saveAmbulance() async {
    final number = _ambulanceController.text.trim();
    if (number.isEmpty) return;
    await context.read<SandyStore>().setAmbulanceNumber(number);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تحديث رقم الإسعاف إلى $number'.tr)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    final theme = Theme.of(context);
    if (_ambulanceController.text.isEmpty) {
      _ambulanceController.text = store.ambulanceNumber;
    }
    return Scaffold(
      appBar: AppBar(title: Text('الطوارئ'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'عند شعورك أنك ستفقد السيطرة، قل للمساعد الصوتي: '.tr,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('رقم الإسعاف'.tr, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ambulanceController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'رقم الإسعاف في بلدك'.tr,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saveAmbulance,
                        child: Text('حفظ'.tr),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إضافة شخص للطوارئ'.tr, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'الاسم (مثال: ابني أحمد)'.tr,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: 'رقم الهاتف'.tr),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _addContact,
                    icon: const Icon(Icons.person_add),
                    label: Text('إضافة'.tr),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'أشخاص الطوارئ (${store.emergencyContacts.length})'.tr,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (store.emergencyContacts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('لا يوجد أشخاص بعد — أضف أحدهم فوق'.tr)),
            )
          else
            for (final contact in store.emergencyContacts)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading:
                      const Icon(Icons.emergency, color: Color(0xFFC94F4F)),
                  title: Text(contact.name),
                  subtitle: Text(contact.phone),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await context
                          .read<SandyStore>()
                          .removeEmergencyContact(contact.id);
                      setState(() {});
                    },
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
