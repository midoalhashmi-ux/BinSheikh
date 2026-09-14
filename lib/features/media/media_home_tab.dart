import 'package:flutter/material.dart';
import '../../core/models/category_model.dart';
import '../../core/services/content_service.dart';
import '../../core/services/watch_history_service.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/player_launcher.dart';
import '../../widgets/poster_card.dart';
import '../../widgets/rating_badge.dart';
import '../../widgets/section_search_field.dart';
import '../channels/channels_screen.dart';

class MediaHomeTab extends StatelessWidget {
  const MediaHomeTab({super.key});

  static const _types = <_MediaType>[
    _MediaType('movies', 'الأفلام', Icons.movie_creation_outlined),
    _MediaType('series', 'المسلسلات', Icons.live_tv_outlined),
    _MediaType('anime', 'الأنمي', Icons.auto_awesome_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    // نجلب كل الأقسام (وليس الجذرية فقط) — صفوف "الأكثر مشاهدة"/"أُضيف
    // حديثاً" تحتاج الوصول لأي مسلسل/أنمي حتى لو كان متداخلاً بقسم أب
    // (مثلاً "مسلسلات آسيوية" ← عمل بعينه)، لا الجذر فقط.
    return StreamBuilder<List<CategoryModel>>(
      stream: ContentService.watchCategories(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, size: 42, color: Colors.white38),
                SizedBox(height: 10),
                Text('تعذر تحميل المحتوى. تحقق من اتصال الإنترنت.'),
              ],
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final allCategories = snapshot.data!;
        final categories = allCategories.where((c) => c.parentId == null).toList();

        // "عمل" حقيقي (مسلسل/أنمي/فيلم بحلقاته) لا مجرد مجلد تنظيمي —
        // يُميَّز بأنه لا يظهر كـ parentId لأي قسم آخر (المجلدات وحدها
        // تُشار إليها كأب). نفس الفكرة المستخدمة بالضبط لتفرقة "قسم-حلقات"
        // عن "قناة بث" بـ ChannelsScreen._isEpisodicShow.
        final parentIds = allCategories.map((c) => c.parentId).whereType<String>().toSet();
        final shows = allCategories
            .where((c) => c.contentType != 'channels' && !parentIds.contains(c.id))
            .toList();

        final recentlyAdded = [...shows]
          ..sort((a, b) =>
              (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
        final mostWatched = shows.where((c) => c.viewCount > 0).toList()
          ..sort((a, b) => b.viewCount.compareTo(a.viewCount));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            Text('المحتوى', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('اختر القسم الذي ترغب بمشاهدته', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            ValueListenableBuilder<List<WatchHistoryEntry>>(
              valueListenable: WatchHistoryService.history,
              builder: (context, history, _) {
                final relevant = history
                    .where((e) => shows.any((c) => c.id == e.categoryId))
                    .take(10)
                    .toList();
                return PosterRow(
                  title: 'شاهدته مؤخراً',
                  cards: [
                    for (final entry in relevant)
                      PosterCard(
                        title: entry.title,
                        imageUrl: entry.logoUrl,
                        onTap: () => PlayerLauncher.openChannel(
                          context,
                          ChannelModel(
                            id: entry.channelId,
                            categoryId: entry.categoryId,
                            title: entry.title,
                            subtitle: '',
                            status: 'active',
                            logoUrl: entry.logoUrl,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            PosterRow(
              title: 'الأكثر مشاهدة',
              cards: [
                for (final show in mostWatched.take(10)) _showCard(context, show),
              ],
            ),
            PosterRow(
              title: 'أُضيف حديثاً',
              cards: [
                for (final show in recentlyAdded.take(10)) _showCard(context, show),
              ],
            ),
            const SizedBox(height: 4),
            Text('تصفح حسب النوع', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            for (final type in _types) ...[
              _MediaCard(
                type: type,
                categoryCount: categories.where((c) => c.contentType == type.key).length,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MediaCategoriesScreen(
                        type: type,
                        categories: categories.where((c) => c.contentType == type.key).toList(),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _showCard(BuildContext context, CategoryModel show) {
    return PosterCard(
      title: show.title,
      imageUrl: show.iconUrl,
      badge: show.rating != null ? RatingBadge(rating: show.rating!) : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChannelsScreen(category: show)),
      ),
    );
  }
}

class MediaCategoriesScreen extends StatefulWidget {
  final _MediaType type;
  final List<CategoryModel> categories;
  const MediaCategoriesScreen({super.key, required this.type, required this.categories});

  @override
  State<MediaCategoriesScreen> createState() => _MediaCategoriesScreenState();
}

class _MediaCategoriesScreenState extends State<MediaCategoriesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final categories = widget.categories
        .where((category) => matchesSearchQuery(category.title, _query))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(type.title)),
      body: Column(
        children: [
          if (widget.categories.isNotEmpty)
            SectionSearchField(onChanged: (value) => setState(() => _query = value)),
          Expanded(
            child: categories.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(type.icon, size: 42, color: Colors.white38),
                  const SizedBox(height: 10),
                  Text(widget.categories.isEmpty
                      ? 'لا توجد أقسام في ${type.title} حالياً'
                      : 'لا توجد نتائج مطابقة'),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.9,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChannelsScreen(category: category)),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (category.iconUrl?.isNotEmpty == true)
                          Image.network(category.iconUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallback(context))
                        else
                          _fallback(context),
                        if (category.rating != null)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: RatingBadge(rating: category.rating!),
                          ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(10, 28, 10, 12),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87],
                              ),
                            ),
                            child: Tooltip(
                              message: category.title,
                              child: Text(category.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
    child: Icon(widget.type.icon, size: 52, color: Theme.of(context).colorScheme.primary),
  );
}

class _MediaCard extends StatelessWidget {
  final _MediaType type;
  final int categoryCount;
  final VoidCallback onTap;
  const _MediaCard({required this.type, required this.categoryCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 62, height: 62,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(type.icon, size: 32, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(type.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(categoryCount == 0 ? 'لا توجد أقسام بعد' : '$categoryCount أقسام',
                    style: theme.textTheme.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaType {
  final String key;
  final String title;
  final IconData icon;
  const _MediaType(this.key, this.title, this.icon);
}
