import 'package:flutter/material.dart';
import '../../core/models/category_model.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/content_service.dart';
import '../../core/services/favorites_service.dart';
import '../../widgets/rating_badge.dart';
import '../channels/channel_card.dart';
import '../channels/channels_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المفضلة')),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: FavoritesService.favoriteCategories,
        builder: (context, favoriteCategoryIds, _) {
          return ValueListenableBuilder<Set<String>>(
            valueListenable: FavoritesService.favorites,
            builder: (context, favoriteChannelIds, _) {
              if (favoriteCategoryIds.isEmpty && favoriteChannelIds.isEmpty) {
                return _buildEmptyState(context);
              }
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (favoriteCategoryIds.isNotEmpty) ...[
                    _SectionLabel('المسلسلات والأنمي (${favoriteCategoryIds.length})'),
                    FutureBuilder<List<CategoryModel>>(
                      future: ContentService.fetchCategoriesByIds(favoriteCategoryIds.toList()),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final categories = snapshot.data!;
                        return Column(
                          children: [
                            for (final category in categories)
                              _FavoriteCategoryTile(category: category),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (favoriteChannelIds.isNotEmpty) ...[
                    _SectionLabel('القنوات (${favoriteChannelIds.length})'),
                    FutureBuilder<List<ChannelModel>>(
                      future: ContentService.fetchChannelsByIds(favoriteChannelIds.toList()),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final channels = snapshot.data!;
                        return Column(
                          children: [
                            for (final channel in channels) ChannelCard(channel: channel),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_border, size: 40, color: Colors.redAccent),
            ),
            const SizedBox(height: 20),
            const Text(
              'لا توجد مفضلة بعد',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'اضغط أيقونة القلب بجانب أي مسلسل، أنمي، أو قناة لإضافته هنا',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}

class _FavoriteCategoryTile extends StatelessWidget {
  final CategoryModel category;
  const _FavoriteCategoryTile({required this.category});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChannelsScreen(category: category)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: category.iconUrl != null && category.iconUrl!.isNotEmpty
                    ? Image.network(
                        category.iconUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallback(accent),
                      )
                    : _fallback(accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: category.title,
                      child: Text(category.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (category.rating != null) ...[
                      const SizedBox(height: 4),
                      RatingBadge(rating: category.rating!),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.favorite, color: Colors.redAccent),
                tooltip: 'إزالة من المفضلة',
                onPressed: () => FavoritesService.toggleFavoriteCategory(category.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback(Color accent) => Container(
        width: 60,
        height: 60,
        color: accent.withValues(alpha: 0.15),
        child: Icon(Icons.video_library_outlined, color: accent),
      );
}
