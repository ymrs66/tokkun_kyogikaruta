// lib/domain/match_plan.dart
//
// 実践練習（12枚固定）の配置と読み順。Flutter に依存しない。
//
// - 場の札：自陣6枚・敵陣6枚（各陣 横3枚×縦2段）。位置は練習の最後まで変わらない
// - 空札の数：K = round(12 × r ÷ (1 − r))。総出題数は 12 + K（なし12／30% 17／50% 24）
// - 読み順：最後は必ず場の札。同じ札は二度読まない
import 'dart:math';

import '../models/card_data.dart';

/// 陣
enum Side { self, enemy }

/// 実践練習の場の札の枚数（固定）
const int matchFieldCount = 12;

/// 1陣の列数・段数
const int matchColumns = 3;
const int matchRowsPerSide = 2;

/// 選べる空札の割合（0 = なし）
const List<int> matchKarafudaPercentOptions = [0, 30, 50];

/// 選べる暗記時間（秒）
const List<int> matchMemorizeSecOptions = [30, 60, 180];

/// 空札の数。割合 r は「全出題数に占める空札の割合」：K = round(12 × r ÷ (1 − r))。
/// 30% → 5.14… → 5、50% → 12。選択肢にない値は 0。
int matchKarafudaCount(int percent) {
  if (!matchKarafudaPercentOptions.contains(percent) || percent == 0) return 0;
  return (matchFieldCount * percent / (100 - percent)).round();
}

/// 総出題数（場の札12＋空札）
int matchTotalReads(int percent) => matchFieldCount + matchKarafudaCount(percent);

/// 場の札の位置（練習中は増えも減りもしない）
class MatchSlot {
  const MatchSlot({
    required this.index,
    required this.side,
    required this.row,
    required this.col,
    required this.card,
  });

  /// 0〜5：敵陣（画面の上から 下段・上段 の順に並べる前の通し番号）、6〜11：自陣
  final int index;
  final Side side;

  /// 陣の中の段（0 = 中央に近い段、1 = 外側の段）
  final int row;
  final int col;
  final CardData card;
}

/// 1回の読み
class ReadItem {
  const ReadItem(this.card, {this.slotIndex});
  final CardData card;

  /// 場の札なら位置の番号、空札なら null
  final int? slotIndex;
  bool get isKarafuda => slotIndex == null;

  @override
  String toString() => isKarafuda ? 'K${card.id}' : 'F${card.id}@$slotIndex';
}

/// 配置と読み順
class MatchPlan {
  const MatchPlan({required this.slots, required this.reads});
  final List<MatchSlot> slots;
  final List<ReadItem> reads;

  int get karafudaCount => reads.where((r) => r.isKarafuda).length;
}

/// 12枚の配置を作る（自陣・敵陣の割り当てもランダム）。
List<MatchSlot> buildMatchSlots({required List<CardData> fieldCards}) {
  assert(fieldCards.length == matchFieldCount);
  return [
    for (var i = 0; i < matchFieldCount; i++)
      MatchSlot(
        index: i,
        side: i < 6 ? Side.enemy : Side.self,
        row: (i % 6) ~/ matchColumns,
        col: (i % 6) % matchColumns,
        card: fieldCards[i],
      ),
  ];
}

/// 読み順を作る：場の札1枚を最後に置き、残りの場の札11枚と空札をシャッフルして前に並べる。
List<ReadItem> buildReadOrder({
  required List<MatchSlot> slots,
  required List<CardData> karafuda,
  required Random rng,
}) {
  final field = [for (final s in slots) ReadItem(s.card, slotIndex: s.index)];
  final last = field.removeAt(rng.nextInt(field.length));
  final head = [...field, for (final c in karafuda) ReadItem(c)]..shuffle(rng);
  return [...head, last];
}

/// 新しい配置と読み順を作る。[keepSlots] を渡すと同じ配置のまま読み順だけ作り直す（同じ配置でもう一度）。
MatchPlan buildMatchPlan({
  required List<CardData> allCards,
  required int karafudaPercent,
  required Random rng,
  List<MatchSlot>? keepSlots,
}) {
  final List<MatchSlot> slots;
  if (keepSlots != null) {
    slots = keepSlots;
  } else {
    final picked = [...allCards]..shuffle(rng);
    slots = buildMatchSlots(fieldCards: picked.take(matchFieldCount).toList());
  }
  final onField = {for (final s in slots) s.card.id};
  final rest = allCards.where((c) => !onField.contains(c.id)).toList()..shuffle(rng);
  final k = matchKarafudaCount(karafudaPercent);
  final reads = buildReadOrder(slots: slots, karafuda: rest.take(k).toList(), rng: rng);
  return MatchPlan(slots: slots, reads: reads);
}

/// 中断した読みを、残りの読み順に入れ直す（練習中の中断から「続ける」）。
///
/// - [remaining]：中断した読みより後の読み（まだ読んでいないもの）
/// - 最後の場の札（残りに場の札がない）なら最後のまま
/// - それ以外は、最後の要素（場の札）より前のランダムな位置。できればすぐ次ではない位置
List<ReadItem> reinsertInterrupted(
    List<ReadItem> remaining, ReadItem interrupted, Random rng) {
  if (remaining.isEmpty) return [interrupted];
  final noFieldLeft = remaining.every((r) => r.isKarafuda);
  if (!interrupted.isKarafuda && noFieldLeft) {
    return [...remaining, interrupted];
  }
  // 入れられる位置：0 〜 remaining.length - 1（最後の場の札の前）。できれば 1 以上
  final maxPos = remaining.length - 1;
  final minPos = maxPos >= 1 ? 1 : 0;
  final pos = minPos + rng.nextInt(maxPos - minPos + 1);
  return [...remaining]..insert(pos, interrupted);
}
