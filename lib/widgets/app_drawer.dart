import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/services/app_settings_service.dart';
import '../features/contact/contact_screen.dart';
import '../features/legal/legal_screen.dart';

/// القائمة الجانبية للشاشة الرئيسية. تُبنى تدريجياً — كل بند جديد من
/// القسم 3 (مشاركة، تواصل معنا، الشروط، الخصوصية) يُضاف هنا.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _shareApp(BuildContext context) async {
    final settings = await AppSettingsService.fetchSettings();
    final link = settings.appStoreUrl.trim();
    final text = link.isNotEmpty
        ? '${settings.shareMessage}\n$link'
        : settings.shareMessage;
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.live_tv_rounded, color: accent, size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'BinSheikh',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: const Text('مشاركة التطبيق'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _shareApp(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: const Text('تواصل معنا'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ContactScreen()),
                      );
                    },
                  ),
                  const Divider(height: 24),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('الشروط والأحكام'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LegalScreen(
                            field: 'terms',
                            title: 'الشروط والأحكام',
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('سياسة الخصوصية'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LegalScreen(
                            field: 'privacy',
                            title: 'سياسة الخصوصية',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
