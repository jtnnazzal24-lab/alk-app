# قواعد R8/ProGuard لإصدار release (minifyEnabled true).

# محرّك Flutter ونظام الإضافات (يُستدعى بالانعكاس من الجانب الأصلي).
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# السمات/التوقيعات التي تعتمد عليها مكتبات التحليل (Gson/JSON).
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses

# flutter_local_notifications يخزّن التنبيهات المجدولة بـ Gson.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }

# Health Connect.
-keep class androidx.health.** { *; }

# الإضافات التي تعتمد JNI/انعكاساً محدوداً.
-keep class com.tekartik.sqflite.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }
-keep class com.lib.flutter_blue_plus.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class net.wolverinebeach.flutter_timezone.** { *; }
-keep class com.eyedeadevelopment.fluttertts.** { *; }
-keep class com.csdcorp.speech_to_text.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
