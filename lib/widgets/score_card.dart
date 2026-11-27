// lib/widgets/score_card.dart
import 'package:flutter/material.dart';

/// 背景画像の上でも文字が読めるように置く、半透明の白いカード
class ScoreCard extends StatelessWidget {
  const ScoreCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material にして、上に置いた ListTile・スイッチのタップの効果（インク）が見えるようにする
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.white.withValues(alpha: 0.88),
        elevation: 1,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: child,
        ),
      ),
    );
  }
}

/// 「項目：値」の1行
class LabelValueRow extends StatelessWidget {
  const LabelValueRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: t.bodyMedium?.copyWith(color: Colors.black54)),
          ),
          Expanded(child: Text(value, style: t.bodyMedium)),
        ],
      ),
    );
  }
}

/// 強調したいお知らせ（最高記録の更新・参考記録など）
class NoticeText extends StatelessWidget {
  const NoticeText(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}
