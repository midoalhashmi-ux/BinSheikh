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
    _TabInfo(title: 'القنوات', icon: Icons.live_tv_outlined, activeIcon: Icons.live_tv),
    _TabInfo(title: 'المحتوى', icon: Icons.video_library_outlined, activeIcon: Icons.video_library),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv_rounded, color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            const Text('BinSheikh'),
          ],
        ),
        // زر القائمة الجانبية (كان يظهر تلقائياً بمكان "leading" — يمين
        // الشاشة في العربية) انتقل الآن ليكون action (يسار الشاشة)، وزر
        // المفضلة انتقل من action إلى leading (يمين الشاشة) — عكس الترتيب
        // السابق تماماً كما طُلب.
        leading: IconButton(
          icon: const Icon(Icons.favorite),
          tooltip: 'المفضلة',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FavoritesScreen()),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'القائمة',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      // endDrawer (بدل drawer) يفتح من نفس جهة زر القائمة (الآن بـ actions،
      // أي يسار الشاشة بالعربية) بدل الجهة المقابلة.
      endDrawer: const AppDrawer(),
      // IndexedStack يحافظ على حالة كل تبويب (مثلاً موضع اليوم المختار في
      // شاشة النتائج) عند التنقل بينهما بدل إعادة بنائه من الصفر.
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          MatchesScreen(),
          ChannelsHomeTab(),
          MediaHomeTab(),
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
