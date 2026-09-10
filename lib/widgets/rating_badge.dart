import 'package:flutter/material.dart';

/// شارة تقييم (مخزّنة 0-100 داخلياً، تُعرض بصيغة "X.X/10" المعتادة —
/// نفس أسلوب IMDb/TMDB) تُظهر أعلى بطاقات الأفلام/المسلسلات/الأنمي.
/// تُبنى فقط عند وجود [CategoryModel.rating] فعلياً — لا تظهر إطلاقاً
/// للأقسام غير المفحوصة بعد أو التي لم يُعثر لها على تطابق موثوق.
class RatingBadge extends StatelessWidget {
  final int rating;
  const RatingBadge({super.key, required this.rating});

  @override
  Widget build(BuildContext context) {
    final outOfTen = (rating / 10).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
          const SizedBox(width: 3),
          Text(
            '$outOfTen/10',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
