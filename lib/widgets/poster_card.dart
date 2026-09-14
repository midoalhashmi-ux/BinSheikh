import 'package:flutter/material.dart';

/// بطاقة بوستر عمودية (صورة + تدرّج + عنوان أسفلها) — نفس تصميم بطاقات
/// شبكة الأقسام الحالية (ChannelsHomeTab/MediaCategoriesScreen)، بس بحجم
/// ثابت يصلح لصف تمرير أفقي (صفوف الرئيسية الديناميكية: شاهدته مؤخراً،
/// الأكثر مشاهدة، أُضيف حديثاً).
class PosterCard extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final IconData fallbackIcon;
  final VoidCallback onTap;
  final Widget? badge;
  final double width;

  const PosterCard({
    super.key,
    required this.title,
    required this.onTap,
    this.imageUrl,
    this.fallbackIcon = Icons.movie_creation_outlined,
    this.badge,
    this.width = 128,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 0.68,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null && imageUrl!.isNotEmpty)
                  Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallback(accent),
                  )
                else
                  _fallback(accent),
                if (badge != null) Positioned(top: 8, right: 8, child: badge!),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: Tooltip(
                      message: title,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
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
        ),
      ),
    );
  }

  Widget _fallback(Color accent) => Container(
        color: accent.withValues(alpha: 0.16),
        child: Icon(fallbackIcon, size: 38, color: accent),
      );
}

/// صف أفقي قابل لإعادة الاستخدام لأي صف بوسترات بالرئيسية (عنوان + زر
/// "عرض الكل" اختياري + تمرير أفقي). يرجع فارغاً (لا شيء يُرسم) لو
/// القائمة فارغة، حتى لا يترك مسافة/عنوان بلا محتوى تحته.
class PosterRow extends StatelessWidget {
  final String title;
  final List<Widget> cards;
  final VoidCallback? onSeeAll;

  const PosterRow({
    super.key,
    required this.title,
    required this.cards,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: const Text('عرض الكل'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 128 / 0.68 + 4,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) => cards[index],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
