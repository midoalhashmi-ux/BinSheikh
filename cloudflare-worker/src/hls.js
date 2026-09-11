// ============================================================================
// توليد/التحقق من توكن موقّع (HMAC-SHA256) لحماية بث HLS + بروكسي يمنع
// وصول رابط المصدر الحقيقي (privateStreams/{channelId}.url) للمستخدم
// إطلاقاً. لا يحتاج أي تخزين إضافي (لا KV) — التحقق حسابي بحت.
// ============================================================================

export const HLS_TOKEN_TTL_SECONDS = 240; // صلاحية كل توكن: 4 دقائق

// مقارنة نصّين بوقت ثابت (تفادي timing attacks) — يُعاد استخدامها أيضاً في
// index.js للتحقق من مفتاح الأدمن (ADMIN_SYNC_SECRET)، بدل مقارنة `!==`
// العادية التي كانت تُسرّب معلومة توقيت عن مدى تطابق البادئة.
export function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
  return [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function signHlsToken(env, channelId, exp) {
  return hmacHex(env.HLS_TOKEN_SECRET, `${channelId}:${exp}`);
}

export async function verifyHlsToken(env, channelId, exp, sig) {
  if (!sig || !exp) return false;
  if (Date.now() / 1000 > Number(exp)) return false;
  const expected = await hmacHex(env.HLS_TOKEN_SECRET, `${channelId}:${exp}`);
  return timingSafeEqual(expected, sig);
}

export function buildHlsPlaybackUrl(workerOrigin, channelId, exp, sig) {
  return `${workerOrigin}/hls/${channelId}/playlist.m3u8?exp=${exp}&sig=${sig}`;
}

// يعيد كتابة كل سطر رابط داخل m3u8 ليمر عبر نفس الـ Worker بنفس التوكن،
// بدل الإشارة لرابط المصدر الحقيقي مباشرة.
export function rewriteHlsPlaylist(text, channelId, exp, sig, workerOrigin) {
  return text
      .split('\n')
      .map((line) => {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) return line;
        const fileName = trimmed.split('/').pop().split('?')[0];
        return `${workerOrigin}/hls/${channelId}/${fileName}?exp=${exp}&sig=${sig}`;
      })
      .join('\n');
}
