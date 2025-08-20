import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../widgets/background_scaffold.dart';
import 'package:tokkun_kyogikaruta/services/ad_service.dart';

import '../providers/game_provider.dart';
import '../providers/game_state.dart';
import '../services/gallery_service.dart';
import '../data/reward_catalog.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _grantedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdService.showInterstitialOnce();
      _maybeGrant();
    });
  }

  Future<void> _maybeGrant() async {
    if (_grantedOnce) return;
    _grantedOnce = true;

    final g = ref.read(gameProvider);
    final int accuracy = (g.correct / GameState.maxRound * 100).round();
    final double avgSec = g.correct == 0 ? 0 : g.totalSec / g.correct;
    final rank = calcRank(accuracy, avgSec);

    // 付与前の状態を保存（complete解禁の検出用）
    final before = await GalleryService.loadOwned();
    final id = await GalleryService.grantOne(rank: rank);

    if (!mounted) return;

    if (id != null) {
      // 獲得演出
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => AlertDialog(
          title: const Text('画像を獲得！'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(RewardCatalog.slots[id], width: 220, fit: BoxFit.cover),
              const SizedBox(height: 8),
              Text('NEW!  ${RewardCatalog.labelOf(id)} を入手しました'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    }

    // コンプリートが今回で解禁されたらお知らせ（任意）
    final after = await GalleryService.loadOwned();
    final justUnlocked = !before.contains(RewardCatalog.completeIndex)
        &&  after.contains(RewardCatalog.completeIndex);
    if (justUnlocked && mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('コンプリート！'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(RewardCatalog.completeImage, width: 220, fit: BoxFit.cover),
              const SizedBox(height: 8),
              const Text('全ランク画像を集めました！'),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    final g = ref.read(gameProvider);
    final int accuracy = (g.correct / GameState.maxRound * 100).round();
    final double avgSec = g.correct == 0 ? 0 : g.totalSec / g.correct;
    final rank = calcRank(accuracy, avgSec).name;

    return BackgroundScaffold(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('--- 結果 ---',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('正解率 : $accuracy %'),
            Text('平均取得秒数 : ${avgSec.toStringAsFixed(1)} 秒'),
            const SizedBox(height: 12),
            Text('ランク : $rank', style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                g.resetGame();
                context.go('/');
              },
              child: const Text('スタートへ戻る'),
            ),
            TextButton(
              onPressed: () => context.go('/gallery'),
              child: const Text('ギャラリーを見る'),
            ),
          ],
        ),
      ),
    );
  }
}
