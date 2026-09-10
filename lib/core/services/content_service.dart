import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category_model.dart';
import '../models/channel_model.dart';

class ContentService {
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
  static Future<void> recordView({
    required String channelId,
    String? categoryId,
  }) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        FirebaseFirestore.instance.collection('channels').doc(channelId),
        {'viewCount': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
      if (categoryId != null && categoryId.isNotEmpty) {
        batch.set(
          FirebaseFirestore.instance.collection('categories').doc(categoryId),
          {'viewCount': FieldValue.increment(1)},
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    } catch (_) {
      // إحصائيات غير حرجة — لا نعطّل تشغيل القناة لأجلها.
    }
  }
}
