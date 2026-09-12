# دليل البناء المحلي (Windows) — BinSheikh

> نفس بيئة جهاز المستخدم الموثَّقة بتفصيل أكبر بـ`sports_player/CLAUDE.md`
> (المستودع الشقيق، نفس الجهاز) — راجعه لو واجهت مشكلة جافا/Gradle/git
> عامة غير مذكورة هنا تحديداً.

## بيئة جهاز المستخدم (Windows، حساب DELL)

- المستودع مستنسخ بمسار: `C:\Users\DELL\Downloads\BinSheikh`
- **استخدم دائماً المسار الكامل لـFlutter** (نفس الجهاز فيه أكثر من نسخة
  Flutter مختلفة على PATH):
  ```
  C:\Users\DELL\Desktop\flutter\flutter\bin\flutter.bat
  ```
  (Flutter 3.47.2 / Dart 3.13.2 — تأكَّد بـ`flutter.bat --version` قبل أي تشخيص).
- **جافا 17 مطلوبة** (نفس إعداد sports_player بالضبط):
  ```powershell
  flutter config --jdk-dir="C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot"
  [System.Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot', 'User')
  ```
  (أغلق PowerShell وافتح واحدة جديدة بعد `SetEnvironmentVariable`).

## أمر البناء

```powershell
cd C:\Users\DELL\Downloads\BinSheikh
git pull
C:\Users\DELL\Desktop\flutter\flutter\bin\flutter.bat build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

الناتج بـ`build\app\outputs\flutter-apk\` — ثبّت `app-arm64-v8a-release.apk`
على الهاتف (أغلب الأجهزة الحديثة).

**التوقيع**: `android/app/build.gradle` هنا يستخدم `signingConfigs.debug`
مباشرة بلا شرط CI — بناء محلي يشتغل من أول محاولة بلا مشكلة توقيع (على
عكس sports_player التي كانت مربوطة حصراً بمتغيرات بيئة Codemagic).

## مشكلة متكررة: `git pull` يرفض التحديث

راجع نفس القسم بـ`sports_player/CLAUDE.md` — نفس السبب (Flutter/Android
Studio يعدّل `pubspec.lock`/`analysis_options.yaml`/ملفات `android/`
تلقائياً) ونفس الحل:
```powershell
git diff <الملف>          # تأكد أنه تغيير تلقائي تافه
git checkout -- <الملف>
git pull
```

## هل BinSheikh منشور على Google Play Console؟

**غير مؤكَّد بعد** — sports_player (المشغّل) مؤكَّد منشور فعلياً؛ اسأل
المستخدم صراحة قبل أي تعديل قد يؤثر على نشر مستقبلي (رقم إصدار،
compileSdk/targetSdk/minSdk، توقيع) إن لم يكن مذكوراً بالمحادثة الحالية.
