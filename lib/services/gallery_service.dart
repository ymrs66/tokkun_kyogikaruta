// lib/services/gallery_service.dart
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/reward_catalog.dart';
import '../providers/game_state.dart';

class GalleryService {
  static const _ownedKey = 'galleryOwnedIds';
  static final _rng = Random();

  static Future<Set<int>> loadOwned() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_ownedKey) ?? const [];
    return list.map(int.parse).toSet();
  }

  static Future<void> _saveOwned(Set<int> owned) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_ownedKey, owned.map((e) => e.toString()).toList());
  }

  /// 1回の結果につき1枚付与:
  ///  1) まず該当ランクの未所持からランダム
  ///  2) そのランクがコンプ済みなら、他ランクの未所持からランダム
  ///  3) すべて集まった瞬間に completeIndex を自動解禁（別枠）
  static Future<int?> grantOne({required Rank rank}) async {
    final owned = await loadOwned();

    // コンプリート枠は通常の候補に含めない
    int? pickFrom(List<int> pool) {
      final remains = pool.where((i) => !owned.contains(i)).toList();
      if (remains.isEmpty) return null;
      return remains[_rng.nextInt(remains.length)];
    }

    // ランク限定：そのランクの未取得が無ければ今回は付与なし
    final group = RewardCatalog.byRank[rank]!;
    int? granted = pickFrom(group);

    // 何も残っていなければ null（以降は complete 解禁チェックのみ）
    if (granted != null) {
      owned.add(granted);
    }

    // 全ランク画像コンプ→コンプリート枠を自動解禁
    if (!owned.contains(RewardCatalog.completeIndex) &&
        RewardCatalog.isComplete(owned)) {
      owned.add(RewardCatalog.completeIndex);
      // ここでは granted は変えない（演出は結果画面の justUnlocked で別表示）
    }

    await _saveOwned(owned);
    return granted;
  }
}
