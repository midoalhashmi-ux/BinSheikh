import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryModel {
  final String id;
  final String title;
  final int order;
  final String? iconUrl;
  final String? parentId;
  final String contentType;
  final int viewCount;
  // نسبة تقييم (0-100) تُجلَب من لوحة التحكم (TMDB للأفلام/المسلسلات،
  // Jikan/MyAnimeList للأنمي) — null يعني لا يوجد تقييم موثوق بعد
  // (قسم لم يُفحص، أو لم يُعثر على تطابق واضح لعنوانه).
  final int? rating;
  // آخر توقيت كتابة للقسم من لوحة التحكم — تُستخدم لصف "أُضيف حديثاً"
  // بالرئيسية. لوحة التحكم تكتبها فقط عند إنشاء القسم لأول مرة (ليس عند
  // كل استيراد لاحق لنفس المسلسل)، فتقارب فعلياً "تاريخ الإضافة" لا مجرد
  // آخر تعديل — راجع categoryOp بمستودع AHMED-dashboard.
  final DateTime? updatedAt;

  CategoryModel({
    required this.id,
    required this.title,
    required this.order,
    this.iconUrl,
    this.parentId,
    this.contentType = 'channels',
    this.viewCount = 0,
    this.rating,
    this.updatedAt,
  });

  factory CategoryModel.fromMap(String id, Map<String, dynamic> map) {
    final rawUpdatedAt = map['updatedAt'];
    return CategoryModel(
      id: id,
      title: map['title'] ?? '',
      order: map['order'] is int
          ? map['order']
          : int.tryParse('${map['order']}') ?? 0,
      iconUrl: map['iconUrl'],
      parentId: map['parentId'],
      contentType: (map['contentType'] ?? 'channels').toString(),
      viewCount: (map['viewCount'] as num?)?.toInt() ?? 0,
      rating: (map['rating'] as num?)?.toInt(),
      updatedAt: rawUpdatedAt is Timestamp ? rawUpdatedAt.toDate() : null,
    );
  }
}
