// test/services/score_repository_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/domain/practice_record.dart';
import 'package:tokkun_kyogikaruta/domain/rank_policy.dart';
import 'package:tokkun_kyogikaruta/services/score_repository.dart';

/// メモリ上の保存先。failKeys に含まれるキーの書き込みは失敗する。
class MemStore implements KeyValueStore {
  final Map<String, Object> data = {};
  final Set<String> failKeys = {};
  @override
  Object? get(String key) => data[key];
  Future<bool> _set(String k, Object v) async {
    if (failKeys.contains(k)) return false;
    data[k] = v;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) => _set(key, value);
  @override
  Future<bool> setInt(String key, int value) => _set(key, value);
  @override
  Future<bool> setDouble(String key, double value) => _set(key, value);
}

int _seq = 0;
PracticeRecord rec({
  Rank rank = Rank.B,
  int accuracy = 90,
  int? avgMs = 2000,
  int karafuda = 0,
  bool reference = false,
  String? session,
}) =>
    PracticeRecord(
      rank: rank,
      accuracy: accuracy,
      avgMs: avgMs,
      successCount: accuracy ~/ 10,
      deduction: 0,
      totalQuestions: 10,
      karafudaPercent: karafuda,
      otetsukiPenalty: false,
      timingVersion: 2,
      isReference: reference,
      sessionId: session ?? 's${_seq++}',
      playedAt: DateTime(2026, 11, 27),
    );

void main() {
  late MemStore store;
  late ScoreRepository repo;
  setUp(() {
    store = MemStore();
    repo = ScoreRepository(store);
  });

  group('既存ユーザーとの互換', () {
    test('既存キーだけのユーザー：旧計測の最高記録として読める', () {
      store.data.addAll(
          {'bestRank': 'A', 'bestAccuracy': 95, 'bestAvgSec': 1.0});
      final b = repo.loadBest(RecordCategory.normal)!;
      expect(b.rank, Rank.A);
      expect(b.accuracy, 95);
      expect(b.avgMs, 1000);
      expect(b.isLegacyTiming, isTrue);
      expect(repo.loadBest(RecordCategory.karafuda), isNull);
    });

    test('下回る結果では既存の記録（既存キー）を書き換えない', () async {
      store.data.addAll(
          {'bestRank': 'A', 'bestAccuracy': 95, 'bestAvgSec': 1.0});
      final o = await repo.save(rec(rank: Rank.B));
      expect(o.bestUpdated, isFalse);
      expect(store.data['bestRank'], 'A');
      expect(store.data['bestAvgSec'], 1.0);
      expect(store.data.containsKey(ScoreRepository.keyBestNormal), isFalse);
      expect(repo.loadLast()!.rank, Rank.B); // 前回の結果は保存
    });

    test('旧計測の記録との比較は +0.5秒（同ランク・同正答率）', () async {
      store.data.addAll(
          {'bestRank': 'S', 'bestAccuracy': 100, 'bestAvgSec': 1.0});
      // 旧 1.0秒 → 比較値 1.5秒。新 1.5秒は同じ → 更新しない
      expect((await repo.save(rec(rank: Rank.S, accuracy: 100, avgMs: 1500)))
          .bestUpdated, isFalse);
      // 新 1.499秒 → 更新
      expect((await repo.save(rec(rank: Rank.S, accuracy: 100, avgMs: 1499)))
          .bestUpdated, isTrue);
      expect(store.data['bestAvgSec'], 1.499);
    });

    test('上回る結果では JSON と既存キーの両方を同じ値に更新', () async {
      store.data.addAll(
          {'bestRank': 'C', 'bestAccuracy': 80, 'bestAvgSec': 3.0});
      final o = await repo.save(rec(rank: Rank.A, accuracy: 95, avgMs: 1800));
      expect(o.bestUpdated, isTrue);
      expect(o.previousBest!.rank, Rank.C);
      expect(store.data['bestRank'], 'A');
      expect(store.data['bestAccuracy'], 95);
      expect(store.data['bestAvgSec'], 1.8);
      expect(repo.loadBest(RecordCategory.normal)!.avgMs, 1800);
    });

    test('ギャラリー・設定のキーには触れない', () async {
      store.data.addAll({
        'galleryOwnedIds': ['8'],
        'settings.v1.soundOn': false,
      });
      await repo.save(rec());
      expect(store.data['galleryOwnedIds'], ['8']);
      expect(store.data['settings.v1.soundOn'], false);
    });
  });

  group('空札なし／空札ありの分離', () {
    test('空札ありの記録は別キー。既存キーは変えない', () async {
      final o = await repo.save(rec(rank: Rank.S, accuracy: 100, karafuda: 30));
      expect(o.bestUpdated, isTrue);
      expect(repo.loadBest(RecordCategory.karafuda)!.rank, Rank.S);
      expect(repo.loadBest(RecordCategory.normal), isNull);
      expect(store.data.containsKey('bestRank'), isFalse);
    });
  });

  group('参考記録・重複', () {
    test('参考記録は最高記録を更新しないが、前回の結果には残る', () async {
      final o = await repo.save(rec(rank: Rank.S, accuracy: 100, reference: true));
      expect(o.bestUpdated, isFalse);
      expect(repo.loadBest(RecordCategory.normal), isNull);
      expect(repo.loadLast()!.isReference, isTrue);
    });

    test('同じ練習（sessionId）は二重に保存しない', () async {
      final r = rec(rank: Rank.C, accuracy: 80, session: 'same');
      expect((await repo.save(r)).duplicate, isFalse);
      final again = await repo.save(rec(rank: Rank.S, accuracy: 100, session: 'same'));
      expect(again.duplicate, isTrue);
      expect(repo.loadBest(RecordCategory.normal)!.rank, Rank.C);
    });
  });

  group('平均なし', () {
    test('平均なし（正解0回）は 0秒として比べない', () async {
      await repo.save(rec(rank: Rank.D, accuracy: 30, avgMs: 9000));
      final o = await repo.save(rec(rank: Rank.D, accuracy: 30, avgMs: null));
      expect(o.bestUpdated, isFalse);
      expect(repo.loadBest(RecordCategory.normal)!.avgMs, 9000);
    });
    test('平均なしの最高記録は既存キーに 0.0 を書くが、読み戻しは平均なし', () async {
      await repo.save(rec(rank: Rank.D, accuracy: 0, avgMs: null));
      expect(store.data['bestAvgSec'], 0.0);
      expect(repo.loadBest(RecordCategory.normal)!.avgMs, isNull);
    });
  });

  group('異常系', () {
    test('JSON が壊れていたら既存キーにフォールバック', () {
      store.data.addAll({
        ScoreRepository.keyBestNormal: '{broken',
        'bestRank': 'B',
        'bestAccuracy': 90,
        'bestAvgSec': 2.0,
      });
      expect(repo.loadBest(RecordCategory.normal)!.rank, Rank.B);
    });

    test('JSON の値が不正（範囲外）でもフォールバック', () {
      final bad = rec(rank: Rank.S).toJson()..['accuracy'] = 999;
      store.data.addAll({
        ScoreRepository.keyBestNormal: jsonEncode(bad),
        'bestRank': 'C',
        'bestAccuracy': 80,
        'bestAvgSec': 3.0,
      });
      expect(repo.loadBest(RecordCategory.normal)!.rank, Rank.C);
    });

    test('最高記録の書き込みに失敗しても既存の記録は残る', () async {
      await repo.save(rec(rank: Rank.B));
      store.failKeys.add(ScoreRepository.keyBestNormal);
      final o = await repo.save(rec(rank: Rank.S, accuracy: 100, avgMs: 1000));
      expect(o.failed, isTrue);
      expect(o.bestUpdated, isFalse);
      expect(repo.loadBest(RecordCategory.normal)!.rank, Rank.B);
      expect(store.data['bestRank'], 'B'); // 既存キーも書き換えない
    });
  });

  test('成績のキー一覧に新旧の両方が含まれる（Phase 3 のリセット用）', () {
    expect(ScoreRepository.allScoreKeys,
        containsAll(['bestRank', 'bestAccuracy', 'bestAvgSec',
          'record.v2.best.normal', 'record.v2.best.karafuda', 'record.v2.last']));
  });
}
