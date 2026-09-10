import 'package:flutter/material.dart';
import '../../core/services/content_service.dart';
import '../../widgets/rating_badge.dart';
import '../../widgets/section_search_field.dart';
import 'channels_screen.dart';

/// تبويب "القنوات": شبكة الأقسام الرئيسية. الضغط على أي قسم يفتح
/// [ChannelsScreen] التي تتفرّع تلقائياً لأقسام فرعية أو قائمة قنوات.
class ChannelsHomeTab extends StatefulWidget {
  const ChannelsHomeTab({super.key});

  @override
  State<ChannelsHomeTab> createState() => _ChannelsHomeTabState();
}

class _ChannelsHomeTabState extends State<ChannelsHomeTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: ContentService.watchRootCategories(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
              child: Text('تعذر تحميل الأقسام. تحقق من اتصال الإنترنت وقواعد Firebase.'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final allCategories = snapshot.data!;
        if (allCategories.isEmpty) return const Center(child: Text('لا توجد أقسام بعد'));
        final categories = allCategories
            .where((category) => matchesSearchQuery(category.title, _query))
            .toList();
        return Column(
          children: [
            SectionSearchField(onChanged: (value) => setState(() => _query = value)),
            Expanded(
              child: categories.isEmpty
                  ? const Center(child: Text('لا توجد نتائج مطابقة'))
                  : GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
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
                      Image.network(category.iconUrl!,
                          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(context))
                    else
                      _fallback(context),
                    if (category.rating != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: RatingBadge(rating: category.rating!),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
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
        );
      },
    );
  }

  Widget _fallback(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      color: accent.withValues(alpha: 0.18),
      child: Icon(Icons.sports_soccer, size: 42, color: accent),
    );
  }
}
