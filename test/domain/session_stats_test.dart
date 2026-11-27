// test/domain/session_stats_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/domain/session_stats.dart';
import 'package:tokkun_kyogikaruta/domain/verdict.dart';

void main() {
  SessionStats make({bool penalty = false}) =>
      SessionStats(totalQuestions: 10, otetsukiPenalty: penalty);

  test('空札なし：正答率は従来どおり 正解数 / 10', () {
    final s = make();
    for (var i = 0; i < 9; i++) {
      s.record(Verdict.correct, elapsedMs: 1000 + i);
    }
    s.record(Verdict.wrong);
    expect(s.accuracyPercent, 90);
    expect(s.judgedCount, 10);
  });

  test('平均取得時間は正解だけ（見送り時間は別）', () {
    final s = make();
    s.record(Verdict.correct, elapsedMs: 1000);
    s.record(Verdict.correct, elapsedMs: 2001);
    s.record(Verdict.passOk, elapsedMs: 500);
    s.record(Verdict.wrong, elapsedMs: 300);
    expect(s.avgTakeMs, 1501); // (1000+2001)/2 = 1500.5 → 1501
    expect(s.avgPassMs, 500);
  });

  test('正解0回なら平均なし（null）で、0秒とは区別する', () {
    final s = make();
    s.record(Verdict.passOk, elapsedMs: 400);
    s.record(Verdict.missed);
    expect(s.avgTakeMs, isNull);
  });

  group('お手つきペナルティ', () {
    void play(SessionStats s) {
      for (var i = 0; i < 6; i++) {
        s.record(Verdict.correct, elapsedMs: 1200);
      }
      s.record(Verdict.passOk, elapsedMs: 900);
      s.record(Verdict.fault);
      s.record(Verdict.fault);
      s.record(Verdict.noAnswer);
    }

    test('OFF：お手つきは不正解になるだけ', () {
      final s = make();
      play(s);
      expect(s.successCount, 7);
      expect(s.deduction, 0);
      expect(s.finalCorrect, 7);
      expect(s.accuracyPercent, 70);
    });

    test('ON：お手つき1回につき正答1問分を引く', () {
      final s = make(penalty: true);
      play(s);
      expect(s.successCount, 7);
      expect(s.deduction, 2);
      expect(s.finalCorrect, 5);
      expect(s.accuracyPercent, 50);
    });

    test('ON：0 未満にならない', () {
      final s = make(penalty: true);
      for (var i = 0; i < 5; i++) {
        s.record(Verdict.fault);
      }
      s.record(Verdict.passOk, elapsedMs: 100);
      expect(s.finalCorrect, 0);
      expect(s.accuracyPercent, 0);
    });
  });
}
