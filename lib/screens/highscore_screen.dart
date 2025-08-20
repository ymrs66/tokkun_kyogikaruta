import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/background_scaffold.dart';

// 追加
import '../services/gallery_service.dart';
import '../data/reward_catalog.dart';
import '../providers/game_state.dart'; // Rank enum 用

class HighScoreScreen extends StatelessWidget {
  const HighScoreScreen({super.key});

  Future<Map<String, dynamic>> _load() async {
    final p = await SharedPreferences.getInstance();
    final owned = await GalleryService.loadOwned(); // 取得済みID
    return {
      'accuracy': p.getInt('bestAccuracy') ?? 0,
      'avgSec'  : p.getDouble('bestAvgSec') ?? 0.0,
      'rankStr' : p.getString('bestRank') ?? 'D',
      'owned'   : owned,
    };
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundScaffold(
      appBar: AppBar(title: const Text('あなたのランク')),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _load(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d        = snap.data!;
          final rankStr  = d['rankStr'] as String;
          final accuracy = d['accuracy'] as int;
          final avgSec   = d['avgSec'] as double;
          final owned    = d['owned'] as Set<int>;

          // String -> Rank
          final Rank rankEnum = Rank.values.firstWhere(
                (e) => e.name == rankStr,
            orElse: () => Rank.D,
          );

          // このランクのスロット(例: Cなら [6,7])
          final indices = RewardCatalog.byRank[rankEnum]!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    AutoSizeText(
                      '最高ランク : ${rankEnum.name}',
                      maxLines: 1,
                      minFontSize: 18,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text('正解率 : $accuracy %'),
                    Text('平均取得 : ${avgSec.toStringAsFixed(1)} 秒'),

                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '取得済み画像（${rankEnum.name}）',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ランクの2枠を固定配置。未取得は hatena を表示
                    Wrap(
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

                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () => context.go('/'),
                      child: const Text('スタートに戻る'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
