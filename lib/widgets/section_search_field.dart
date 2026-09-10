import 'package:flutter/material.dart';

/// حقل بحث بسيط يُستخدم أعلى شاشات الأقسام/القنوات لفلترة القائمة
/// المحمّلة فعلاً بالعنوان (عربي أو إنجليزي — مقارنة نصية بسيطة تعمل
/// بأي لغة دون أي حاجة لترجمة).
class SectionSearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String hintText;

  const SectionSearchField({
    super.key,
    required this.onChanged,
    this.hintText = 'ابحث بالاسم...',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// مطابقة نصية بسيطة (تجاهل حالة الأحرف) — تُستخدم لفلترة العناوين.
bool matchesSearchQuery(String title, String query) {
  if (query.trim().isEmpty) return true;
  return title.toLowerCase().contains(query.trim().toLowerCase());
}
