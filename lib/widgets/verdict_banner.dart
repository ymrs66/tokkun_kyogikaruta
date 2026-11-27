// lib/widgets/verdict_banner.dart
import 'package:flutter/material.dart';

import '../domain/verdict.dart';

/// 判定の表示（650ms）。札の上ではなく、札の下の情報欄に重ねて表示する
/// （札を隠さない・レイアウトの高さを変えない）。入力は通さない。
class VerdictBanner extends StatelessWidget {
  const VerdictBanner({super.key, required this.verdict, this.elapsedMs});

  final Verdict verdict;

  /// 正解・見送り成功のときの反応時間
  final int? elapsedMs;

  static (Color, IconData, String, String?) styleOf(Verdict v) => switch (v) {
        Verdict.correct => (const Color(0xFF2E7D32), Icons.check_circle, '正解！', null),
        Verdict.passOk => (const Color(0xFF1F6FB2), Icons.pan_tool_outlined, '見送り成功', '空札でした'),
        Verdict.wrong => (const Color(0xFFC62828), Icons.close_rounded, '残念', '赤枠が読まれた札'),
        Verdict.wrongPass => (const Color(0xFFC62828), Icons.close_rounded, '場にある札でした', '赤枠が読まれた札'),
        Verdict.missed => (const Color(0xFFC62828), Icons.timer_off_outlined, '時間切れ', '赤枠が読まれた札'),
        Verdict.fault => (const Color(0xFFEF6C00), Icons.warning_amber_rounded, 'お手つき！', '空札でした'),
        Verdict.noAnswer => (const Color(0xFFC62828), Icons.timer_off_outlined, '未回答', '空札でした（見送りを押す）'),
      };

  @override
  Widget build(BuildContext context) {
    final (color, icon, label, sub) = styleOf(verdict);
    final time = elapsedMs == null ? null : '${(elapsedMs! / 1000).toStringAsFixed(2)} 秒';
    final detail = [?time, ?sub].join('　');
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.93),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  if (detail.isNotEmpty)
                    Text(detail, style: const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
