import 'package:flutter/material.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/content_service.dart';
import '../../core/services/favorites_service.dart';
import '../channels/channel_card.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المفضلة')),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: FavoritesService.favorites,
        builder: (context, favoriteIds, _) {
          if (favoriteIds.isEmpty) {
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
                      'لا توجد قنوات مفضلة بعد',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اضغط أيقونة القلب بجانب أي قناة لإضافتها هنا',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            );
          }
          return FutureBuilder<List<ChannelModel>>(
            future: ContentService.fetchChannelsByIds(favoriteIds.toList()),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final channels = snapshot.data!;
              if (channels.isEmpty) {
                return const Center(
                  child: Text('تعذر تحميل القنوات المفضلة، حاول لاحقاً'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: channels.length,
                itemBuilder: (context, index) =>
                    ChannelCard(channel: channels[index]),
              );
            },
          );
        },
      ),
    );
  }
}
