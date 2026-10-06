import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../services/lock_state.dart';
import '../services/security_service.dart';
import '../state/sandy_store.dart';

/// حاجز قفل التطبيق.
///
/// يُوضع في `MaterialApp.builder` فيلتفّ حول **شجرة التنقّل كاملة**، أي أن كل
/// الشاشات المدفوعة (من ضغط إشعار تذكير، أو اختصار صوتي، أو أي مسار داخلي)
/// تبقى خلف القفل ولا يمكن الوصول إليها قبل التحقق بالبصمة/رمز الجهاز.
///
/// ويُعاد القفل تلقائياً عندما يغادر التطبيق الواجهة الأمامية (انتقال لتطبيق
/// آخر أو إطفاء الشاشة)، فلا تبقى بيانات المريض مكشوفة بين الاستخدامات.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.store, required this.child});

  final SandyStore store;
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  static const String _pinStorageKey = 'alk.app.lock.pin';

  bool _unlocked = false;
  bool _checking = false;
  String? _errorMessage;
  String _pinInput = '';
  bool _pinMode = false;
  bool _pinNeedsSetup = false;
  bool _pinResetMode = false;

  /// طلب التحقق تلقائياً مرة واحدة فقط لكل فترة قفل (لا نُزعج المستخدم
  /// بمحاولة جديدة في كل إعادة بناء).
  bool _autoPrompted = false;

  /// هل كان المخزن محمَّلاً في آخر مزامنة؟ نكتشف به لحظة وصول بيانات الإقلاع
  /// (البدء البارد) لنطبّق القفل قبل عرض أي بيانات.
  bool _storeWasLoaded = false;

  /// حالة القفل قبل آخر تحديث في المخزن؛ نستخدمها لاكتشاف الانتقال من
  /// "غير مفعّل" إلى "مفعّل" أثناء التشغيل العادي، حتى نطلب المصادقة فوراً.
  bool _wasLockEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // المخزن يُحمَّل بعد أول إطار عادةً (RootGate.initState)، فنتابع تغيّره حتى
    // نحسم القفل بمجرد وصول بيانات `lockEnabled`؛ وإلا فقد يُفتح التطبيق مرة
    // واحدة بلا قفل عند البدء البارد (البيانات تُقرأ قبل معرفة الإعداد).
    _storeWasLoaded = widget.store.loaded;
    _wasLockEnabled = widget.store.patient.lockEnabled;
    widget.store.addListener(_onStoreChanged);
    _syncLockState();
    if (widget.store.loaded && widget.store.patient.lockEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _authenticate(auto: true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant LockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLockState();
  }

  /// يُستدعى عند كل تغيّر في المخزن لالتقاط حالتين:
  /// 1) لحظة اكتمال تحميل بيانات الإقلاع والقفل مُفعَّل ⇒ يُطبَّق القفل فوراً
  ///    قبل رسم أي شاشة بيانات (إصلاح البدء البارد).
  /// 2) إيقاف القفل من الإعدادات ⇒ يُفتح التطبيق ويُزامَن الحاجز العام.
  void _onStoreChanged() {
    if (!mounted) return;
    final wasEnabled = _wasLockEnabled;
    final justLoaded = !_storeWasLoaded && widget.store.loaded;
    _storeWasLoaded = widget.store.loaded;
    final enabled = widget.store.patient.lockEnabled;
    _wasLockEnabled = enabled;

    if ((justLoaded && enabled) || (!wasEnabled && enabled)) {
      setState(() {
        _unlocked = false;
        _errorMessage = null;
        _autoPrompted = false;
      });
      AppLockState.instance.lock();
      _authenticate(auto: true);
      return;
    }

    if (!enabled && (!_unlocked || AppLockState.instance.isLocked)) {
      setState(() {
        _unlocked = true;
        _errorMessage = null;
        _autoPrompted = false;
      });
      AppLockState.instance.unlock();
    }
  }

  /// يوافق حالة الحاجز مع إعداد المستخدم (قفل التطبيق مفعّل/معطّل).
  void _syncLockState() {
    if (!widget.store.patient.lockEnabled) {
      _unlocked = true;
      _autoPrompted = false;
      AppLockState.instance.unlock();
      return;
    }
    if (_unlocked) return;
    AppLockState.instance.lock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند مغادرة الواجهة (تطبيق آخر / شاشة مُطفأة) يُعاد القفل فوراً.
    // لا نستعمل `inactive` لأن نافذة البصمة نفسها تمرّ بها.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lockNow();
    }
    super.didChangeAppLifecycleState(state);
  }

  void _lockNow() {
    if (!widget.store.patient.lockEnabled) return;
    if (!_unlocked) {
      AppLockState.instance.lock();
      return;
    }
    if (!mounted) return;
    setState(() {
      _unlocked = false;
      _errorMessage = null;
      _autoPrompted = false;
    });
    AppLockState.instance.lock();
  }

  Future<void> _authenticate({bool auto = false}) async {
    if (_checking || _unlocked) return;
    if (auto && _autoPrompted) return;
    if (auto) _autoPrompted = true;

    setState(() {
      _checking = true;
      _errorMessage = null;
      _pinMode = false;
      _pinNeedsSetup = false;
      _pinResetMode = false;
      _pinInput = '';
    });

    try {
      final available = await SecurityService.instance.isBiometricsAvailable();

      if (available) {
        final ok = await SecurityService.instance.authenticate(
          localizedReason: 'افتح ALK للوصول إلى بياناتك الصحية'.tr,
        );

        if (ok && mounted) {
          setState(() {
            _unlocked = true;
            _autoPrompted = false;
            _pinMode = false;
            _pinNeedsSetup = false;
            _pinResetMode = false;
            _pinInput = '';
          });
          AppLockState.instance.unlock();
          return;
        }

        // فشل/أُلغيت البصمة بعد ضغط المستخدم على زر الفتح (رجوع، بصمة غير
        // مسجّلة، خطأ في نافذة النظام): لا نترك المستخدم أمام زر ميت — نعرض
        // بديل PIN داخل التطبيق فوراً (إنشاء جديد أو إدخال المحفوظ)، مع رسالة
        // توضح ما حدث. أما المحاولة التلقائية (auto) عند الإقلاع/الاستئناف
        // فتبقى على شاشة البصمة دون قفز مفاجئ لوضع PIN.
        if (mounted && !auto) {
          final storedPin = await _readStoredPin();
          final needsSetup = storedPin == null;
          setState(() {
            _pinMode = true;
            _pinNeedsSetup = needsSetup;
            _pinResetMode = false;
            _pinInput = '';
            _errorMessage = needsSetup
                ? 'تعذر فتح البصمة — أنشئ رقم PIN مكونًا من 4 أرقام كبديل'.tr
                : 'تعذر فتح البصمة — أدخل رقم PIN الخاص بك'.tr;
          });
        }
        return;
      }

      if (mounted) {
        final storedPin = await _readStoredPin();
        final needsSetup = storedPin == null;
        setState(() {
          _pinMode = true;
          _pinNeedsSetup = needsSetup;
          _pinResetMode = false;
          _pinInput = '';
          _errorMessage = needsSetup
              ? 'أنشئ رقم PIN مكونًا من 4 أرقام'.tr
              : 'أدخل رقم PIN الخاص بك'.tr;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'خطأ في المصادقة: ${e.toString()}'.tr);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<String?> _readStoredPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_pinStorageKey);
    return pin != null && pin.isNotEmpty ? pin : null;
  }

  Future<void> _submitPin() async {
    if (_pinInput.length != 4) {
      setState(() => _errorMessage = 'أدخل 4 أرقام فقط'.tr);
      return;
    }

    final storedPin = await _readStoredPin();
    if (storedPin == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pinStorageKey, _pinInput);
      setState(() {
        _unlocked = true;
        _pinMode = false;
        _pinNeedsSetup = false;
        _pinResetMode = false;
        _pinInput = '';
        _errorMessage = null;
      });
      AppLockState.instance.unlock();
      return;
    }

    if (_pinResetMode) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pinStorageKey, _pinInput);
      setState(() {
        _unlocked = true;
        _pinResetMode = false;
        _pinMode = false;
        _pinNeedsSetup = false;
        _pinInput = '';
        _errorMessage = null;
      });
      AppLockState.instance.unlock();
      return;
    }

    if (_pinInput == storedPin) {
      setState(() {
        _unlocked = true;
        _pinMode = false;
        _pinNeedsSetup = false;
        _pinResetMode = false;
        _pinInput = '';
        _errorMessage = null;
      });
      AppLockState.instance.unlock();
      return;
    }

    setState(() {
      _pinInput = '';
      _errorMessage = 'رقم PIN غير صحيح'.tr;
    });
  }

  Future<void> _resetPin() async {
    final storedPin = await _readStoredPin();
    if (storedPin == null) {
      setState(() {
        _pinMode = true;
        _pinResetMode = false;
        _pinNeedsSetup = true;
        _pinInput = '';
        _errorMessage = 'أنشئ رقم PIN مكونًا من 4 أرقام'.tr;
      });
      return;
    }

    setState(() {
      _pinMode = true;
      _pinResetMode = true;
      _pinNeedsSetup = false;
      _pinInput = '';
      _errorMessage = 'أدخل رقم PIN الجديد'.tr;
    });
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked || !widget.store.patient.lockEnabled) {
      return widget.child;
    }
    final theme = Theme.of(context);
    final title = _pinMode
        ? (_pinNeedsSetup ? 'أنشئ PIN'.tr : 'ادخل PIN'.tr)
        : 'ALK مقفل'.tr;

    final subtitle = _pinMode
        ? (_pinNeedsSetup
            ? 'أنشئ رقم PIN مكونًا من 4 أرقام'.tr
            : (_pinResetMode
                ? 'أدخل رقم PIN الجديد'.tr
                : 'أدخل رقم PIN الخاص بك'.tr))
        : 'استخدم بصمة إصبعك أو رمز الجهاز للفتح'.tr;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_pinMode) ...[
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 4,
                      obscureText: true,
                      enabled: !_checking,
                      onChanged: (value) => _pinInput = value,
                      onSubmitted: (_) => _submitPin(),
                      decoration: InputDecoration(
                        labelText: _pinNeedsSetup ? 'PIN'.tr : 'PIN'.tr,
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _checking ? null : _submitPin,
                    icon: const Icon(Icons.lock_open),
                    label: Text('فتح'.tr),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _checking ? null : _resetPin,
                    child: Text('تغيير PIN'.tr),
                  ),
                  TextButton.icon(
                    onPressed: _checking ? null : () => _authenticate(),
                    icon: const Icon(Icons.fingerprint),
                    label: Text('استخدام البصمة'.tr),
                  ),
                ] else ...[
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _checking ? null : () => _authenticate(),
                    icon: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open),
                    label: Text(_checking ? 'جاري التحقق...'.tr : 'فتح'.tr),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
