import 'package:flutter/material.dart';
import '../../core/models/category_model.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/content_service.dart';
import '../../core/services/favorites_service.dart';
import '../../widgets/section_search_field.dart';
import 'channel_card.dart';

class ChannelsScreen extends StatefulWidget {
  final CategoryModel category;
  const ChannelsScreen({super.key, required this.category});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.title),
        centerTitle: true,
      ),
      body: Column(
        children: [
          SectionSearchField(onChanged: (value) => setState(() => _query = value)),
          Expanded(
            child: StreamBuilder<List<CategoryModel>>(
              stream: ContentService.watchChildCategories(widget.category.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded, size: 42, color: Colors.white38),
                          const SizedBox(height: 10),
                          Text('تعذر تحميل الأقسام الفرعية.\nتحقق من اتصال الإنترنت.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allChildCategories = snapshot.data!;
                if (allChildCategories.isNotEmpty) {
                  final childCategories = allChildCategories
                      .where((child) => matchesSearchQuery(child.title, _query))
                      .toList();
                  if (childCategories.isEmpty) {
                    return const Center(child: Text('لا توجد نتائج مطابقة'));
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: childCategories.length,
                    itemBuilder: (context, index) {
                      final child = childCategories[index];
                      return Card(
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChannelsScreen(category: child),
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (child.iconUrl != null && child.iconUrl!.isNotEmpty)
                                Image.network(
                                  child.iconUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.15),
                                  ),
                                )
                              else
                                Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.15),
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
                                    message: child.title,
                                    child: Text(
                                      child.title,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.5,
                                        height: 1.2,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }
                return _ChannelsList(category: widget.category, query: _query);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelsList extends StatelessWidget {
  final CategoryModel category;
  final String query;
  const _ChannelsList({required this.category, required this.query});

  // "قسم-حلقات" (مسلسل/أنمي/فيلم كامل) مقابل قناة بث مباشر مستقلة —
  // الأول يُفضَّل ككل من هنا، الثاني يبقى يُفضَّل من بطاقة القناة نفسها.
  bool get _isEpisodicShow => category.contentType != 'channels';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChannelModel>>(
      stream: ContentService.watchChannelsForCategory(category.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 42),
                  const SizedBox(height: 10),
                  const Text(
                    'تعذر تحميل القنوات.\nتحقق من اتصال الإنترنت وحاول مرة أخرى.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ChannelsScreen(category: category),
                      ),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allChannels = snapshot.data!;
        if (allChannels.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.live_tv_outlined, size: 42, color: Colors.white38),
                SizedBox(height: 10),
                Text('لا توجد قنوات بعد في هذا القسم'),
              ],
            ),
          );
        }
        final channels =
            allChannels.where((channel) => matchesSearchQuery(channel.title, query)).toList();
        if (channels.isEmpty) {
          return const Center(child: Text('لا توجد نتائج مطابقة'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: channels.length + (_isEpisodicShow ? 1 : 0),
          itemBuilder: (context, index) {
            if (_isEpisodicShow && index == 0) {
              return _FavoriteShowHeader(category: category);
            }
            final channel = channels[_isEpisodicShow ? index - 1 : index];
            return ChannelCard(channel: channel, showFavoriteButton: !_isEpisodicShow);
          },
        );
      },
    );
  }
}

/// شريط تفضيل المسلسل/الأنمي كاملاً (بدل تفضيل حلقة واحدة) — يظهر أعلى
/// قائمة الحلقات فقط عندما يكون القسم من نوع محتوى حلقي (مسلسل/أنمي/فيلم).
class _FavoriteShowHeader extends StatelessWidget {
  final CategoryModel category;
  const _FavoriteShowHeader({required this.category});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ValueListenableBuilder<Set<String>>(
        valueListenable: FavoritesService.favoriteCategories,
        builder: (context, favoriteIds, _) {
          final isFavorite = favoriteIds.contains(category.id);
          return ListTile(
            leading: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? Colors.redAccent : Colors.white60,
            ),
            title: Text(
              isFavorite ? 'مُضاف للمفضلة' : 'أضف هذا المسلسل للمفضلة',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('يُضاف القسم كاملاً بدل حلقة واحدة'),
            onTap: () => FavoritesService.toggleFavoriteCategory(category.id),
            trailing: Switch(
              value: isFavorite,
              onChanged: (_) => FavoritesService.toggleFavoriteCategory(category.id),
            ),
          );
        },
      ),
    );
  }
}
