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
import '../widgets/back_to_home.dart';
import 'result_screen.dart' show ConditionChip, formatAvg;

class HighScoreScreen extends ConsumerWidget {
  const HighScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(scoreRepositoryProvider);
    final bestNormal = repo.loadBest(RecordCategory.normal);
    final bestKarafuda = repo.loadBest(RecordCategory.karafuda);
    final last = repo.loadLast();
    // 取得済み画像は、空札なしの最高ランクの枠を表示（従来どおり。記録がなければ D）
    final Rank rankEnum = bestNormal?.rank ?? Rank.D;
    final indices = RewardCatalog.byRank[rankEnum]!;
    final t = Theme.of(context).textTheme;

    // Phase 4 で実践練習の成績を加えるときは、ここを「反応練習／実践練習」のタブにする
    return BackToHome(
      child: BackgroundScaffold(
      appBar: homeAppBar(context, '成績・ランク'),
      child: FutureBuilder<Set<int>>(
        future: GalleryService.loadOwned(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final owned = snap.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child: Text('反応練習',
                            style: t.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                shadows: const [Shadow(color: Colors.white, blurRadius: 6)])),
                      ),
                    ),
                    _RecordCard(title: '最高ランク（空札なし）', record: bestNormal, big: true),
                    const SizedBox(height: 10),
                    _RecordCard(title: '最高ランク（空札あり）', record: bestKarafuda),
                    const SizedBox(height: 10),
                    _RecordCard(title: '前回の結果', record: last, showReference: true),
                    const SizedBox(height: 14),
                    ScoreCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('取得済み画像（${rankEnum.name}）', style: t.titleMedium),
                          const SizedBox(height: 8),
                          // ランクの2枠を固定配置。未取得は hatena を表示
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
                                      owned.contains(i)
                                          ? RewardCatalog.slots[i]
                                          : RewardCatalog.hatena,
                                      width: MediaQuery.of(context).size.width / 3,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
        },
      ),
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
