# أيقونة التطبيق

## لإنشاء أيقونة التطبيق:

1. أنشئ صورة بحجم 1024×1024 بكسل بصيغة PNG
2. سمّها `app_icon.png` وضعها في هذا المجلد
3. أضف التالي إلى `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1

flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icon/app_icon.png"
```

4. شغّل:
```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

## مقاسات الأيقونات:

| المنصة | المجلد | المقاس |
|--------|--------|--------|
| Android | mipmap-mdpi | 48×48 |
| Android | mipmap-hdpi | 72×72 |
| Android | mipmap-xhdpi | 96×96 |
| Android | mipmap-xxhdpi | 144×144 |
| Android | mipmap-xxxhdpi | 192×192 |
| iOS | Assets.xcassets | مقاسات متعددة |

## الألوان المقترحة للأيقونة:

- الخلفية: #2563EB (الأزرق الأساسي)
- الرمز: #FFFFFF (الأبيض)
