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

  CategoryModel({
    required this.id,
    required this.title,
    required this.order,
    this.iconUrl,
    this.parentId,
    this.contentType = 'channels',
    this.viewCount = 0,
    this.rating,
  });

  factory CategoryModel.fromMap(String id, Map<String, dynamic> map) {
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
    );
  }
}
