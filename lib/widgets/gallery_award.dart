// lib/widgets/gallery_award.dart
//
// ギャラリー画像の獲得・コンプリートのお知らせ（反応練習・実践練習の結果画面で共通）
import 'package:flutter/material.dart';

import '../data/reward_catalog.dart';
import '../providers/game_state.dart' show ResultOutcome;

Future<void> showGalleryAward(BuildContext context, ResultOutcome outcome) async {
  final id = outcome.grantedGalleryId;
  if (id != null) {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dctx) => AlertDialog(
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
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // コンプリートが今回で解禁されたらお知らせ
  if (outcome.completeUnlocked && context.mounted) {
    await showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('コンプリート！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(RewardCatalog.completeImage, width: 220, fit: BoxFit.cover),
            const SizedBox(height: 8),
            const Text('全ランク画像を集めました！'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('OK'))],
      ),
    );
  }
}
