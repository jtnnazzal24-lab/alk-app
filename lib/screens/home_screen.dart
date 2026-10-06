import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/sandy_store.dart';
import '../theme/alk_theme.dart';
import '../widgets/speak_button.dart';
import 'medications_screen.dart';
import 'voice_assistant_screen.dart';
import 'vitals_screen.dart';
import 'journals_screen.dart';
import 'more_screen.dart';

/// Main home screen with bottom navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Voice assistant navigation bridge ("افتح القياسات" → switch tab).
    VoiceNavigator.open = (screen) {
      const map = {
        'home': 0,
        'medications': 1,
        'vitals': 2,
        'journals': 3,
        'more': 4,
      };
      final index = map[screen];
      if (index != null && mounted) setState(() => _currentIndex = index);
    };
  }

  @override
  void dispose() {
    VoiceNavigator.open = null;
    super.dispose();
  }

  // Recreate the tab list only when the selected index changes (the built
  // widgets are const, and the visible tab reacts to the store on its own via
  // context.watch). Kept out of build so a store notification never rebuilds
  // the whole shell.
  late final List<Widget> _screens = const <Widget>[
    _DashboardTab(),
    MedicationsScreen(),
    VitalsScreen(),
    JournalsScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _screens[_currentIndex]),
      floatingActionButton: FloatingActionButton.large(
        tooltip: 'المساعد الصوتي'.tr,
        child: const Icon(Icons.mic, size: 36),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const VoiceAssistantScreen(),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: 'الرئيسية'.tr,
          ),
          NavigationDestination(
            icon: const Icon(Icons.medication_outlined),
            selectedIcon: const Icon(Icons.medication),
            label: 'أدويتي'.tr,
          ),
          NavigationDestination(
            icon: const Icon(Icons.favorite_outline),
            selectedIcon: const Icon(Icons.favorite),
            label: 'القياسات'.tr,
          ),
          NavigationDestination(
            icon: const Icon(Icons.book_outlined),
            selectedIcon: const Icon(Icons.book),
            label: 'يومياتي'.tr,
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            selectedIcon: const Icon(Icons.more_horiz),
            label: 'المزيد'.tr,
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير'.tr;
    if (hour < 18) return 'مساء الخير'.tr;
    return 'مساء النور'.tr;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // لوحة الألوان تتبع سطوع الثيم: كانت ثابتة فاتحة (AlkColors.light) فتظهر
    // شريحة الالتزام والأيقونات باهتة/غير مقروءة في الوضع الداكن.
    final palette = AlkPalette.of(context);
    // شفافية التظليل الملوّن لشرائح الحالة: تُرفع في الوضع الداكن لأن اللون
    // الناعم (10%) يغرق في الخلفية الداكنة فيكاد لا يُرى.
    final tintAlpha = theme.brightness == Brightness.dark ? 0.18 : 0.1;
    final patientName = store.patient.fullName.isNotEmpty
        ? store.patient.fullName
        : 'المستخدم'.tr;

    final todayMeds = store.medications;
    final takenCount = todayMeds.where((m) => m.taken).length;
    final adherence = todayMeds.isEmpty ? 0.0 : takenCount / todayMeds.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: SpeakButton(
                      text: 'مرحبا. أنا رفيقك الصحي. لديك $takenCount من ${todayMeds.length} جرعات اليوم. اضغط زر المايك الكبير وتحدث معي ببطء.'.tr,
                      languageTag: store.languageTag,
                    ),
                  ),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/images/alk-logo.png',
                        width: 104,
                        height: 104,
                        fit: BoxFit.contain,
                        semanticLabel: 'شعار ALK'.tr,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_greeting()}، $patientName'.tr,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'رفيقك الصحي اليوم'.tr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Adherence card
          Card(
            color: adherence >= 0.8
                ? palette.success.withValues(alpha: tintAlpha)
                : adherence >= 0.5
                    ? palette.gold.withValues(alpha: tintAlpha)
                    : palette.error.withValues(alpha: tintAlpha),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    adherence >= 0.8
                        ? Icons.check_circle
                        : Icons.access_time,
                    color: adherence >= 0.8
                        ? palette.success
                        : palette.gold,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الالتزام بالأدوية'.tr,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text('$takenCount من ${todayMeds.length} جرعات'.tr),
                      ],
                    ),
                  ),
                  Text(
                    '${(adherence * 100).toInt()}%',
                    style: theme.textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Today's medications
          if (todayMeds.isNotEmpty) ...[
            Text('أدوية اليوم'.tr, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...todayMeds.take(3).map((med) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.medication),
                    title: Text(med.name),
                    subtitle: Text(med.time),
                    trailing: med.taken
                        ? Icon(Icons.check_circle, color: palette.success)
                        : const Icon(Icons.access_time),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
