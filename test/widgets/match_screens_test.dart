// test/widgets/match_screens_test.dart
//
// 実践練習の画面：開始画面・暗記／練習画面・結果画面・成績タブ・ホームの導線・画面サイズ・縦向き固定
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tokkun_kyogikaruta/app.dart';
import 'package:tokkun_kyogikaruta/domain/match_judge.dart';
import 'package:tokkun_kyogikaruta/domain/match_plan.dart';
import 'package:tokkun_kyogikaruta/providers/game_provider.dart';
import 'package:tokkun_kyogikaruta/providers/game_state.dart' show ElapsedClock;
import 'package:tokkun_kyogikaruta/providers/match_state.dart';
import 'package:tokkun_kyogikaruta/providers/settings_provider.dart';
import 'package:tokkun_kyogikaruta/services/orientation_lock.dart';
import 'package:tokkun_kyogikaruta/widgets/match_field.dart';

import '../providers/game_state_test.dart' show FakeAudio;

/// テストの時間（tester.pump で進む）で計る時計
class TesterClock implements ElapsedClock {
  TesterClock(this.binding);
  final TestWidgetsFlutterBinding binding;
  Duration _acc = Duration.zero;
  DateTime? _startedAt;
  DateTime get _now => binding.clock.now();
  @override
  void start() => _startedAt ??= _now;
  @override
  void stop() {
    if (_startedAt != null) {
      _acc += _now.difference(_startedAt!);
      _startedAt = null;
    }
  }

  @override
  void reset() {
    _acc = Duration.zero;
    if (_startedAt != null) _startedAt = _now;
  }

  @override
  int get elapsedMs =>
      (_acc + (_startedAt == null ? Duration.zero : _now.difference(_startedAt!))).inMilliseconds;
}

final orientationCalls = <List<DeviceOrientation>>[];

Future<(SharedPreferences, MatchState)> pumpApp(WidgetTester tester,
    {Size size = const Size(393, 852),
    Map<String, Object> prefs = const {},
    double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  orientationCalls.clear();
  OrientationLock.setter = (o) async => orientationCalls.add(o);
  OrientationLock.releaseDelay = Duration.zero;
  SharedPreferences.setMockInitialValues(Map.of(prefs));
  final p = await SharedPreferences.getInstance();
  final match = MatchState(rng: Random(5), clockFactory: () => TesterClock(tester.binding));
  addTearDown(match.reset);
  appRouter.go('/');
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(p),
      practiceAudioFactoryProvider.overrideWithValue(FakeAudio.new),
      matchProvider.overrideWith((ref) => match),
    ],
    child: const App(),
  ));
  await tester.pumpAndSettle();
  return (p, match);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

/// ホーム → 実践練習 → はじめる → 暗記画面
Future<void> toMemorize(WidgetTester tester) async {
  await tapText(tester, '実践練習');
  await tester.ensureVisible(find.byKey(const ValueKey('match-start')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('match-start')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600)); // 画面の切り替えのアニメーションを終える
}

/// 暗記終了 → カウントダウン3秒 → 受付
Future<void> toAccepting(WidgetTester tester, MatchState m) async {
  if (m.phase == MatchPhase.memorizing) {
    await tester.tap(find.byKey(const ValueKey('end-memorize')));
    await tester.pump();
  }
  if (m.phase == MatchPhase.feedback) await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  expect(m.phase, MatchPhase.accepting);
}

Rect slotRect(WidgetTester tester, int i) => tester.getRect(find.byKey(ValueKey('pos-$i')));

Future<void> leave(WidgetTester tester, MatchState m) async {
  m.reset();
  appRouter.go('/');
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 200)); // 縦向き固定の解除を待つ
}

void main() {
  tearDown(() {
    OrientationLock.setter = null;
    OrientationLock.releaseDelay = const Duration(milliseconds: 100);
  });

  group('開始画面', () {
    testWidgets('初期値：暗記1分・空札30%・全17問。選んだ条件は保存され、ホームにも表示', (tester) async {
      final (p, m) = await pumpApp(tester);
      expect(find.text('暗記 1分・空札 30%'), findsOneWidget); // ホームの条件
      await tapText(tester, '実践練習');
      expect(find.textContaining('全17問（場の札12枚＋空札5枚）'), findsOneWidget);
      await tester.tap(find.text('50%'));
      await tester.pumpAndSettle();
      expect(find.textContaining('全24問（場の札12枚＋空札12枚）'), findsOneWidget);
      await tester.tap(find.text('なし'));
      await tester.pumpAndSettle();
      expect(find.textContaining('全12問（場の札12枚）'), findsOneWidget);
      await tester.tap(find.text('3分'));
      await tester.pumpAndSettle();
      expect(p.getInt(SettingsKeys.matchKarafudaPercent), 0);
      expect(p.getInt(SettingsKeys.matchMemorizeSec), 180);
      expect(find.textContaining('正式ルールではなく'), findsOneWidget);
      // 戻る → ホームに条件が表示される
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('暗記 3分・空札なし'), findsOneWidget);
      await leave(tester, m);
    });

    testWidgets('はじめる → 暗記画面（12枚）。縦向きに固定し、ホームに戻ると解除', (tester) async {
      final (_, m) = await pumpApp(tester);
      await toMemorize(tester);
      expect(m.phase, MatchPhase.memorizing);
      expect(find.byKey(const ValueKey('band-memorize')), findsOneWidget);
      for (var i = 0; i < 12; i++) {
        expect(find.byKey(ValueKey('slot-$i')), findsOneWidget);
      }
      expect(orientationCalls.first,
          [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      await leave(tester, m);
      expect(orientationCalls.last, isEmpty, reason: 'アプリの既定（縦横）に戻す');
      expect(OrientationLock.holders, 0);
    });
  });

  group('暗記・練習画面', () {
    testWidgets('暗記から練習へ移っても札の座標・大きさは同じ。判定表示でも変わらない', (tester) async {
      final (_, m) = await pumpApp(tester);
      await toMemorize(tester);
      final before = [for (var i = 0; i < 12; i++) slotRect(tester, i)];
      await toAccepting(tester, m);
      final after = [for (var i = 0; i < 12; i++) slotRect(tester, i)];
      expect(after, before, reason: 'before=$before after=$after');
      final t = m.current!.slotIndex;
      if (t != null) {
        await tester.tap(find.byKey(ValueKey('slot-$t')));
        await tester.pump();
        expect(m.lastOutcome, MatchOutcome.correct);
        expect([for (var i = 0; i < 12; i++) slotRect(tester, i)], before);
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.byKey(ValueKey('empty-$t')), findsOneWidget);
        expect(slotRect(tester, t), before[t]);
      }
      await leave(tester, m);
    });

    testWidgets('同陣ミス：情報欄に表示（札の上には文字を出さない）、受付は続く。空白は押しても何も起きない', (tester) async {
      final (_, m) = await pumpApp(tester, prefs: {SettingsKeys.matchKarafudaPercent: 0});
      await toMemorize(tester);
      await toAccepting(tester, m);
      // 1枚目を取って空白を作る
      final first = m.current!.slotIndex!;
      await tester.tap(find.byKey(ValueKey('slot-$first')));
      await tester.pump(const Duration(milliseconds: 700));
      await toAccepting(tester, m);
      final t = m.current!.slotIndex!;
      final other = m.slots
          .firstWhere((s) => s.side == m.slots[t].side && s.index != t && m.occupied.contains(s.index))
          .index;
      await tester.tap(find.byKey(ValueKey('slot-$other')));
      await tester.pump();
      expect(find.byKey(const ValueKey('band-same-side')), findsOneWidget);
      expect(m.phase, MatchPhase.accepting);
      // 判定の文字は札の外（情報欄）
      final band = tester.getRect(find.byKey(const ValueKey('band-same-side')));
      for (var i = 0; i < 12; i++) {
        if (find.byKey(ValueKey('slot-$i')).evaluate().isEmpty) continue;
        expect(band.overlaps(slotRect(tester, i)), isFalse);
      }
      // 空白を押しても何も起きない
      await tester.tap(find.byKey(ValueKey('empty-$first')));
      await tester.pump();
      expect(m.readsDone, 1);
      expect(m.stats.otetsuki, 0);
      await tester.tap(find.byKey(ValueKey('slot-$t')));
      await tester.pump();
      expect(m.lastOutcome, MatchOutcome.correct);
      expect(find.byKey(const ValueKey('band-verdict')), findsOneWidget);
      await leave(tester, m);
    });

    testWidgets('戻る → 一時停止して札を隠す → 続けると参考記録、札の配置は同じ', (tester) async {
      final (_, m) = await pumpApp(tester);
      await toMemorize(tester);
      await toAccepting(tester, m);
      final slotsBefore = m.slots;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(m.isPaused, isTrue);
      expect(find.byKey(const ValueKey('slot-0')), findsNothing); // 隠している
      expect(find.textContaining('札を隠しています'), findsWidgets);
      expect(find.textContaining('参考記録となり'), findsOneWidget);
      await tester.tap(find.text('続ける'));
      await tester.pump();
      expect(m.isReference, isTrue);
      expect(m.slots, same(slotsBefore));
      expect(find.text('参考記録'), findsOneWidget); // AppBar の表示
      await leave(tester, m);
    });

    testWidgets('最後の読みの判定確定後に戻る：「結果を見る」だけ → 通常の記録として結果へ', (tester) async {
      final (p, m) = await pumpApp(tester, prefs: {SettingsKeys.matchKarafudaPercent: 0});
      await toMemorize(tester);
      while (m.readsDone < 11) {
        await toAccepting(tester, m);
        await tester.tap(find.byKey(ValueKey('slot-${m.current!.slotIndex}')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
      }
      await toAccepting(tester, m);
      await tester.tap(find.byKey(ValueKey('slot-${m.current!.slotIndex}')));
      await tester.pump(); // 判定表示中
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('練習が終わりました'), findsOneWidget);
      expect(find.text('中断する'), findsNothing);
      await tester.tap(find.text('結果を見る'));
      await tester.pumpAndSettle();
      expect(find.text('実践練習 結果'), findsOneWidget);
      expect(m.isReference, isFalse);
      expect(p.containsKey('record.v2.match.best.k0'), isTrue);
      await leave(tester, m);
    });

    testWidgets('暗記中の中断ダイアログは「参考記録にはなりません」', (tester) async {
      final (_, m) = await pumpApp(tester);
      await toMemorize(tester);
      await tester.tap(find.text('中断'));
      await tester.pumpAndSettle();
      expect(find.textContaining('参考記録にはなりません'), findsOneWidget);
      await tester.tap(find.text('中断する'));
      await tester.pumpAndSettle();
      expect(m.phase, MatchPhase.idle);
      expect(find.text('反応練習'), findsOneWidget); // ホーム
    });

    const sizes = {
      '小型 360×640': Size(360, 640),
      'iPhone SE 相当 375×667': Size(375, 667),
      'iPhone 15 相当 393×852': Size(393, 852),
      'タブレット 800×1280': Size(800, 1280),
    };
    for (final e in sizes.entries) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('${e.key}・文字 ×$scale：12枚と見送りが画面内、はみ出しなし、札は 44 以上', (tester) async {
          final (_, m) = await pumpApp(tester, size: e.value, textScale: scale);
          await toMemorize(tester);
          await toAccepting(tester, m);
          expect(tester.takeException(), isNull);
          final screen = Offset.zero & e.value;
          for (var i = 0; i < 12; i++) {
            final r = slotRect(tester, i);
            expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight - const Offset(1, 1)),
                isTrue, reason: '札 $i: $r');
            expect(r.width, greaterThanOrEqualTo(MatchFieldMetrics.minCardWidth));
            expect(r.width / r.height, closeTo(cardAspect, 0.01));
            expect(r.width, lessThanOrEqualTo(MatchFieldMetrics.maxCardWidth));
          }
          final pass = tester.getRect(find.text('見 送 り'));
          expect(screen.contains(pass.bottomRight - const Offset(1, 1)), isTrue);
          final passBtn = tester.getRect(find.ancestor(of: find.text('見 送 り'), matching: find.byType(OutlinedButton)));
          expect(passBtn.height, greaterThanOrEqualTo(48));
          // 敵陣は上、自陣は下
          final enemy = tester.getRect(find.byKey(const ValueKey('enemy-side')));
          final self = tester.getRect(find.byKey(const ValueKey('self-side')));
          expect(enemy.bottom, lessThan(self.top));
          await leave(tester, m);
        });
      }
    }

    testWidgets('横向きのスマートフォン（向きの固定が効かない場合）：練習を止めて縦向きを促す', (tester) async {
      final (_, m) = await pumpApp(tester);
      await toMemorize(tester);
      await toAccepting(tester, m);
      tester.view.physicalSize = const Size(852, 393);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('rotate-notice')), findsOneWidget);
      expect(m.isPaused, isTrue);
      // 縦に戻すと中断ダイアログ（続けるか選ぶ）
      tester.view.physicalSize = const Size(393, 852);
      await tester.pumpAndSettle();
      expect(find.text('練習を中断しますか？'), findsOneWidget);
      await tester.tap(find.text('中断する'));
      await tester.pumpAndSettle();
    });

    testWidgets('タブレット横 1280×800 でも札が押せる大きさなら練習できる', (tester) async {
      final (_, m) = await pumpApp(tester, size: const Size(1280, 800));
      await toMemorize(tester);
      await toAccepting(tester, m);
      expect(find.byKey(const ValueKey('rotate-notice')), findsNothing);
      expect(slotRect(tester, 0).width, greaterThanOrEqualTo(MatchFieldMetrics.minCardWidth));
      await leave(tester, m);
    });
  });

  group('結果画面・成績画面', () {
    Future<void> playAll(WidgetTester tester, MatchState m) async {
      while (!m.finished) {
        await toAccepting(tester, m);
        final cur = m.current!;
        if (cur.isKarafuda) {
          await tester.tap(find.text('見 送 り'));
        } else {
          await tester.pump(const Duration(milliseconds: 1200));
          await tester.tap(find.byKey(ValueKey('slot-${cur.slotIndex}')));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('全問取る → 結果（条件・ランク・最高記録・正答率・詳細の順）→ 成績タブに表示', (tester) async {
      final (p, m) = await pumpApp(tester, size: const Size(393, 852));
      await toMemorize(tester);
      await playAll(tester, m);
      expect(find.text('実践練習 結果'), findsOneWidget);
      // 獲得ダイアログが出ていれば閉じる
      if (find.text('OK').evaluate().isNotEmpty) {
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      final y = [
        tester.getRect(find.text('空札 30%・暗記 1分')).top,
        tester.getRect(find.byKey(const ValueKey('match-rank'))).top,
        tester.getRect(find.textContaining('最高記録を更新しました')).top,
        tester.getRect(find.text('最終正答率')).top,
        tester.getRect(find.text('取った札')).top,
        tester.getRect(find.byKey(const ValueKey('match-home'))).top,
      ];
      for (var i = 1; i < y.length; i++) {
        expect(y[i], greaterThan(y[i - 1]), reason: '表示の順 $i');
      }
      expect(find.text('ランク S'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(p.containsKey('record.v2.match.best.k30'), isTrue);
      expect(p.containsKey('record.v2.last'), isFalse, reason: '反応練習の前回には書かない');
      expect(p.getStringList('galleryOwnedIds'), isNotEmpty, reason: '共通のギャラリーに付与');

      await tester.tap(find.byKey(const ValueKey('match-home')));
      await tester.pumpAndSettle();
      await tapText(tester, '成績・ランク');
      await tester.tap(find.text('実践練習').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('空札 30%・全17問'), findsOneWidget);
      expect(find.text('S'), findsWidgets);
      await leave(tester, m);
    });

    testWidgets('同じ配置でもう一度 → 参考記録（最高記録・ギャラリーの対象外）', (tester) async {
      final (p, m) = await pumpApp(tester, prefs: {SettingsKeys.matchKarafudaPercent: 0});
      await toMemorize(tester);
      await playAll(tester, m);
      if (find.text('OK').evaluate().isNotEmpty) {
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      final owned = p.getStringList('galleryOwnedIds');
      final slots = m.slots;
      await tester.ensureVisible(find.byKey(const ValueKey('match-same')));
      await tester.tap(find.byKey(const ValueKey('match-same')));
      await tester.pump();
      await tester.pump();
      expect(m.slots, same(slots));
      expect(m.isReference, isTrue);
      await playAll(tester, m);
      expect(find.textContaining('同じ配置での練習のため'), findsOneWidget);
      expect(p.getStringList('galleryOwnedIds'), owned);
      await leave(tester, m);
    });

    testWidgets('結果画面の戻る：ゲームをリセットしてホームへ', (tester) async {
      final (_, m) = await pumpApp(tester, prefs: {SettingsKeys.matchKarafudaPercent: 0});
      await toMemorize(tester);
      await playAll(tester, m);
      if (find.text('OK').evaluate().isNotEmpty) {
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(m.phase, MatchPhase.idle);
      expect(find.text('反応練習'), findsOneWidget);
    });
  });

  test('総出題数の表示に使う値', () {
    expect(matchTotalReads(30), 17);
  });
}
