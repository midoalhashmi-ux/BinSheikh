import 'package:flutter/material.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/favorites_service.dart';
import '../../core/services/player_launcher.dart';

class ChannelCard extends StatelessWidget {
  final ChannelModel channel;
  // يُخفى زر القلب على مستوى الحلقة عندما تكون المفضلة مُفعَّلة على مستوى
  // القسم كاملاً (مسلسل/أنمي) بدل الحلقة الواحدة — راجع _ChannelsList.
  final bool showFavoriteButton;
  const ChannelCard({
    super.key,
    required this.channel,
    this.showFavoriteButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final disabled = channel.status == 'disabled';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: disabled
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('هذه القناة متوقفة مؤقتاً.')),
                )
            : () => PlayerLauncher.openChannel(context, channel.id,
                categoryId: channel.categoryId, title: channel.title),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: channel.logoUrl != null && channel.logoUrl!.isNotEmpty
                    ? Image.network(
                        channel.logoUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallbackLogo(accent),
                      )
                    : _fallbackLogo(accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: channel.title,
                      child: Text(channel.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 3),
                    Text(channel.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white60)),
                  ],
                ),
              ),
              if (showFavoriteButton)
                ValueListenableBuilder<Set<String>>(
                  valueListenable: FavoritesService.favorites,
                  builder: (context, favoriteIds, _) {
                    final isFavorite = favoriteIds.contains(channel.id);
                    return IconButton(
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite ? Colors.redAccent : Colors.white38,
                      ),
                      tooltip: isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                      onPressed: () => FavoritesService.toggleFavorite(channel.id),
                    );
                  },
                ),
              if (!disabled)
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackLogo(Color accent) {
    return Container(
      width: 60,
      height: 60,
      color: accent.withValues(alpha: 0.15),
      child: Icon(Icons.sports_soccer, color: accent),
    );
  }
}
