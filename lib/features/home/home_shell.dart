import 'package:flutter/material.dart';
import '../channels/channels_home_tab.dart';
import '../favorites/favorites_screen.dart';
import '../media/media_home_tab.dart';
import '../search/global_search_screen.dart';
import '../../widgets/app_drawer.dart';

/// الشاشة الجذر للتطبيق: شريط تنقل سفلي بتبويبين فقط — "أفلام ومسلسلات"
/// و"نتائج وقنوات" (نتائج مباريات اليوم كصف أعلى تبويب القنوات، بدل
/// تبويب ثالث مستقل). القائمة الجانبية (مشاركة، تواصل، الشروط، الخصوصية)
/// والمفضلة والبحث تبقى متاحة من الأعلى بغض النظر عن التبويب.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _tabIndex = 0;

  static const _tabs = [
    _TabInfo(title: 'أفلام ومسلسلات', icon: Icons.video_library_outlined, activeIcon: Icons.video_library),
    _TabInfo(title: 'نتائج وقنوات', icon: Icons.live_tv_outlined, activeIcon: Icons.live_tv),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          'BinSheikh',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 21,
            letterSpacing: 0.3,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        // زر القائمة الجانبية انتقل من leading (يمين الشاشة بالعربية) إلى
        // actions (يسار الشاشة)، والقائمة نفسها تفتح من نفس الجهة
        // (endDrawer بدل drawer — اتجاه الشاشة RTL فتُفتح "end" من
        // اليسار) — القائمة تفتح دائماً من نفس جهة زرّها بدل الجهة
        // المقابلة.
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'بحث',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: 'المفضلة',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FavoritesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'القائمة',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      endDrawer: const AppDrawer(),
      // IndexedStack يحافظ على حالة كل تبويب عند التنقل بينهما بدل إعادة
      // بنائه من الصفر.
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          MediaHomeTab(),
          ChannelsHomeTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.activeIcon),
              label: tab.title,
            ),
        ],
      ),
    );
  }
}

class _TabInfo {
  final String title;
  final IconData icon;
  final IconData activeIcon;
  const _TabInfo({required this.title, required this.icon, required this.activeIcon});
}
