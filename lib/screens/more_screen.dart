import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/alk_theme.dart';
import 'chat_screen.dart';
import 'nutrition_screen.dart';
import 'patient_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'smart_care_screen.dart';
import 'wellbeing_screen.dart';

/// More tab - navigation to chat, settings, and other features.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('المزيد'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile card
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF4E7D61),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.health_and_safety,
                    size: 48, color: Colors.white),
                const SizedBox(height: 12),
                Text('ALK بجانبك'.tr,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    )),
                const SizedBox(height: 4),
                Text('رفيق للتنظيم والمتابعة اليومية'.tr,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: const Color(0xFFE4DCCB))),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Menu items
          _MoreTile(
            icon: Icons.person,
            title: 'ملف المريض'.tr,
            subtitle: 'الهوية الصحية والأدوية'.tr,
            onTap: () => _open(context, const PatientScreen()),
          ),
          _MoreTile(
            icon: Icons.chat,
            title: 'محادثة ALK'.tr,
            subtitle: 'دعم عام ونصائح'.tr,
            onTap: () => _open(context, const ChatScreen()),
          ),
          _MoreTile(
            icon: Icons.restaurant,
            title: 'التغذية'.tr,
            subtitle: 'تتبع الوجبات وتأثيرها على السكر والضغط والقلب'.tr,
            onTap: () => _open(context, const NutritionScreen()),
          ),
          _MoreTile(
            icon: Icons.favorite,
            title: 'العافية والحركة'.tr,
            subtitle: 'تمارين وموسيقى هادئة'.tr,
            onTap: () => _open(context, const WellbeingScreen()),
          ),
          _MoreTile(
            icon: Icons.assessment,
            title: 'التقارير'.tr,
            subtitle: 'ملخص الالتزام والقياسات'.tr,
            onTap: () => _open(context, const ReportsScreen()),
          ),
          _MoreTile(
            icon: Icons.health_and_safety,
            title: 'الرعاية الذكية'.tr,
            subtitle: 'تنبيهات التفاعلات والأنماط وبطاقة الطوارئ'.tr,
            onTap: () => _open(context, const SmartCareScreen()),
          ),
          _MoreTile(
            icon: Icons.settings,
            title: 'الإعدادات'.tr,
            subtitle: 'الخصوصية والتذكيرات'.tr,
            onTap: () => _open(context, const SettingsScreen()),
          ),

          const SizedBox(height: 24),
          Card(
            // بطاقة إرشادية: الخلفية تتبع سطوع الثيم حتى يبقى النص مقروءاً
            // في الوضع الداكن (بدل مربع أبيض فارغ).
            color: AlkPalette.of(context).goldSoft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'ALK لا يقدم تشخيصًا طبيًا. تواصل مع طبيبك عند وجود عرض مقلق.'
                    .tr,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
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
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
