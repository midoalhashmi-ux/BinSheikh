import 'package:flutter/material.dart';

/// زر واحد من أزرار الشاشة الرئيسية (شاشة "المحتوى")، مُدار بالكامل من
/// لوحة التحكم عبر settings/homeButtons — راجع MediaHomeTab. كل زر إما
/// يفتح شجرة نوع محتوى كامل (كما كان قبل هذه الميزة: أفلام/مسلسلات/أنمي)
/// أو يفتح قسماً رئيسياً محدداً مباشرة (linkType == category).
class HomeButtonConfig {
  final String id;
  final String label;
  final String icon;
  final String linkType; // 'contentType' | 'category'
  final String? contentType;
  final String? categoryId;

  const HomeButtonConfig({
    required this.id,
    required this.label,
    required this.icon,
    required this.linkType,
    this.contentType,
    this.categoryId,
  });

  factory HomeButtonConfig.fromMap(Map<String, dynamic> map) {
    return HomeButtonConfig(
      id: (map['id'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      icon: (map['icon'] ?? 'folder').toString(),
      linkType: (map['linkType'] ?? 'contentType').toString(),
      contentType: map['contentType']?.toString(),
      categoryId: map['categoryId']?.toString(),
    );
  }

  /// القيمة الافتراضية قبل أي تخصيص من لوحة التحكم — نفس الثلاثة أنواع
  /// التي كانت مبرمجة يدوياً بالكود قبل هذه الميزة، حتى لا يتغير شيء
  /// لمن لم يستخدم اللوحة الجديدة بعد.
  static const defaults = <HomeButtonConfig>[
    HomeButtonConfig(id: 'movies', label: 'الأفلام', icon: 'movie', linkType: 'contentType', contentType: 'movies'),
    HomeButtonConfig(id: 'series', label: 'المسلسلات', icon: 'tv', linkType: 'contentType', contentType: 'series'),
    HomeButtonConfig(id: 'anime', label: 'الأنمي', icon: 'anime', linkType: 'contentType', contentType: 'anime'),
  ];
}

/// سجل الأيقونات المتاحة للاختيار من لوحة التحكم — أسماء يجب أن تطابق
/// حرفياً قيم <select id="home-button-icon"> بملف AHMED-dashboard/app.js.
const Map<String, IconData> homeButtonIcons = {
  'movie': Icons.movie_creation_outlined,
  'tv': Icons.live_tv_outlined,
  'anime': Icons.auto_awesome_outlined,
  'channels': Icons.tv_outlined,
  'sports': Icons.sports_soccer_outlined,
  'kids': Icons.child_care_outlined,
  'documentary': Icons.public_outlined,
  'music': Icons.music_note_outlined,
  'game': Icons.sports_esports_outlined,
  'star': Icons.star_outline,
  'folder': Icons.folder_outlined,
};

IconData iconForHomeButton(String icon) => homeButtonIcons[icon] ?? Icons.folder_outlined;
