// lib/services/score_repository.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/practice_record.dart';

/// 成績の保存先（テストで失敗を再現できるように SharedPreferences を包む）
abstract class KeyValueStore {
  Object? get(String key);
  Future<bool> setString(String key, String value);
  Future<bool> setInt(String key, int value);
  Future<bool> setDouble(String key, double value);
  Future<bool> remove(String key);
  Set<String> get keys;
}

class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore(this._p);
  final SharedPreferences _p;
  @override
  Object? get(String key) => _p.get(key);
  @override
  Future<bool> remove(String key) => _p.remove(key);
  @override
  Set<String> get keys => _p.getKeys();
  @override
  Future<bool> setString(String key, String value) => _p.setString(key, value);
  @override
  Future<bool> setInt(String key, int value) => _p.setInt(key, value);
  @override
  Future<bool> setDouble(String key, double value) => _p.setDouble(key, value);
}

/// 保存の結果
class SaveOutcome {
  const SaveOutcome({
    required this.bestUpdated,
    required this.duplicate,
    required this.failed,
    this.previousBest,
  });

  /// 最高記録を更新した
  final bool bestUpdated;

  /// 同じ練習（sessionId）の結果がすでに保存されていたので、何もしなかった
  final bool duplicate;

  /// 書き込みに失敗した（既存の最高記録はそのまま）
  final bool failed;
  final PracticeRecord? previousBest;
}

/// 最高記録（空札なし／空札あり）と前回の結果の読み書き。
///
/// - 1回の結果の組を1つのキーに JSON で保存する（項目ごとの書き込みで値がずれないように）
/// - 既存のキー（bestRank・bestAccuracy・bestAvgSec）は、空札なしの最高記録として読み、
///   更新したときは JSON の後に同じ値を書き戻す（旧版との互換）
/// - ギャラリー（galleryOwnedIds）・設定（settings.v1.*）には触れない
class ScoreRepository {
  ScoreRepository(this._store);
  final KeyValueStore _store;

  static const keyBestNormal = 'record.v2.best.normal';
  static const keyBestKarafuda = 'record.v2.best.karafuda';
  static const keyLast = 'record.v2.last';
  static const legacyRank = 'bestRank';
  static const legacyAccuracy = 'bestAccuracy';
  static const legacyAvgSec = 'bestAvgSec';

  /// 成績として扱うすべてのキー（Phase 3 の「成績をリセット」で新旧両方を消すため）
  static const allScoreKeys = [
    keyBestNormal,
    keyBestKarafuda,
    keyLast,
    legacyRank,
    legacyAccuracy,
    legacyAvgSec,
  ];

  /// 新しい形式の成績キーの接頭辞（Phase 4 で実践練習の記録を足しても、ここで一緒に消える）
  static const recordPrefix = 'record.v2.';

  /// 成績をリセットする（新旧の成績キーだけ。ギャラリー・設定には触れない）。
  /// 1つでも削除に失敗したら false。
  Future<bool> resetScores() async {
    final targets = <String>{
      ...allScoreKeys,
      ..._store.keys.where((k) => k.startsWith(recordPrefix)),
    };
    var ok = true;
    for (final k in targets) {
      if (_store.get(k) == null) continue;
      if (!await _store.remove(k)) ok = false;
    }
    return ok;
  }

  static String _bestKey(RecordCategory c) =>
      c == RecordCategory.normal ? keyBestNormal : keyBestKarafuda;

  PracticeRecord? _readJson(String key) {
    final raw = _store.get(key);
    if (raw is! String) return null;
    try {
      return PracticeRecord.fromJson(jsonDecode(raw));
    } on FormatException {
      return null; // 壊れていたら「ない」として扱う（呼び出し側でフォールバック）
    }
  }

  PracticeRecord? _readLegacy() {
    final r = _store.get(legacyRank);
    final a = _store.get(legacyAccuracy);
    final s = _store.get(legacyAvgSec);
    return PracticeRecord.fromLegacy(
      rankName: r is String ? r : null,
      accuracy: a is int ? a : null,
      avgSec: s is double ? s : (s is int ? s.toDouble() : null),
    );
  }

  /// 最高記録を読む。空札なしは、JSON がない・壊れているときに既存のキーから読む。
  PracticeRecord? loadBest(RecordCategory category) {
    final json = _readJson(_bestKey(category));
    if (json != null) return json;
    return category == RecordCategory.normal ? _readLegacy() : null;
  }

  /// 前回の結果
  PracticeRecord? loadLast() => _readJson(keyLast);

  /// 1回の結果を保存する。
  Future<SaveOutcome> save(PracticeRecord record) async {
    final last = loadLast();
    if (last != null && last.sessionId == record.sessionId) {
      return const SaveOutcome(bestUpdated: false, duplicate: true, failed: false);
    }

    final current = loadBest(record.category);
    var bestUpdated = false;
    var failed = false;
    if (isNewBest(record, current)) {
      final ok = await _store.setString(
          _bestKey(record.category), jsonEncode(record.toJson()));
      if (ok) {
        bestUpdated = true;
        if (record.category == RecordCategory.normal) {
          // 旧版との互換：JSON を書いた後に既存の3キーへ同じ値を書く
          await _store.setString(legacyRank, record.rank.name);
          await _store.setInt(legacyAccuracy, record.accuracy);
          await _store.setDouble(
              legacyAvgSec, record.avgMs == null ? 0.0 : record.avgMs! / 1000);
        }
      } else {
        failed = true;
      }
    }
    final lastOk = await _store.setString(keyLast, jsonEncode(record.toJson()));
    return SaveOutcome(
      bestUpdated: bestUpdated,
      duplicate: false,
      failed: failed || !lastOk,
      previousBest: current,
    );
  }
}
