# سيّار | SAYYAR — حزمة المصدر المصححة

هذه حزمة مصدر Flutter لتطبيق سيّار، وليست APK جاهزاً.

## محتويات الحزمة
- `lib/main.dart`: واجهة عربية وخريطة وبحث أماكن ومسار تجريبي وإرشاد صوتي أولي.
- `pubspec.yaml`: حزم Flutter وقيد Dart SDK مصحح.
- `.github/workflows/build-apk.yml`: بناء APK عبر GitHub Actions وإضافة صلاحيات الإنترنت والموقع.
- `android_notes/AndroidManifest_permissions.txt`: مرجع للصلاحيات.

## رفع الملفات إلى مستودع GitHub
استخرج ZIP، ثم استبدل الملفات ذات الأسماء نفسها في المستودع: `pubspec.yaml` و`lib/main.dart` و`.github/workflows/build-apk.yml` و`README_AR.md` و`android_notes/AndroidManifest_permissions.txt`. حافظ على المسارات كما هي. بعد حفظ التغييرات افتح Actions وشغّل `Build SAYYAR APK`.

## ملاحظات مهمة
هذه نسخة مصدر مصححة مبدئياً وليست نسخة نهائية مختبرة على هاتف. نجاح البناء لا يضمن عمل كل ميزة على كل جهاز. البحث يعتمد على خدمة Nominatim العامة والتوجيه على خادم Valhalla تجريبي، وقد تكون الخدمات محدودة أو غير متاحة أحياناً. الخريطة الحالية ثنائية الأبعاد وليست ملاحة ثلاثية الأبعاد كاملة.
