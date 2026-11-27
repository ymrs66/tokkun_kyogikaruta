// lib/widgets/match_field.dart
//
// 実践練習の場（敵陣6枚・中央の情報欄・自陣6枚）。暗記中も練習中も同じ部品で描くので、
// 札の座標・大きさは暗記から練習へ移っても変わらない。判定の表示は枠線だけで、札の大きさ・位置は変えない。
import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/match_plan.dart';
import '../providers/match_state.dart';

/// 札の縦横比（画像 160×213）
const double cardAspect = 160 / 213;

/// 札の大きさ・間隔の計算結果
class MatchFieldMetrics {
  const MatchFieldMetrics({
    required this.cardW,
    required this.cardH,
    required this.colGap,
    required this.rowGap,
    required this.band,
    required this.sidePad,
    required this.labelW,
  });
  final double cardW;
  final double cardH;

  /// 横の札の間隔
  final double colGap;

  /// 同じ陣の段の間隔
  final double rowGap;

  /// 中央の情報欄（敵陣と自陣の間）の高さ
  final double band;

  /// 陣の枠の内側の余白
  final double sidePad;

  /// 陣の名前（敵陣・自陣）を縦書きで置く幅
  final double labelW;

  /// 札を押せる大きさがあるか（44dp 未満なら練習を止めて縦向きを促す）
  bool get usable => cardW >= minCardWidth;

  /// 陣の枠の幅（陣の名前・余白・札3枚・間隔・枠線）
  double get sideWidth => (labelW + sidePad) * 2 + cardW * 3 + colGap * 3 + 2.4;

  /// 場全体の高さ
  double get fieldHeight => sidePad * 4 + rowGap * 2 + cardH * 4 + band + 5;

  /// 札の最小幅（iOS のタップ領域 44pt に合わせる）
  static const double minCardWidth = 44;

  /// 札の最大幅。実物の取り札（約 5.3×7.3cm）はおよそ 330×460dp だが、
  /// 縦4段では大きなタブレットでも入らない。場全体を一目で見渡せる大きさ（実物の半分程度）で止める。
  static const double maxCardWidth = 170;

  /// 画面（本体）の大きさから計算する。[bottomArea] は下のボタンの領域。
  static MatchFieldMetrics compute(Size body, {required double bottomArea}) {
    MatchFieldMetrics fit(double colGap, double rowGap, double band, double sidePad, double labelW) {
      const outer = 6.0; // 画面の上下左右の余白
      // 陣の枠線（1.2×2）の分も差し引く
      final byH = (body.height - outer * 2 - bottomArea - band - sidePad * 4 - rowGap * 2 - 5) / 4;
      final byW = (body.width - outer * 2 - (labelW + sidePad + 1.5) * 2 - colGap * 3) / 3;
      final w = max(0.0, min(min(byH * cardAspect, byW), maxCardWidth));
      return MatchFieldMetrics(
          cardW: w, cardH: w / cardAspect, colGap: colGap, rowGap: rowGap,
          band: band, sidePad: sidePad, labelW: labelW);
    }

    // まずスマートフォン向けの間隔で計算し、札が大きい（タブレット）ときは間隔・情報欄も広げて計算し直す
    final base = fit(6, 6, 44, 4, 18);
    if (base.cardW < 110) return base;
    final s = base.cardW / 110;
    return fit(min(6 * s, 14), min(6 * s, 14), min(44 * s, 72), min(4 * s, 10), 22);
  }
}

/// 実践練習の場
class MatchFieldView extends StatelessWidget {
  const MatchFieldView({
    super.key,
    required this.metrics,
    required this.match,
    required this.band,
    this.onTapSlot,
  });

  final MatchFieldMetrics metrics;
  final MatchState match;

  /// 中央の情報欄の中身
  final Widget band;

  /// 札を押したとき（暗記中・受付中以外は null）
  final void Function(int slotIndex)? onTapSlot;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final visible = match.fieldVisible;

    Widget slot(MatchSlot s) {
      final occupied = match.occupied.contains(s.index);
      final mark = match.marks[s.index];
      final Color? frame = switch (mark) {
        SlotMark.taken => const Color(0xFF2E7D32),
        SlotMark.missed => const Color(0xFFC62828),
        SlotMark.touched => const Color(0xFFEF6C00),
        null => null,
      };
      final Widget content;
      if (!visible) {
        content = const SizedBox.expand(); // 一時停止中は札を隠す（覆いは陣の上に描く）
      } else if (!occupied) {
        // 取った・取り逃した位置：同じ大きさの空白（押しても何も起きない）
        content = DecoratedBox(
          key: ValueKey('empty-${s.index}'),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(color: Colors.black.withValues(alpha: 0.18), width: 1),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      } else {
        content = GestureDetector(
          key: ValueKey('slot-${s.index}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTapSlot == null ? null : () => onTapSlot!(s.index),
          child: Transform.rotate(
            angle: s.side == Side.enemy ? pi : 0,
            child: Image.asset(s.card.imagePath, fit: BoxFit.contain),
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: m.colGap / 2),
        child: SizedBox(
          key: ValueKey('pos-${s.index}'), // 位置（札があっても空白でも同じ大きさ・座標）
          width: m.cardW,
          height: m.cardH,
          child: DecoratedBox(
            // 強調は枠線を重ねるだけ（札の大きさ・位置は変えない。文字を隠さない）
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: frame == null ? null : Border.all(color: frame, width: 3.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: content,
          ),
        ),
      );
    }

    // 段の並び：敵陣は 外側の段（row 1）→ 中央に近い段（row 0）、自陣は 中央に近い段 → 外側の段
    Widget rowOf(Side side, int row) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in match.slots.where((s) => s.side == side && s.row == row)) slot(s),
          ],
        );

    Widget sideBox(Side side) {
      final enemy = side == Side.enemy;
      final rows = enemy ? [1, 0] : [0, 1];
      final color = enemy ? const Color(0xFFC62828) : const Color(0xFF1565C0);
      final label = SizedBox(
        width: m.labelW,
        child: Text(
          enemy ? '敵\n陣' : '自\n陣',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: m.labelW * 0.62, height: 1.15, color: color, fontWeight: FontWeight.bold),
        ),
      );
      return Container(
        key: ValueKey(enemy ? 'enemy-side' : 'self-side'),
        padding: EdgeInsets.all(m.sidePad),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                label,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    rowOf(side, rows[0]),
                    SizedBox(height: m.rowGap),
                    rowOf(side, rows[1]),
                  ],
                ),
                SizedBox(width: m.labelW),
              ],
            ),
            if (!visible)
              Positioned.fill(
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8DDB8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('一時停止中（札を隠しています）',
                      style: TextStyle(color: Colors.black54)),
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        sideBox(Side.enemy),
        // 情報欄は陣と同じ幅（大きな画面で横に広がりすぎない）
        SizedBox(height: m.band, width: m.sideWidth, child: band),
        sideBox(Side.self),
      ],
    );
  }
}
