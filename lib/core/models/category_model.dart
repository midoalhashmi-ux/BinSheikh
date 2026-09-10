class CategoryModel {
  final String id;
  final String title;
  final int order;
  final String? iconUrl;
  final String? parentId;
  final String contentType;
  final int viewCount;

  CategoryModel({
    required this.id,
    required this.title,
    required this.order,
    this.iconUrl,
    this.parentId,
    this.contentType = 'channels',
    this.viewCount = 0,
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
    );
  }
}
