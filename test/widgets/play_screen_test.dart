import 'dart:math';

// test/widgets/play_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tokkun_kyogikaruta/models/game_config.dart';
import 'package:tokkun_kyogikaruta/providers/game_provider.dart';
import 'package:tokkun_kyogikaruta/providers/game_state.dart';
import 'package:tokkun_kyogikaruta/providers/settings_provider.dart';
import 'package:tokkun_kyogikaruta/screens/play_screen.dart';
import 'package:tokkun_kyogikaruta/widgets/pass_button.dart';

import 'package:tokkun_kyogikaruta/services/audio_service.dart';

import '../providers/game_state_test.dart' show FakeAudio, BrokenAudio;

Future<GameState> pumpPlay(WidgetTester tester,
    {required Size size,
    GameConfig cfg = const GameConfig(),
    Map<String, Object> prefs = const {},
    PracticeAudio Function()? audio}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(Map.of(prefs));
  final sp = await SharedPreferences.getInstance();
  final game = GameState()..startGame(cfg);
  addTearDown(game.abort); // テストが途中で失敗してもタイマーを残さない
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const PlayScreen()),
    GoRoute(path: '/result', builder: (_, __) => const Scaffold()),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(sp),
      practiceAudioFactoryProvider.overrideWithValue(audio ?? FakeAudio.new),
      gameProvider.overrideWith((ref) => game),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  return game;
}

Future<void> finish(WidgetTester tester, GameState g) async {
  g.abort();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  const sizes = {
    '小型スマホ縦 360×640': Size(360, 640),
    '標準スマホ縦 393×852': Size(393, 852),
    'スマホ横 852×393': Size(852, 393),
    'タブレット縦 800×1280': Size(800, 1280),
  };

  testWidgets('空札なしなら見送りボタンはない', (tester) async {
    final g = await pumpPlay(tester, size: const Size(393, 852));
    expect(find.byType(PassButton), findsNothing);
    expect(find.text('中断'), findsOneWidget);
    await finish(tester, g);
  });

  for (final e in sizes.entries) {
    testWidgets('空札あり・${e.key}：はみ出さず、札6枚と見送りが画面内に収まる', (tester) async {
      final g = await pumpPlay(tester,
          size: e.value, cfg: const GameConfig(karafudaPercent: 30));
      expect(tester.takeException(), isNull);
      final screen = Offset.zero & e.value;
      // 札の画像は assets/images/001.png〜100.png
      final cardImage = RegExp(r'^assets/images/\d{3}\.png$');
      final cards = find.byWidgetPredicate(
          (w) => w is Image && (w.image is AssetImage) &&
              cardImage.hasMatch((w.image as AssetImage).assetName));
      expect(cards, findsNWidgets(6));
      for (final el in cards.evaluate()) {
        final r = tester.getRect(find.byWidget(el.widget));
        expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight - const Offset(1, 1)),
            isTrue, reason: '札が画面外: $r');
      }
      final pass = tester.getRect(find.byType(PassButton));
      expect(screen.contains(pass.bottomRight - const Offset(1, 1)), isTrue,
          reason: '見送りが画面外: $pass');
      expect(pass.height, greaterThanOrEqualTo(48));
      // 札と見送りが重ならない
      for (final el in cards.evaluate()) {
        final r = tester.getRect(find.byWidget(el.widget));
        expect(r.overlaps(pass), isFalse);
      }
      await finish(tester, g);
    });
  }

  testWidgets('見送りはカウントダウン中は押せず、受付中に押せる', (tester) async {
    final g = await pumpPlay(tester,
        size: const Size(393, 852), cfg: const GameConfig(karafudaPercent: 50));
    PassButton btn() => tester.widget<PassButton>(find.byType(PassButton));
    expect(btn().enabled, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(g.phase, PlayPhase.accepting);
    expect(btn().enabled, isTrue);
    await tester.tap(find.byType(PassButton));
    await tester.pump();
    expect(g.stats.judgedCount, 1);
    await finish(tester, g);
  });

  testWidgets('中断：ダイアログは1つだけ、表示中は時間が進まない、続けると別の札', (tester) async {
    final g = await pumpPlay(tester, size: const Size(393, 852));
    await tester.pump(const Duration(seconds: 3)); // 受付中
    final before = g.current.id;
    await tester.tap(find.text('中断'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    // 戻る操作を続けても2つ目は出ない（1回目の戻るでダイアログが閉じて「続ける」になる）
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsNothing);
    expect(g.phase, PlayPhase.countdown);
    expect(g.current.id, isNot(before));
    expect(g.isReference, isTrue);
    // もう一度中断 → 中断する
    await tester.tap(find.text('中断'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(g.stats.judgedCount, 0); // ダイアログ中は時間切れにならない
    await tester.tap(find.text('中断する'));
    await tester.pumpAndSettle();
    expect(g.phase, PlayPhase.idle);
  });

  group('inactive・バックグラウンド化での中断', () {
    Future<void> lifecycle(WidgetTester tester, List<AppLifecycleState> states) async {
      for (final st in states) {
        tester.binding.handleAppLifecycleStateChanged(st);
        await tester.pump();
      }
    }

    testWidgets('inactive で止まり、戻るまでダイアログは出ない。戻ると1つだけ出る', (tester) async {
      final g = await pumpPlay(tester, size: const Size(393, 852));
      await tester.pump(const Duration(seconds: 3)); // 受付中
      expect(g.phase, PlayPhase.accepting);
      await lifecycle(tester, [AppLifecycleState.inactive]);
      expect(g.phase, PlayPhase.paused);
      expect(find.byType(AlertDialog), findsNothing);
      // inactive → hidden → paused が続いても中断は1回
      final seq = g.questionSeq;
      await lifecycle(tester, [AppLifecycleState.hidden, AppLifecycleState.paused]);
      expect(g.questionSeq, seq);
      // 止まっている間は時間切れにならない
      await tester.pump(const Duration(seconds: 30));
      expect(g.stats.judgedCount, 0);
      // 戻る
      await lifecycle(tester, [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      // もう一度 inactive → resumed（通知を引き出してすぐ戻した）でもダイアログは1つ
      await lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('続ける'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(g.phase, PlayPhase.countdown);
      expect(g.isReference, isTrue);
      await finish(tester, g);
    });

    testWidgets('カウントダウン中の inactive でも止まる', (tester) async {
      final g = await pumpPlay(tester, size: const Size(393, 852));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(g.phase, PlayPhase.countdown);
      await lifecycle(tester, [AppLifecycleState.inactive]);
      expect(g.phase, PlayPhase.paused);
      await tester.pump(const Duration(seconds: 10));
      expect(g.phase, PlayPhase.paused);
      await finish(tester, g);
    });
  });

  group('音声と文字の表示', () {
    testWidgets('音声 OFF・文字 OFF でも上の句の文字を表示する', (tester) async {
      final g = await pumpPlay(tester, size: const Size(393, 852), prefs: {
        SettingsKeys.soundOn: false,
        SettingsKeys.textFlowOn: false,
      });
      await tester.pump(const Duration(seconds: 3));
      expect(find.text(g.current.upper), findsOneWidget);
      await finish(tester, g);
    });

    testWidgets('音声 ON・文字 OFF なら文字は出さない（従来どおり）', (tester) async {
      final g = await pumpPlay(tester, size: const Size(393, 852), prefs: {
        SettingsKeys.textFlowOn: false,
      });
      await tester.pump(const Duration(seconds: 3));
      expect(find.text(g.current.upper), findsNothing);
      await finish(tester, g);
    });

    testWidgets('音声を再生できないときは文字を表示して知らせる（文字 OFF でも）', (tester) async {
      final g = await pumpPlay(tester, size: const Size(393, 852),
          prefs: {SettingsKeys.textFlowOn: false}, audio: BrokenAudio.new);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(g.audioUnavailable, isTrue);
      expect(find.text(g.current.upper), findsOneWidget);
      await tester.pump();
      expect(find.textContaining('読み上げ音声を再生できない'), findsOneWidget);
      await finish(tester, g);
    });
  });

  testWidgets('タブレット：札と情報欄を上下の中央に寄せる。スマートフォンは従来どおり上詰め', (tester) async {
    Future<double> topOfCards(Size size) async {
      final g = await pumpPlay(tester, size: size, cfg: const GameConfig(karafudaPercent: 30));
      final cardImage = RegExp(r'^assets/images/\d{3}\.png$');
      final cards = find.byWidgetPredicate((w) =>
          w is Image && (w.image is AssetImage) && cardImage.hasMatch((w.image as AssetImage).assetName));
      final top = cards.evaluate().map((e) => tester.getRect(find.byWidget(e.widget)).top).reduce(min);
      await finish(tester, g);
      return top;
    }

    expect(await topOfCards(const Size(393, 852)), lessThan(80)); // AppBar のすぐ下
    expect(await topOfCards(const Size(800, 1280)), greaterThan(150)); // 中央寄せ
  });
}
