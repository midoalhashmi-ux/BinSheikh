import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تخزين محلي (على الجهاز) لمعرّفات القنوات/الأقسام المفضلة.
/// لا يحتاج حساب مستخدم أو اتصال بالخادم — يعمل حتى بدون إنترنت.
///
/// نميّز بين نوعين من المفضلة:
/// - [favorites]: قنوات فردية (تبويب "القنوات" — البث المباشر، كل قناة
///   كيان مستقل بذاته فلا معنى لتفضيل "القسم" الذي يجمعها).
/// - [favoriteCategories]: أقسام كاملة (مسلسل/أنمي كامل — تبويب
///   "أفلام/مسلسلات") بدل تفضيل حلقة واحدة عشوائية منه، حتى لا تمتلئ
///   المفضلة بحلقات متفرقة لا تمثل المسلسل ككل.
class FavoritesService {
  static const _channelPrefsKey = 'favorite_channel_ids';
  static const _categoryPrefsKey = 'favorite_category_ids';

  /// القيمة الحالية لمعرّفات القنوات المفضلة. أي واجهة تستمع لها
  /// (عبر ValueListenableBuilder) تتحدث تلقائياً عند أي إضافة/إزالة.
  static final ValueNotifier<Set<String>> favorites =
      ValueNotifier<Set<String>>(<String>{});

  /// القيمة الحالية لمعرّفات الأقسام (مسلسلات/أنمي) المفضلة.
  static final ValueNotifier<Set<String>> favoriteCategories =
      ValueNotifier<Set<String>>(<String>{});

  static bool _loaded = false;

  /// يُستحسن استدعاؤها مرة عند بدء التطبيق (main.dart) حتى تكون
  /// المفضلة جاهزة قبل رسم أول شاشة. آمنة الاستدعاء أكثر من مرة.
  static Future<void> init() => _ensureLoaded();

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    favorites.value = (prefs.getStringList(_channelPrefsKey) ?? const []).toSet();
    favoriteCategories.value =
        (prefs.getStringList(_categoryPrefsKey) ?? const []).toSet();
    _loaded = true;
  }

  static Future<bool> isFavorite(String channelId) async {
    await _ensureLoaded();
    return favorites.value.contains(channelId);
  }

  static Future<void> toggleFavorite(String channelId) async {
    await _ensureLoaded();
    final updated = Set<String>.from(favorites.value);
    if (!updated.remove(channelId)) {
      updated.add(channelId);
    }
    favorites.value = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_channelPrefsKey, updated.toList());
  }

  static Future<bool> isFavoriteCategory(String categoryId) async {
    await _ensureLoaded();
    return favoriteCategories.value.contains(categoryId);
  }

  static Future<void> toggleFavoriteCategory(String categoryId) async {
    await _ensureLoaded();
    final updated = Set<String>.from(favoriteCategories.value);
    if (!updated.remove(categoryId)) {
      updated.add(categoryId);
    }
    favoriteCategories.value = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_categoryPrefsKey, updated.toList());
  }
}
