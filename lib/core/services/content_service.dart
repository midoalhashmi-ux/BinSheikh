import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category_model.dart';
import '../models/channel_model.dart';
import '../models/home_button_model.dart';

class ContentService {
  /// أزرار الشاشة الرئيسية (شاشة "المحتوى")، تُدار من لوحة التحكم عبر
  /// settings/homeButtons. مستند فارغ/غير موجود (قبل أي تخصيص) يعني
  /// الرجوع للثلاثة أزرار الافتراضية — لا يظهر أي فراغ بالشاشة أبداً.
  static Stream<List<HomeButtonConfig>> watchHomeButtons() {
    return FirebaseFirestore.instance
        .collection('settings')
        .doc('homeButtons')
        .snapshots()
        .map((snap) {
      final raw = snap.data()?['buttons'];
      if (raw is! List || raw.isEmpty) return HomeButtonConfig.defaults;
      final parsed = raw
          .whereType<Map>()
          .map((m) => HomeButtonConfig.fromMap(Map<String, dynamic>.from(m)))
          .where((b) => b.label.isNotEmpty)
          .toList();
      return parsed.isEmpty ? HomeButtonConfig.defaults : parsed;
    });
  }

  static Stream<List<CategoryModel>> watchCategories() {
    return FirebaseFirestore.instance
        .collection('categories')
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => CategoryModel.fromMap(d.id, d.data()))
            .toList());
  }

  static Stream<List<CategoryModel>> watchRootCategories() {
    return watchCategories().map(
      (categories) => categories.where((category) => category.parentId == null).toList(),
    );
  }

  static Stream<List<CategoryModel>> watchChildCategories(String parentId) {
    return watchCategories().map(
      (categories) => categories
          .where((category) => category.parentId == parentId)
          .toList(),
    );
  }

  static Stream<List<ChannelModel>> watchChannelsForCategory(
      String categoryId) {
    return FirebaseFirestore.instance
        .collection('channels')
        .where('categoryId', isEqualTo: categoryId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ChannelModel.fromMap(d.id, d.data()))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order)));
  }

  /// يجلب بيانات قنوات محددة بمعرّفاتها (تُستخدم لشاشة المفضلة).
  /// جلب لحظي واحد (وليس Stream) — يُعاد استدعاؤه كلما تغيّرت قائمة المفضلة.
  static Future<List<ChannelModel>> fetchChannelsByIds(
      List<String> ids) async {
    if (ids.isEmpty) return [];
    final futures = ids.map(
      (id) => FirebaseFirestore.instance.collection('channels').doc(id).get(),
    );
    final snapshots = await Future.wait(futures);
    return snapshots
        .where((snap) => snap.exists && snap.data() != null)
        .map((snap) => ChannelModel.fromMap(snap.id, snap.data()!))
        .toList();
  }

  /// يجلب بيانات أقسام محددة بمعرّفاتها (تُستخدم لشاشة المفضلة — مسلسلات
  /// وأنمي كاملة مُفضَّلة على مستوى القسم بدل حلقة واحدة).
  static Future<List<CategoryModel>> fetchCategoriesByIds(
      List<String> ids) async {
    if (ids.isEmpty) return [];
    final futures = ids.map(
      (id) => FirebaseFirestore.instance.collection('categories').doc(id).get(),
    );
    final snapshots = await Future.wait(futures);
    return snapshots
        .where((snap) => snap.exists && snap.data() != null)
        .map((snap) => CategoryModel.fromMap(snap.id, snap.data()!))
        .toList();
  }

  /// يسجّل مشاهدة (عدّاد بسيط) لكل من القناة/الحلقة وقسمها المباشر —
  /// تُقرأ هذه العدّادات من لوحة التحكم لعرض إحصائيات "الأكثر مشاهدة".
  /// غير حرجة أبداً: أي فشل (بدون إنترنت مثلاً) يُتجاهل بصمت ولا يجب أن
  /// يعطّل فتح القناة نفسها.
  ///
  /// بجانب العدّاد التراكمي (viewCount)، تُكتب بنفس الدفعة زيادة على
  /// مستند يومي منفصل (dailyViews/{YYYY-MM-DD} بتوقيت UTC، لتطابق كيفية
  /// حساب لوحة التحكم لمدى التواريخ) — يسمح هذا بفلترة إحصائيات لوحة
  /// التحكم بمدى زمني (اليوم/آخر أسبوع/مدى مخصص)، وهو غير ممكن من
  /// viewCount وحده لأنه بلا أي بُعد زمني.
  static Future<void> recordView({
    required String channelId,
    String? categoryId,
  }) async {
    try {
      final today = DateTime.now().toUtc();
      final dateId =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final batch = FirebaseFirestore.instance.batch();
      final channelRef = FirebaseFirestore.instance.collection('channels').doc(channelId);
      batch.set(
        channelRef,
        {'viewCount': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
      batch.set(
        channelRef.collection('dailyViews').doc(dateId),
        {'count': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
      if (categoryId != null && categoryId.isNotEmpty) {
        final categoryRef = FirebaseFirestore.instance.collection('categories').doc(categoryId);
        batch.set(
          categoryRef,
          {'viewCount': FieldValue.increment(1)},
          SetOptions(merge: true),
        );
        batch.set(
          categoryRef.collection('dailyViews').doc(dateId),
          {'count': FieldValue.increment(1)},
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    } catch (_) {
      // إحصائيات غير حرجة — لا نعطّل تشغيل القناة لأجلها.
    }
  }
}
