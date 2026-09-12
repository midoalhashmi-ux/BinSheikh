import 'package:flutter/material.dart';
import '../../core/models/category_model.dart';
import '../../core/models/home_button_model.dart';
import '../../core/services/content_service.dart';
import '../../widgets/rating_badge.dart';
import '../../widgets/section_search_field.dart';
import '../channels/channels_screen.dart';

class MediaHomeTab extends StatelessWidget {
  const MediaHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CategoryModel>>(
      stream: ContentService.watchRootCategories(),
      builder: (context, categoriesSnapshot) {
        if (categoriesSnapshot.hasError) {
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
        if (!categoriesSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final categories = categoriesSnapshot.data!;
        return StreamBuilder<List<HomeButtonConfig>>(
          stream: ContentService.watchHomeButtons(),
          builder: (context, buttonsSnapshot) {
            final buttons = buttonsSnapshot.data ?? HomeButtonConfig.defaults;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('المحتوى', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('اختر القسم الذي ترغب بمشاهدته', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 18),
                  // كل الأزرار تملأ المساحة المتبقية بالتساوي مهما كان
                  // عددها (Expanded بنفس الوزن لكل واحد) بدل ارتفاع ثابت
                  // يترك فراغاً أو يفيض عن الشاشة — بناءً على طلب صريح.
                  Expanded(
                    child: Column(
                      children: [
                        for (final button in buttons) ...[
                          Expanded(
                            child: _HomeButtonCard(
                              button: button,
                              categoryCount: _countFor(button, categories),
                              onTap: () => _open(context, button, categories),
                            ),
                          ),
                          if (button != buttons.last) const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  int _countFor(HomeButtonConfig button, List<CategoryModel> categories) {
    if (button.linkType == 'category') return 1;
    return categories.where((c) => c.contentType == button.contentType).length;
  }

  void _open(BuildContext context, HomeButtonConfig button, List<CategoryModel> categories) {
    if (button.linkType == 'category') {
      CategoryModel? category;
      for (final c in categories) {
        if (c.id == button.categoryId) { category = c; break; }
      }
      if (category == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('القسم المرتبط بهذا الزر لم يعد موجوداً.')),
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChannelsScreen(category: category!)),
      );
      return;
    }
    final type = _MediaType(button.contentType ?? '', button.label, iconForHomeButton(button.icon));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MediaCategoriesScreen(
          type: type,
          categories: categories.where((c) => c.contentType == type.key).toList(),
        ),
      ),
    );
  }
}

class _MediaCategoriesScreen extends StatefulWidget {
  final _MediaType type;
  final List<CategoryModel> categories;
  const _MediaCategoriesScreen({required this.type, required this.categories});

  @override
  State<_MediaCategoriesScreen> createState() => _MediaCategoriesScreenState();
}

class _MediaCategoriesScreenState extends State<_MediaCategoriesScreen> {
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

class _HomeButtonCard extends StatelessWidget {
  final HomeButtonConfig button;
  final int categoryCount;
  final VoidCallback onTap;
  const _HomeButtonCard({required this.button, required this.categoryCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = iconForHomeButton(button.icon);
    return SizedBox.expand(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Container(
                  width: 62, height: 62,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, size: 32, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(button.label, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(categoryCount == 0 ? 'لا توجد أقسام بعد' : '$categoryCount أقسام',
                        style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left),
              ],
            ),
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
