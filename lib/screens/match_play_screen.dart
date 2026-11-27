// lib/screens/match_play_screen.dart
//
// 実践練習の暗記・練習画面。暗記と練習を1つの画面で切り替えるので、札の座標・大きさは変わらない。
// 縦向きを基本とし、画面が小さすぎる（横向きのスマートフォン・iPad の画面分割など）ときは練習を止めて縦向きを促す。
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/match_judge.dart';
import '../providers/game_provider.dart';
import '../providers/match_state.dart';
import '../providers/settings_provider.dart';
import '../services/orientation_lock.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/match_field.dart';
import '../widgets/pass_button.dart';

class MatchPlayScreen extends HookConsumerWidget {
  const MatchPlayScreen({super.key});

  /// 中断ダイアログ。表示中はタイマー・音声・進行を止め、札を隠す。[dialogOpen] でダイアログを1つだけにする。
  static Future<void> openPauseDialog(
      BuildContext context, WidgetRef ref, ObjectRef<bool> dialogOpen) async {
    final m = ref.read(matchProvider);
    final newlyPaused = m.requestPause();
    if (!newlyPaused && !m.isPaused) return; // 練習中でない
    if (dialogOpen.value) return;
    dialogOpen.value = true;
    final memorizing = m.pausedDuringMemorize;
    if (m.pausedAfterFinalJudgement) {
      // 最後の読みの判定は確定済み：通常の記録として結果へ（判定前の中断とは区別する）
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dctx) => AlertDialog(
          title: const Text('練習が終わりました'),
          content: const Text('最後の問題まで判定済みです。結果を表示します。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('結果を見る')),
          ],
        ),
      );
      dialogOpen.value = false;
      m.resume(); // 残りの読みがないので、そのまま終了して結果画面へ
      return;
    }
    final quit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('練習を中断しますか？'),
        scrollable: true,
        content: Text(memorizing
            ? '暗記の時間を止めて、札を隠しています。\n'
                '続ける場合は、残りの時間から暗記を再開します（参考記録にはなりません）。'
            : '読み上げと時間計測を停止し、札を隠しています。\n'
                '続ける場合は、別の札から出題します（札の配置は変わりません）。\n'
                '再開後の成績は参考記録となり、最高記録の更新・ギャラリー獲得の対象外になります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('続ける')),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('中断する')),
        ],
      ),
    );
    dialogOpen.value = false;
    if (quit == true || !m.resume()) {
      m.abort();
      if (context.mounted) context.go('/');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(matchProvider);
    final soundOn = ref.watch(soundOnProvider);
    final flowOn = ref.watch(textFlowOnProvider);
    final audioFactory = ref.read(practiceAudioFactoryProvider);
    final audio = useMemoized(audioFactory);
    final dialogOpen = useRef(false);
    final pausedByLayout = useRef(false);

    // 縦向きに固定。表示で暗記を始め、閉じるときに音声を解放する
    useEffect(() {
      OrientationLock.acquirePortrait();
      final match = ref.read(matchProvider);
      match.attachAudio(audio);
      match.setMuted(!ref.read(soundOnProvider));
      WidgetsBinding.instance.addPostFrameCallback((_) => match.begin());
      return () {
        match.detachAudio(audio);
        if (match.phase != MatchPhase.finished && match.phase != MatchPhase.idle) {
          WidgetsBinding.instance.addPostFrameCallback((_) => match.abort());
        }
        audio.dispose();
        OrientationLock.releasePortrait();
      };
    }, [audio]);

    // 全部読み終えたら結果画面へ
    useEffect(() {
      if (m.finished) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => context.mounted ? context.go('/match/result') : null);
      }
      return null;
    }, [m.finished]);

    // inactive・バックグラウンド：その時点で止める。戻ったら中断ダイアログ
    useOnAppLifecycleStateChange((_, state) {
      final match = ref.read(matchProvider);
      switch (state) {
        case AppLifecycleState.inactive:
        case AppLifecycleState.hidden:
        case AppLifecycleState.paused:
          match.requestPause();
        case AppLifecycleState.resumed:
          if (match.isPaused && !pausedByLayout.value && context.mounted) {
            openPauseDialog(context, ref, dialogOpen);
          }
        case AppLifecycleState.detached:
          break;
      }
    });

    useEffect(() {
      if (m.audioUnavailable) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('読み上げ音声を再生できないため、上の句の文字を表示します')));
        });
      }
      return null;
    }, [m.audioUnavailable]);

    // 判定の振動
    useEffect(() {
      final o = m.lastOutcome;
      if (o != null) {
        (o == MatchOutcome.correct || o.isPassSuccess)
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.heavyImpact();
      }
      return null;
    }, [m.lastOutcomeSeq]);
    useEffect(() {
      if (m.sameSideSeq > 0) HapticFeedback.selectionClick();
      return null;
    }, [m.sameSideSeq]);

    final seq = m.questionSeq;
    final memorizing = m.phase == MatchPhase.memorizing ||
        m.phase == MatchPhase.ready ||
        m.pausedDuringMemorize;
    final showText = flowOn || !soundOn || m.audioUnavailable;

    final title = memorizing
        ? '暗記 ${_mmss(m.memorizeRemainingMs)}'
        : '問 ${m.readNo} / ${m.totalReads}';

    return PopScope(
      canPop: false,
      child: BackButtonListener(
        onBackButtonPressed: () async {
          if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
          openPauseDialog(context, ref, dialogOpen);
          return true;
        },
        child: BackgroundScaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leadingWidth: 96,
            // 中断は左上（札・見送りボタンから離す）。押してもダイアログで確認する
            leading: TextButton.icon(
              onPressed: () => openPauseDialog(context, ref, dialogOpen),
              icon: const Icon(Icons.close),
              label: const Text('中断'),
            ),
            title: FittedBox(fit: BoxFit.scaleDown, child: Text(title)),
            actions: [
              if (m.isReference)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Chip(
                    label: Text('参考記録', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
              IconButton(
                tooltip: soundOn ? 'サウンドOFF' : 'サウンドON',
                icon: Icon(soundOn ? Icons.volume_up : Icons.volume_off),
                onPressed: () {
                  ref.read(settingsProvider.notifier).setSoundOn(!soundOn);
                  m.setMuted(soundOn);
                },
              ),
              IconButton(
                tooltip: flowOn ? '文字表示OFF' : '文字表示ON',
                icon: Icon(flowOn ? Icons.subtitles : Icons.subtitles_off),
                onPressed: () => ref.read(settingsProvider.notifier).setTextFlowOn(!flowOn),
              ),
            ],
          ),
          child: LayoutBuilder(builder: (ctx, box) {
            const bottomArea = 68.0; // ボタン 52 ＋ 上下の余白
            final metrics = MatchFieldMetrics.compute(box.biggest, bottomArea: bottomArea);

            if (!metrics.usable) {
              // 画面が小さすぎる：止めて縦向きを促す（戻ったら中断ダイアログで続けるか選ぶ）
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final match = ref.read(matchProvider);
                if (match.requestPause()) pausedByLayout.value = true;
              });
              return const _RotateNotice();
            }
            if (pausedByLayout.value) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!pausedByLayout.value || !context.mounted) return;
                pausedByLayout.value = false;
                if (ref.read(matchProvider).isPaused) openPauseDialog(context, ref, dialogOpen);
              });
            }

            final band = _InfoBand(match: m, showText: showText, memorizing: memorizing);
            final buttonW = metrics.sideWidth.clamp(200.0, 480.0);
            return Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  MatchFieldView(
                    metrics: metrics,
                    match: m,
                    band: band,
                    onTapSlot: m.canAcceptInput ? (i) => m.onSlotTap(i, seq: seq) : null,
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 52,
                    width: buttonW,
                    child: memorizing
                        ? FilledButton.icon(
                            key: const ValueKey('end-memorize'),
                            onPressed: m.phase == MatchPhase.memorizing ? m.endMemorize : null,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('暗記終了', style: TextStyle(fontSize: 18)),
                          )
                        : PassButton(enabled: m.canAcceptInput, onPressed: () => m.onPass(seq: seq)),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

String _mmss(int ms) {
  final s = (ms + 999) ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// 中央の情報欄：左に「上の句・カウントダウン・判定」のどれか1つ、右に秒数（重ならない）
class _InfoBand extends StatelessWidget {
  const _InfoBand({required this.match, required this.showText, required this.memorizing});
  final MatchState match;
  final bool showText;
  final bool memorizing;

  static (Color, String)? verdictOf(MatchOutcome o, int? ms) => switch (o) {
        MatchOutcome.correct =>
          (const Color(0xFF2E7D32), '正解  ${((ms ?? 0) / 1000).toStringAsFixed(2)}秒'),
        MatchOutcome.oppositeSide => (const Color(0xFFEF6C00), 'お手つき（反対の陣）・取り逃し'),
        MatchOutcome.timeUp => (const Color(0xFFC62828), '取り逃し（時間切れ）'),
        MatchOutcome.passOnField => (const Color(0xFFC62828), '取り逃し（場にある札）'),
        MatchOutcome.karafudaTouched => (const Color(0xFFEF6C00), 'お手つき（空札）'),
        MatchOutcome.passOk => (const Color(0xFF1F6FB2), '見送り成功（空札）'),
        MatchOutcome.waitOk => (const Color(0xFF1F6FB2), '見送り成功（空札）'),
        MatchOutcome.sameSide => null,
      };

  @override
  Widget build(BuildContext context) {
    final m = match;
    Widget main;
    Color? bg;
    if (memorizing) {
      main = const Text('札の位置を覚えてください（上：敵陣／下：自陣）', key: ValueKey('band-memorize'));
    } else if (m.phase == MatchPhase.feedback && m.lastOutcome != null) {
      final v = verdictOf(m.lastOutcome!, m.lastElapsedMs)!;
      bg = v.$1;
      main = Text(v.$2,
          key: const ValueKey('band-verdict'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
    } else if (m.showSameSide) {
      bg = const Color(0xFFEF6C00);
      main = const Text('同陣ミス（減点なし・そのまま取れます）',
          key: ValueKey('band-same-side'),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
    } else if (m.phase == MatchPhase.countdown) {
      main = Text('${m.countdown}',
          key: const ValueKey('band-countdown'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold));
    } else if (m.phase == MatchPhase.accepting && showText && m.current != null) {
      main = Text(m.current!.card.upper, key: const ValueKey('band-upper'));
    } else {
      main = const SizedBox.shrink();
    }
    final sec = memorizing ? null : m.elapsedSec;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: bg ?? Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                child: main is Text
                    ? AutoSizeText(main.data!,
                        key: main.key,
                        maxLines: 1,
                        minFontSize: 9,
                        style: main.style ?? const TextStyle(fontSize: 16))
                    : main,
              ),
            ),
          ),
          if (!memorizing)
            SizedBox(
              width: 44,
              child: Text(sec == null ? '—' : '$sec秒',
                  key: const ValueKey('band-sec'),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class _RotateNotice extends StatelessWidget {
  const _RotateNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          key: const ValueKey('rotate-notice'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.screen_rotation, size: 36),
              SizedBox(height: 8),
              Text('画面を縦向きにしてください', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('札が小さくなりすぎるため、練習を一時停止しています。', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
