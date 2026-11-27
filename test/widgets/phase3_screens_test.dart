// test/widgets/phase3_screens_test.dart
//
// Phase 3：ホーム画面のレイアウト、設定画面、3種類のリセット、戻る操作、背景の表示範囲。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tokkun_kyogikaruta/app.dart';
import 'package:tokkun_kyogikaruta/domain/practice_record.dart';
import 'package:tokkun_kyogikaruta/domain/rank_policy.dart';
import 'package:tokkun_kyogikaruta/providers/game_provider.dart';
import 'package:tokkun_kyogikaruta/providers/settings_provider.dart';
import 'package:tokkun_kyogikaruta/widgets/background_scaffold.dart';

Future<SharedPreferences> pumpApp(WidgetTester tester,
    {Size size = const Size(393, 852), Map<String, Object> prefs = const {}}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(Map.of(prefs));
  final p = await SharedPreferences.getInstance();
  appRouter.go('/'); // 前のテストの画面が残らないように
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(p)],
    child: const App(),
  ));
  await tester.pumpAndSettle();
  return p;
}

Future<void> goTo(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

String record(Rank rank, {int karafuda = 0}) => jsonEncode(PracticeRecord(
      rank: rank,
      accuracy: 90,
      avgMs: 2000,
      successCount: 9,
      deduction: 0,
      totalQuestions: 10,
      karafudaPercent: karafuda,
      otetsukiPenalty: false,
      timingVersion: 2,
      isReference: false,
      sessionId: 's-$rank-$karafuda',
      playedAt: DateTime(2026, 11, 27),
    ).toJson());

void main() {
  group('ホーム画面（4サイズ）', () {
    const sizes = {
      '小型スマホ縦 360×640': Size(360, 640),
      '標準スマホ縦 393×852': Size(393, 852),
      'スマホ横 852×393': Size(852, 393),
      'タブレット縦 800×1280': Size(800, 1280),
    };
    for (final e in sizes.entries) {
      testWidgets('${e.key}：タイトル・反応練習と説明文が画面内、はみ出しなし', (tester) async {
        await pumpApp(tester, size: e.value);
        expect(tester.takeException(), isNull);
        final screen = Offset.zero & e.value;
        for (final text in ['競技かるた特訓', '反応練習', '札の認識力・判断力・反応速度を鍛える']) {
          final r = tester.getRect(find.text(text));
          expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight - const Offset(1, 1)),
              isTrue, reason: '$text が画面外: $r');
        }
        // 導線（スクロールすれば届く）
        for (final label in ['遊び方説明', '成績・ランク', 'ギャラリー', '設定', 'プライバシーポリシー']) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        // Phase 3 では表示しない・廃止したもの
        expect(find.text('実践練習'), findsNothing);
        expect(find.text('スコアのリセット'), findsNothing);
        expect(find.text('スタート'), findsNothing);
      });
    }

    testWidgets('空札ありのときは条件を説明文の下に表示', (tester) async {
      await pumpApp(tester, prefs: {
        SettingsKeys.karafudaEnabled: true,
        SettingsKeys.karafudaPercent: 50,
        SettingsKeys.otetsukiPenalty: true,
      });
      expect(find.text('空札あり 50%・お手つきペナルティ'), findsOneWidget);
    });
  });

  group('設定画面', () {
    testWidgets('初期値：空札なし、割合とペナルティは操作できない', (tester) async {
      await pumpApp(tester);
      await goTo(tester, '設定');
      final kara = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '空札あり'));
      expect(kara.value, isFalse);
      final penalty =
          tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'お手つきペナルティ'));
      expect(penalty.onChanged, isNull);
      final seg = tester.widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>));
      expect(seg.onSelectionChanged, isNull);
      expect(find.text('10問中 3問が空札になります。'), findsOneWidget);
    });

    testWidgets('空札あり → 割合 20/30/50% を選べ、説明の問題数が変わり、保存される', (tester) async {
      final p = await pumpApp(tester);
      await goTo(tester, '設定');
      await tester.tap(find.widgetWithText(SwitchListTile, '空札あり'));
      await tester.pumpAndSettle();
      for (final (label, percent, count) in [
        ('少なめ（20%）', 20, 2),
        ('多め（50%）', 50, 5),
        ('ふつう（30%）', 30, 3),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(p.getInt(SettingsKeys.karafudaPercent), percent);
        expect(find.text('10問中 $count問が空札になります。'), findsOneWidget);
      }
      await tester.tap(find.widgetWithText(SwitchListTile, 'お手つきペナルティ'));
      await tester.pumpAndSettle();
      expect(p.getBool(SettingsKeys.karafudaEnabled), isTrue);
      expect(p.getBool(SettingsKeys.otetsukiPenalty), isTrue);
    });

    testWidgets('音声と文字表示を両方 OFF にすると注意を表示', (tester) async {
      await pumpApp(tester);
      await goTo(tester, '設定');
      await tester.tap(find.widgetWithText(SwitchListTile, '読み上げ音声'));
      await tester.pumpAndSettle();
      expect(find.textContaining('両方OFF'), findsNothing);
      await tester.tap(find.widgetWithText(SwitchListTile, '上の句の文字表示'));
      await tester.pumpAndSettle();
      expect(find.textContaining('両方OFF'), findsOneWidget);
    });
  });

  group('3種類のリセットの独立性', () {
    Map<String, Object> allData() => {
          'bestRank': 'A',
          'bestAccuracy': 95,
          'bestAvgSec': 1.9,
          'record.v2.best.normal': record(Rank.A),
          'record.v2.best.karafuda': record(Rank.B, karafuda: 30),
          'record.v2.last': record(Rank.B, karafuda: 30),
          'record.v2.match.best': 'phase4-placeholder', // Phase 4 で増える成績キー
          'galleryOwnedIds': ['2', '8'],
          SettingsKeys.karafudaEnabled: true,
          SettingsKeys.soundOn: false,
        };

    Future<void> tapReset(WidgetTester tester, String label, List<String> confirms) async {
      await tester.scrollUntilVisible(find.text(label), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      for (final c in confirms) {
        await tester.tap(find.text(c));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('成績をリセット：新旧の成績キーだけが消え、ギャラリー・設定は残る', (tester) async {
      final p = await pumpApp(tester, prefs: allData());
      await goTo(tester, '設定');
      await tapReset(tester, '成績をリセット', ['リセット']);
      for (final k in ['bestRank', 'bestAccuracy', 'bestAvgSec', 'record.v2.best.normal',
        'record.v2.best.karafuda', 'record.v2.last', 'record.v2.match.best']) {
        expect(p.containsKey(k), isFalse, reason: k);
      }
      expect(p.getStringList('galleryOwnedIds'), ['2', '8']);
      expect(p.getBool(SettingsKeys.karafudaEnabled), isTrue);
      expect(p.getBool(SettingsKeys.soundOn), isFalse);
    });

    testWidgets('ギャラリーをリセット：2段階の確認、成績・設定は残る', (tester) async {
      final p = await pumpApp(tester, prefs: allData());
      await goTo(tester, '設定');
      // 1段階目でキャンセルすれば消えない
      await tapReset(tester, 'ギャラリーをリセット', ['キャンセル']);
      expect(p.getStringList('galleryOwnedIds'), ['2', '8']);
      await tapReset(tester, 'ギャラリーをリセット', ['次へ', '消す']);
      expect(p.containsKey('galleryOwnedIds'), isFalse);
      expect(p.getString('bestRank'), 'A');
      expect(p.containsKey('record.v2.best.normal'), isTrue);
      expect(p.getBool(SettingsKeys.karafudaEnabled), isTrue);
    });

    testWidgets('設定を初期値に戻す：設定だけが消え、成績・ギャラリーは残る', (tester) async {
      final p = await pumpApp(tester, prefs: allData());
      await goTo(tester, '設定');
      await tapReset(tester, '設定を初期値に戻す', ['戻す']);
      expect(p.containsKey(SettingsKeys.karafudaEnabled), isFalse);
      expect(p.containsKey(SettingsKeys.soundOn), isFalse);
      expect(p.getString('bestRank'), 'A');
      expect(p.getStringList('galleryOwnedIds'), ['2', '8']);
      // 画面も初期値になる
      final kara = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '空札あり'));
      expect(kara.value, isFalse);
    });
  });

  group('戻る操作（ホームへ）', () {
    for (final (label, appBarTitle) in [
      ('遊び方説明', '遊び方'),
      ('成績・ランク', '成績・ランク'),
      ('ギャラリー', 'ギャラリー'),
      ('設定', '設定'),
      ('プライバシーポリシー', 'プライバシーポリシー'),
    ]) {
      testWidgets('$label → 戻る → ホーム', (tester) async {
        await pumpApp(tester);
        await goTo(tester, label);
        expect(find.widgetWithText(AppBar, appBarTitle), findsOneWidget);
        await pressBack(tester);
        expect(find.text('反応練習'), findsOneWidget);
        // AppBar の矢印でも戻れる
        await goTo(tester, label);
        await tester.tap(find.byTooltip('ホームへ戻る'));
        await tester.pumpAndSettle();
        expect(find.text('反応練習'), findsOneWidget);
      });
    }

    testWidgets('設定の確認ダイアログが出ているときの戻るは、ダイアログを閉じるだけ', (tester) async {
      await pumpApp(tester);
      await goTo(tester, '設定');
      await tester.scrollUntilVisible(find.text('成績をリセット'), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('成績をリセット'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await pressBack(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.widgetWithText(AppBar, '設定'), findsOneWidget);
    });
  });

  testWidgets('遊び方：通知・アプリ切り替えでの一時停止と参考記録を説明している', (tester) async {
    await pumpApp(tester);
    await goTo(tester, '遊び方説明');
    await tester.scrollUntilVisible(find.textContaining('通知やコントロールセンター'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('通知やコントロールセンター'), findsOneWidget);
    expect(find.textContaining('「参考記録」になります'), findsOneWidget);
  });

  testWidgets('成績画面：記録が少なくても背景が画面いっぱい（BackgroundScaffold）', (tester) async {
    await pumpApp(tester, size: const Size(393, 852));
    await goTo(tester, '成績・ランク');
    final container = find.descendant(
        of: find.byType(BackgroundScaffold), matching: find.byType(Container)).first;
    final r = tester.getRect(container);
    // AppBar の下から画面の下端まで
    expect(r.bottom, 852);
    expect(r.width, 393);
    expect(find.text('反応練習'), findsOneWidget); // 見出し
  });

  testWidgets('成績画面：成績のキーを読める（Provider 経由）', (tester) async {
    await pumpApp(tester, prefs: {'record.v2.best.normal': record(Rank.S)});
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    expect(container.read(scoreRepositoryProvider).loadBest(RecordCategory.normal)!.rank,
        Rank.S);
  });
}
