# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## قواعد حماية صارمة — اقرأها قبل أي تعديل

ملفات/إعدادات ممنوع تعديلها بدون إذن صريح من المستخدم: `lib/main.dart`,
`lib/firebase_options.dart`, `android/app/google-services.json`,
`android/build.gradle` (تحديداً `applicationId`/`minSdkVersion`/
`targetSdkVersion`/`compileSdkVersion`/`signingConfigs`), `codemagic.yaml`،
ملفات التوقيع، أي ترقية لحزمة **موجودة أصلاً** بـ`pubspec.yaml`، وأسماء
حقول/مجموعات Firestore (خصوصاً `channels`, `categories`, `privateStreams`,
`settings/player`) — مشتركة مع `sports_player` (يقرأها عبر الووركر) ومع
`AHMED-dashboard` (يكتب فيها مباشرة). أي تعديل يمس هذي المناطق: توقف
واشرح للمستخدم ولا تفترض الموافقة.

**روابط m3u8 الحقيقية لا تُقرأ من هذا التطبيق مطلقاً** — لا حتى بمجموعة
`privateStreams` نفسها (`firestore.rules` تمنع القراءة العامة عنها
صراحة). أي وصول لرابط بث حقيقي يمر إجبارياً عبر `POST /getStreamUrl`
بالووركر (`cloudflare-worker/src/index.js`)، الذي يستخدم صلاحيات خادم
(Admin-equivalent) لا تصل لأي عميل.

## البنية المعمارية — منظومة 3 مستودعات

هذا المستودع (BinSheikh، اسم الحزمة الداخلي `sports_stream_app`) يتشارك
نفس مشروع Firebase (`sports-stream-app-36a7a`) ونفس Cloudflare Worker
(`binsheikh-api.<subdomain>.workers.dev`) مع:

- **sports_player** — تطبيق منفصل وظيفته الوحيدة تشغيل الفيديو (أفلام/
  مسلسلات/أنمي عبر اكتشاف WebView تلقائي من مواقع خارجية، ومباريات
  محمية عبر الووركر). هذا التطبيق (BinSheikh) **لا يفتح أي مصدر بث
  بنفسه للمحتوى العام** — يرسل معرّف القناة فقط عبر `PlayerLauncher`
  ويترك التشغيل الفعلي بالكامل لـsports_player.
- **AHMED-dashboard** — لوحة تحكم HTML/JS خام يديرها فريق المحتوى؛
  تكتب مباشرة بمجموعات Firestore هنا (`channels`/`categories`) وتستدعي
  `POST /import/site` بنفس الووركر لاستيراد كتالوجات مواقع خارجية.

### آلية تسليم القناة لتطبيق المشغل (`lib/core/services/player_launcher.dart`)

`PlayerLauncher.openChannel` هو المسار الوحيد الحقيقي لفتح محتوى (تستخدمه
`channel_card.dart`/`global_search_screen.dart`/`media_home_tab.dart`) —
بالترتيب: (1) `AndroidIntent` صريح موجَّه لاسم حزمة المشغل بالضبط
(`settings.androidPackage`) لضمان فتح sports_player تحديداً بدون نافذة
اختيار، (2) رابط عميق عام (`settings.deepLinkScheme://play?channelId=`)
كخطة بديلة، (3) نافذة تحميل المشغل من المتجر. هذي الإعدادات الثلاثة
(`deepLinkScheme`/`androidPackage`/`storeUrl`) تُقرأ حياً من مستند
Firestore `settings/player` — تتغيّر من لوحة التحكم بدون أي حاجة لإعادة
بناء/نشر التطبيق. حارس بسيط (`_lastOpenAt`, ثانية واحدة) يمنع فتح مزدوج
من ضغطة سريعة مكررة.

**كود ميت لاحظه ولا تُعِد استخدامه بالخطأ**: `lib/features/watch/
watch_screen.dart` و`lib/core/services/secure_stream_service.dart`
(يستدعي `/getStreamUrl` مباشرة من هذا التطبيق) — غير مستوردَين من أي
مكان آخر بالكود؛ بقايا من تصميم أقدم كان BinSheikh يشغّل المحتوى بنفسه
قبل فصل sports_player. المسار الحالي الوحيد هو `PlayerLauncher`.

### طبقة المحتوى (`lib/core/services/content_service.dart`)

كل الشاشات (`channels_screen`, `media_home_tab`, `global_search_screen`,
`favorites_screen`...) تُغذّى من `Stream`ات Firestore حيّة على مجموعتَي
`categories`/`channels` (لا حالة API/تخزين مؤقت وسيطة). `categoryId`
بمجموعة `categories` يحدّد التسلسل الهرمي (`parentId == null` = قسم
رئيسي). `ContentService.recordView` يزيد عدّاد `viewCount` بكتابة batch
غير حرجة (تُقرأ من لوحة التحكم لإحصائيات "الأكثر مشاهدة") — مسموحة بدون
تسجيل دخول بـ`firestore.rules` لكن **بشرط دقيق**: التعديل يقتصر على
`viewCount +1` فقط، أي حقل آخر يتطلب `request.auth`.

### `cloudflare-worker/` — الخادم الخلفي الموحَّد (ملف واحد رئيسي)

`src/index.js` (~1260 سطر) يخدم **كل** المنظومة بستة مسارات + بروكسي HLS:

- `POST /getStreamUrl` — يقرأ `privateStreams/{channelId}` (سيرفر فقط)،
  يدعم مصدر ثابت (`url`) أو API خارجي حي (`apiUrl`، يُجلب عند كل طلب
  ويُخزَّن كنسخة احتياطية عند نجاحه)، ثم **لا يُرجع الرابط الحقيقي أبداً** —
  يوقّع توكن HMAC مؤقّت (`signHlsToken`) ويبني رابط تشغيل يمر عبر الووركر
  نفسه (`buildHlsPlaybackUrl`).
- `GET /hls/:channelId/:file` (`handleHlsProxy`) — يتحقق من التوكن، يجلب
  من المصدر الحقيقي دون كشفه، ويعيد كتابة الـm3u8 بحيث كل segment يمر
  أيضاً عبر نفس الووركر.
- `POST /refreshMatches` / `/getMatchStats` / `/getPreMatchInfo` — مزامنة
  مباريات API-Football (مجدولة كل ساعة عبر `wrangler.toml` + يدوياً من
  لوحة التحكم)، تُخزَّن بمجموعة `matches_daily/{dateId}` (قراءة عامة،
  كتابة ممنوعة تماماً من أي عميل — Admin SDK فقط).
- `POST /import/site` (`handleSiteImport` + دوال `site*` العديدة) — يستورد
  كتالوج موقع خارجي (يستدعيه AHMED-dashboard). يحتوي منطق فرز نوع
  المحتوى (فلم/مسلسل/أنمي)، استخراج الحلقات، واستبعاد روابط ترقيم
  الصفحات (`siteLooksLikePagerLabel`) — **هذا هو نفس الملف اللي يحتاج
  تنسيق مع site-importer.js بـAHMED-dashboard عند تعديل منطق التصنيف**.
- `POST /ratings/search` — تقييمات (Jikan للأنمي بلا مفتاح، TMDB
  للأفلام/المسلسلات بمفتاح اختياري `TMDB_API_KEY`).

**`functions/index.js` (Firebase Cloud Functions) غير مستخدَم إطلاقاً
حالياً** — تعليق صريح بأول الملف يوضح إنه استُبدل بالكامل بالووركر
(تفادي اشتراط خطة Blaze)، محفوظ فقط كمرجع. لا تفترض إنه منشور أو يعمل.

راجع `cloudflare-worker/README.md` لخطوات النشر (`wrangler secret put`
لأربعة أسرار + `wrangler deploy`) — أي تعديل بمفاتيح/أسرار الووركر خارج
هذا المسار يحتاج تأكيد من المستخدم.

### `firestore.rules` — ملخص الصلاحيات

- `categories`/`channels`: قراءة عامة، كتابة تتطلب `request.auth` **إلا**
  زيادة `viewCount` بالضبط +1 (بلا تسجيل دخول).
- `settings/*`: قراءة عامة (يشمل `settings/player` أعلاه)، كتابة تتطلب
  تسجيل دخول.
- `contactMessages`: أي عميل يقدر ينشئ رسالة، القراءة/الإدارة محصورة
  بحساب لوحة التحكم.
- `privateStreams`: قراءة/كتابة تتطلبان تسجيل دخول بالكامل — **لا قراءة
  عامة إطلاقاً**، الووركر يتجاوز هذي القاعدة بصلاحيات خادم منفصلة.
- `matches_daily`: قراءة عامة، كتابة ممنوعة من أي عميل (Admin SDK فقط
  عبر الووركر).

## أوامر التطوير

```bash
flutter pub get                 # تثبيت التبعيات
flutter analyze                 # فحص ثابت
flutter test                    # الاختبارات (لا يوجد مجلد test/ حالياً)
```

البناء (Codemagic، `codemagic.yaml`): `flutter build apk --release
--split-per-abi` بلا أي إعداد توقيع مخصَّص (APK غير موقَّع بمفتاح إصدار
حقيقي بهذا الـworkflow — أبسط بكثير من إعداد sports_player).
