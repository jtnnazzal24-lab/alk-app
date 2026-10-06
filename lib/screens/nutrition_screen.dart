import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/food_advice.dart';
import '../l10n/app_strings.dart';
import '../logic/food_med_analysis.dart';
import '../logic/fat_exercise_advice.dart';
import '../services/notification_service.dart';
import '../services/voice_service.dart';
import '../widgets/speak_button.dart';
import '../models/sandy_data.dart';
import '../state/sandy_store.dart';
import '../theme/alk_theme.dart';

/// Nutrition tracker — logs foods the patient eats and shows, per food,
/// whether it can affect blood sugar, blood pressure, or heart health, plus
/// plain-language advice to reduce it and healthier alternatives.
///
/// The latest sugar reading is surfaced near the tracker so the patient can
/// compare before/after their meals.
class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  final _nameController = TextEditingController();
  String _mealType = FoodMealType.lunch;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('اكتب اسم الطعام قبل الحفظ'.tr)),
      );
      return;
    }
    final store = context.read<SandyStore>();
    final analysis = analyzeFoodEntry(name);
    await store.addFood(name, _mealType);
    if (!mounted) return;
    _nameController.clear();
    setState(() {});
    // المستوى الأول/الثاني: إشعار صوتي فوري عند تجاوز حد الدهون (over)
    // أو الاقتراب منه (warn) — صوت نظام + نطق بطيء لكبير السن.
    final dayAdvice = adviceForDay(data: store.data);
    if (dayAdvice.level == FatAdviceLevel.over ||
        dayAdvice.level == FatAdviceLevel.warn) {
      await _announceFoodLevel(store, dayAdvice);
      if (!mounted) return;
      _showFatAdviceSheet(dayAdvice);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          analysis.hasConcerns
              ? 'تم تسجيل ${_mealType == FoodMealType.snack ? 'الوجبة' : _mealType} وتحليله'.tr
              : 'تم تسجيل الطعام'.tr,
        ),
      ),
    );
  }

  /// ورقة سفلية تعرض النصيحة التعويضية للتخلص من ضرر الدهون المشبعة.
  /// يصدر إشعار نظام بصوت + ينطق التحذير ببطء (المستوى الأول أقوى من الثاني).
  Future<void> _announceFoodLevel(
      SandyStore store, FatExerciseAdvice advice) async {
    final isOver = advice.level == FatAdviceLevel.over;
    final title = isOver
        ? 'تنبيه المستوى الأول: تجاوزت حد الدهون'.tr
        : 'تنبيه المستوى الثاني: اقتربت من حد الدهون'.tr;
    final spoken =
        'تنبيه غذائي. ${adviceSummaryText(advice)}. ${advice.conditionAdvice}'
            .tr;
    try {
      await NotificationService.instance.showFoodAlertNotification(
        level: advice.level,
        title: title,
        body: adviceSummaryText(advice).tr,
      );
    } catch (_) {}
    // نطق فوري بطيء — يعمل والتطبيق مفتوح (TTS لا يعمل من الخلفية،
    // لذا يبقى صوت الإشعار هو ما يوقظ المريض عندما يكون التطبيق مغلقاً).
    try {
      await VoiceService.instance
          .speakSlow(spoken, languageTag: store.languageTag)
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  void _showFatAdviceSheet(FatExerciseAdvice advice) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('توازن الدهون اليومي'.tr,
                      style: Theme.of(ctx).textTheme.titleMedium),
                ),
                SpeakButton(
                  text:
                      'توازن الدهون. ${adviceSummaryText(advice)}. ${advice.conditionAdvice}'.tr,
                  languageTag: context.read<SandyStore>().languageTag,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _FatAdviceView(advice: advice),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.check),
                label: Text('حسناً'.tr),
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
    final theme = Theme.of(context);
    final foods = store.foodEntries;
    final liveAnalysis = analyzeFoodEntry(_nameController.text);

    return Scaffold(
      appBar: AppBar(
        title: Text('التغذية'.tr),
        actions: [
          SpeakButton(
            text: 'هذه صفحة التغذية. سأخبرك ببطء كيف تؤثر وجبات الفطور والغداء والعشاء على دواء الصباح، مع الكمية المناسبة والبديل.'.tr,
            languageTag: store.languageTag,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAddCard(context, theme, liveAnalysis, store),
          const SizedBox(height: 8),
          _buildMorningMedsCard(store, theme),
          const SizedBox(height: 8),
          _buildDayAnalysis(store, theme),
          _buildLatestSugar(context, store),
          const SizedBox(height: 16),
          Text('وجبات اليوم'.tr, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (foods.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('لا توجد وجبات مسجّلة بعد'.tr),
              ),
            )
          else
            ...foods.map((f) => _buildFoodTile(context, theme, f)),
        ],
      ),
    );
  }

  Widget _buildAddCard(
    BuildContext context,
    ThemeData theme,
    FoodAnalysis liveAnalysis,
    SandyStore store,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ما الذي تناولته اليوم؟'.tr, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'اسم الطعام أو الشراب'.tr,
                hintText: 'مثال: أرز أبيض، مخلل، عصير غازي...'.tr,
              ),
            ),
            if (liveAnalysis.hasConcerns) ...[
              const SizedBox(height: 12),
              _buildLiveAnalysis(theme, liveAnalysis),
            ] else if (_nameController.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.primary, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'لا يُعرف لهذه الأكلة تأثير واضح على السكر أو الضغط أو القلب.'.tr,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            if (_nameController.text.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _FatAdviceView(
                advice: adviceForFoods(
                  foods: [_nameController.text.trim()],
                  conditionName: store.patient.conditionName,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: FoodMealType.all
                  .map((m) => ChoiceChip(
                        label: Text(m.tr),
                        selected: _mealType == m,
                        onSelected: (_) => setState(() => _mealType = m),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text('إضافة الوجبة'.tr),
              ),
            ),
            const SizedBox(height: 12),
            Text('أمثلة سريعة:'.tr, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _QuickChip(
                  'خبز أبيض'.tr,
                  onTap: () => setState(() => _nameController.text = 'خبز أبيض'),
                ),
                _QuickChip(
                  'عصير غازي'.tr,
                  onTap: () => setState(() => _nameController.text = 'عصير غازي'),
                ),
                _QuickChip(
                  'مخلل'.tr,
                  onTap: () => setState(() => _nameController.text = 'مخلل'),
                ),
                _QuickChip(
                  'دجاج مقلي'.tr,
                  onTap: () =>
                      setState(() => _nameController.text = 'دجاج مقلي'),
                ),
                _QuickChip(
                  'برجر'.tr,
                  onTap: () => setState(() => _nameController.text = 'برجر'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveAnalysis(ThemeData theme, FoodAnalysis analysis) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('هذا الطعام يؤثر على:'.tr,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...analysis.concerns.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _ConcernView(concern: c),
              )),
        ],
      ),
    );
  }

  Widget _buildMorningMedsCard(SandyStore store, ThemeData theme) {
    final morning = morningMedications(store.medications);
    final txt = morning.isEmpty ? 'لا يوجد دواء صباحي مسجل — اضف دواء بموعد قبل 12 ظهرا'.tr : 'دواء الصباح: ${morning.map((m) => m.name).join('، ')}'.tr;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.medication),
        title: Text('تفاعل الغذاء مع دواء الصباح'.tr),
        subtitle: Text(txt),
      ),
    );
  }

  Widget _buildDayAnalysis(SandyStore store, ThemeData theme) {
    final map = analyzeDayMealsWithMeds(entries: store.foodEntries, medications: store.medications);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('تحليل الوجبات مع دواء الصباح'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final meal in [FoodMealType.breakfast, FoodMealType.lunch, FoodMealType.dinner])
          _buildMealCard(theme, map[meal]!),
      ],
    );
  }

  Widget _buildMealCard(ThemeData theme, MealMedAnalysis a) {
    Color c;
    if (a.risk == MealRisk.high) { c = Colors.red; }
    else if (a.risk == MealRisk.medium) { c = Colors.orange; }
    else if (a.risk == MealRisk.low) { c = Colors.amber.shade700; }
    else { c = Colors.green; }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('وجبة ${a.mealType}'.tr, style: theme.textTheme.titleSmall)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(MealRisk.label(a.risk).tr, style: TextStyle(color: c, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(a.summary.tr, style: theme.textTheme.bodySmall),
            for (final it in a.items) ...[
              const Divider(),
              Text(it.foodName.tr, style: theme.textTheme.titleSmall),
              Text('الكمية: ${it.amountAdvice}'.tr, style: theme.textTheme.bodySmall),
              Text('البديل: ${it.alternative}'.tr, style: theme.textTheme.bodySmall),
              Text('التوقيت: ${it.timingAdvice}'.tr, style: theme.textTheme.bodySmall),
            ],
            if (a.foods.isEmpty)
              Text('لم تسجل اصناف في وجبة ${a.mealType} بعد.'.tr, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestSugar(BuildContext context, SandyStore store) {
    final sugarReadings =
        store.vitals.where((v) => v.kind == VitalKind.sugar).toList();
    if (sugarReadings.isEmpty) return const SizedBox.shrink();
    final latest = sugarReadings.first;
    return Card(
      // خلفية ناعمة تتبع سطوع الثيم (كانت ثابتة فاتحة فتظهر كمربع أبيض فارغ
      // في الوضع الداكن مع نص فاتح غير مقروء).
      color: AlkPalette.of(context).tealSoft,
      child: ListTile(
        leading: const Icon(Icons.monitor_heart, color: Color(0xFF1F8A8A)),
        title: Text('آخر قراءة سكر: ${latest.value}'.tr),
        subtitle: Text('${latest.createdAt} — قارنها قبل وبعد الوجبات'.tr),
      ),
    );
  }

  Widget _buildFoodTile(BuildContext context, ThemeData theme, FoodEntry f) {
    final analysis = analyzeFoodEntry(f.name);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.restaurant, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.name.tr, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(f.mealType.tr, style: theme.textTheme.bodySmall),
                      if (analysis.hasConcerns)
                        for (final c in analysis.concerns) ...[
                          const SizedBox(width: 8),
                          _ImpactBadge(kind: c.kind),
                        ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'حذف'.tr,
              onPressed: () => context.read<SandyStore>().removeFood(f.id),
            ),
          ],
        ),
      ),
    );
  }
}
/// A red/yellow badge naming the affected body system for a concern.
class _ImpactBadge extends StatelessWidget {
  final String kind;

  const _ImpactBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final isSugar = kind == FoodImpactKind.sugar;
    final isPressure = kind == FoodImpactKind.pressure;
    final color = isSugar
        ? const Color(0xFFE07A3F)
        : (isPressure ? const Color(0xFFC94F4F) : const Color(0xFF7A6BA8));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        FoodImpactKind.label(kind),
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}

/// A concern row with label + advice.
class _ConcernView extends StatelessWidget {
  final FoodConcern concern;

  const _ConcernView({required this.concern});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          FoodImpactKind.label(concern.kind).tr,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(concern.advice.tr, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Tappable chip that fills the food-name field via [onTap].
class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(label), onPressed: onTap);
  }
}

/// بطاقة النصيحة التعويضية للدهون المشبعة — تعرض الحالة والتمارين المقترحة
/// والنصيحة المخصصة للمرض المزمن.
class _FatAdviceView extends StatelessWidget {
  final FatExerciseAdvice advice;

  const _FatAdviceView({required this.advice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color c;
    switch (advice.level) {
      case FatAdviceLevel.over:
        c = Colors.red;
        break;
      case FatAdviceLevel.warn:
        c = Colors.orange;
        break;
      case FatAdviceLevel.ok:
        c = Colors.green;
        break;
      default:
        c = theme.colorScheme.primary;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department, color: c, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'الدهون المشبعة: ${FatAdviceLevel.label(advice.level)}'.tr,
                  style: TextStyle(color: c, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(adviceSummaryText(advice).tr, style: theme.textTheme.bodySmall),
          if (advice.suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('تمارين تعويضية مقترحة:'.tr, style: theme.textTheme.bodySmall),
            for (final s in advice.suggestions)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.directions_walk, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${s.exercise} — ${s.minutes.toStringAsFixed(0)} دقيقة'.tr,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 6),
          Text(advice.conditionAdvice.tr, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}