import 'package:flutter/foundation.dart';

/// حالة قفل التطبيق المشتركة.
///
/// الحاجز (`LockGate`) هو من يضبط الحالة، وجذر التطبيق (`RootGate`) يستمع
/// لها لتنفيذ ما طُلب أثناء القفل — مثلاً فتح شاشة الأدوية بعد ضغط تذكير
/// جرعة، أو فتح المساعد الصوتي القادم من اختصار النظام. بهذا لا يمكن لأي
/// مسار (إشعار، اختصار، Intent من تطبيق آخر) أن يتخطى القفل.
class AppLockState extends ChangeNotifier {
  AppLockState._();

  static final AppLockState instance = AppLockState._();

  bool _locked = false;

  /// القفل مغلق (لا وصول لبيانات المريض) — يُفعَّل فقط عند تفعيل المستخدم
  /// لقفل التطبيق، وحتى ينتهي التحقق بالبصمة/رمز الجهاز.
  bool get isLocked => _locked;

  /// حمولة تذكير دواء نُقر عليها أثناء القفل: تُنفَّذ بعد فتح القفل.
  String? _pendingReminderPayload;

  /// طلب فتح المساعد الصوتي (اختصار/Google Assistant) أثناء القفل.
  bool _pendingVoiceAssistant = false;

  void setLocked(bool value) {
    if (_locked == value) return;
    _locked = value;
    notifyListeners();
  }

  void lock() => setLocked(true);

  void unlock() => setLocked(false);

  void requestReminderAfterUnlock(String payload) {
    _pendingReminderPayload = payload;
  }

  void requestVoiceAssistantAfterUnlock() {
    _pendingVoiceAssistant = true;
  }

  /// يسترجع الحمولة المعلّقة (مرة واحدة) أو null.
  String? takePendingReminderPayload() {
    final payload = _pendingReminderPayload;
    _pendingReminderPayload = null;
    return payload;
  }

  /// يسترجع طلب المساعد الصوتي المعلّق (مرة واحدة).
  bool takePendingVoiceAssistant() {
    final value = _pendingVoiceAssistant;
    _pendingVoiceAssistant = false;
    return value;
  }

  /// إعادة الحالة للاختبارات.
  @visibleForTesting
  void resetForTesting() {
    _locked = false;
    _pendingReminderPayload = null;
    _pendingVoiceAssistant = false;
  }
}
