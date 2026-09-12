import 'package:flutter/material.dart';
import '../../core/models/category_model.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/content_service.dart';
import '../../core/services/player_launcher.dart';
import '../../widgets/rating_badge.dart';
import '../../widgets/section_search_field.dart';
import '../channels/channels_screen.dart';

/// بحث موحّد يدوّر بكل المحتوى دفعة واحدة (أفلام/مسلسلات/أنمي/قنوات)
/// بدل الاقتصار على فلترة عناوين الأقسام الظاهرة بنفس الشاشة الحالية
/// فقط (matchesSearchQuery المستخدمة بكل شاشة أخرى) — هنا تُطبَّق على كل
/// الأقسام وكل القنوات/الحلقات معاً، بغض النظر عن مكانها بشجرة الأقسام.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  String _query = '';
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            hintText: 'ابحث عن فيلم، مسلسل، أنمي أو قناة...',
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'مسح',
              onPressed: () => setState(() {
                _controller.clear();
                _query = '';
              }),
            ),
        ],
      ),
      body: _query.trim().isEmpty ? _buildHint() : _buildResults(context),
    );
  }

  Widget _buildResults(BuildContext context) {
    return StreamBuilder<List<CategoryModel>>(
      stream: ContentService.watchCategories(),
      builder: (context, categorySnapshot) {
        return StreamBuilder<List<ChannelModel>>(
          stream: ContentService.watchAllChannels(),
          builder: (context, channelSnapshot) {
            if (!categorySnapshot.hasData || !channelSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final allCategories = categorySnapshot.data!;
            final matchingCategories =
                allCategories.where((c) => matchesSearchQuery(c.title, _query)).toList();
            final matchingChannels = channelSnapshot.data!
                .where((c) => matchesSearchQuery(c.title, _query))
                .toList();
            if (matchingCategories.isEmpty && matchingChannels.isEmpty) {
              return _buildEmpty();
            }
            final categoryById = {for (final c in allCategories) c.id: c};
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (matchingCategories.isNotEmpty) ...[
                  _SectionLabel('الأقسام (${matchingCategories.length})'),
                  for (final category in matchingCategories.take(30))
                    _CategoryResultTile(category: category),
                  const SizedBox(height: 8),
                ],
                if (matchingChannels.isNotEmpty) ...[
                  _SectionLabel('حلقات/قنوات (${matchingChannels.length})'),
                  for (final channel in matchingChannels.take(50))
                    _ChannelResultTile(
                      channel: channel,
                      categoryTitle: categoryById[channel.categoryId]?.title,
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHint() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: Colors.white38),
            SizedBox(height: 14),
            Text(
              'اكتب اسم فيلم أو مسلسل أو أنمي أو قناة — البحث يدوّر بكل المحتوى مرة واحدة',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.white38),
            SizedBox(height: 14),
            Text('لا توجد نتائج مطابقة', style: TextStyle(color: Colors.white60)),
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

class _CategoryResultTile extends StatelessWidget {
  final CategoryModel category;
  const _CategoryResultTile({required this.category});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final typeLabel = switch (category.contentType) {
      'movies' => 'فيلم',
      'series' => 'مسلسل',
      'anime' => 'أنمي',
      _ => 'قسم قنوات',
    };
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
                borderRadius: BorderRadius.circular(10),
                child: category.iconUrl?.isNotEmpty == true
                    ? Image.network(category.iconUrl!,
                        width: 52, height: 52, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallback(accent))
                    : _fallback(accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(typeLabel, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  ],
                ),
              ),
              if (category.rating != null) RatingBadge(rating: category.rating!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback(Color accent) => Container(
        width: 52,
        height: 52,
        color: accent.withValues(alpha: 0.15),
        child: Icon(Icons.video_library_outlined, color: accent),
      );
}

class _ChannelResultTile extends StatelessWidget {
  final ChannelModel channel;
  final String? categoryTitle;
  const _ChannelResultTile({required this.channel, this.categoryTitle});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final disabled = channel.status == 'disabled';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: disabled
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('هذه القناة متوقفة مؤقتاً.')),
                )
            : () => PlayerLauncher.openChannel(context, channel),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: channel.logoUrl?.isNotEmpty == true
                    ? Image.network(channel.logoUrl!,
                        width: 52, height: 52, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallback(accent))
                    : _fallback(accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(channel.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (categoryTitle != null) ...[
                      const SizedBox(height: 3),
                      Text(categoryTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                    ],
                  ],
                ),
              ),
              if (!disabled)
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback(Color accent) => Container(
        width: 52,
        height: 52,
        color: accent.withValues(alpha: 0.15),
        child: Icon(Icons.live_tv_outlined, color: accent),
      );
}
