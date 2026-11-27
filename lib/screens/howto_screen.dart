import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/back_to_home.dart';
import '../domain/rank_policy.dart';

class HowToScreen extends StatelessWidget {
  const HowToScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BackToHome(
      child: BackgroundScaffold(
        appBar: homeAppBar(context, '遊び方'),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1) 反応練習とは
            const SectionCard(
              title: '＜反応練習とは＞',
              children: [
                _BulletRow(icon: Icons.bolt, text: '札の認識力・判断力・反応速度を鍛える練習です'),
                _BulletRow(icon: Icons.play_circle, text: '上の句が読まれたら、対応する下の句の札をタップします'),
                _BulletRow(icon: Icons.analytics_outlined, text: '10問で正答率と平均取得時間を計測し、ランクを判定します'),
              ],
            ),
            const SizedBox(height: 12),

            // 2) 空札・見送り・お手つき
            const SectionCard(
              title: '＜空札・見送り・お手つき＞（設定で「空札あり」にしたとき）',
              children: [
                _BulletRow(icon: Icons.help_outline, text: '空札（からふだ）：場にない札が読まれることがあります'),
                _BulletRow(icon: Icons.pan_tool_outlined, text: '見送り：空札だと思ったら、画面下の「見送り」を押します（見送り成功）'),
                _BulletRow(icon: Icons.warning_amber_rounded, text: 'お手つき：空札のときに札を押すと「お手つき」になります'),
                _BulletRow(icon: Icons.timer_off_outlined, text: '空札で何もしないまま時間切れになると「未回答」（不正解）です'),
                _BulletRow(icon: Icons.close_rounded, text: '場にある札で見送りを押すと「見送りミス」、時間切れは「取り逃し」です'),
                _Footnote(
                    text: '※反応練習は、判断の速さを鍛えるためのアプリ独自の簡易ルールです。'
                        '競技かるたの実際のルールでは、空札では何もしない（札に触れない）ことが正しく、'
                        '「見送り」の操作はありません。また、出札と同じ陣の別の札に触れてもお手つきにはなりません。'),
              ],
            ),
            const SizedBox(height: 12),

            // 3) お手つきペナルティ
            const SectionCard(
              title: '＜お手つきペナルティ＞',
              children: [
                _BulletRow(icon: Icons.remove_circle_outline, text: 'ONにすると、お手つき1回につき正答から1問分を差し引きます'),
                _Footnote(text: '※競技かるたで、お手つきをすると相手から札を1枚送られるのに近い扱いです。設定画面で変更できます。'),
              ],
            ),
            const SizedBox(height: 12),

            // 4) ランク判定基準
            SectionCard(
              title: '＜ランク判定基準＞',
              children: [
                // 基準値は lib/domain/rank_policy.dart の1か所にある
                for (final r in RankPolicy.rules)
                  _RankRow(
                    rank: r.rank.name,
                    rule: '正答率 ${r.minAccuracy}% 以上 かつ '
                        '平均取得 ${formatSecondsLimit(r.maxAvgMs)} 秒以内',
                  ),
                const _RankRow(rank: 'D', rule: '上記以外'),
                const _Footnote(
                    text: '※正答率＝（正解＋見送り成功−ペナルティ）÷10問。'
                        '平均取得時間は、正解した札の反応時間（ミリ秒単位）の平均です。'),
              ],
            ),
            const SizedBox(height: 12),

            // 5) 参考記録・ギャラリー
            const SectionCard(
              title: '＜参考記録・ギャラリー＞',
              children: [
                _BulletRow(icon: Icons.emoji_events_outlined, text: '練習を最後まで終えると、結果のランクに応じてギャラリーの画像を1枚獲得できます'),
                _BulletRow(icon: Icons.pause_circle_outline, text: '途中で中断して続けた練習（アプリを閉じた・通知を開いたなども含む）は「参考記録」になります'),
                _BulletRow(icon: Icons.block, text: '参考記録は、最高記録の更新・ギャラリーの獲得の対象外です'),
              ],
            ),
            const SizedBox(height: 12),

            // 6) プレイ中の設定（ミュート・文字表示）
            const SectionCard(
              title: '＜プレイ中の設定＞',
              children: [
                _BulletRow(icon: Icons.volume_up, text: '右上のスピーカー：読み上げ音声のON/OFF'),
                _BulletRow(icon: Icons.subtitles, text: '右上の「文」アイコン：上の句の文字表示のON/OFF'),
                _Footnote(text: '※音声と文字が両方OFFのときは、札が分かるように文字を表示します。'),
              ],
            ),

            const SizedBox(height: 24),

            Center(
              child: ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('ホームに戻る'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 共通カード
class SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SectionCard({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.bodyMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 箇条書き（アイコン付き）
class _BulletRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BulletRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: AutoSizeText(text, style: style, maxLines: 2)),
        ],
      ),
    );
  }
}

/// ランク行（見た目統一）
class _RankRow extends StatelessWidget {
  final String rank;
  final String rule;
  const _RankRow({required this.rank, required this.rule});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Text(rank, style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(width: 10),
          Expanded(child: AutoSizeText(rule, style: style, maxLines: 2)),
        ],
      ),
    );
  }
}

/// フッターメモ
class _Footnote extends StatelessWidget {
  final String text;
  const _Footnote({required this.text});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: style),
    );
  }
}
