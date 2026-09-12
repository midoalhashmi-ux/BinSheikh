import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel_model.dart';

/// عنصر واحد بسجل "شاهدته مؤخراً" — لقطة من بيانات القناة/الحلقة وقت
/// فتحها، بدل الاعتماد على جلبها من Firestore لاحقاً (قد تُحذف أو
/// تتغيّر). لا نحفظ موضع التشغيل (بالثواني): المشاهدة الفعلية تتم بتطبيق
/// المشغّل المنفصل تماماً (راجع PlayerLauncher) وهذا التطبيق لا يملك أي
/// رؤية على تقدّم التشغيل هناك — الصف يعيد فتح نفس الحلقة بضغطة واحدة
/// بدل استكمال دقيق من نفس اللحظة.
class WatchHistoryEntry {
  final String channelId;
  final String categoryId;
  final String title;
  final String? logoUrl;
  final DateTime watchedAt;

  const WatchHistoryEntry({
    required this.channelId,
    required this.categoryId,
    required this.title,
    this.logoUrl,
    required this.watchedAt,
  });

  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'categoryId': categoryId,
        'title': title,
        'logoUrl': logoUrl,
        'watchedAt': watchedAt.toIso8601String(),
      };

  static WatchHistoryEntry? fromJson(Map<String, dynamic> json) {
    final channelId = json['channelId'] as String?;
    final title = json['title'] as String?;
    final watchedAtRaw = json['watchedAt'] as String?;
    if (channelId == null || channelId.isEmpty || title == null || watchedAtRaw == null) {
      return null;
    }
    final watchedAt = DateTime.tryParse(watchedAtRaw);
    if (watchedAt == null) return null;
    return WatchHistoryEntry(
      channelId: channelId,
      categoryId: (json['categoryId'] as String?) ?? '',
      title: title,
      logoUrl: json['logoUrl'] as String?,
      watchedAt: watchedAt,
    );
  }
}

/// تخزين محلي (على الجهاز) لآخر القنوات/الحلقات المفتوحة — يغذّي صف
/// "شاهدته مؤخراً" بالرئيسية. نفس فكرة FavoritesService (بدون حساب
/// مستخدم أو اتصال خادم)، لكن كسجل مرتّب بالأحدث أولاً بدل مجموعة.
class WatchHistoryService {
  static const _prefsKey = 'watch_history_v1';
  static const maxEntries = 20;

  static final ValueNotifier<List<WatchHistoryEntry>> history =
      ValueNotifier<List<WatchHistoryEntry>>(const <WatchHistoryEntry>[]);

  static bool _loaded = false;

  /// يُستحسن استدعاؤها مرة عند بدء التطبيق (main.dart)، زي FavoritesService.init.
  static Future<void> init() => _ensureLoaded();

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        history.value = decoded
            .whereType<Map<String, dynamic>>()
            .map(WatchHistoryEntry.fromJson)
            .whereType<WatchHistoryEntry>()
            .toList();
      } catch (_) {
        // بيانات محفوظة تالفة (تنسيق قديم مثلاً) — نبدأ بسجل فارغ بدل تعطّل الرئيسية.
        history.value = const <WatchHistoryEntry>[];
      }
    }
    _loaded = true;
  }

  /// يُسجَّل عند فتح أي قناة/حلقة فعلياً (راجع PlayerLauncher.openChannel).
  /// إعادة فتح نفس العنصر تنقله لأعلى القائمة بدل تكراره.
  static Future<void> record(ChannelModel channel) async {
    await _ensureLoaded();
    final updated = history.value.where((e) => e.channelId != channel.id).toList();
    updated.insert(
      0,
      WatchHistoryEntry(
        channelId: channel.id,
        categoryId: channel.categoryId,
        title: channel.title,
        logoUrl: channel.logoUrl,
        watchedAt: DateTime.now(),
      ),
    );
    if (updated.length > maxEntries) updated.removeRange(maxEntries, updated.length);
    history.value = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(updated.map((e) => e.toJson()).toList()));
  }
}
