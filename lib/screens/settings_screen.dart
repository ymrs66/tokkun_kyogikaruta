// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/question_plan.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../services/gallery_service.dart';
import '../widgets/back_to_home.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/score_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _percentLabels = {20: '少なめ', 30: 'ふつう', 50: '多め'};

  Future<bool> _confirm(BuildContext context,
      {required String title, required String message, required String ok}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: Text(ok)),
        ],
      ),
    );
    return r ?? false;
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final t = Theme.of(context).textTheme;
    final karaCount = karafudaCountFor(percent: s.karafudaPercent, total: 10);

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ScoreCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall?.copyWith(color: Colors.black54)),
                ...children,
              ],
            ),
          ),
        );

    Widget desc(String text, {bool enabled = true}) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(text,
              style: t.bodySmall?.copyWith(color: enabled ? Colors.black87 : Colors.black38)),
        );

    final bothOff = !s.soundOn && !s.textFlowOn;

    return BackToHome(
      child: BackgroundScaffold(
        appBar: homeAppBar(context, '設定'),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                section('反応練習', [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('空札あり'),
                    value: s.karafudaEnabled,
                    onChanged: n.setKarafudaEnabled,
                  ),
                  desc('場にない札（空札）も読まれます。空札だと思ったら「見送り」を押してください。'
                      '空札で札を取ると「お手つき」になります。'),
                  const SizedBox(height: 8),
                  Text('空札の割合',
                      style: t.bodyLarge?.copyWith(
                          color: s.karafudaEnabled ? null : Colors.black38)),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    segments: [
                      for (final p in karafudaPercentOptions.where((p) => p > 0))
                        ButtonSegment(value: p, label: Text('${_percentLabels[p]}（$p%）')),
                    ],
                    selected: {s.karafudaPercent},
                    showSelectedIcon: false,
                    onSelectionChanged:
                        s.karafudaEnabled ? (v) => n.setKarafudaPercent(v.first) : null,
                  ),
                  const SizedBox(height: 4),
                  desc('10問中 $karaCount問が空札になります。', enabled: s.karafudaEnabled),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('お手つきペナルティ',
                        style: TextStyle(color: s.karafudaEnabled ? null : Colors.black38)),
                    value: s.otetsukiPenalty,
                    onChanged: s.karafudaEnabled ? n.setOtetsukiPenalty : null,
                  ),
                  desc('ONにすると、お手つき1回につき正答から1問分を差し引きます（競技かるたで札を1枚送られるのに近い扱い）。'
                      '空札ありのときだけ有効です。',
                      enabled: s.karafudaEnabled),
                ]),
                section('表示・音', [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('読み上げ音声'),
                    value: s.soundOn,
                    onChanged: n.setSoundOn,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('上の句の文字表示'),
                    value: s.textFlowOn,
                    onChanged: n.setTextFlowOn,
                  ),
                  desc('練習中も画面右上のアイコンで切り替えられます。'),
                  if (bothOff)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '音声と文字表示が両方OFFだと、読まれた札が分かりません。'
                        'この場合、練習中は上の句の文字を表示します。',
                        style: t.bodySmall,
                      ),
                    ),
                ]),
                section('データ', [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restart_alt),
                    title: const Text('成績をリセット'),
                    subtitle: const Text('反応練習・実践練習の最高記録と前回の結果を消します。ギャラリーと設定は残ります。'),
                    onTap: () async {
                      if (!await _confirm(context,
                          title: '成績をリセットしますか？',
                          message: '反応練習・実践練習の最高記録と前回の結果を消します。もとに戻せません。',
                          ok: 'リセット')) {
                        return;
                      }
                      final ok = await ref.read(scoreRepositoryProvider).resetScores();
                      if (context.mounted) {
                        _toast(context, ok ? '成績をリセットしました' : 'リセットできませんでした');
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.photo_library_outlined, color: Color(0xFFC62828)),
                    title: const Text('ギャラリーをリセット',
                        style: TextStyle(color: Color(0xFFC62828))),
                    subtitle: const Text('獲得した画像をすべて消します。成績と設定は残ります。'),
                    onTap: () async {
                      if (!await _confirm(context,
                          title: 'ギャラリーをリセットしますか？',
                          message: '獲得した画像がすべて未獲得に戻ります。',
                          ok: '次へ')) {
                        return;
                      }
                      if (!context.mounted) return;
                      if (!await _confirm(context,
                          title: '本当に消しますか？',
                          message: '獲得した画像はもとに戻せません。',
                          ok: '消す')) {
                        return;
                      }
                      final ok = await GalleryService.reset();
                      if (context.mounted) {
                        _toast(context, ok ? 'ギャラリーをリセットしました' : 'リセットできませんでした');
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.settings_backup_restore),
                    title: const Text('設定を初期値に戻す'),
                    subtitle: const Text('この画面の設定だけを戻します。成績とギャラリーは残ります。'),
                    onTap: () async {
                      if (!await _confirm(context,
                          title: '設定を初期値に戻しますか？',
                          message: '空札なし・ペナルティなし・音声あり・文字表示あり、実践練習は暗記1分・空札30%に戻ります。',
                          ok: '戻す')) {
                        return;
                      }
                      await n.resetToDefaults();
                      if (context.mounted) _toast(context, '設定を初期値に戻しました');
                    },
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
