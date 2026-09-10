import 'package:flutter/material.dart';
import '../channels/channels_home_tab.dart';
import '../favorites/favorites_screen.dart';
import '../matches/matches_screen.dart';
import '../media/media_home_tab.dart';
import '../../widgets/app_drawer.dart';

/// الشاشة الجذر للتطبيق: شريط تنقل سفلي بتبويبين — "النتائج" (مباريات
/// اليوم/الغد) و"القنوات" (أقسام البث). القائمة الجانبية (مشاركة، تواصل،
/// الشروط، الخصوصية) والمفضلة تبقى متاحة من الأعلى بغض النظر عن التبويب.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _tabIndex = 0;

  static const _tabs = [
    _TabInfo(title: 'النتائج', icon: Icons.scoreboard_outlined, activeIcon: Icons.scoreboard),
    _TabInfo(title: 'أفلام/مسلسلات', icon: Icons.video_library_outlined, activeIcon: Icons.video_library),
    _TabInfo(title: 'القنوات', icon: Icons.live_tv_outlined, activeIcon: Icons.live_tv),
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
        // زر القائمة الجانبية في leading (يمين الشاشة بالعربية)، وزر
        // المفضلة في actions (يسار الشاشة) — القائمة تفتح drawer من نفس
        // جهة زرّها بدل الجهة المقابلة.
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'القائمة',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: 'المفضلة',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FavoritesScreen()),
            ),
          ),
        ],
      ),
      // drawer يفتح من نفس جهة زر القائمة (leading، يمين الشاشة بالعربية).
      drawer: const AppDrawer(),
      // IndexedStack يحافظ على حالة كل تبويب (مثلاً موضع اليوم المختار في
      // شاشة النتائج) عند التنقل بينهما بدل إعادة بنائه من الصفر.
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          MatchesScreen(),
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
