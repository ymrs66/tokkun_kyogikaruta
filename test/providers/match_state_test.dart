// test/providers/match_state_test.dart
//
// 実践練習の進行：暗記・読み・同陣ミス・時間切れ境界・中断と再開・保存とギャラリー
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/domain/match_judge.dart';
import 'package:tokkun_kyogikaruta/domain/match_plan.dart';
import 'package:tokkun_kyogikaruta/domain/rank_policy.dart';
import 'package:tokkun_kyogikaruta/providers/match_state.dart';
import 'package:tokkun_kyogikaruta/services/score_repository.dart';

import '../services/score_repository_test.dart' show MemStore;
import 'game_state_test.dart' show FakeClock, FakeAudio, BrokenAudio;

const fb = Duration(milliseconds: 650);
const cd = Duration(seconds: 1);

MatchState newMatch(FakeAsync fa, {int seed = 1}) =>
    MatchState(rng: Random(seed), clockFactory: () => FakeClock(fa));

/// 準備 → 暗記開始
MatchState startMatch(FakeAsync fa, {int memorize = 30, int karafuda = 0, int seed = 1}) {
  final m = newMatch(fa, seed: seed)
    ..start(MatchConfig(memorizeSec: memorize, karafudaPercent: karafuda));
  m.begin();
  return m;
}

/// 受付まで進める（カウントダウン3秒）
void toAccepting(FakeAsync fa, MatchState m) {
  if (m.phase == MatchPhase.memorizing) m.endMemorize();
  if (m.phase == MatchPhase.feedback) fa.elapse(fb);
  fa.elapse(cd * 3);
  expect(m.phase, MatchPhase.accepting);
}

int slotOf(MatchState m) => m.current!.slotIndex!;
int sameSideOther(MatchState m) {
  final t = slotOf(m);
  return m.slots
      .firstWhere((s) => s.side == m.slots[t].side && s.index != t && m.occupied.contains(s.index))
      .index;
}

int oppositeOf(MatchState m) {
  final t = slotOf(m);
  return m.slots.firstWhere((s) => s.side != m.slots[t].side && m.occupied.contains(s.index)).index;
}

/// 残りの読みを、場の札は正解・空札は見送りで終える
void playOut(FakeAsync fa, MatchState m, {int ms = 1000}) {
  while (!m.finished) {
    toAccepting(fa, m);
    fa.elapse(Duration(milliseconds: ms));
    if (m.current!.isKarafuda) {
      m.onPass();
    } else {
      m.onSlotTap(slotOf(m));
    }
    fa.elapse(fb);
  }
}

void main() {
  group('暗記', () {
    test('暗記時間が過ぎると練習へ。使った暗記時間を記録', () {
      fakeAsync((fa) {
        final m = startMatch(fa, memorize: 30);
        expect(m.phase, MatchPhase.memorizing);
        fa.elapse(const Duration(seconds: 29));
        expect(m.phase, MatchPhase.memorizing);
        expect(m.memorizeRemainingMs, inInclusiveRange(750, 1000));
        fa.elapse(const Duration(seconds: 1));
        expect(m.phase, MatchPhase.countdown);
        expect(m.memorizeUsedMs, 30000);
      });
    });

    test('「暗記終了」ですぐ練習へ。二重に押しても1回だけ', () {
      fakeAsync((fa) {
        final m = startMatch(fa, memorize: 60);
        fa.elapse(const Duration(seconds: 12));
        m.endMemorize();
        final seq = m.questionSeq;
        m.endMemorize();
        expect(m.questionSeq, seq);
        expect(m.memorizeUsedMs, 12000);
        expect(m.phase, MatchPhase.countdown);
        fa.elapse(const Duration(seconds: 60)); // 暗記のタイマーが残っていても練習は乱れない
        expect(m.memorizeUsedMs, 12000);
        expect(m.phase, isNot(MatchPhase.memorizing));
        expect(m.readsDone, 4); // 1回あたり 3秒＋10秒＋0.65秒の時間切れが4回
      });
    });

    test('暗記中の中断 → 続ける：残り時間から再開、参考記録にしない', () {
      fakeAsync((fa) {
        final m = startMatch(fa, memorize: 30);
        fa.elapse(const Duration(seconds: 10));
        expect(m.requestPause(), isTrue);
        expect(m.fieldVisible, isFalse); // 札を隠す
        expect(m.pausedDuringMemorize, isTrue);
        fa.elapse(const Duration(seconds: 100)); // 停止中は進まない
        expect(m.phase, MatchPhase.paused);
        m.resume();
        expect(m.phase, MatchPhase.memorizing);
        expect(m.isReference, isFalse);
        fa.elapse(const Duration(seconds: 20));
        expect(m.phase, MatchPhase.countdown);
        expect(m.memorizeUsedMs, 30000);
      });
    });

    test('暗記から練習への切り替えでタイマーが重ならない（暗記終了と時間切れが同時）', () {
      fakeAsync((fa) {
        final m = startMatch(fa, memorize: 30);
        fa.elapse(const Duration(seconds: 30));
        m.endMemorize(); // すでに練習へ移っている
        expect(m.phase, MatchPhase.countdown);
        fa.elapse(cd * 3);
        expect(m.phase, MatchPhase.accepting);
        expect(m.readsDone, 0);
      });
    });
  });

  group('出題と終了', () {
    for (final (percent, total) in [(0, 12), (30, 17), (50, 24)]) {
      test('空札 $percent%：ちょうど $total 回読んで終了、場の札はすべて空白', () {
        fakeAsync((fa) {
          final m = startMatch(fa, karafuda: percent);
          expect(m.totalReads, total);
          final readIds = <int>[];
          while (!m.finished) {
            toAccepting(fa, m);
            readIds.add(m.current!.card.id);
            if (m.current!.isKarafuda) {
              m.onPass();
            } else {
              m.onSlotTap(slotOf(m));
            }
            fa.elapse(fb);
          }
          expect(readIds.length, total);
          expect(readIds.toSet().length, total, reason: '重複なし');
          expect(m.occupied, isEmpty);
          expect(m.stats.taken, 12);
          expect(m.stats.passSuccess, total - 12);
          expect(m.stats.rank, Rank.S);
        });
      });
    }

    test('最後に読まれるのは場の札（空札だけが残って続くことはない）', () {
      for (var seed = 0; seed < 20; seed++) {
        fakeAsync((fa) {
          final m = startMatch(fa, karafuda: 50, seed: seed);
          ReadItem? last;
          while (!m.finished) {
            toAccepting(fa, m);
            last = m.current;
            m.onPass();
            fa.elapse(fb);
          }
          expect(last!.isKarafuda, isFalse);
        });
      }
    });
  });

  group('判定と札の位置', () {
    test('正解：判定表示中は緑の枠で残し、次の読みで空白。ほかの札の位置は変わらない', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        final before = [for (final s in m.slots) (s.index, s.card.id, s.side, s.row, s.col)];
        toAccepting(fa, m);
        final t = slotOf(m);
        m.onSlotTap(t);
        expect(m.lastOutcome, MatchOutcome.correct);
        expect(m.occupied.contains(t), isTrue);
        expect(m.marks[t], SlotMark.taken);
        fa.elapse(fb);
        expect(m.occupied.contains(t), isFalse);
        expect([for (final s in m.slots) (s.index, s.card.id, s.side, s.row, s.col)], before);
      });
    });

    test('取り逃し（時間切れ）：赤い枠で位置を示してから空白', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        final t = slotOf(m);
        fa.elapse(const Duration(seconds: 10));
        expect(m.lastOutcome, MatchOutcome.timeUp);
        expect(m.marks[t], SlotMark.missed);
        expect(m.occupied.contains(t), isTrue);
        fa.elapse(fb);
        expect(m.occupied.contains(t), isFalse);
        expect(m.stats.missed, 1);
      });
    });

    test('同陣ミス：受付を続け、時間はリセットされない。その後に正しい札で正解', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        fa.elapse(const Duration(milliseconds: 1200));
        m.onSlotTap(sameSideOther(m));
        expect(m.phase, MatchPhase.accepting);
        expect(m.showSameSide, isTrue);
        expect(m.stats.sameSide, 1);
        fa.elapse(const Duration(milliseconds: 800));
        m.onSlotTap(slotOf(m));
        expect(m.lastOutcome, MatchOutcome.correct);
        expect(m.lastElapsedMs, 2000, reason: '同陣ミスで計測をやり直さない');
        expect(m.stats.accuracyPercent, 8); // 1枚 ÷ 12
      });
    });

    test('同陣ミスを何回しても減点なし', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        for (var i = 0; i < 4; i++) {
          m.onSlotTap(sameSideOther(m));
        }
        m.onSlotTap(slotOf(m));
        expect(m.stats.sameSide, 4);
        expect(m.stats.otetsuki, 0);
      });
    });

    test('反対の陣：お手つき＋取り逃し、読まれた札は空白に', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        final t = slotOf(m);
        final o = oppositeOf(m);
        m.onSlotTap(o);
        expect(m.lastOutcome, MatchOutcome.oppositeSide);
        expect(m.marks[t], SlotMark.missed);
        expect(m.marks[o], SlotMark.touched);
        fa.elapse(fb);
        expect(m.occupied.contains(t), isFalse);
        expect(m.occupied.contains(o), isTrue, reason: '押した札は残る');
        expect(m.stats.otetsuki, 1);
        expect(m.stats.missed, 1);
      });
    });

    test('場の札で見送り：取り逃し', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        m.onPass();
        expect(m.lastOutcome, MatchOutcome.passOnField);
        expect(m.stats.missed, 1);
      });
    });

    test('空札：見送りで10秒を待たずに次へ、何もしないと10秒で見送り成功、押すとお手つき', () {
      fakeAsync((fa) {
        final m = startMatch(fa, karafuda: 50);
        var pass = 0, wait = 0, touch = 0;
        while (!m.finished && (pass == 0 || wait == 0 || touch == 0)) {
          toAccepting(fa, m);
          if (!m.current!.isKarafuda) {
            m.onSlotTap(slotOf(m));
          } else if (pass == 0) {
            fa.elapse(const Duration(milliseconds: 500));
            m.onPass();
            expect(m.lastOutcome, MatchOutcome.passOk);
            pass++;
          } else if (wait == 0) {
            fa.elapse(const Duration(milliseconds: 9999));
            expect(m.phase, MatchPhase.accepting);
            fa.elapse(const Duration(milliseconds: 1));
            expect(m.lastOutcome, MatchOutcome.waitOk);
            wait++;
          } else {
            m.onSlotTap(m.occupied.first);
            expect(m.lastOutcome, MatchOutcome.karafudaTouched);
            touch++;
          }
          fa.elapse(fb);
        }
        expect(m.stats.passSuccess, 2);
        expect(m.stats.otetsuki, 1);
      });
    });

    test('空白の位置を押しても判定・お手つきにならない', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        final first = slotOf(m);
        m.onSlotTap(first);
        fa.elapse(fb);
        toAccepting(fa, m);
        m.onSlotTap(first); // 空白
        expect(m.phase, MatchPhase.accepting);
        expect(m.readsDone, 1);
        expect(m.stats.otetsuki + m.stats.sameSide, 0);
      });
    });

    test('9.999秒は有効、10秒ちょうどは時間切れ', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        fa.elapse(const Duration(milliseconds: 9999));
        m.onSlotTap(slotOf(m));
        expect(m.lastOutcome, MatchOutcome.correct);
        expect(m.lastElapsedMs, 9999);
        fa.elapse(fb);
        toAccepting(fa, m);
        fa.elapse(const Duration(milliseconds: 10000));
        expect(m.lastOutcome, MatchOutcome.timeUp);
      });
    });

    test('連続タップ・時間切れと同時のタップでも判定は1回', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        final t = slotOf(m);
        m.onSlotTap(t);
        m.onSlotTap(t);
        m.onPass();
        expect(m.readsDone, 1);
        fa.elapse(fb);
        toAccepting(fa, m);
        fa.elapse(const Duration(milliseconds: 10000));
        m.onSlotTap(slotOf(m));
        expect(m.readsDone, 2);
        expect(m.stats.taken, 1);
      });
    });

    test('前の読みの画面からのタップ（古い seq）は無視', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        final oldSeq = m.questionSeq;
        m.onSlotTap(slotOf(m));
        fa.elapse(fb);
        toAccepting(fa, m);
        m.onSlotTap(m.occupied.first, seq: oldSeq);
        expect(m.readsDone, 1);
      });
    });
  });

  group('中断と再開', () {
    test('読みの途中の中断：その読みは取り消して後ろへ入れ直し、配置は同じ。続けると参考記録', () {
      fakeAsync((fa) {
        final m = startMatch(fa, karafuda: 30);
        toAccepting(fa, m);
        m.onSlotTap(sameSideOther(m)); // 同陣ミス1回 → 取り消される
        final interrupted = m.current!;
        final slotsBefore = m.slots;
        final occBefore = {...m.occupied};
        expect(m.requestPause(), isTrue);
        expect(m.fieldVisible, isFalse);
        expect(m.stats.sameSide, 0);
        expect(m.readsDone, 0);
        expect(m.queue.contains(interrupted), isTrue);
        expect(m.queue.length, 17);
        expect(m.queue.last.isKarafuda, isFalse);
        fa.elapse(const Duration(seconds: 30)); // 停止中に時間切れにならない
        expect(m.phase, MatchPhase.paused);
        m.resume();
        expect(m.isReference, isTrue);
        expect(m.slots, same(slotsBefore));
        expect(m.occupied, occBefore);
        expect(m.current, isNot(interrupted), reason: 'すぐに同じ札は読まない');
        playOut(fa, m);
        expect(m.readsDone, 17);
        expect(m.stats.taken, 12);
      });
    });

    test('判定表示中の中断：判定済みの札は空白になり、再出題・再集計しない', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        final t = slotOf(m);
        final id = m.current!.card.id;
        m.onSlotTap(t);
        m.requestPause();
        expect(m.occupied.contains(t), isFalse);
        expect(m.readsDone, 1);
        expect(m.queue.any((r) => r.card.id == id), isFalse);
        m.resume();
        playOut(fa, m);
        expect(m.stats.taken, 12);
        expect(m.readsDone, 12);
      });
    });

    test('最後の読みの判定表示中に中断 → 続ける：二重判定なしで終了（参考記録にしない）', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        while (m.readsDone < 11) {
          toAccepting(fa, m);
          m.onSlotTap(slotOf(m));
          fa.elapse(fb);
        }
        toAccepting(fa, m);
        m.onSlotTap(slotOf(m));
        expect(m.requestPause(), isTrue);
        expect(m.requestPause(), isFalse, reason: '重ねて止めない');
        expect(m.pausedAfterFinalJudgement, isTrue);
        m.resume();
        expect(m.finished, isTrue);
        expect(m.readsDone, 12);
        expect(m.isReference, isFalse);
      });
    });

    test('最後の読みの判定前の中断は「判定確定後」と区別する（続けると参考記録）', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        while (m.readsDone < 11) {
          toAccepting(fa, m);
          m.onSlotTap(slotOf(m));
          fa.elapse(fb);
        }
        toAccepting(fa, m);
        m.requestPause();
        expect(m.pausedAfterFinalJudgement, isFalse);
        m.resume();
        expect(m.isReference, isTrue);
      });
    });

    test('最後の場の札の途中で中断しても、最後のまま読み直す', () {
      fakeAsync((fa) {
        final m = startMatch(fa, karafuda: 30);
        while (m.queue.isNotEmpty) {
          toAccepting(fa, m);
          m.current!.isKarafuda ? m.onPass() : m.onSlotTap(slotOf(m));
          fa.elapse(fb);
        }
        toAccepting(fa, m);
        final last = m.current!;
        m.requestPause();
        expect(m.queue, [last]);
        m.resume();
        toAccepting(fa, m);
        expect(m.current, last);
        m.onSlotTap(slotOf(m));
        fa.elapse(fb);
        expect(m.finished, isTrue);
        expect(m.isReference, isTrue);
      });
    });

    test('終了後・準備前の中断は何もしない', () {
      fakeAsync((fa) {
        final m = newMatch(fa);
        expect(m.requestPause(), isFalse);
        m.start(const MatchConfig(memorizeSec: 30, karafudaPercent: 0));
        expect(m.requestPause(), isFalse); // 画面表示前
      });
    });
  });

  group('音声', () {
    test('読みごとに準備・再生し、判定・中断で止める', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        final audio = FakeAudio();
        m.attachAudio(audio);
        toAccepting(fa, m);
        fa.flushMicrotasks();
        expect(audio.log.where((e) => e.startsWith('prepare')).length, 1);
        expect(audio.log.where((e) => e.startsWith('play')).length, 1);
        m.requestPause();
        fa.flushMicrotasks();
        expect(audio.log.last, 'pause');
      });
    });

    test('音声を再生できないときは audioUnavailable（文字を表示）', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        m.attachAudio(BrokenAudio());
        toAccepting(fa, m);
        fa.flushMicrotasks();
        expect(m.audioUnavailable, isTrue);
      });
    });
  });

  group('保存とギャラリー', () {
    late MemStore store;
    late ScoreRepository repo;
    setUp(() {
      store = MemStore();
      repo = ScoreRepository(store);
    });

    test('結果の保存とギャラリー付与は1回だけ。空札の割合別のキーに保存', () {
      fakeAsync((fa) {
        final m = startMatch(fa, karafuda: 30);
        playOut(fa, m, ms: 1200);
        var grants = 0;
        Future<(int?, bool)> grant(Rank r) async {
          grants++;
          return (3, false);
        }

        late dynamic out1;
        m.finalizeResult(repository: repo, grantGallery: grant).then((o) => out1 = o);
        m.finalizeResult(repository: repo, grantGallery: grant);
        fa.flushMicrotasks();
        expect(grants, 1);
        expect(out1.record.rank, Rank.S);
        expect(out1.save.bestUpdated, isTrue);
        expect(repo.loadMatchBest(30)!.mode, PracticeMode.match);
        expect(repo.loadMatchBest(30)!.memorizeSec, 30);
        expect(repo.loadMatchBest(30)!.totalQuestions, 17);
        expect(repo.loadLast(), isNull, reason: '反応練習の前回には書かない');
      });
    });

    test('参考記録（中断して続けた）は最高記録・ギャラリーの対象外', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        toAccepting(fa, m);
        m.requestPause();
        m.resume();
        playOut(fa, m);
        var grants = 0;
        m.finalizeResult(repository: repo, grantGallery: (r) async {
          grants++;
          return (1, false);
        });
        fa.flushMicrotasks();
        expect(grants, 0);
        expect(repo.loadMatchBest(0), isNull);
        expect(repo.loadMatchLast()!.isReference, isTrue);
      });
    });

    test('同じ配置でもう一度：位置と札は同じ、参考記録', () {
      fakeAsync((fa) {
        final m = startMatch(fa);
        playOut(fa, m);
        final slots = m.slots;
        m.restartSamePlacement();
        expect(m.slots, same(slots));
        expect(m.isReference, isTrue);
        expect(m.occupied.length, 12);
        expect(m.phase, MatchPhase.ready);
        m.begin();
        playOut(fa, m);
        var grants = 0;
        m.finalizeResult(repository: repo, grantGallery: (r) async {
          grants++;
          return (1, false);
        });
        fa.flushMicrotasks();
        expect(grants, 0);
      });
    });

    test('お手つきの減点と記録の値（減点前の取得数・減点数）', () {
      fakeAsync((fa) {
        final m = startMatch(fa, karafuda: 50);
        var touched = false;
        while (!m.finished) {
          toAccepting(fa, m);
          if (m.current!.isKarafuda) {
            if (!touched) {
              m.onSlotTap(m.occupied.first);
              touched = true;
            } else {
              m.onPass();
            }
          } else {
            fa.elapse(const Duration(milliseconds: 1000));
            m.onSlotTap(slotOf(m));
          }
          fa.elapse(fb);
        }
        final r = m.buildRecord();
        expect(r.successCount, 12);
        expect(r.deduction, 1);
        expect(r.accuracy, 92);
        expect(r.rank, Rank.B);
        expect(r.counts['karafudaTouched'], 1);
      });
    });
  });
}
