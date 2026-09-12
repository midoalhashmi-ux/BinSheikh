import 'package:flutter/material.dart';
import '../../core/data/football_ar_translations.dart';
import '../../core/models/category_model.dart';
import '../../core/models/match_model.dart';
import '../../core/services/content_service.dart';
import '../../core/services/matches_service.dart';
import '../../widgets/section_search_field.dart';
import '../matches/match_details_screen.dart';
import '../matches/matches_screen.dart';
import 'channels_screen.dart';

/// تبويب "نتائج وقنوات": نتائج مباريات اليوم كصف أفقي أعلى الصفحة (مع
/// رابط "عرض الكل" لشاشة النتائج الكاملة بتنقّل الأيام والفلاتر)، وتحته
/// مباشرة شبكة أقسام القنوات المباشرة — بدون أي صفحة وسيطة فارغة، كل
/// المحتوى يظهر بمجرد فتح التبويب.
class ChannelsHomeTab extends StatefulWidget {
  const ChannelsHomeTab({super.key});

  @override
  State<ChannelsHomeTab> createState() => _ChannelsHomeTabState();
}

class _ChannelsHomeTabState extends State<ChannelsHomeTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: ContentService.watchRootCategories(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
              child: Text('تعذر تحميل الأقسام. تحقق من اتصال الإنترنت وقواعد Firebase.'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        // تبويب "القنوات" يعرض فقط أقسام القنوات المباشرة — أقسام
        // الأفلام/المسلسلات/الأنمي تظهر حصراً بتبويب "أفلام/مسلسلات"
        // (كانت تظهر بالاثنين معاً بسبب غياب هذا الفلتر).
        final channelCategories = snapshot.data!
            .where((category) => category.contentType == 'channels')
            .toList();
        final categories = channelCategories
            .where((category) => matchesSearchQuery(category.title, _query))
            .toList();
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SectionSearchField(onChanged: (value) => setState(() => _query = value)),
            ),
            const SliverToBoxAdapter(child: _TodayMatchesRow()),
            if (channelCategories.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('لا توجد أقسام بعد')),
              )
            else if (categories.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('لا توجد نتائج مطابقة')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.95,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _CategoryTile(category: categories[index]),
                    childCount: categories.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final CategoryModel category;
  const _CategoryTile({required this.category});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChannelsScreen(category: category)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (category.iconUrl?.isNotEmpty == true)
              Image.network(category.iconUrl!,
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(context))
            else
              _fallback(context),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Tooltip(
                  message: category.title,
                  child: Text(category.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          height: 1.2,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      color: accent.withValues(alpha: 0.18),
      child: Icon(Icons.sports_soccer, size: 42, color: accent),
    );
  }
}

/// صف أفقي مضغوط لنتائج مباريات اليوم فقط (بدون فلاتر/بحث/تنقّل أيام —
/// هذي موجودة بشاشة النتائج الكاملة خلف "عرض الكل"). يختفي كلياً لو ما
/// فيه مباريات اليوم بدل ترك عنوان بلا محتوى تحته.
class _TodayMatchesRow extends StatefulWidget {
  const _TodayMatchesRow();

  @override
  State<_TodayMatchesRow> createState() => _TodayMatchesRowState();
}

class _TodayMatchesRowState extends State<_TodayMatchesRow> {
  late final Future<List<MatchModel>> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _future = MatchesService.fetchMatches(DateTime(now.year, now.month, now.day));
  }

  static const _statusPriority = {
    MatchStatus.live: 0,
    MatchStatus.upcoming: 1,
    MatchStatus.postponed: 2,
    MatchStatus.finished: 3,
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MatchModel>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final matches = snapshot.data!
            .where((m) => FootballTranslations.isSupportedLeague(m.leagueNameEn, m.leagueCountryEn))
            .toList()
          ..sort((a, b) {
            final byStatus = _statusPriority[a.status]!.compareTo(_statusPriority[b.status]!);
            if (byStatus != 0) return byStatus;
            return a.kickoff.compareTo(b.kickoff);
          });
        if (matches.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('نتائج اليوم',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('النتائج')),
                          body: const MatchesScreen(),
                        ),
                      ),
                    ),
                    child: const Text('عرض الكل'),
                  ),
                ],
              ),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: matches.length > 12 ? 12 : matches.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => _MatchMiniCard(match: matches[index]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MatchMiniCard extends StatelessWidget {
  final MatchModel match;
  const _MatchMiniCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 148,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MatchDetailsScreen(match: match)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  FootballTranslations.leagueWithCountry(match.leagueNameEn, match.leagueCountryEn),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.5, color: Colors.white54),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: _team(match.homeTeamEn, match.homeLogo)),
                    SizedBox(width: 42, child: _centerInfo(primary)),
                    Expanded(child: _team(match.awayTeamEn, match.awayLogo)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _team(String nameEn, String? logo) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logo != null)
          Image.network(logo, width: 22, height: 22,
              errorBuilder: (_, __, ___) => const Icon(Icons.shield_outlined, size: 22))
        else
          const Icon(Icons.shield_outlined, size: 22),
        const SizedBox(height: 3),
        Text(
          FootballTranslations.team(nameEn),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 9),
        ),
      ],
    );
  }

  Widget _centerInfo(Color primary) {
    switch (match.status) {
      case MatchStatus.live:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${match.homeScore ?? 0}-${match.awayScore ?? 0}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: primary)),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
              child: const Text('مباشر', style: TextStyle(color: Colors.white, fontSize: 8)),
            ),
          ],
        );
      case MatchStatus.finished:
        return Text('${match.homeScore ?? 0}-${match.awayScore ?? 0}',
            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12));
      case MatchStatus.postponed:
        return const Text('مؤجلة',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.orangeAccent, fontSize: 9));
      case MatchStatus.upcoming:
        return Text(FootballTranslations.formatTime12(match.kickoff),
            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10));
    }
  }
}
