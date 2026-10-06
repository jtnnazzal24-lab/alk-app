package com.alk.health

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// MainActivity with a small launch bridge:
/// - Static launcher shortcuts (long-press icon / "Hey Google") can open the
///   app with extra `screen=voice` to land directly on the voice assistant.
/// - Flutter asks for it via MethodChannel `alk/launch` (initialScreen) and
///   receives `screen` events on subsequent voice launches (singleTop).
///
/// الأمان:
///  * FLAG_SECURE يمنع لقطات الشاشة ومعاينة «التطبيقات الحديثة» لبيانات المريض.
///  * الـ extra `screen` يُقبل من الاختصار الرسمي (ACTION_VIEW) فقط؛ وأي شاشة
///    تُفتح في التطبيق تمرّ أصلاً بحاجز القفل (LockGate) عند تفعيله.
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alk/launch")
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "initialScreen") {
                result.success(screenExtra(intent) ?: "")
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val screen = screenExtra(intent)
        if (screen != null) channel?.invokeMethod("screen", screen)
    }

    /// يعيد قيمة الـ extra `screen` للاختصار الرسمي فقط (ACTION_VIEW) ويتجاهل
    /// أي Intent قادم من تطبيق آخر بفعل/صيغة مختلفة.
    private fun screenExtra(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_VIEW) return null
        return intent.getStringExtra(EXTRA_SCREEN)
    }

    companion object {
        const val EXTRA_SCREEN = "screen"
    }
}
