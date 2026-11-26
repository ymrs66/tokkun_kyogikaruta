import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/background_scaffold.dart';

class HowToScreen extends StatelessWidget {
  const HowToScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return BackgroundScaffold(
      appBar: AppBar(title: const Text('遊び方')),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),

          // 1) 操作方法
          SectionCard(
            title: '＜操作方法＞',
            children: [
              _BulletRow(icon: Icons.play_circle, text: '上の句が流れたら対応する下の句札をタップ'),
              _BulletRow(icon: Icons.analytics_outlined, text: '10問連続で正解率と平均取得秒数を計測'),
            ],
          ),

          const SizedBox(height: 12),

          // 2) プレイ中の設定（ミュート・文字表示）
          SectionCard(
            title: '＜プレイ中の設定＞',
            children: const [
              _BulletRow(icon: Icons.volume_up, text: 'ミュート切替：右上のスピーカーで効果音のON/OFF'),
              _BulletRow(icon: Icons.subtitles, text: '文字表示切替：右上の「文」アイコンで句の表示ON/OFF'),
              _Footnote(text: '※プレイ中いつでも変更できます。'),
            ],
          ),

          const SizedBox(height: 12),

          // 3) ランク判定基準
          SectionCard(
            title: '＜ランク判定基準＞',
            children: [
              _RankRow(rank: 'S', rule: '正解率 100% 以上 かつ 平均取得 1 秒以内'),
              _RankRow(rank: 'A', rule: '正解率 95% 以上 かつ 平均取得 1.5 秒以内'),
              _RankRow(rank: 'B', rule: '正解率 90% 以上 かつ 平均取得 2 秒以内'),
              _RankRow(rank: 'C', rule: '正解率 80% 以上 かつ 平均取得 3 秒以内'),
              _RankRow(rank: 'D', rule: '上記以外'),
            ],
          ),

          const SizedBox(height: 24),

          Center(
            child: ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('スタートに戻る'),
            ),
          ),
        ],
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
              color: Theme.of(context).colorScheme.surfaceVariant,
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
