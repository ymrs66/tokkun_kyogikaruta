// lib/screens/play_screen.dart
import 'dart:math' show min, pi;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/verdict.dart';
import '../models/card_data.dart';
import '../providers/game_provider.dart';
import '../providers/game_state.dart';
import '../providers/settings_provider.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/pass_button.dart';
import '../widgets/verdict_banner.dart';

/// 札の縦横比（画像 160×213）
const double _cardAspect = 160 / 213;

class PlayScreen extends HookConsumerWidget {
  const PlayScreen({super.key});

  /// 中断ダイアログ（「✕ 中断」・戻る・inactive／バックグラウンドからの復帰）。
  /// 表示中はタイマー・音声・進行を止める。[dialogOpen] でダイアログを1つだけにする。
  static Future<void> openPauseDialog(
      BuildContext context, WidgetRef ref, ObjectRef<bool> dialogOpen) async {
    final g = ref.read(gameProvider);
    final newlyPaused = g.requestPause();
    if (!newlyPaused && !g.isPaused) return; // 練習中でない（終了後・開始前など）
    if (dialogOpen.value) return; // すでに表示中
    dialogOpen.value = true;
    final canResume = g.canResume;
    final quit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('練習を中断しますか？'),
        // 小型端末・横画面でもボタンが隠れないようにスクロール可能にする
        scrollable: true,
        content: Text(canResume
            // 判定前に止めた場合は別の札で出し直し、判定済みなら次の問題（どちらも別の札）
            ? '読み上げと時間計測を停止しています。\n'
                '続ける場合は、別の札から出題します。\n'
                '再開後の成績は参考記録となり、最高記録の更新・ギャラリー獲得の対象外になります。'
            : '読み上げと時間計測を停止しています。\n'
                '残りの問題に使える札がないため、続けることはできません。'),
        actions: [
          if (canResume)
            TextButton(
                onPressed: () => Navigator.pop(dctx, false), child: const Text('続ける')),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true), child: const Text('中断する')),
        ],
      ),
    );
    dialogOpen.value = false;
    // 「戻る」でダイアログを閉じた（null）ときは「続ける」と同じ
    if (quit == true || !g.resume()) {
      g.abort();
      if (context.mounted) context.go('/');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider);
    final soundOn = ref.watch(soundOnProvider);
    final flowOn = ref.watch(textFlowOnProvider);
    final audioFactory = ref.read(practiceAudioFactoryProvider);
    final audio = useMemoized(audioFactory);

    // 練習画面の表示で1問目を始め、閉じるときに音声を解放する
    useEffect(() {
      final game = ref.read(gameProvider);
      game.attachAudio(audio);
      game.setMuted(!ref.read(soundOnProvider));
      // build 中に状態を変えないよう、最初のフレームの後に始める
      WidgetsBinding.instance.addPostFrameCallback((_) => game.begin());
      return () {
        game.detachAudio(audio);
        if (game.phase != PlayPhase.finished && game.phase != PlayPhase.idle) {
          // 画面の破棄中に通知しないよう、次のフレームで止める
          WidgetsBinding.instance.addPostFrameCallback((_) => game.abort());
        }
        audio.dispose();
      };
    }, [audio]);

    // 10問終了で結果画面へ
    useEffect(() {
      if (g.finished) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => context.mounted ? context.go('/result') : null,
        );
      }
      return null;
    }, [g.finished]);

    final dialogOpen = useRef(false);

    // inactive（iOS のコントロールセンター・通知、Android の通知の引き出しなど）・バックグラウンド化：
    // その時点で止める（何度来ても1回だけ）。画面に戻ったら中断ダイアログを出す。
    useOnAppLifecycleStateChange((_, state) {
      final game = ref.read(gameProvider);
      switch (state) {
        case AppLifecycleState.inactive:
        case AppLifecycleState.hidden:
        case AppLifecycleState.paused:
          game.requestPause();
        case AppLifecycleState.resumed:
          if (game.isPaused && context.mounted) openPauseDialog(context, ref, dialogOpen);
        case AppLifecycleState.detached:
          break;
      }
    });

    // 音声を再生できなかったときは知らせる（文字は自動で表示する）
    useEffect(() {
      if (g.audioUnavailable) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('読み上げ音声を再生できないため、上の句の文字を表示します')));
        });
      }
      return null;
    }, [g.audioUnavailable]);

    // 判定の振動（判定ごとに1回）
    useEffect(() {
      final v = g.lastVerdict;
      if (v != null) {
        v.isSuccess ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
      }
      return null;
    }, [g.lastVerdictSeq]);

    // 上の句の文字スクロール（受付開始で流す）
    final animCtrl = useAnimationController(duration: const Duration(seconds: 8));
    useEffect(() {
      if (g.phase == PlayPhase.accepting) {
        animCtrl.forward(from: 0);
      } else if (g.phase == PlayPhase.countdown || g.phase == PlayPhase.ready) {
        animCtrl.reset();
      } else if (g.phase == PlayPhase.paused) {
        animCtrl.stop();
      }
      return null;
    }, [g.phase, g.questionSeq]);
    final slideAnim = useMemoized(
        () => Tween(begin: const Offset(1, 0), end: const Offset(-1, 0))
            .animate(CurvedAnimation(parent: animCtrl, curve: Curves.linear)),
        [animCtrl]);

    final seq = g.questionSeq;
    final showPass = g.config.karafudaEnabled;

    Widget card(CardData c, {required bool enemy, required double w}) {
      final highlight = g.phase == PlayPhase.feedback && g.highlightCardId == c.id;
      return GestureDetector(
        onTap: () => g.onCardTap(c.id, seq: seq),
        child: SizedBox(
          width: w,
          height: w / _cardAspect,
          child: DecoratedBox(
            // 強調は枠を重ねるだけ（札の大きさ・位置は変えない）
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: highlight ? Border.all(color: const Color(0xFFC62828), width: 4) : null,
            ),
            child: Transform.rotate(
              angle: enemy ? pi : 0,
              child: Image.asset(c.imagePath, fit: BoxFit.contain),
            ),
          ),
        ),
      );
    }

    Widget cardRow(List<CardData> cards, {required bool enemy, required double w}) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final c in cards)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: card(c, enemy: enemy, w: w),
              ),
          ],
        );

    // 音声と文字が両方 OFF・音声を再生できないときは、問題が分かるよう文字を表示する
    final info = _InfoArea(
      game: g,
      flowOn: flowOn || !soundOn || g.audioUnavailable,
      slide: slideAnim,
    );

    void pass() => g.onPass(seq: seq);

    return PopScope(
      canPop: false,
      child: BackButtonListener(
        onBackButtonPressed: () async {
          // ダイアログ表示中は、通常どおりダイアログを閉じる
          if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
          openPauseDialog(context, ref, dialogOpen);
          return true;
        },
        child: BackgroundScaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leadingWidth: 96,
            leading: TextButton.icon(
              onPressed: () => openPauseDialog(context, ref, dialogOpen),
              icon: const Icon(Icons.close),
              label: const Text('中断'),
            ),
            title: const Text('札合わせ'),
            actions: [
              IconButton(
                tooltip: soundOn ? 'サウンドOFF' : 'サウンドON',
                icon: Icon(soundOn ? Icons.volume_up : Icons.volume_off),
                onPressed: () {
                  ref.read(settingsProvider.notifier).setSoundOn(!soundOn);
                  g.setMuted(soundOn); // 再生は止めず、音量だけ切り替える
                },
              ),
              IconButton(
                tooltip: flowOn ? '文字スクロールOFF' : '文字スクロールON',
                icon: Icon(flowOn ? Icons.subtitles : Icons.subtitles_off),
                onPressed: () =>
                    ref.read(settingsProvider.notifier).setTextFlowOn(!flowOn),
              ),
            ],
          ),
          child: LayoutBuilder(builder: (ctx, box) {
            final landscape = box.maxWidth > box.maxHeight;
            const pad = 8.0;
            const rowGap = 12.0;
            const cardGap = 8.0;

            if (landscape) {
              // 横画面：左に札（2段）、右に情報と縦長の見送りボタン
              final sideW = min(260.0, box.maxWidth * 0.34);
              final cardsW = box.maxWidth - sideW - pad * 3;
              final byH = (box.maxHeight - pad * 2 - rowGap) / 2 * _cardAspect;
              final byW = (cardsW - cardGap * 3) / 3;
              final w = min(min(byH, byW), 200.0);
              return Padding(
                padding: const EdgeInsets.all(pad),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          cardRow(g.enemyCards, enemy: true, w: w),
                          const SizedBox(height: rowGap),
                          cardRow(g.selfCards, enemy: false, w: w),
                        ],
                      ),
                    ),
                    const SizedBox(width: pad),
                    SizedBox(
                      width: sideW,
                      child: Column(
                        children: [
                          SizedBox(height: 120, child: info),
                          const SizedBox(height: 12),
                          if (showPass)
                            Expanded(
                              child: SizedBox(
                                width: double.infinity,
                                child: PassButton(
                                    enabled: g.canAcceptInput, onPressed: pass, vertical: true),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // 縦画面：敵陣・自陣・情報欄・（空札ありなら）下に見送りボタン。スクロールしない
            const infoH = 120.0;
            const passH = 56.0;
            const passGap = 16.0;
            const bottomPad = 16.0;
            final reserved = pad * 2 + rowGap + infoH + bottomPad + (showPass ? passH + passGap : 0);
            final byH = (box.maxHeight - reserved) / 2 * _cardAspect;
            final byW = (min(box.maxWidth, 640.0) - pad * 2 - cardGap * 3) / 3;
            final w = min(min(byH, byW), 200.0).clamp(40.0, 200.0);
            return Padding(
              padding: const EdgeInsets.fromLTRB(pad, pad, pad, bottomPad),
              child: Column(
                children: [
                  cardRow(g.enemyCards, enemy: true, w: w),
                  const SizedBox(height: rowGap),
                  cardRow(g.selfCards, enemy: false, w: w),
                  SizedBox(height: infoH, child: info),
                  const Spacer(),
                  if (showPass)
                    SizedBox(
                      height: passH,
                      width: min(box.maxWidth - pad * 2, 480),
                      child: PassButton(enabled: g.canAcceptInput, onPressed: pass),
                    ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// 問番号・上の句（またはカウントダウン）・経過秒数。判定の表示はここに重ねる。
class _InfoArea extends StatelessWidget {
  const _InfoArea({required this.game, required this.flowOn, required this.slide});

  final GameState game;
  final bool flowOn;
  final Animation<Offset> slide;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final counting = g.phase == PlayPhase.countdown || g.phase == PlayPhase.ready;
    final qNo = min(g.round + (g.phase == PlayPhase.feedback ? 0 : 1), g.totalQuestions);
    final sec = g.elapsedSec;
    final upper = (g.currentKind == null) ? '' : g.current.upper;

    final ticker = SizedBox(
      height: 56,
      child: counting
          ? Center(
              child: Text('${g.countdown}',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            )
          : (flowOn && g.phase != PlayPhase.paused
              ? ClipRect(
                  child: SlideTransition(
                    position: slide,
                    child: Center(
                      child: AutoSizeText(upper,
                          maxLines: 1,
                          minFontSize: 12,
                          overflow: TextOverflow.fade,
                          style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                )
              : const SizedBox.shrink()),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('問 $qNo / ${g.totalQuestions}',
                style: Theme.of(context).textTheme.titleMedium),
            ticker,
            Text('読みはじめから ${sec ?? '—'} 秒',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        if (g.phase == PlayPhase.feedback && g.lastVerdict != null)
          VerdictBanner(verdict: g.lastVerdict!, elapsedMs: g.lastElapsedMs),
      ],
    );
  }
}
