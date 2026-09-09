import 'package:flutter/material.dart';
import '../../core/models/category_model.dart';
import '../../core/services/content_service.dart';
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
    return StreamBuilder<List<CategoryModel>>(
      stream: ContentService.watchRootCategories(),
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
        final categories = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            Text('المحتوى', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('اختر القسم الذي ترغب بمشاهدته', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
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
}

class MediaCategoriesScreen extends StatelessWidget {
  final _MediaType type;
  final List<CategoryModel> categories;
  const MediaCategoriesScreen({super.key, required this.type, required this.categories});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(type.title)),
      body: categories.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(type.icon, size: 42, color: Colors.white38),
                  const SizedBox(height: 10),
                  Text('لا توجد أقسام في ${type.title} حالياً'),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
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
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(10, 22, 10, 12),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87],
                              ),
                            ),
                            child: Text(category.title,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _fallback(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
    child: Icon(type.icon, size: 52, color: Theme.of(context).colorScheme.primary),
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
