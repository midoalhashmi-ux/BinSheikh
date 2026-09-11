import { getDoc, setDoc } from './firestore.js';
import {
  HLS_TOKEN_TTL_SECONDS,
  signHlsToken,
  verifyHlsToken,
  buildHlsPlaybackUrl,
  rewriteHlsPlaylist,
  timingSafeEqual,
} from './hls.js';

// ============================================================================
// بديل Firebase Cloud Functions لهذا المشروع — يعمل على Cloudflare Workers،
// بدون الحاجة لخطة Blaze أو حساب فوترة سعودي عبر CNTXT، وبنفس فكرة الحماية
// تماماً: كل سرّ (مفتاح API-Football، بيانات حساب خدمة Google) يبقى هنا
// فقط، ولا يصل إطلاقاً لكود الموبايل أو المتصفح.
//
// نقطتان يخدمهما هذا الملف:
//   1) POST /getStreamUrl   — يُستدعى من تطبيق المشغل، يرجّع رابط m3u8 الحقيقي.
//   2) POST /refreshMatches — يُستدعى من لوحة التحكم (زر "مزامنة الآن").
//   3) scheduled()          — Cron Trigger كل ساعة، نفس منطق refreshMatches.
// ============================================================================

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, x-admin-key',
};

// مقارنة مفتاح الأدمن بوقت ثابت (راجع timingSafeEqual في hls.js) بدل
// مقارنة `!==` العادية المستخدمة سابقاً بكل نقاط التحقق الثلاث أدناه.
function isAdminAuthorized(request, env) {
  const adminKey = request.headers.get('x-admin-key') || '';
  return Boolean(env.ADMIN_SYNC_SECRET) && timingSafeEqual(adminKey, env.ADMIN_SYNC_SECRET);
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

// ---------------------------------------------------------------------------
// 1) getStreamUrl — نفس منطق دالة Firebase الأصلية بالضبط.
// ---------------------------------------------------------------------------
async function handleGetStreamUrl(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: 'invalid-argument', message: 'body غير صالح.' }, 400);
  }

  const channelId = body && body.channelId;
  if (!channelId || typeof channelId !== 'string') {
    return json({ error: 'invalid-argument', message: 'channelId مطلوب.' }, 400);
  }

  const [streamDoc, channelDoc] = await Promise.all([
    getDoc(env, `privateStreams/${channelId}`),
    getDoc(env, `channels/${channelId}`),
  ]);

  if (channelDoc && channelDoc.status === 'disabled') {
    return json({ error: 'permission-denied', message: 'هذه القناة موقوفة مؤقتاً.' }, 403);
  }

  if (channelDoc && channelDoc.protected === false && channelDoc.directUrl) {
    return json({ url: channelDoc.directUrl, expiresIn: null });
  }

  if (!streamDoc) {
    return json({ error: 'not-found', message: 'لم يتم تسجيل مصدر بث لهذه القناة بعد.' }, 404);
  }

  // لو القناة مربوطة برابط API خارجي (مثل سكربتات جلب الروابط اللحظية)،
  // نجيب الرابط الحقيقي "حي" من نفس هذا الـ API عند كل طلب مشاهدة فعلي —
  // بدل الاعتماد على رابط مخزَّن قديم قد يكون انتهى. لو الجلب الحي فشل
  // (السيرفر الخارجي واقف، أو رجّع شكل غير متوقع)، نرجع لآخر رابط ناجح
  // محفوظ في privateStreams.url بدل ما تنقطع المشاهدة بالكامل.
  let url = streamDoc.url;
  if (streamDoc.apiUrl && typeof streamDoc.apiUrl === 'string') {
    try {
      const liveResponse = await fetch(streamDoc.apiUrl, {
        headers: {
          'User-Agent': 'okhttp/4.12.0',
          'Accept': 'application/json',
        },
      });
      if (liveResponse.ok) {
        const liveBody = await liveResponse.json();
        if (liveBody && typeof liveBody.url === 'string' && liveBody.url) {
          url = liveBody.url;
          // نخزّن آخر رابط ناجح كنسخة احتياطية (fallback)، وننتظر اكتمال
          // الحفظ (لا fire-and-forget) لأن /hls (بروكسي التشغيل الفعلي)
          // يقرأ نفس هذا الحقل بعد لحظات — لازم يجده محدَّثاً فوراً.
          await setDoc(env, `privateStreams/${channelId}`, {
            url,
            apiUrl: streamDoc.apiUrl,
            updatedAt: new Date().toISOString(),
          }).catch(() => {});
        }
      }
    } catch (_) {
      // نتجاهل الخطأ ونكمل بالرابط المخزَّن (url) كنسخة احتياطية أدناه.
    }
  }

  if (!url || typeof url !== 'string') {
    return json({ error: 'not-found', message: 'رابط البث لهذه القناة غير مضبوط.' }, 404);
  }

  // بدل إرجاع رابط المصدر الحقيقي مباشرة (كان يبقى صالحاً 4 ساعات كاملة
  // ومكشوفاً بالكامل لأي حد يعترض الطلب أو يفحص التطبيق) — نرجّع رابط
  // موقّت يمر عبر هذا الـ Worker نفسه (بروكسي)، فرابط privateStreams
  // الحقيقي ما يوصل لجهاز المستخدم إطلاقاً ولا حتى لحظة واحدة.
  const requestUrl = new URL(request.url);
  const exp = Math.floor(Date.now() / 1000) + HLS_TOKEN_TTL_SECONDS;
  const sig = await signHlsToken(env, channelId, exp);
  const playbackUrl = buildHlsPlaybackUrl(requestUrl.origin, channelId, exp, sig);

  return json({ url: playbackUrl, kind: 'hls', expiresIn: HLS_TOKEN_TTL_SECONDS });
}

// ---------------------------------------------------------------------------
// 1.5) بروكسي بث HLS — يتحقق من التوكن، يجيب من المصدر الحقيقي (بدون
//      كشفه)، ويعيد كتابة الـ m3u8 ليمر كل segment عبر نفس الـ Worker.
// ---------------------------------------------------------------------------
async function handleHlsProxy(request, env, channelId, file) {
  const requestUrl = new URL(request.url);
  const exp = requestUrl.searchParams.get('exp');
  const sig = requestUrl.searchParams.get('sig');

  const valid = await verifyHlsToken(env, channelId, exp, sig);
  if (!valid) {
    return json({ error: 'invalid-token', message: 'رابط غير صالح أو منتهي.' }, 403);
  }

  const streamDoc = await getDoc(env, `privateStreams/${channelId}`);
  const originUrl = streamDoc && streamDoc.url;
  if (!originUrl || typeof originUrl !== 'string') {
    return json({ error: 'not-found', message: 'رابط البث لهذه القناة غير مضبوط.' }, 404);
  }

  // نفترض إن originUrl هو رابط ملف m3u8 الرئيسي؛ باقي الملفات (segments)
  // تُبنى بنفس مجلد المصدر مع اسم الملف المطلوب.
  const originBase = originUrl.substring(0, originUrl.lastIndexOf('/'));
  const targetUrl = file === 'playlist.m3u8' ? originUrl : `${originBase}/${file}`;

  const originResponse = await fetch(targetUrl, {
    headers: { 'user-agent': 'Mozilla/5.0' },
  });

  if (!originResponse.ok) {
    return json({ error: 'origin-fetch-failed', message: 'تعذر الوصول لمصدر البث.' }, 502);
  }

  if (file.endsWith('.m3u8')) {
    const text = await originResponse.text();
    const rewritten = rewriteHlsPlaylist(text, channelId, exp, sig, requestUrl.origin);
    return new Response(rewritten, {
      headers: {
        'content-type': 'application/vnd.apple.mpegurl',
        'cache-control': 'no-store',
        ...CORS_HEADERS,
      },
    });
  }

  // segments (.ts / .m4s) تُبثّ كما هي مباشرة بدون تحميلها كاملة بالذاكرة
  return new Response(originResponse.body, {
    headers: {
      'content-type': originResponse.headers.get('content-type') || 'video/mp2t',
      'cache-control': 'no-store',
      ...CORS_HEADERS,
    },
  });
}

// ---------------------------------------------------------------------------
// 2) مباريات اليوم — API-Football
// ---------------------------------------------------------------------------
//
// قائمة الدوريات/الكؤوس المسموحة فقط (نفس القائمة بالضبط الموجودة في
// lib/core/data/football_ar_translations.dart بالتطبيق) — نستبعد أي دوري
// آخر هنا مباشرة عند المصدر بدل الاعتماد فقط على فلترة التطبيق، حتى لا
// تُخزَّن أصلاً مئات مباريات الدرجة الثانية/الثالثة والدول غير المطلوبة في
// Firestore (توفير تخزين + سرعة تحميل الشاشة). القائمتان يجب أن تبقيا
// متطابقتين — أي إضافة دوري جديد لازم تنعكس بالملفين معاً.
const ALLOWED_LEAGUE_NAMES = new Set([
  'saudi professional league', 'saudi pro league', 'saudi king cup',
  'egyptian premier league',
  'uae arabian gulf league', 'uae pro league',
  'qatar stars league',
  'iraqi premier league',
  'kuwaiti premier league',
  'moroccan botola pro',
  'tunisian ligue 1',
  'algerian ligue professionnelle 1',
  'caf champions league', 'caf confederation cup',
  'afc champions league', 'afc champions league elite',
  'english premier league', 'premier league',
  'spanish la liga', 'la liga',
  'italian serie a', 'serie a',
  'german bundesliga', 'bundesliga',
  'french ligue 1', 'ligue 1',
  'uefa champions league', 'uefa europa league', 'uefa europa conference league',
  'fifa world cup', 'world cup',
  'fifa club world cup', 'club world cup',
  'world cup qualification caf', 'world cup - qualification africa',
  'world cup qualification afc', 'world cup - qualification asia',
  'africa cup of nations',
  'afc asian cup',
  'premier soccer league', 'betway premiership',
  'npfl', 'nigeria professional football league',
  'fa cup', 'copa del rey', 'coppa italia', 'dfb pokal', 'dfb-pokal',
  'coupe de france', 'efl cup', 'carabao cup',
]);

function isAllowedLeague(leagueName) {
  return ALLOWED_LEAGUE_NAMES.has((leagueName || '').toString().trim().toLowerCase());
}

function mapFixtureStatus(shortStatus) {
  const s = (shortStatus || '').toString().toUpperCase();
  if (['1H', '2H', 'HT', 'ET', 'P', 'LIVE', 'BT'].includes(s)) return 'LIVE';
  if (['FT', 'AET', 'PEN'].includes(s)) return 'FT';
  if (['PST', 'CANC', 'ABD', 'SUSP', 'INT'].includes(s)) return 'PST';
  return 'NS';
}

function normalizeFixture(fx) {
  const fixture = fx.fixture || {};
  const league = fx.league || {};
  const teams = fx.teams || {};
  const goals = fx.goals || {};

  const dateIso = (fixture.date || '').toString();
  const dateEvent = dateIso.split('T')[0] || '';
  const timePart = dateIso.split('T')[1] || '00:00:00';
  const strTime = timePart.replace(/[+-]\d{2}:\d{2}$/, '').replace('Z', '');

  return {
    idEvent: String(fixture.id ?? ''),
    strLeague: league.name || '',
    // ناقص سابقاً — بدونه أي دوري بنفس الاسم بأكثر من دولة (Premier
    // League إنجلترا/مصر، Serie A إيطاليا/البرازيل، Bundesliga
    // ألمانيا/النمسا) يوصل للتطبيق بدولة فاضية، فتستبعده isSupportedLeague
    // بالكامل ظناً منه أن التصنيف غير مؤكد.
    strLeagueCountry: league.country || '',
    strLeagueBadge: league.logo || null,
    strHomeTeam: (teams.home && teams.home.name) || '',
    strAwayTeam: (teams.away && teams.away.name) || '',
    strHomeTeamBadge: (teams.home && teams.home.logo) || null,
    strAwayTeamBadge: (teams.away && teams.away.logo) || null,
    // معرّفا الفريقين في API-Football — لازمان لجلب معلومات ما قبل
    // المباراة (getPreMatchInfo): آخر 5 مباريات لكل فريق + آخر مواجهات.
    homeTeamId: (teams.home && teams.home.id) ? String(teams.home.id) : null,
    awayTeamId: (teams.away && teams.away.id) ? String(teams.away.id) : null,
    dateEvent,
    strTime: strTime || '00:00:00',
    intHomeScore: goals.home ?? null,
    intAwayScore: goals.away ?? null,
    strStatus: mapFixtureStatus(fixture.status && fixture.status.short),
    strVenue: (fixture.venue && fixture.venue.name) || null,
  };
}

async function fetchFixturesOnce(env, dateStr) {
  const response = await fetch(
      `https://v3.football.api-sports.io/fixtures?date=${dateStr}`,
      { headers: { 'x-apisports-key': env.API_FOOTBALL_KEY } },
  );

  if (!response.ok) {
    throw new Error(`تعذر الاتصال بـ API-Football (${response.status}).`);
  }

  const body = await response.json();

  // API-Football يرجّع HTTP 200 حتى في حالة خطأ فعلي (مفتاح غير صالح،
  // انتهاء الحصة اليومية/الدقيقية، معامل غير صحيح...) — الخطأ يظهر فقط
  // داخل body.errors مع response فاضية. بدون هذا الفحص كانت كل هذه
  // الحالات تُعامَل بصمت على أنها "0 مباراة اليوم" بدل إظهار السبب
  // الحقيقي، وهذا على الأغلب هو سبب اختفاء كل المباريات فجأة.
  const apiErrors = body.errors;
  const hasApiErrors = apiErrors &&
      (Array.isArray(apiErrors) ? apiErrors.length > 0 : Object.keys(apiErrors).length > 0);
  if (hasApiErrors) {
    throw new Error(`API-Football رجّع خطأ: ${JSON.stringify(apiErrors)}`);
  }

  return (body.response || []).map(normalizeFixture);
}

async function fetchAndStoreFixtures(env, dateStr, { finalize = false, retryOnEmpty = false } = {}) {
  let allEvents = await fetchFixturesOnce(env, dateStr);

  // السبب الفعلي وراء "الساعة 6 = صفر، الساعة 7 = 300، الساعة 8 = صفر...":
  // API-Football نفسه يرجّع أحياناً استجابة فارغة تماماً لطلب سليم 100%
  // (بدون أي خطأ HTTP ولا خطأ داخل body.errors) ثم يرجّع النتائج الصحيحة
  // فوراً عند إعادة نفس الطلب بعد ثوانٍ — وهذا ما كان يفسّر لماذا "مزامنة
  // الآن" اليدوية كانت تُصلح الوضع فوراً بعد ظهوره فارغاً تلقائياً. الحل:
  // إعادة محاولة واحدة بعد مهلة قصيرة قبل اعتماد نتيجة فارغة، فقط أثناء
  // المزامنة التلقائية غير المراقَبة (retryOnEmpty=true) حيث لا يوجد
  // مستخدم ينتظر الرد فوراً كما في زر "مزامنة الآن" اليدوي.
  if (allEvents.length === 0 && retryOnEmpty) {
    await new Promise((resolve) => setTimeout(resolve, 8000));
    try {
      allEvents = await fetchFixturesOnce(env, dateStr);
    } catch (_) {
      // تجاهل فشل إعادة المحاولة — نكمل بالنتيجة الفارغة الأصلية ونطبّق
      // حماية "عدم الكتابة فوق بيانات جيدة سابقة" أدناه.
    }
  }

  // الطلب بدون أي تصفية يرجّع مئات المباريات يومياً (كل درجات ودوريات
  // العالم، حتى الدرجات الهاوية والشبابية المغمورة والدول غير المطلوبة).
  // نطبّق فلترين معاً:
  //   1) isAllowedLeague — يستبعد أي دوري ليس ضمن القائمة المعتمدة
  //      (درجة أولى فقط من الدوريات/الكؤوس المطلوبة).
  //   2) شعارات كاملة — الدوريات المسموحة نفسها نادراً ما ينقصها شعار،
  //      لكن نُبقي الفحص احتياطاً لمنع أي صورة مكسورة.
  const events = [];
  let excludedLeagueCount = 0;
  let excludedBadgeCount = 0;
  const excludedLeagueSample = new Set();

  for (const event of allEvents) {
    if (!isAllowedLeague(event.strLeague)) {
      excludedLeagueCount++;
      if (excludedLeagueSample.size < 15) excludedLeagueSample.add(event.strLeague);
      continue;
    }
    if (!(event.strHomeTeamBadge && event.strAwayTeamBadge && event.strLeagueBadge)) {
      excludedBadgeCount++;
      continue;
    }
    events.push(event);
  }

  // حماية إضافية: إن رجعت هذه المزامنة بصفر مباراة رغم إعادة المحاولة،
  // ولدينا فعلاً بيانات جيدة مخزّنة سابقاً لنفس اليوم، لا نمسحها بصفر —
  // على الأرجح هذه استجابة مؤقتة من API-Football وليست حقيقة "لا مباريات
  // اليوم". نُحدّث updatedAt فقط ليعكس وقت آخر محاولة، ونُبقي المباريات
  // كما هي حتى المزامنة التالية.
  if (events.length === 0 && retryOnEmpty) {
    const existing = await getDoc(env, `matches_daily/${dateStr}`);
    if (existing && Array.isArray(existing.events) && existing.events.length > 0) {
      await setDoc(env, `matches_daily/${dateStr}`, {
        ...existing,
        updatedAt: new Date(),
      });
      return {
        count: existing.events.length,
        rawCount: existing.rawResultsCount ?? existing.events.length,
        keptExisting: true,
      };
    }
  }

  await setDoc(env, `matches_daily/${dateStr}`, {
    events,
    updatedAt: new Date(),
    source: 'api-football',
    rawResultsCount: allEvents.length,
    // تشخيص مؤقت: يوضح سبب استبعاد كل مباراة لم تظهر في القائمة النهائية،
    // بدل التخمين. excludedLeagueSample أسماء دوريات فعلية من المصدر لم
    // تُطابق isAllowedLeague — تفيد لو الاسم مختلف عمّا هو متوقع بالقائمة.
    debugExcludedByLeague: excludedLeagueCount,
    debugExcludedByBadge: excludedBadgeCount,
    debugExcludedLeagueSample: Array.from(excludedLeagueSample),
    // finalized = true يعني "يوم ماضٍ اكتملت نتائجه ولن يُعاد جلبه مرة
    // أخرى" — هذا هو أساس توفير حصة API-Football عند تفعيل نافذة الأيام
    // الماضية (راجع runScheduledSync أدناه).
    finalized: finalize,
  });

  return { count: events.length, rawCount: allEvents.length };
}

function todayDateKey() {
  return dateKeyOffset(0);
}

// يرجّع مفتاح تاريخ (YYYY-MM-DD) بإزاحة أيام عن اليوم الحالي (UTC).
// offset موجب = أيام قادمة، سالب = أيام ماضية.
function dateKeyOffset(offsetDays) {
  const now = new Date();
  now.setUTCDate(now.getUTCDate() + offsetDays);
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}-${String(now.getUTCDate()).padStart(2, '0')}`;
}

// ---------------------------------------------------------------------------
// مزامنة نافذة 7 أيام (من -3 إلى +3) بأقل استهلاك ممكن لحصة API-Football:
//   - اليوم: تُجلب كل ساعة (نفس ما كان سابقاً) لأنها الوحيدة التي تحتاج
//     تحديث نتائج مباشر خلال اليوم.
//   - الأيام القادمة (+1 إلى +3): تُجلب مرة واحدة فقط يومياً (عند الساعة
//     0 بتوقيت UTC) — الجدول لا يتغير كل ساعة، يكفي تحديث يومي (يلتقط
//     أي تأجيل/تعديل موعد).
//   - الأيام الماضية (-1 إلى -3): تُجلب مرة واحدة واحدة فقط طوال عمرها
//     (عند تحوّلها لأول مرة إلى "يوم ماضٍ")، ثم تُعلَّم finalized=true
//     ولا يُعاد الاتصال بـ API-Football لأجلها إطلاقاً بعد ذلك — نتيجة
//     مباراة منتهية لن تتغير.
//
// الحصيلة: 24 طلب/يوم (اليوم كل ساعة) + ~4 طلبات إضافية فقط مرة واحدة
// يومياً (3 أيام قادمة + يوم ماضٍ واحد جديد) ≈ 28 طلب/يوم، بدل 168 لو
// جُلبت كل الأيام السبعة كل ساعة.
async function runScheduledSync(env) {
  try {
    // retryOnEmpty: true — هذه هي المزامنة التلقائية غير المراقَبة، فمن
    // الأفضل تحمّل ثانية إضافية لإعادة محاولة عند استجابة فارغة بدل تخزين
    // "0 مباراة" خاطئة قد تبقى ظاهرة للمستخدمين ساعة كاملة حتى المزامنة
    // التالية.
    await fetchAndStoreFixtures(env, dateKeyOffset(0), { retryOnEmpty: true });
  } catch (_) {
    // فشل مزامنة اليوم لا يجب أن يمنع محاولة مزامنة الأيام القادمة/الماضية
    // أدناه (كانت سابقاً تتوقف بالكامل لأن هذا الاستدعاء لم يكن ضمن try/catch،
    // فأي خطأ عابر بمصدر البيانات كان يُسقط التشغيل كله لتلك الساعة).
  }

  const hour = new Date().getUTCHours();

  // مشكلة كانت هنا: الأيام القادمة (غداً وبعد غد...) كانت تُجلب فقط عند
  // الساعة 0 UTC بالضبط. لو التطبيق فُتح في أي وقت آخر قبل أول تشغيل
  // للووركر بعد منتصف الليل (مثلاً بعد نشر أول مرة، أو بعد توقف مؤقت)،
  // يبقى مستند "غداً" غير موجود إطلاقاً في Firestore طوال اليوم كامل،
  // فتظهر الشاشة فارغة رغم وجود مباريات فعلية. الحل: نجلب اليوم القادم
  // فوراً لو مستنده غير موجود أصلاً (بغض النظر عن الساعة)، ثم نكتفي
  // بتحديث مرة واحدة يومياً عند منتصف الليل بعد أول تعبئة (لالتقاط أي
  // تأجيل/تعديل موعد لاحقاً) — بدون أي زيادة في استهلاك الحصة اليومية
  // في الوضع المستقر.
  for (const offset of [1, 2, 3]) {
    const dateStr = dateKeyOffset(offset);
    try {
      const existing = await getDoc(env, `matches_daily/${dateStr}`);
      if (!existing || hour === 0) {
        await fetchAndStoreFixtures(env, dateStr, { retryOnEmpty: true });
      }
    } catch (_) {
      // تجاهل فشل يوم قادم واحد، لا نوقف بقية المزامنة بسببه.
    }
  }

  for (const offset of [-1, -2, -3]) {
    const dateStr = dateKeyOffset(offset);
    try {
      const existing = await getDoc(env, `matches_daily/${dateStr}`);
      if (existing && existing.finalized === true) continue;
      if (!existing || hour === 0) {
        await fetchAndStoreFixtures(env, dateStr, { finalize: true, retryOnEmpty: true });
      }
    } catch (_) {
      // نفس الشيء — يوم ماضٍ واحد يفشل لا يوقف البقية، وسيُعاد المحاولة
      // غداً تلقائياً لأنه لن يكون finalized بعد.
    }
  }
}

async function handleRefreshMatches(request, env) {
  if (!isAdminAuthorized(request, env)) {
    return json({ error: 'permission-denied', message: 'غير مصرح.' }, 403);
  }

  let body = {};
  try {
    body = await request.json();
  } catch (_) {
    // body اختياري — لو ما أُرسل، نستخدم تاريخ اليوم.
  }

  // يدعم مزامنة يوم واحد (body.date) أو نافذة الأيام كاملة دفعة واحدة
  // (body.syncWindow = true) — مفيد لزر "مزامنة الآن" بلوحة التحكم بعد
  // نشر هذا التحديث لأول مرة، حتى تمتلئ الأيام السبعة فوراً بدل انتظار
  // المزامنة التلقائية اليومية.
  if (body.syncWindow === true) {
    const results = {};
    for (const offset of [-3, -2, -1, 0, 1, 2, 3]) {
      const dateStr = dateKeyOffset(offset);
      try {
        results[dateStr] = await fetchAndStoreFixtures(env, dateStr, { finalize: offset < 0, retryOnEmpty: true });
      } catch (error) {
        results[dateStr] = `error: ${String(error && error.message || error)}`;
      }
    }
    return json({ ok: true, results });
  }

  const dateStr = body.date || todayDateKey();
  try {
    const { count, rawCount } = await fetchAndStoreFixtures(env, dateStr, { retryOnEmpty: true });
    return json({ ok: true, count, rawCount, date: dateStr });
  } catch (error) {
    return json({ ok: false, message: String(error && error.message || error) }, 500);
  }
}

// ---------------------------------------------------------------------------
// 3) إحصائيات مباراة واحدة عند فتحها من التطبيق (استحواذ، تسديدات،
//    ركنيات، بطاقات...) — مع كاش بـ Firestore حتى يشترك كل المستخدمين
//    بنفس النتيجة المخزّنة بدل أن يستهلك كل ضغطة من كل مستخدم طلب
//    API-Football منفصل:
//      - مباراة منتهية: تُخزّن نهائياً، لا يُعاد جلبها أبداً بعد أول مرة.
//      - مباراة مباشرة: كاش لمدة دقيقة واحدة فقط قبل إعادة الجلب.
//      - مباراة لم تبدأ: لا يُرسل أي طلب لـ API-Football أصلاً (العميل
//        يتحقق من الحالة محلياً قبل الاتصال بهذه النقطة).
// ---------------------------------------------------------------------------
const LIVE_STATS_CACHE_MS = 60 * 1000;

async function handleGetMatchStats(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: 'invalid-argument', message: 'body غير صالح.' }, 400);
  }

  const fixtureId = body && body.fixtureId;
  if (!fixtureId || typeof fixtureId !== 'string') {
    return json({ error: 'invalid-argument', message: 'fixtureId مطلوب.' }, 400);
  }

  const cacheKey = `matches_stats/${fixtureId}`;
  const cached = await getDoc(env, cacheKey);
  const now = Date.now();

  if (cached) {
    const isFresh = cached.matchFinished === true
        || (now - (cached.fetchedAtMs || 0)) < LIVE_STATS_CACHE_MS;
    if (isFresh) {
      return json({ statistics: cached.statistics, cached: true });
    }
  }

  let response;
  try {
    response = await fetch(
        `https://v3.football.api-sports.io/fixtures/statistics?fixture=${encodeURIComponent(fixtureId)}`,
        { headers: { 'x-apisports-key': env.API_FOOTBALL_KEY } },
    );
  } catch (_) {
    if (cached) return json({ statistics: cached.statistics, cached: true, stale: true });
    return json({ error: 'upstream-error', message: 'تعذر الاتصال بمصدر الإحصائيات.' }, 502);
  }

  if (!response.ok) {
    if (cached) return json({ statistics: cached.statistics, cached: true, stale: true });
    return json({ error: 'upstream-error', message: 'تعذر جلب الإحصائيات حالياً.' }, 502);
  }

  const data = await response.json();
  const rawTeams = data.response || [];

  if (rawTeams.length === 0) {
    return json({ statistics: null, message: 'لا توجد إحصائيات متاحة لهذه المباراة بعد.' });
  }

  const statistics = rawTeams.map((team) => ({
    teamId: (team.team && team.team.id) ?? null,
    teamName: (team.team && team.team.name) || '',
    stats: (team.statistics || []).map((s) => ({ type: s.type, value: s.value })),
  }));

  // نعتمد على العميل لإخبارنا هل المباراة انتهت (body.finished) بدل
  // طلب API إضافي فقط لمعرفة الحالة — الحالة أصلاً معروفة عند العميل
  // من matches_daily.
  const matchFinished = body.finished === true;

  await setDoc(env, cacheKey, {
    statistics,
    matchFinished,
    fetchedAtMs: now,
  });

  return json({ statistics, cached: false });
}

// ---------------------------------------------------------------------------
// 4) معلومات ما قبل المباراة: آخر 5 مباريات لكل فريق + آخر مواجهات مباشرة
//    بينهما. كاش مشترك بين كل المستخدمين لمدة 12 ساعة، بمفتاح مبني على
//    رقمي الفريقين فقط (بدون ترتيب مضيف/ضيف) — بهذا الشكل أي عدد من
//    المستخدمين يفتحون أي مباراة بين نفس الفريقين خلال نفس اليوم يشتركون
//    في 3 طلبات API-Football واحدة فقط بدل 3 طلبات لكل فتحة شاشة.
// ---------------------------------------------------------------------------
async function fetchApiFootballJson(env, path) {
  const response = await fetch(`https://v3.football.api-sports.io${path}`, {
    headers: { 'x-apisports-key': env.API_FOOTBALL_KEY },
  });
  if (!response.ok) {
    throw new Error(`API-Football HTTP ${response.status}`);
  }
  const body = await response.json();
  const apiErrors = body.errors;
  const hasApiErrors = apiErrors &&
      (Array.isArray(apiErrors) ? apiErrors.length > 0 : Object.keys(apiErrors).length > 0);
  if (hasApiErrors) {
    throw new Error(`API-Football رجّع خطأ: ${JSON.stringify(apiErrors)}`);
  }
  return body.response || [];
}

// يحوّل مباراة سابقة (من fixtures أو headtohead) إلى نتيجة مبسّطة من
// منظور فريق واحد (perspectiveTeamId) — فوز/تعادل/خسارة + الخصم + التاريخ.
// يتجاهل المباريات غير المنتهية (لا نتيجة نهائية بعد).
function buildFormEntry(fx, perspectiveTeamId) {
  const fixture = fx.fixture || {};
  const league = fx.league || {};
  const teams = fx.teams || {};
  const goals = fx.goals || {};
  const statusShort = (fixture.status && fixture.status.short) || '';
  if (!['FT', 'AET', 'PEN'].includes(statusShort)) return null;
  if (goals.home == null || goals.away == null) return null;

  const homeId = teams.home && teams.home.id;
  const isHome = String(homeId) === String(perspectiveTeamId);
  const dateIso = (fixture.date || '').toString();

  return {
    opponentEn: isHome ? ((teams.away && teams.away.name) || '') : ((teams.home && teams.home.name) || ''),
    teamScore: isHome ? goals.home : goals.away,
    opponentScore: isHome ? goals.away : goals.home,
    dateEvent: dateIso.split('T')[0] || '',
    leagueNameEn: league.name || '',
  };
}

const PRE_MATCH_CACHE_MS = 12 * 60 * 60 * 1000; // 12 ساعة

async function handleGetPreMatchInfo(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: 'invalid-argument', message: 'body غير صالح.' }, 400);
  }

  const homeTeamId = body && body.homeTeamId;
  const awayTeamId = body && body.awayTeamId;
  if (!homeTeamId || !awayTeamId) {
    return json({ error: 'invalid-argument', message: 'homeTeamId و awayTeamId مطلوبان.' }, 400);
  }

  // مفتاح الكاش لا يعتمد على ترتيب مضيف/ضيف — نفس زوج الفريقين يعيد
  // استخدام نفس النتيجة المخزّنة بغض النظر عن مين المضيف في هذه المباراة.
  const pairKey = [String(homeTeamId), String(awayTeamId)].sort().join('_');
  const cacheKey = `prematch_info/${pairKey}`;

  const cached = await getDoc(env, cacheKey);
  const now = Date.now();
  if (cached && (now - (cached.fetchedAtMs || 0)) < PRE_MATCH_CACHE_MS) {
    return json({ info: cached.info, cached: true });
  }

  try {
    const [h2hRaw, homeRaw, awayRaw] = await Promise.all([
      fetchApiFootballJson(env, `/fixtures/headtohead?h2h=${homeTeamId}-${awayTeamId}&last=5`),
      fetchApiFootballJson(env, `/fixtures?team=${homeTeamId}&last=5`),
      fetchApiFootballJson(env, `/fixtures?team=${awayTeamId}&last=5`),
    ]);

    const info = {
      h2h: h2hRaw.map((fx) => buildFormEntry(fx, homeTeamId)).filter(Boolean),
      homeForm: homeRaw.map((fx) => buildFormEntry(fx, homeTeamId)).filter(Boolean),
      awayForm: awayRaw.map((fx) => buildFormEntry(fx, awayTeamId)).filter(Boolean),
    };

    await setDoc(env, cacheKey, { info, fetchedAtMs: now });
    return json({ info, cached: false });
  } catch (error) {
    if (cached) return json({ info: cached.info, cached: true, stale: true });
    return json({ error: 'upstream-error', message: 'تعذر جلب معلومات ما قبل المباراة حالياً.' }, 502);
  }
}

// ---------------------------------------------------------------------------
// Site importer — generic server-side HTML reader used by the dashboard's
// "استيراد تلقائي من رابط موقع" feature. The admin pastes a catalog-page URL
// from ANY site (not one hardcoded domain); this route reads that public
// page and its own linked pages only. It does not alter any existing
// playback/API/HLS routes above.
// ---------------------------------------------------------------------------
const SITE_MAX_HTML = 2_000_000;
const SITE_MAX_RESULTS = 5000;
const SITE_JUNK_PATH = /\/(wp-content|wp-json|wp-admin|wp-login|feed|tag|category|page\/\d+|author|comments?|cart|checkout|login|register|contact|about|privacy|terms|sitemap|rss|search)(\/|$|\?)/i;

function siteDecodeHtml(value) {
  return String(value || '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)));
}

function siteText(value) {
  return siteDecodeHtml(String(value || '').replace(/<[^>]*>/g, ' '))
    .replace(/\s+/g, ' ').trim();
}

// Basic SSRF guard: this endpoint is admin-key gated, but we still refuse to
// let the worker fetch internal/loopback/link-local addresses on the admin's
// behalf.
function siteIsPrivateHost(hostname) {
  const h = String(hostname || '').toLowerCase();
  if (!h || h === 'localhost' || h.endsWith('.local')) return true;
  if (/^127\.|^0\.|^10\.|^169\.254\.|^192\.168\./.test(h)) return true;
  if (/^172\.(1[6-9]|2\d|3[0-1])\./.test(h)) return true;
  if (h === '::1' || h.startsWith('fc') || h.startsWith('fd') || h.startsWith('fe80')) return true;
  return false;
}

function siteAbsUrl(value, base) {
  try {
    const url = new URL(String(value || ''), base);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return '';
    if (siteIsPrivateHost(url.hostname)) return '';
    url.hash = '';
    return url.href;
  } catch (_) { return ''; }
}

// A few multi-part public suffixes where the naive "last two labels" rule
// below would wrongly treat unrelated sites as the same one (e.g. any two
// ".co.uk" sites). Not exhaustive — just covers common cases well enough
// for this heuristic.
const SITE_MULTIPART_SUFFIXES = new Set([
  'co.uk', 'org.uk', 'gov.uk', 'ac.uk', 'co.il', 'co.jp', 'co.nz', 'co.kr',
  'com.sa', 'com.eg', 'com.au', 'com.br', 'com.tr', 'com.cn', 'com.mx',
]);
function siteRegistrableDomain(hostname) {
  const parts = String(hostname || '').toLowerCase().split('.').filter(Boolean);
  if (parts.length <= 2) return parts.join('.');
  const lastTwo = parts.slice(-2).join('.');
  if (SITE_MULTIPART_SUFFIXES.has(lastTwo) && parts.length >= 3) return parts.slice(-3).join('.');
  return lastTwo;
}

// Many sites spread pages across sibling subdomains (e.g. episode pages on
// ww5.example.com while the show page is on ww4.example.com — confirmed on
// a real site during this session, where strict origin-matching silently
// dropped every real episode link and a fallback heuristic grabbed an
// unrelated nav link instead). Same registrable domain is treated as "the
// same site" instead of requiring an exact origin match.
function siteSameOrigin(url, baseHostname) {
  try { return siteRegistrableDomain(new URL(url).hostname) === siteRegistrableDomain(baseHostname); } catch (_) { return false; }
}

function siteImageFromTag(tag, base) {
  const attrs = String(tag || '');
  // "src" stays last on purpose: lazy-load scripts commonly leave a generic
  // placeholder (e.g. a "no poster" image) there until JS swaps it in from
  // one of these custom attributes, so checking src first would silently
  // return the placeholder for every single item instead of the real image.
  const names = ['data-image', 'data-src', 'data-lazy-src', 'data-original', 'data-echo', 'data-lazy', 'src'];
  for (const name of names) {
    const re = new RegExp('\\b' + name + '\\s*=\\s*["\']([^"\']+)["\']', 'i');
    const m = attrs.match(re);
    if (m) {
      const url = siteAbsUrl(m[1], base);
      if (url && !/\.svg(?:$|\?)/i.test(url)) return url;
    }
  }
  const srcset = attrs.match(/\bsrcset\s*=\s*["']([^"']+)["']/i);
  if (srcset) {
    const candidate = srcset[1].split(',').map(x => x.trim().split(/\s+/)[0]).find(Boolean);
    const url = siteAbsUrl(candidate, base);
    if (url) return url;
  }
  return '';
}

// Scans an arbitrary HTML fragment (e.g. a card/anchor's inner HTML) for a
// poster image, trying <img> tags first and then a CSS background-image —
// many Arabic streaming/anime WordPress themes render the poster as
// `<div class="poster" style="background-image:url(...)"></div>` with no
// <img> tag at all, which a naive <img>-only scan would miss entirely.
function siteImageFrom(html, base) {
  const imgs = String(html || '').match(/<img\b[^>]*>/gi) || [];
  for (const tag of imgs) {
    const url = siteImageFromTag(tag, base);
    if (url) return url;
  }
  const bg = String(html || '').match(/background(?:-image)?\s*:[^;"']*url\(\s*['"]?([^'")]+)['"]?\s*\)/i);
  if (bg) {
    const url = siteAbsUrl(bg[1], base);
    if (url) return url;
  }
  return '';
}

function siteExtractTitle(html, fallback = '') {
  const og = String(html || '').match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']*)["']/i);
  if (og) return siteText(og[1]);
  const h = String(html || '').match(/<h[1-2][^>]*>([\s\S]*?)<\/h[1-2]>/i);
  if (h) return siteText(h[1]);
  const title = String(html || '').match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (title) {
    const raw = siteText(title[1]);
    const parts = raw.split(/\s*[|–-]\s*/);
    if (parts.length > 1 && parts[parts.length - 1].split(' ').length <= 4) {
      const trimmed = parts.slice(0, -1).join(' - ').trim();
      if (trimmed) return trimmed;
    }
    return raw;
  }
  return siteText(fallback);
}

// Looks for a per-item thumbnail inside the anchor tag's own inner HTML first
// (the usual case for a catalog grid: <a><img src="..."></a>), and only
// falls back to the page-wide og:image when nothing is found there — using
// the page-wide image for every catalog item was a real bug in the previous
// RistoAnime-only version (every show got the same thumbnail).
function siteExtractThumbnail(html, base) {
  const og = String(html || '').match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i);
  if (og) {
    const url = siteAbsUrl(og[1], base);
    if (url) return url;
  }
  return siteImageFrom(html, base);
}

// A catalog/series card usually wraps unrelated badges (genre, quality,
// rating, a repeated episode-number badge) inside the same <a> as the real
// title — taking the whole anchor's text mixes all of that together. The
// anchor's own title="" attribute is the cleanest source when present (a
// common accessibility/SEO convention themes keep free of badge clutter);
// a heading tag inside the card is the next best signal; then an image's
// alt text; the full stripped text is only a last resort.
function siteLinkTitle(attrs, innerHtml, fallbackText) {
  const titleAttr = String(attrs || '').match(/\btitle\s*=\s*["']([^"']+)["']/i);
  if (titleAttr) { const t = siteText(titleAttr[1]); if (t) return t; }
  const h = String(innerHtml || '').match(/<h[1-6][^>]*>([\s\S]*?)<\/h[1-6]>/i);
  if (h) { const t = siteText(h[1]); if (t) return t; }
  const alt = String(innerHtml || '').match(/\balt\s*=\s*["']([^"']+)["']/i);
  if (alt) { const t = siteText(alt[1]); if (t) return t; }
  return siteText(fallbackText);
}

// Generic words that appear in almost every season/episode link on these
// sites and so carry no identifying signal (both languages, since sites mix
// Arabic and English/transliterated titles freely).
const SITE_STOPWORDS = new Set([
  'season', 'episode', 'online', 'translated', 'sub', 'dub', 'anime', 'series', 'watch', 'movie',
  'الموسم', 'الحلقة', 'الحلقه', 'مترجم', 'مترجمة', 'مترجمه', 'اون', 'لاين', 'اونلاين', 'انمي', 'انمى',
  'مشاهدة', 'تحميل', 'حلقة', 'حلقه', 'جميع', 'حلقات', 'مسلسل', 'مسلسلات', 'فيلم', 'افلام',
]);

function siteSignificantTokens(text) {
  const raw = String(text || '').toLowerCase();
  const tokens = raw.match(/[a-z0-9]+|[؀-ۿ]+/g) || [];
  return tokens.filter(t => t.length >= 3 && !SITE_STOPWORDS.has(t));
}

// A season/episode candidate must share at least one identifying word with
// the show it supposedly belongs to. Without this, a sidebar "latest
// episodes across the site" widget — common on these WordPress themes and
// present on nearly every page — gets misread as this show's own seasons,
// mixing in unrelated shows. If we have no tokens to compare against, stay
// permissive rather than silently discarding everything.
function siteBelongsToShow(candidateText, candidateUrl, showTokens) {
  if (!showTokens.length) return true;
  const tokens = siteSignificantTokens(`${candidateText} ${decodeURIComponent(candidateUrl)}`);
  return tokens.some(t => showTokens.includes(t));
}

function siteLinks(html, base) {
  const out = [];
  const re = /<a\b([^>]*?)\bhref\s*=\s*["']([^"']+)["']([^>]*)>([\s\S]*?)<\/a>/gi;
  let m;
  while ((m = re.exec(String(html || ''))) && out.length < SITE_MAX_RESULTS) {
    const url = siteAbsUrl(m[2], base);
    if (!url) continue;
    out.push({ url, text: siteText(m[4]), html: m[4], attrs: `${m[1]} ${m[3]}` });
  }
  return out;
}

// A numbered pager (1, 2, 3 ... 20) commonly repeats the same offset/page
// links in every direction (prev arrow, a disabled "current page" item, a
// jump-to-last-page link) — taking "whichever matching link happens to come
// last in the HTML" previously grabbed the current page's own link back
// instead of the real next one, silently truncating pagination after page 2
// on a real site. Comparing page numbers against the current page fixes it.
function siteNextPage(links, pageUrl) {
  for (const link of links) {
    if (/\bnext\b|التالي|الصفحة التالية|older posts/i.test(link.text)) return link.url;
  }
  let currentPage = 1;
  try {
    const u = new URL(pageUrl);
    const raw = u.searchParams.get('offset') || u.searchParams.get('page');
    if (raw && /^\d+$/.test(raw)) currentPage = Number(raw);
  } catch (_) { /* pageUrl missing/invalid — treat as page 1 */ }
  let best = null;
  for (const link of links) {
    const m = link.url.match(/[?&](?:offset|page)=(\d+)/i);
    if (!m) continue;
    const n = Number(m[1]);
    if (n > currentPage && (!best || n < best.n)) best = { n, url: link.url };
  }
  return best ? best.url : '';
}

function siteLooksLikeEpisode(text, url) {
  const s = `${text} ${decodeURIComponent(url)}`;
  return /الحلقة|الحلقه|episode|\bep[-_ ]?\d+/i.test(s);
}

function siteLooksLikeSeason(text, url) {
  return /الموسم|season/i.test(`${text} ${decodeURIComponent(url)}`);
}

function siteEpisodeNumber(text, url = '') {
  const s = decodeURIComponent(`${text} ${url}`);
  const patterns = [
    /(?:الحلقة|episode|ep|الحلقه)\s*[-#:：]?\s*(\d+(?:\.\d+)?)/i,
    /[-_ ](\d{1,4})(?:[-_ ]|$)/,
  ];
  for (const re of patterns) {
    const m = s.match(re);
    if (m) return Number(m[1]);
  }
  return null;
}

// Fallback for sites that list episodes without ever using the word
// "episode"/"الحلقة" — e.g. a row of plain numbered links. Groups links by
// their URL with the trailing number stripped and picks the largest group.
function siteDetectNumberedSeries(links, pageUrl) {
  const groups = new Map();
  for (const link of links) {
    if (link.url === pageUrl) continue;
    const m = link.url.match(/^(.*?)(\d+)\/?(?:[?#].*)?$/);
    if (!m) continue;
    const key = m[1];
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push({ ...link, num: Number(m[2]) });
  }
  let best = null;
  for (const arr of groups.values()) {
    if (arr.length >= 3 && (!best || arr.length > best.length)) best = arr;
  }
  return best ? best.sort((a, b) => a.num - b.num) : null;
}

async function siteFetchHtml(url) {
  const response = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; AHMED-dashboard site importer)',
      'Accept': 'text/html,application/xhtml+xml',
    },
    redirect: 'follow',
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const text = await response.text();
  if (text.length > SITE_MAX_HTML) return text.slice(0, SITE_MAX_HTML);
  return text;
}

function siteStripSlash(url) { return String(url || '').replace(/\/$/, ''); }

function siteParseCatalog(html, base) {
  const baseHostname = new URL(base).hostname;
  const basePath = siteStripSlash(base);
  const links = siteLinks(html, base).filter(l => siteSameOrigin(l.url, baseHostname) && siteStripSlash(l.url) !== basePath);
  const candidates = links.filter(l => l.text && !SITE_JUNK_PATH.test(new URL(l.url).pathname));

  // Group by first path segment (e.g. "/anime/one-piece" -> "anime") and use
  // the largest group — this is what makes catalog detection work on any
  // site's URL scheme instead of one hardcoded path prefix.
  const groups = new Map();
  for (const link of candidates) {
    const seg = new URL(link.url).pathname.split('/').filter(Boolean)[0] || '';
    if (!groups.has(seg)) groups.set(seg, []);
    groups.get(seg).push(link);
  }
  let chosen = [];
  for (const arr of groups.values()) if (arr.length > chosen.length) chosen = arr;
  if (chosen.length < 3) chosen = candidates;

  const result = [];
  const seen = new Set();
  for (const link of chosen) {
    if (seen.has(link.url)) continue;
    seen.add(link.url);
    // Deliberately no whole-page fallback here: this used to fall back to a
    // single page-wide image and stamp it on every catalog item (a real bug
    // in the old RistoAnime-only version). Leaving it null when the card has
    // no image of its own lets the show's own page (visited next) supply an
    // accurate poster instead of a wrong shared one.
    const thumb = siteImageFrom(link.html, base);
    result.push({ url: link.url, title: siteLinkTitle(link.attrs, link.html, link.text), thumbnail: thumb || null });
    if (result.length >= SITE_MAX_RESULTS) break;
  }
  return result;
}

function siteParseSeries(html, pageUrl, fallbackTitle = '', fallbackThumbnail = '') {
  const baseHostname = new URL(pageUrl).hostname;
  const basePath = siteStripSlash(pageUrl);
  const links = siteLinks(html, pageUrl).filter(l => siteSameOrigin(l.url, baseHostname) && siteStripSlash(l.url) !== basePath);
  const ownTitle = siteExtractTitle(html, fallbackTitle);
  const showTokens = siteSignificantTokens(`${fallbackTitle} ${ownTitle} ${decodeURIComponent(new URL(pageUrl).pathname)}`);
  const episodes = [];
  const seasons = [];
  const leftover = [];
  const seenEpisodes = new Set();
  const seenSeasons = new Set();
  for (const link of links) {
    // The card's own heading (siteLinkTitle), not the whole anchor's raw
    // text — cards on these themes commonly bleed adjacent-card text into
    // the same <a>'s stripped text, which previously caused unrelated
    // shows/episodes to be misclassified as this show's own seasons.
    const linkTitle = siteLinkTitle(link.attrs, link.html, link.text);
    if (!siteBelongsToShow(linkTitle, link.url, showTokens)) { leftover.push(link); continue; }
    // Episode first: a URL slug like ".../season-4-episode-8/" matches both
    // patterns, but it links straight to a playable episode, not a season
    // index page, so the episode reading is the useful one when both match.
    if (siteLooksLikeEpisode(linkTitle, link.url)) {
      if (seenEpisodes.has(link.url)) continue;
      seenEpisodes.add(link.url);
      episodes.push({
        url: link.url,
        title: linkTitle || decodeURIComponent(new URL(link.url).pathname),
        episodeNumber: siteEpisodeNumber(linkTitle, link.url),
        thumbnail: siteImageFrom(link.html, pageUrl) || null,
      });
      continue;
    }
    if (siteLooksLikeSeason(linkTitle, link.url)) {
      if (!seenSeasons.has(link.url)) {
        seenSeasons.add(link.url);
        seasons.push({ url: link.url, title: linkTitle || decodeURIComponent(new URL(link.url).pathname), episodes: [] });
      }
      continue;
    }
    leftover.push(link);
  }
  if (!episodes.length && !seasons.length) {
    const numbered = siteDetectNumberedSeries(leftover, pageUrl);
    if (numbered) {
      for (const link of numbered) {
        if (seenEpisodes.has(link.url)) continue;
        seenEpisodes.add(link.url);
        episodes.push({
          url: link.url,
          title: siteLinkTitle(link.attrs, link.html, link.text) || `الحلقة ${link.num}`,
          episodeNumber: link.num,
          thumbnail: siteImageFrom(link.html, pageUrl) || null,
        });
      }
    }
  }
  return {
    title: ownTitle,
    thumbnail: siteExtractThumbnail(html, pageUrl) || fallbackThumbnail || null,
    episodes,
    seasons,
    nextPageUrl: siteNextPage(links, pageUrl) || '',
  };
}

// Some sites render an episode "info" page with no playable embed at all —
// the real player lives one click deeper, at the same URL plus a "watch"
// segment (e.g. ".../episode-8/" -> ".../episode-8/watch"), reached through
// a single "شاهد الآن/Watch now"-style link. Detected once per site from a
// sample episode (see resolveEpisode below) rather than assumed, so sites
// where the episode link is already directly playable are left alone.
function siteFindWatchLink(html, pageUrl) {
  const baseHostname = new URL(pageUrl).hostname;
  const base = siteStripSlash(pageUrl);
  const links = siteLinks(html, pageUrl).filter(l => siteSameOrigin(l.url, baseHostname) && l.url !== pageUrl);
  for (const link of links) {
    if (siteStripSlash(link.url) === `${base}/watch`) return link.url;
  }
  for (const link of links) {
    if (/مشاهدة|شاهد|\bwatch\b/i.test(link.text)) return link.url;
  }
  return '';
}

async function handleSiteImport(request, env) {
  if (!isAdminAuthorized(request, env)) {
    return json({ error: 'permission-denied', message: 'غير مصرح.' }, 403);
  }
  let body;
  try { body = await request.json(); } catch (_) { return json({ error: 'invalid-argument', message: 'body غير صالح.' }, 400); }
  const action = body && body.action;
  try {
    if (action === 'catalog') {
      const url = siteAbsUrl(body.url);
      if (!url) return json({ error: 'invalid-argument', message: 'رابط صفحة القائمة غير صالح.' }, 400);
      const html = await siteFetchHtml(url);
      const parsed = siteParseCatalog(html, url);
      const nextPageUrl = siteNextPage(siteLinks(html, url).filter(l => siteSameOrigin(l.url, new URL(url).hostname)), url);
      return json({ ok: true, series: parsed, nextPageUrl: nextPageUrl || null });
    }
    if (action === 'series') {
      const url = siteAbsUrl(body.url);
      if (!url) return json({ error: 'invalid-argument', message: 'رابط الصفحة مطلوب.' }, 400);
      const html = await siteFetchHtml(url);
      const parsed = siteParseSeries(html, url, body.fallbackTitle || '', body.fallbackThumbnail || '');
      return json({ ok: true, ...parsed });
    }
    if (action === 'resolveEpisode') {
      const url = siteAbsUrl(body.url);
      if (!url) return json({ error: 'invalid-argument', message: 'رابط الحلقة مطلوب.' }, 400);
      const html = await siteFetchHtml(url);
      const watchUrl = siteFindWatchLink(html, url);
      return json({ ok: true, watchUrl: watchUrl || null });
    }
    return json({ error: 'invalid-argument', message: 'إجراء استيراد غير معروف.' }, 400);
  } catch (error) {
    return json({ error: 'upstream-error', message: String(error && error.message || error) }, 502);
  }
}

// ---------------------------------------------------------------------------
// التقييمات — POST /ratings/search
// يبحث عن نسبة تقييم لعنوان قسم (أفلام/مسلسلات عبر TMDB، أنمي عبر Jikan/
// MyAnimeList) ويرجّعها بدون كتابة أي شيء لـ Firestore — لوحة التحكم
// (ratings.js) هي من تكتب النتيجة، بنفس اتصالها المصادق عليه أصلاً.
// أي فشل بالمطابقة يرجّع rating: null بدل تخمين رقم خاطئ.
// ---------------------------------------------------------------------------
async function ratingsSearchJikan(title) {
  const url = `https://api.jikan.moe/v4/anime?q=${encodeURIComponent(title)}&limit=1&sfw=true`;
  const response = await fetch(url);
  if (!response.ok) return { rating: null, source: null };
  const data = await response.json();
  const item = data && Array.isArray(data.data) ? data.data[0] : null;
  const score = item && typeof item.score === 'number' ? item.score : null;
  if (score == null) return { rating: null, source: null, matchedTitle: item ? item.title : null };
  return { rating: Math.round(score * 10), source: 'jikan', matchedTitle: item.title };
}

async function ratingsSearchTmdb(title, mediaType, apiKey) {
  const url = `https://api.themoviedb.org/3/search/${mediaType}?query=${encodeURIComponent(title)}&api_key=${apiKey}&language=ar`;
  const response = await fetch(url);
  if (!response.ok) return { rating: null, source: null };
  const data = await response.json();
  const item = data && Array.isArray(data.results) ? data.results[0] : null;
  const score = item && typeof item.vote_average === 'number' ? item.vote_average : null;
  const voteCount = (item && item.vote_count) || 0;
  // نتجاهل تقييمات بعدد أصوات ضئيل جداً — قد تكون تطابقاً خاطئاً لعنوان
  // مشابه وليس نفس العمل فعلياً، أفضل نتركه بدون تقييم بدل رقم مضلِّل.
  if (score == null || voteCount < 5) {
    return { rating: null, source: null, matchedTitle: item ? (item.title || item.name) : null };
  }
  return { rating: Math.round(score * 10), source: 'tmdb', matchedTitle: item.title || item.name };
}

async function handleRatingsSearch(request, env) {
  if (!isAdminAuthorized(request, env)) {
    return json({ error: 'permission-denied', message: 'غير مصرح.' }, 403);
  }
  let body;
  try { body = await request.json(); } catch (_) { return json({ error: 'invalid-argument', message: 'body غير صالح.' }, 400); }
  const title = String((body && body.title) || '').trim();
  const contentType = body && body.contentType;
  if (!title) return json({ error: 'invalid-argument', message: 'العنوان مطلوب.' }, 400);

  try {
    if (contentType === 'anime') {
      const result = await ratingsSearchJikan(title);
      return json({ ok: true, ...result });
    }
    if (contentType === 'movies' || contentType === 'series') {
      if (!env.TMDB_API_KEY) {
        return json({ ok: true, rating: null, source: null, reason: 'tmdb-not-configured' });
      }
      const mediaType = contentType === 'movies' ? 'movie' : 'tv';
      const result = await ratingsSearchTmdb(title, mediaType, env.TMDB_API_KEY);
      return json({ ok: true, ...result });
    }
    return json({ error: 'invalid-argument', message: 'نوع محتوى غير مدعوم للتقييمات.' }, 400);
  } catch (error) {
    return json({ error: 'upstream-error', message: String(error && error.message || error) }, 502);
  }
}

// ---------------------------------------------------------------------------
// التوجيه (Routing)
// ---------------------------------------------------------------------------
export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    if (request.method === 'POST' && url.pathname === '/getStreamUrl') {
      return handleGetStreamUrl(request, env);
    }

    if (request.method === 'POST' && url.pathname === '/refreshMatches') {
      return handleRefreshMatches(request, env);
    }

    if (request.method === 'POST' && url.pathname === '/getMatchStats') {
      return handleGetMatchStats(request, env);
    }

    if (request.method === 'POST' && url.pathname === '/getPreMatchInfo') {
      return handleGetPreMatchInfo(request, env);
    }

    if (request.method === 'POST' && url.pathname === '/import/site') {
      return handleSiteImport(request, env);
    }

    if (request.method === 'POST' && url.pathname === '/ratings/search') {
      return handleRatingsSearch(request, env);
    }

    const hlsMatch = request.method === 'GET' && url.pathname.match(/^\/hls\/([^/]+)\/(.+)$/);
    if (hlsMatch) {
      const [, channelId, file] = hlsMatch;
      return handleHlsProxy(request, env, channelId, file);
    }

    return json({ error: 'not-found', message: 'مسار غير معروف.' }, 404);
  },

  // Cron Trigger — مضبوط في wrangler.toml ليعمل كل ساعة تلقائياً.
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runScheduledSync(env));
  },
};
