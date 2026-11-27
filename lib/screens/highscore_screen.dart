import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../widgets/background_scaffold.dart';

import '../domain/practice_record.dart';
import '../providers/game_provider.dart';
import '../services/gallery_service.dart';
import '../data/reward_catalog.dart';
import '../providers/game_state.dart'; // Rank enum 用
import '../widgets/score_card.dart';
import '../domain/match_plan.dart';
import '../widgets/back_to_home.dart';
import 'result_screen.dart' show ConditionChip, formatAvg;

class HighScoreScreen extends ConsumerWidget {
  const HighScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(scoreRepositoryProvider);
    final t = Theme.of(context).textTheme;

    // 反応練習・実践練習をタブで切り替える。ギャラリーは両モード共通
    return BackToHome(
      child: DefaultTabController(
        length: 2,
        child: BackgroundScaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'ホームへ戻る',
              onPressed: () => context.go('/'),
            ),
            title: const Text('成績・ランク'),
            bottom: const TabBar(tabs: [Tab(text: '反応練習'), Tab(text: '実践練習')]),
          ),
          child: FutureBuilder<Set<int>>(
            future: GalleryService.loadOwned(),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final owned = snap.data!;
              Widget page(List<Widget> cards, Rank galleryRank) => SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          children: [
                            ...cards,
                            const SizedBox(height: 14),
                            _GalleryCard(rank: galleryRank, owned: owned),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () => context.go('/'),
                              child: const Text('ホームに戻る'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );

              // 反応練習
              final bestNormal = repo.loadBest(RecordCategory.normal);
              final bestKarafuda = repo.loadBest(RecordCategory.karafuda);
              final reaction = page([
                _RecordCard(title: '最高ランク（空札なし）', record: bestNormal, big: true),
                const SizedBox(height: 10),
                _RecordCard(title: '最高ランク（空札あり）', record: bestKarafuda),
                const SizedBox(height: 10),
                _RecordCard(title: '前回の結果', record: repo.loadLast(), showReference: true),
              ], bestNormal?.rank ?? Rank.D); // 従来どおり空札なしの最高ランクの枠

              // 実践練習（空札の割合別の3条件）
              final matchBests = [for (final k in matchKarafudaPercentOptions) (k, repo.loadMatchBest(k))];
              final bestMatchRank = matchBests
                  .map((e) => e.$2?.rank)
                  .whereType<Rank>()
                  .fold<Rank?>(null, (a, b) => a == null || b.index < a.index ? b : a);
              final match = page([
                for (final (k, r) in matchBests) ...[
                  _RecordCard(
                    title: '最高ランク（${k == 0 ? '空札なし' : '空札 $k%'}・全${matchTotalReads(k)}問）',
                    record: r,
                    big: k == 30,
                  ),
                  const SizedBox(height: 10),
                ],
                _RecordCard(title: '前回の結果', record: repo.loadMatchLast(), showReference: true),
                const SizedBox(height: 6),
                Text('暗記時間は記録しますが、最高記録の分け方には使いません。',
                    style: t.bodySmall?.copyWith(shadows: const [Shadow(color: Colors.white, blurRadius: 6)])),
              ], bestMatchRank ?? Rank.D);

              return TabBarView(children: [reaction, match]);
            },
          ),
        ),
      ),
    );
  }
}

/// 取得済み画像（ランクの2枠。両モード共通のギャラリー）
class _GalleryCard extends StatelessWidget {
  const _GalleryCard({required this.rank, required this.owned});
  final Rank rank;
  final Set<int> owned;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final indices = RewardCatalog.byRank[rank]!;
    final w = (MediaQuery.of(context).size.width / 3).clamp(80.0, 180.0);
    return ScoreCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('取得済み画像（${rank.name}）', style: t.titleMedium),
          Text('ギャラリーは反応練習・実践練習で共通です', style: t.bodySmall),
          const SizedBox(height: 8),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final i in indices)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      owned.contains(i) ? RewardCatalog.slots[i] : RewardCatalog.hatena,
                      width: w,
                      fit: BoxFit.cover,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.title,
    required this.record,
    this.big = false,
    this.showReference = false,
  });

  final String title;
  final PracticeRecord? record;
  final bool big;
  final bool showReference;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = record;
    return ScoreCard(
      child: Column(
        children: [
          Text(title, style: t.titleSmall?.copyWith(color: Colors.black54)),
          const SizedBox(height: 4),
          if (r == null)
            Text('まだ記録がありません', style: t.bodyMedium)
          else ...[
            AutoSizeText(
              r.rank.name,
              maxLines: 1,
              style: big ? t.headlineMedium : t.titleLarge,
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text('正答率 ${r.accuracy} %'),
                Text('平均 ${r.isLegacyTiming && r.avgMs != null ? '${(r.avgMs! / 1000).toStringAsFixed(1)} 秒' : formatAvg(r.avgMs)}'),
                if (r.isLegacyTiming) const _Tag('旧計測'),
                if (!r.isLegacyTiming) ConditionChip(record: r),
                if (showReference && r.isReference) const _Tag('参考記録'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}
