// lib/screens/play_screen.dart
import 'dart:ui';                 // ← ぼかし用（BackdropFilter）
import 'package:flutter/services.dart';
import 'dart:math' show pi;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/card_data.dart';
import '../providers/game_provider.dart';
import '../providers/game_state.dart';
import '../widgets/background_scaffold.dart';
import '../services/audio_service.dart';
import '../providers/settings_provider.dart';

class PlayScreen extends HookConsumerWidget {
  const PlayScreen({super.key});

  /* ---------- ヘルパ ---------- */
  void _handleTap(BuildContext ctx, GameState g, CardData c, KarutaAudio audio) {
    audio.stop();                 // 次の問題へ行くので停止
    final ok = g.tap(c);
    _flashCenter(ctx, ok: ok);      // ★ SnackBar の代わりに中央フラッシュ
  }

  void _flashCenter(BuildContext context, {required bool ok}) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    final Color color = ok ? Colors.green : Colors.red;
    final String label = ok ? '正解！' : '残念';
    // ハプティックは任意
    ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer( // ★背面のタップをブロックしない
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  scale: 1.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 20)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(ok ? Icons.check_circle : Icons.close_rounded,
                            color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    // 650ms後に自動で消す
    Future.delayed(const Duration(milliseconds: 650)).then((_) {
      // removeは1回だけ
      try { entry.remove(); } catch (_) {}
    });
  }

  Future<void> _confirmBack(BuildContext ctx, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        content: const Text('タイトルへ戻りますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),  child: const Text('OK')),
        ],
      ),
    );
    if (ok ?? false) {
      ref.read(gameProvider).resetGame();
      if (ctx.mounted) ctx.go('/');
    }
  }

  Widget _ticker(bool counting, int counter, Animation<Offset> slide, String text, {required bool flowOn}) {
    return SizedBox(
      height: 64,                        // 高さ固定でレイアウトを揺らさない
      child: counting
          ? Center(
        child: AutoSizeText(
          '$counter',
          maxLines: 1,
          minFontSize: 20,
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
        ),
      )
          : (flowOn
          // ON: スライド表示
          ? SlideTransition(
          position: slide,
          child: AutoSizeText(
              text,
              maxLines: 2,
              minFontSize: 12,
              overflow: TextOverflow.fade,
              style: const TextStyle(fontSize: 20),
          ),
      )
    // OFF: 文字そのものを非表示に（高さは SizedBox で確保）
          : const SizedBox.shrink()),
    );
  }

  /* ------------------------------ build ------------------------------ */
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g        = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider);
    final soundOn  = ref.watch(soundOnProvider);
    final flowOn   = ref.watch(textFlowOnProvider);
    final audio    = useMemoized(() => KarutaAudio(), []);
    useEffect(() { return () { audio.dispose(); }; }, [audio]); // 破棄

    /* ゲーム終了時に結果画面へ */
    useEffect(() {
      if (g.finished) {
        WidgetsBinding.instance.addPostFrameCallback(
              (_) => context.mounted ? context.go('/result') : null,
        );
      }
      return null;
    }, [g.finished]);

    /* カウントダウン用 hooks */
    final isCounting = useState(true);
    final counter    = useState(3);
    final animCtrl   = useAnimationController(duration: const Duration(seconds: 8));
    final slideAnim  = Tween(begin: const Offset(1, 0), end: const Offset(-1, 0))
        .animate(CurvedAnimation(parent: animCtrl, curve: Curves.linear));

    /* 3→2→1 → 詠み上げ開始（音声はプリロードしておき、0の瞬間に resume） */
    useEffect(() {
      if (isCounting.value) {
        var cancelled = false;
        Future.doWhile(() async {
          await Future.delayed(const Duration(seconds: 1));
          if (cancelled) return false;
          counter.value -= 1;
          if (counter.value == 0) {
            isCounting.value = false;
            // 同期性を上げるため同フレームで実行
            animCtrl.forward();
            // 準備済みをそのまま再生（ミュートなら音量0で進行）
            audio.playPrepared(muted: !soundOn);
            // ★ ここで 10 秒計測を開始（3,2,1 の後にスタート）
            ref.read(gameProvider).startMeasurement();
            return false;
          }
          return true;
        });
        return () { cancelled = true; };
      }
      return null;
    }, [isCounting.value, g.current.id]); // soundOnは入れない（ズレ回避）

    /* 新しい札になったらリセット */
    useEffect(() {
      // 新しい札の音源を先にロード→巻き戻して一時停止
      audio.prepareUpper(g.current.id);
      isCounting.value = false;
      Future.microtask(() => isCounting.value = true);
      counter.value = 3;
      animCtrl.reset();
      return null;
    }, [g.current.id]);

    /* --------- レイアウト --------- */
    final w = MediaQuery.of(context).size.width;
    const horizontalPadding = 8.0;       // SingleChildScrollView の左右 padding と合わせる
    const spacing = 8.0;                  // Wrap の spacing
    const cols = 3;

    // 画面幅から 3 列のカード幅を逆算（最小90 / 最大240に丸める）
    final contentW = w - horizontalPadding * 2;
    final rawCardW = (contentW - spacing * (cols - 1)) / cols;
    final cardW = rawCardW.clamp(90.0, 240.0);

    // 行間は固定でOK
    const gapH = 16.0;


    Widget cardWidget(CardData c, {bool flip = false}) => GestureDetector(
        onTap: () {
    // カウントダウン中はタップ無効（視覚的フィードバックだけ出したければここで軽いバイブ等）
              if (isCounting.value) return;
              _handleTap(context, notifier, c, audio);
            },
      child: Transform.rotate(
        angle: flip ? pi : 0,
        child: Image.asset(c.imagePath, width: cardW),
      ),
    );
    // Android の「戻る」（target 36 では予測型「戻る」）で練習中にアプリが閉じないよう、
    // 「スタートに戻る」ボタンと同じ確認ダイアログを出す。
    // - PopScope(canPop: false)：「戻る」を Flutter 側で処理することを Android に伝える
    // - BackButtonListener：go_router 13.x はルートが1つだけのとき PopScope の
    //   コールバックを呼ばないため、Router より先に「戻る」を受け取って処理する
    return PopScope(
      canPop: false,
      child: BackButtonListener(
        onBackButtonPressed: () async {
          // ダイアログ表示中は、通常どおりダイアログを閉じる
          if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
          _confirmBack(context, ref);
          return true;
        },
        child: BackgroundScaffold(
        appBar: AppBar(
            title: const Text('百人一首 - 札合わせ'),
            actions: [
              IconButton(
                tooltip: soundOn ? 'サウンドOFF' : 'サウンドON',
                icon: Icon(soundOn ? Icons.volume_up : Icons.volume_off),
                onPressed: () {
                  ref.read(soundOnProvider.notifier).state = !soundOn;
                  // 再生は止めない。音量だけ切り替える
                  audio.setMuted(soundOn); // soundOnは旧値なので「今からミュートするか」を表す
                },
              ),
              IconButton(
                  tooltip: flowOn ? '文字スクロールOFF' : '文字スクロールON',
                  icon: Icon(flowOn ? Icons.subtitles : Icons.subtitles_off),
                  onPressed: () {
                    ref.read(textFlowOnProvider.notifier).state = !flowOn;
                    // アニメは裏で走らせておくので特に制御不要（ONに戻したら途中から見える）
                    },
              ),
            ],
          ),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          return SingleChildScrollView(
            // 画面が小さい端末でも必ずスクロール可能に
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              // ビューポート高に満たないときは最小高さで下まで広げる
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                // SafeArea は BackgroundScaffold 側で入っているので固定パディングでOK
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 敵陣
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: spacing,
                        runSpacing: spacing,
                        children: g.enemyCards
                            .map((c) => GestureDetector(
                          onTap: () {
                            if (isCounting.value) return;
                            _handleTap(context, notifier, c, audio);
                          },
                          child: Transform.rotate(
                            angle: pi,
                            child: Image.asset(c.imagePath, width: cardW.toDouble()),
                          ),
                        ))
                            .toList(),
                      ),
                    ),

                    SizedBox(height: gapH),

                    // 自陣
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: spacing,
                        runSpacing: spacing,
                        children: g.selfCards
                            .map((c) => GestureDetector(
                          onTap: () {
                            if (isCounting.value) return;
                            _handleTap(context, notifier, c, audio);
                          },
                          child: Image.asset(c.imagePath, width: cardW.toDouble()),
                        ))
                            .toList(),
                      ),
                    ),

                    const SizedBox(height: 16),

                    AutoSizeText(
                      '問 ${g.round + 1} / ${GameState.maxRound}',
                      maxLines: 1,
                      minFontSize: 14,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    _ticker(
                      isCounting.value,
                      counter.value,
                      slideAnim,
                      g.current.upper,
                      flowOn: flowOn,
                    ),
                    AutoSizeText(
                      '読みはじめから ${g.elapsedSec} 秒',
                      maxLines: 1,
                      minFontSize: 12,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),

                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: () => _confirmBack(context, ref),
                      child: const Text('スタートに戻る'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
        ),
      ),
    );
  }
}
