// test/providers/game_state_test.dart
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/domain/practice_record.dart';
import 'package:tokkun_kyogikaruta/domain/question_plan.dart';
import 'package:tokkun_kyogikaruta/domain/verdict.dart';
import 'package:tokkun_kyogikaruta/models/card_data.dart';
import 'package:tokkun_kyogikaruta/models/game_config.dart';
import 'package:tokkun_kyogikaruta/providers/game_state.dart';
import 'package:tokkun_kyogikaruta/services/audio_service.dart';
import 'package:tokkun_kyogikaruta/services/score_repository.dart';

import '../services/score_repository_test.dart' show MemStore;

/// fake_async の時間で進む計測。[skewMs] で時計のずれ（Timer より早い・遅い）を再現する。
class FakeClock implements ElapsedClock {
  FakeClock(this.fa, {this.skewMs = 0});
  final FakeAsync fa;
  int skewMs;
  Duration _acc = Duration.zero;
  Duration? _startedAt;
  @override
  void start() => _startedAt ??= fa.elapsed;
  @override
  void stop() {
    if (_startedAt != null) {
      _acc += fa.elapsed - _startedAt!;
      _startedAt = null;
    }
  }

  @override
  void reset() {
    _acc = Duration.zero;
    if (_startedAt != null) _startedAt = fa.elapsed;
  }

  @override
  int get elapsedMs {
    final running = _startedAt == null ? Duration.zero : fa.elapsed - _startedAt!;
    final ms = (_acc + running).inMilliseconds;
    return ms == 0 ? 0 : ms + skewMs;
  }
}

class FakeAudio implements PracticeAudio {
  final List<String> log = [];
  @override
  Future<void> prepare(int cardId) async => log.add('prepare:$cardId');
  @override
  Future<void> play({required bool muted}) async => log.add('play:$muted');
  @override
  Future<void> pause() async => log.add('pause');
  @override
  Future<void> setMuted(bool muted) async => log.add('mute:$muted');
  @override
  Future<void> stop() async => log.add('stop');
  @override
  Future<void> dispose() async => log.add('dispose');
}

/// どの操作も失敗する音声（同期の例外・非同期の例外）
class BrokenAudio implements PracticeAudio {
  int calls = 0;
  @override
  Future<void> prepare(int cardId) {
    calls++;
    throw StateError('sync failure');
  }

  @override
  Future<void> play({required bool muted}) {
    calls++;
    return Future.error(StateError('async failure'));
  }

  @override
  Future<void> pause() => Future.error(StateError('x'));
  @override
  Future<void> setMuted(bool muted) => Future.error(StateError('x'));
  @override
  Future<void> stop() => Future.error(StateError('x'));
  @override
  Future<void> dispose() async {}
}

const cd = Duration(seconds: 1);
const fb = Duration(milliseconds: 650);

void main() {
  late FakeAudio audio;

  GameState newGame(FakeAsync fa,
      {GameConfig cfg = const GameConfig(), int seed = 1, int skew = 0, List<CardData>? cardSet}) {
    final g = GameState(
        rng: Random(seed), clock: FakeClock(fa, skewMs: skew), cardSet: cardSet);
    audio = FakeAudio();
    g.attachAudio(audio);
    g.startGame(cfg);
    g.begin();
    return g;
  }

  /// カウントダウン（3秒）を進めて受付中にする
  void toAccepting(FakeAsync fa, GameState g) {
    expect(g.phase, PlayPhase.countdown);
    fa.elapse(cd * 3);
    expect(g.phase, PlayPhase.accepting);
  }

  /// 正しく答える（取り札は出札をタップ、空札は見送り）
  void answerCorrectly(GameState g) {
    if (g.currentKind == QuestionKind.karafuda) {
      g.onPass();
    } else {
      g.onCardTap(g.current.id);
    }
  }

  group('空札なし（既存の流れの回帰）', () {
    test('10問すべて取り札・正解で 100%・終了', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        expect(g.plan.every((k) => k == QuestionKind.field), isTrue);
        for (var i = 0; i < 10; i++) {
          toAccepting(fa, g);
          fa.elapse(const Duration(milliseconds: 800));
          final onField = [...g.selfCards, ...g.enemyCards].any((c) => c.id == g.current.id);
          expect(onField, isTrue);
          g.onCardTap(g.current.id);
          expect(g.lastVerdict, Verdict.correct);
          fa.elapse(fb);
        }
        expect(g.phase, PlayPhase.finished);
        expect(g.round, 10);
        expect(g.stats.accuracyPercent, 100);
        expect(g.stats.avgTakeMs, 800);
        expect(g.buildRecord().rank.name, 'S');
      });
    });

    test('反応時間はミリ秒（1234ms）', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        toAccepting(fa, g);
        fa.elapse(const Duration(milliseconds: 1234));
        g.onCardTap(g.current.id);
        expect(g.lastElapsedMs, 1234);
        expect(g.stats.takeMs, [1234]);
      });
    });

    test('秒数の表示：受付中は1秒ごと、次の問題のカウントダウン中は null（B10）', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        expect(g.elapsedSec, isNull);
        toAccepting(fa, g);
        expect(g.elapsedSec, 0);
        fa.elapse(const Duration(milliseconds: 2500));
        expect(g.elapsedSec, 2);
        g.onCardTap(g.current.id);
        expect(g.elapsedSec, 2); // 判定表示中はそのまま
        fa.elapse(fb);
        expect(g.phase, PlayPhase.countdown);
        expect(g.elapsedSec, isNull);
      });
    });
  });

  group('連続入力・二重判定', () {
    test('同じ問題で2回タップしても判定は1回', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        toAccepting(fa, g);
        final id = g.current.id;
        g.onCardTap(id);
        g.onCardTap(id);
        g.onPass();
        expect(g.round, 1);
        expect(g.stats.judgedCount, 1);
      });
    });

    test('カウントダウン中・判定表示中の入力は無視', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        g.onCardTap(g.current.id); // カウントダウン中
        g.onPass();
        expect(g.stats.judgedCount, 0);
        toAccepting(fa, g);
        g.onCardTap(g.current.id);
        fa.elapse(const Duration(milliseconds: 300)); // 判定表示中
        g.onCardTap(g.current.id);
        expect(g.stats.judgedCount, 1);
      });
    });

    test('古い問題番号の入力は無視', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        toAccepting(fa, g);
        final oldSeq = g.questionSeq;
        g.onCardTap(g.current.id, seq: oldSeq);
        fa.elapse(fb + cd * 3);
        expect(g.phase, PlayPhase.accepting);
        g.onCardTap(g.current.id, seq: oldSeq); // 前の問題の画面からのタップ
        expect(g.stats.judgedCount, 1);
      });
    });

    test('時間切れとタップが同時でも判定は1回', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        toAccepting(fa, g);
        fa.elapse(const Duration(milliseconds: 10000)); // ここで時間切れ
        g.onCardTap(g.current.id);
        expect(g.stats.judgedCount, 1);
        expect(g.lastVerdict, Verdict.missed);
      });
    });
  });

  group('9.999秒と10秒の境界（実際の経過時間で判断）', () {
    test('9999ms のタップは有効', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        toAccepting(fa, g);
        fa.elapse(const Duration(milliseconds: 9999));
        g.onCardTap(g.current.id);
        expect(g.lastVerdict, Verdict.correct);
        expect(g.lastElapsedMs, 9999);
      });
    });

    test('Timer より先に計測が10000msに達していたら、タップでも時間切れ', () {
      fakeAsync((fa) {
        final g = newGame(fa, skew: 1); // 時計が Timer より 1ms 進んでいる
        toAccepting(fa, g);
        fa.elapse(const Duration(milliseconds: 9999)); // 計測は 10000ms
        g.onCardTap(g.current.id);
        expect(g.lastVerdict, Verdict.missed);
      });
    });

    test('Timer が早く呼ばれても、計測が10000ms未満なら時間切れにしない', () {
      fakeAsync((fa) {
        final g = newGame(fa, skew: -5); // 時計が 5ms 遅れている
        toAccepting(fa, g);
        fa.elapse(const Duration(milliseconds: 10000)); // 計測は 9995ms
        expect(g.phase, PlayPhase.accepting);
        g.onCardTap(g.current.id);
        expect(g.lastVerdict, Verdict.correct);
      });
    });

    test('Timer が早い場合も、残り時間の後に時間切れになる', () {
      fakeAsync((fa) {
        final g = newGame(fa, skew: -5);
        toAccepting(fa, g);
        fa.elapse(const Duration(milliseconds: 10005));
        expect(g.lastVerdict, Verdict.missed);
        expect(g.stats.judgedCount, 1);
      });
    });
  });

  group('空札', () {
    for (final (percent, k) in [(20, 2), (30, 3), (50, 5)]) {
      test('空札 $percent%：10問中 $k 問、正しく答えれば 100%', () {
        fakeAsync((fa) {
          final g = newGame(fa, cfg: GameConfig(karafudaPercent: percent));
          expect(g.plan.where((q) => q == QuestionKind.karafuda).length, k);
          var karaSeen = 0;
          for (var i = 0; i < 10; i++) {
            toAccepting(fa, g);
            if (g.currentKind == QuestionKind.karafuda) {
              karaSeen++;
              final field = [...g.selfCards, ...g.enemyCards].map((c) => c.id);
              expect(field.contains(g.current.id), isFalse);
            }
            fa.elapse(const Duration(milliseconds: 700));
            answerCorrectly(g);
            fa.elapse(fb);
          }
          expect(karaSeen, k);
          expect(g.stats.count(Verdict.passOk), k);
          expect(g.stats.accuracyPercent, 100);
          expect(g.stats.avgPassMs, 700);
        });
      });
    }

    test('見送り成功・見送りミス・お手つき・未回答・取り逃しの判定', () {
      fakeAsync((fa) {
        final g = newGame(fa, cfg: const GameConfig(karafudaPercent: 50));
        final seen = <Verdict>{};
        var karaStep = 0;
        var fieldStep = 0;
        for (var i = 0; i < 10; i++) {
          toAccepting(fa, g);
          final kara = g.currentKind == QuestionKind.karafuda;
          if (kara) {
            switch (karaStep++ % 3) {
              case 0:
                g.onPass();
              case 1:
                g.onCardTap(g.selfCards.first.id);
              default:
                fa.elapse(const Duration(seconds: 10));
            }
          } else {
            if (fieldStep++ % 2 == 0) {
              g.onPass();
            } else {
              fa.elapse(const Duration(seconds: 10));
            }
          }
          seen.add(g.lastVerdict!);
          fa.elapse(fb);
        }
        expect(seen, containsAll([Verdict.passOk, Verdict.fault, Verdict.noAnswer,
          Verdict.wrongPass, Verdict.missed]));
      });
    });

    test('取り札の問題で別の札 → 不正解、出札を強調', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        toAccepting(fa, g);
        final other = [...g.selfCards, ...g.enemyCards].firstWhere((c) => c.id != g.current.id);
        final layout = [...g.selfCards, ...g.enemyCards].map((c) => c.id).toList();
        g.onCardTap(other.id);
        expect(g.lastVerdict, Verdict.wrong);
        expect(g.highlightCardId, g.current.id);
        // 判定表示中は札の位置が変わらない
        expect([...g.selfCards, ...g.enemyCards].map((c) => c.id).toList(), layout);
      });
    });

    test('お手つきペナルティ ON/OFF', () {
      for (final penalty in [false, true]) {
        fakeAsync((fa) {
          final g = newGame(fa,
              cfg: GameConfig(karafudaPercent: 30, otetsukiPenalty: penalty));
          for (var i = 0; i < 10; i++) {
            toAccepting(fa, g);
            if (g.currentKind == QuestionKind.karafuda) {
              g.onCardTap(g.selfCards.first.id); // すべてお手つき
            } else {
              g.onCardTap(g.current.id);
            }
            fa.elapse(fb);
          }
          expect(g.stats.count(Verdict.fault), 3);
          expect(g.stats.successCount, 7);
          expect(g.stats.deduction, penalty ? 3 : 0);
          expect(g.stats.accuracyPercent, penalty ? 40 : 70);
        });
      }
    });
  });

  group('中断・再開', () {
    test('受付中に一時停止：時間切れにならず、音声も止まる', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        toAccepting(fa, g);
        fa.elapse(const Duration(seconds: 2));
        expect(g.requestPause(), isTrue);
        expect(audio.log.last, 'pause');
        fa.elapse(const Duration(seconds: 30));
        expect(g.phase, PlayPhase.paused);
        expect(g.stats.judgedCount, 0);
        expect(g.requestPause(), isFalse); // 二重に止めない（ダイアログは1つ）
      });
    });

    test('続ける：同じ種類の別の札でカウントダウンから。問題数は進まず参考記録', () {
      fakeAsync((fa) {
        final g = newGame(fa, cfg: const GameConfig(karafudaPercent: 30));
        toAccepting(fa, g);
        final before = g.current.id;
        final kind = g.currentKind;
        g.requestPause();
        expect(g.canResume, isTrue);
        expect(g.resume(), isTrue);
        expect(g.phase, PlayPhase.countdown);
        expect(g.current.id, isNot(before));
        expect(g.currentKind, kind);
        expect(g.round, 0);
        expect(g.isReference, isTrue);
        expect(g.elapsedSec, isNull);
        expect(audio.log.last, 'prepare:${g.current.id}');
      });
    });

    test('中断を繰り返しても、空札の数と判定数（10）は変わらない', () {
      fakeAsync((fa) {
        final g = newGame(fa, cfg: const GameConfig(karafudaPercent: 50));
        final read = <int>{};
        for (var i = 0; i < 10; i++) {
          toAccepting(fa, g);
          for (var r = 0; r < 3; r++) {
            read.add(g.current.id); // 読みかけた札
            g.requestPause();
            g.resume();
            toAccepting(fa, g);
          }
          expect(read.contains(g.current.id), isFalse, reason: '読みかけた札を再び読まない');
          answerCorrectly(g);
          read.add(g.current.id);
          fa.elapse(fb);
        }
        expect(g.phase, PlayPhase.finished);
        expect(g.stats.judgedCount, 10);
        expect(g.stats.count(Verdict.passOk), 5);
        expect(g.stats.count(Verdict.correct), 5);
        expect(g.buildRecord().isReference, isTrue);
      });
    });

    test('判定表示中に止めて続けると、次の問題から', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        toAccepting(fa, g);
        g.onCardTap(g.current.id);
        expect(g.phase, PlayPhase.feedback);
        g.requestPause();
        g.resume();
        expect(g.round, 1);
        expect(g.stats.judgedCount, 1);
        expect(g.phase, PlayPhase.countdown);
      });
    });

    test('山札が足りなくなったら続けられない（実際の残数で判断）', () {
      fakeAsync((fa) {
        // 9枚だけ：場6・山札3。空札50%（5問）は足りないが、計画の作り方に関係なく判断できる
        final few = [for (var i = 1; i <= 9; i++) CardData(i, '上$i', '下$i')];
        final g = newGame(fa, cardSet: few);
        var resumes = 0;
        while (true) {
          toAccepting(fa, g);
          g.requestPause();
          if (!g.canResume) break;
          g.resume();
          resumes++;
          expect(resumes, lessThan(20));
        }
        expect(g.phase, PlayPhase.paused);
        expect(g.resume(), isFalse);
        g.abort();
        expect(g.phase, PlayPhase.idle);
      });
    });

    test('中断する：タイマー・音声を止め、その後に何も進まない', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        toAccepting(fa, g);
        g.requestPause();
        g.abort();
        expect(audio.log.last, 'stop');
        final seq = g.questionSeq;
        fa.elapse(const Duration(minutes: 1));
        expect(g.phase, PlayPhase.idle);
        expect(g.questionSeq, seq);
        expect(g.stats.judgedCount, 0);
      });
    });
  });

  group('音声の失敗・非同期処理の後始末', () {
    test('音声の準備・再生がすべて失敗しても、練習は最後まで進む', () {
      fakeAsync((fa) {
        final g = GameState(rng: Random(3), clock: FakeClock(fa));
        final broken = BrokenAudio();
        g.attachAudio(broken);
        g.startGame(const GameConfig(karafudaPercent: 30));
        g.begin();
        for (var i = 0; i < 10; i++) {
          toAccepting(fa, g);
          answerCorrectly(g);
          fa.elapse(fb);
        }
        fa.flushMicrotasks();
        expect(g.phase, PlayPhase.finished);
        expect(g.stats.accuracyPercent, 100);
        expect(broken.calls, greaterThan(0));
      });
    });

    test('練習の終了後・中断後にタイマーが残らない', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        for (var i = 0; i < 10; i++) {
          toAccepting(fa, g);
          answerCorrectly(g);
          fa.elapse(fb);
        }
        expect(g.phase, PlayPhase.finished);
        expect(fa.pendingTimers, isEmpty);

        final g2 = newGame(fa);
        toAccepting(fa, g2);
        g2.requestPause();
        expect(fa.pendingTimers, isEmpty, reason: '一時停止中は時間が進まない');
        g2.resume();
        toAccepting(fa, g2);
        g2.abort();
        expect(fa.pendingTimers, isEmpty);
      });
    });
  });

  group('結果の確定（保存・ギャラリー）', () {
    Future<(ResultOutcome, ResultOutcome, int)> finishAndFinalize(
        FakeAsync fa, GameState g, ScoreRepository repo) async {
      var grants = 0;
      Future<(int?, bool)> grant(_) async {
        grants++;
        return (8, false);
      }

      final a = g.finalizeResult(repository: repo, grantGallery: grant);
      final b = g.finalizeResult(repository: repo, grantGallery: grant);
      fa.flushMicrotasks();
      return (await a, await b, grants);
    }

    void playAll(FakeAsync fa, GameState g) {
      for (var i = 0; i < 10; i++) {
        toAccepting(fa, g);
        fa.elapse(const Duration(milliseconds: 900));
        answerCorrectly(g);
        fa.elapse(fb);
      }
    }

    test('2回呼んでも保存・ギャラリー付与は1回', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        playAll(fa, g);
        final repo = ScoreRepository(MemStore());
        late (ResultOutcome, ResultOutcome, int) r;
        finishAndFinalize(fa, g, repo).then((v) => r = v);
        fa.flushMicrotasks();
        expect(identical(r.$1, r.$2), isTrue);
        expect(r.$3, 1);
        expect(r.$1.save.bestUpdated, isTrue);
        expect(r.$1.grantedGalleryId, 8);
        expect(repo.loadBest(RecordCategory.normal)!.rank.name, 'S');
      });
    });

    test('参考記録：最高記録もギャラリーも対象外、前回の結果には残る', () {
      fakeAsync((fa) {
        final g = newGame(fa);
        toAccepting(fa, g);
        g.requestPause();
        g.resume();
        playAll(fa, g);
        final repo = ScoreRepository(MemStore());
        late (ResultOutcome, ResultOutcome, int) r;
        finishAndFinalize(fa, g, repo).then((v) => r = v);
        fa.flushMicrotasks();
        expect(r.$1.record.isReference, isTrue);
        expect(r.$1.save.bestUpdated, isFalse);
        expect(r.$3, 0);
        expect(r.$1.grantedGalleryId, isNull);
        expect(repo.loadBest(RecordCategory.normal), isNull);
        expect(repo.loadLast()!.isReference, isTrue);
      });
    });
  });
}
