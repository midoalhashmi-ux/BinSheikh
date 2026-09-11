# التوثيق التقني — BinSheikh (تطبيق المحتوى + الووركر المشترك)

> هذا الملف مرجع تقني شامل لهذا المستودع، بحيث يقدر أي مبرمج أو نموذج ذكاء
> اصطناعي آخر يفهم بنية المشروع كاملة بدون الحاجة لقراءة كل الكود من الصفر.
> **كل تعديل جوهري أو إصلاح مشكلة لاحق يُضاف كصف جديد في جدول "سجل المشاكل
> والحلول" بالأسفل** — سطر واحد مختصر لكل عمود، بدون كود أو شرح مطوّل
> (التفاصيل الكاملة موجودة برسالة الكوميت نفسها، هذا الجدول فهرس سريع فقط).

## 1. نظرة عامة على المنظومة الكاملة (3 مستودعات مترابطة)

| المستودع | الدور |
|---|---|
| **BinSheikh** (هذا المستودع) | تطبيق المحتوى الرئيسي (Flutter/Android) — يعرض للمستخدم النهائي الأقسام/القنوات/الأفلام/المسلسلات/الأنمي/مباريات اليوم. يحتوي أيضاً كود الووركر المشترك (`cloudflare-worker/`) وقواعد أمان Firestore المُطبَّقة فعلياً على المشروع بالكامل (`firestore.rules`). |
| **sports_player** | تطبيق Flutter/Android منفصل، وظيفته الوحيدة تشغيل الفيديو الفعلي — يُفتح من هذا التطبيق عبر `app_links` بمعرّف قناة/حلقة. |
| **AHMED-dashboard** | لوحة تحكم ويب ثابتة (HTML/JS/CSS خام) يديرها فريق المحتوى — إضافة/تعديل الأقسام/القنوات، ومتابعة الإحصائيات. |

- **مشروع Firebase المشترك**: `sports-stream-app-36a7a` — راجع
  `lib/firebase_options.dart`.
- **Cloudflare Worker المشترك**: `https://binsheikh-api.binsheikh.workers.dev`
  (الكود المصدري هنا، `cloudflare-worker/`).

## 2. بنية `lib/`

- `core/models/` — `category_model`, `channel_model`, `match_model`,
  `match_stats_model`, `player_settings`, `pre_match_info_model`.
- `core/services/`:
  - `content_service.dart` — قراءة/كتابة `categories` + `channels`،
    وتسجيل عدّاد المشاهدات (`recordView`، راجع القسم 5 بالأسفل).
  - `matches_service.dart` + `match_stats_service.dart` +
    `pre_match_service.dart` — مباريات اليوم، تُقرأ مباشرة من
    `matches_daily` بـ Firestore (تُعبّأ عبر الووركر `/refreshMatches`،
    وليس عبر هذه الخدمات).
  - `secure_stream_service.dart` — يطلب رابط بث مؤقت من الووركر
    (`/getStreamUrl`) — نفس النقطة التي يستخدمها sports_player، لكن هنا
    تُستخدم فقط لأغراض مساعدة (وليس التشغيل الفعلي، الذي يتم بتطبيق
    sports_player المنفصل).
  - `favorites_service.dart`, `contact_service.dart`, `legal_service.dart`,
    `app_update_service.dart`, `app_settings_service.dart`,
    `feature_flags_service.dart`, `player_launcher.dart` (يفتح تطبيق
    sports_player عبر `app_links`), `worker_config.dart`.
- `features/` — `channels/`, `media/` (تصفح أفلام/مسلسلات/أنمي)،
  `matches/`، `favorites/`، `contact/`، `legal/`، `settings/` (تحديث
  إجباري)، `watch/`، وكذلك `home/home_shell.dart`.
- `widgets/` — `app_drawer.dart`, `rating_badge.dart`,
  `section_search_field.dart`.
- `main.dart` — تهيئة Firebase + بوابة تحديث إجباري (`_UpdateGateState`) +
  معالج أخطاء عام (`runZonedGuarded`/`FlutterError.onError`/
  `PlatformDispatcher.onError`، يسجّل عبر `debugPrint` فقط — لا توجد خدمة
  سجل مخصصة بهذا التطبيق كـ`SessionLogService` بـ sports_player).
- `theme/` — `app_theme.dart` + `dynamic_theme_service.dart` (ثيم ديناميكي
  من إعدادات لوحة التحكم).

## 3. `functions/` — Cloud Functions قديمة، **غير مستخدمة حالياً**

تم الانتقال بالكامل إلى Cloudflare Workers (القسم التالي) لتفادي اشتراط خطة
Firebase Blaze. الكود بـ `functions/index.js` (يتضمن `getStreamUrl` القديمة
ومزامنة مباريات من TheSportsDB) **محفوظ فقط كمرجع** ولن يعمل أي شيء منه إلا
بعد `firebase deploy --only functions` يدوياً — لا حاجة للمسّه حالياً.

## 4. `cloudflare-worker/` — الووركر المشترك بين الثلاثة

- **`src/index.js`** — نقطة الدخول، يوجّه المسارات:
  - `POST /getStreamUrl` — رابط بث مؤقت لقناة (يحلّ محل Cloud Function
    القديمة `getStreamUrl`).
  - `POST /refreshMatches` — يحدّث مباريات اليوم من API-Football إلى
    `matches_daily` (يتطلب مفتاح إداري).
  - `POST /getMatchStats` — إحصائيات مباراة.
  - `POST /getPreMatchInfo` — معلومات ما قبل المباراة.
  - `POST /import/site` — استيراد محتوى من موقع خارجي (يتطلب مفتاح إداري)
    — يُستخدم من `site-importer.js` بلوحة التحكم (AHMED-dashboard).
  - `POST /ratings/search` — بحث تقييمات TMDB/MyAnimeList — يُستخدم من
    `ratings.js` بلوحة التحكم.
  - `GET /hls/{channelId}/{file}` — بروكسي HLS محمي بتوكن.
- **`src/hls.js`** — توليد/التحقق من توكن HLS بتوقيع HMAC-SHA256 + مقارنة
  زمنية ثابتة (`timingSafeEqual`) لمنع هجوم توقيت (timing attack).
- **`src/firestore.js`** — عميل REST مباشر لـ Firestore من داخل الووركر
  (بدون Admin SDK — لا تدعمه بيئة Cloudflare Workers) — يستخدم مفتاح
  خدمة/توكن مخزَّن كسرّ Cloudflare (`wrangler secret`).
- **المفتاح الإداري** (`ADMIN_SYNC_SECRET`) يُتحقق منه الآن عبر
  `isAdminAuthorized()` موحّدة (بعد إصلاح هذه الجلسة، راجع سجل الحلول
  أدناه) بدل مقارنة نصية مباشرة.

## 5. `firestore.rules` — القواعد الفعلية المُطبَّقة على المشروع بالكامل

⚠️ هذا الملف موجود فعلياً هنا فقط، لكنه ينطبق على **مشروع Firebase
بالكامل** (المستخدَم أيضاً من BinSheikh وsports_player وAHMED-dashboard) —
أي تعديل عليه يتطلب `firebase deploy --only firestore:rules` من هذا
المجلد ليصبح فعلياً (تعديل الملف بالكود وحده لا يكفي أبداً).

- `categories`/`channels`: قراءة عامة (`allow read: if true`) بدون تسجيل
  دخول. الإنشاء/الحذف يتطلبان `request.auth != null` (حساب لوحة التحكم
  فقط). تحديث `viewCount` مسموح بدون تسجيل دخول لكن بشرط صارم: الحقل
  الوحيد المتغيّر هو `viewCount` وبالضبط +1 — أي محاولة تعديل حقل آخر أو
  زيادة بغير 1 تُرفض.
- `categories/{id}/dailyViews/{YYYY-MM-DD}` و
  `channels/{id}/dailyViews/{YYYY-MM-DD}` (أُضيفت هذه الجلسة): نفس منطق
  +1 بالضبط، لكن كمستند يومي منفصل بدل عدّاد تراكمي واحد — يسمح للوحة
  التحكم بفلترة الإحصائيات بمدى زمني (اليوم/آخر أسبوع/مدى مخصص). القراءة
  تتطلب تسجيل دخول (خاصة بلوحة التحكم فقط، ليست بيانات عامة).
- `privateStreams`: قراءة/كتابة لحساب لوحة التحكم فقط — لا يقرأها أي تطبيق
  عميل مباشرة (الووركر يصل لها عبر REST مباشر بصلاحيات خاصة تتجاوز هذه
  القواعد).
- `matches_daily`: قراءة عامة، كتابة ممنوعة تماماً من أي عميل.
- `contactMessages`: إنشاء عام (رسالة تواصل/إبلاغ)، قراءة/تعديل/حذف لحساب
  لوحة التحكم فقط.

## 6. تدفق عدّاد المشاهدات (`dailyViews`) — الميزة المُضافة هذه الجلسة

1. عند فتح المستخدم قناة/حلقة في BinSheikh، `content_service.dart` →
   `recordView(channelId, categoryId?)`.
2. يحسب `dateId` بتوقيت UTC (`YYYY-MM-DD`) لمطابقة ما تتوقعه لوحة التحكم
   بالضبط.
3. `batch` واحد يزيد: `channels/{id}.viewCount +1`،
   `channels/{id}/dailyViews/{dateId}.count +1`، وإن وُجد قسم: نفس
   الشيئين لـ `categories/{categoryId}`.
4. **غير حرج أبداً**: أي فشل (لا إنترنت مثلاً) يُبتلع بصمت (`catch` فاضٍ)
   ولا يعطّل فتح القناة نفسها أبداً.

⚠️ **ملاحظة مهمة جداً**: هذا الكود مدفوع للمستودع لكن **لم يُبنَ وينشر بعد
عبر Codemagic** — أي أن `dailyViews` لن تبدأ الكتابة فعلياً في الإنتاج حتى
يُعاد بناء تطبيق BinSheikh نفسه ونشره. قواعد Firestore وحدها (المنشورة
فعلاً) لا تكفي لتشغيل هذه الميزة.

## سجل المشاكل والحلول

| # | المشكلة | الحل | الكوميت |
|---|---|---|---|
| 1 | فحوصات null ميتة (`storeUrl` غير nullable أصلاً) بملفَين | إزالتها | `4f5ea3a` |
| 2 | لا معالج أخطاء عام بـ`main.dart` | `runZonedGuarded`+`FlutterError.onError`+`PlatformDispatcher.onError` (`debugPrint` فقط) | نفس `4f5ea3a` |
| 3 | `MediaCategoriesScreen` عام رغم استخدامه محلياً فقط (lint) | إعادة تسمية لـ`_MediaCategoriesScreen` | نفس الكوميت |
| 4 | استيراد غير مستخدم بـ`app_update_dialog.dart` | إزالته | نفس الكوميت |
| 5 | حقل ميت `_info` بـ`_UpdateGateState` | إزالته | نفس الكوميت |
| 6 | تحقق المفتاح الإداري بالووركر بمقارنة نصية مباشرة (عرضة نظرياً لـtiming attack) بـ3 نقاط | توحيد عبر `isAdminAuthorized()`/`timingSafeEqual` | `4f5ea3a` |
| 7 | `viewCount` تراكمي بلا بُعد زمني → لا فلترة تاريخية بإحصائيات لوحة التحكم | بنية `dailyViews` يومية (قواعد Firestore + كتابة `content_service.dart`) — ⚠️ قواعد Firestore منشورة فعلاً، لكن كود BinSheikh نفسه لم يُبنَ/يُنشر بعد | `0354bde` |
| 8 | استيراد المواقع (`site-importer.js`/الووركر): حلقة من أنمي مختلف تسربت لاستيراد أنمي آخر — `siteBelongsToShow` كان يكتفي بكلمة مشتركة واحدة فقط (كافية للتطابق العرضي بين عملين مختلفين) | يتطلب الآن كلمتين متطابقتين على الأقل لو كان للمرشّح كلمتان دالتان فأكثر | `6c2c560` — ⚠️ يحتاج `npx wrangler deploy` من `cloudflare-worker/` |
| 9 | تخمين نوع المحتوى (أنمي/مسلسل) بالاستيراد بلا إشارة بنائية موثوقة، لا مجموعة بيانات لتصحيحه يدوياً | مجموعة Firestore جديدة `importSites/{domain}` (سجل مواقع معروفة بنوع مؤكَّد لكل دومين) — تُقرأ من `AHMED-dashboard/site-importer.js`؛ إداري بالكامل (`request.auth != null`)، لا يقرأها تطبيق المحتوى ولا المشغل | `56914c1` — ⚠️ يحتاج `firebase deploy --only firestore:rules --project sports-stream-app-36a7a` |
| 10 | استيراد عنصر بلا صورة حقيقية أو بصورة معطوبة كان يظهر بلوقو/أيقونة الموقع نفسه بدل تركه بلا صورة (og:image الافتراضي لإضافات Yoast/RankMath) | `siteLooksLikeSiteLogo` تستبعد أي رابط صورة يشبه لوقو/أيقونة/بديل افتراضي بكل نقاط الاستخراج؛ الأولوية: og:image حقيقي ← صورة بطاقة القائمة ← مسح صفحة العنصر ← بلا صورة (العنصر يُستورد طبيعياً بدون حذف) | `68f7dc3` — ⚠️ يحتاج `npx wrangler deploy` من `cloudflare-worker/` |
