import 'dart:async';
import 'dart:math';
import '../data/cards.dart';
import '../models/card_data.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Rank { S, A, B, C, D }

Rank calcRank(int accuracy, double avgSec) {
  // 速いほど上：avgSec は小さいほど良い
  if (accuracy == 100 && avgSec <= 0.5) return Rank.S;
  if (accuracy >= 95 && avgSec <= 1.0) return Rank.A;
  if (accuracy >= 90 && avgSec <= 2.0) return Rank.B;
  if (accuracy >= 80 && avgSec <= 3.0) return Rank.C;
  return Rank.D;
}

class GameState extends ChangeNotifier {
  final _rng = Random();
  bool finished = false;           // ゲーム終了フラグ

  // 公開プロパティ
  late List<CardData> selfCards, enemyCards;
  late CardData current;
  int score = 0;
  int remainingTime = 10;            // UIに残秒を出したい場合用
  int elapsedSec    = 0;             // 読みはじめからの経過秒（UI表示用）

  static const int maxRound = 10;

  int round = 0;               // 何問目か (1〜10)
  int correct = 0;             // 正解数
  int wrong   = 0;             // 誤タップ数 ※タイムアップは wrong に含めない
  int totalSec = 0;            // 正解に要した秒数合計 (10 秒 - remainingTime)

  // 内部
  late List<CardData> _deck;          // ← _remaining をリネーム
  Timer? _phaseTimer;                 // 上下句 10 秒用
  DateTime _startAt = DateTime.now();

  bool _started = false;
  GameState() {
    _prepareDeck();        // 山札だけ用意、タイマーは動かさない
  }

  void startGame() {
    if (_started) return;
    _started = true;
    finished    = false;
    score       = round = correct = wrong = totalSec = 0;
    elapsedSec  = 0;

    _prepareDeck();
    _nextRound();          // ← ここで初めてタイマーが動く
  }

  void _prepareDeck() {
    _deck = List<CardData>.from(cards)..shuffle(_rng);
  }

  /* 6枚場札を作って current を決める */
  void _nextRound() {
    if (_deck.length < 6) {
      finished = true;                // デッキ不足＝終了
      _phaseTimer?.cancel();
      notifyListeners();
      return;
    }

    current = _deck.removeLast();
    _deck.shuffle(_rng);
    final wrong5 = _deck.take(5).toList();
    _deck.removeRange(0, 5);

    final List<CardData> pool = [...wrong5, current]..shuffle(_rng);
    selfCards  = pool.sublist(0, 3);
    enemyCards = pool.sublist(3);

    notifyListeners();
  }

  String rollingMsg = '';     // 表示するメッセージ
  int countdown = 0;          // 3,2,1,0 で 0 の時に流れ開始

  /// true=正解, false=誤答
  bool tap(CardData tapped) {
    final tookSec = 10 - remainingTime;
    final isCorrect = tapped == current;

    if (isCorrect) {
      correct++;
      totalSec += tookSec;
    } else {
      wrong++;
    }

    _phaseTimer?.cancel();
    _goNextSong();            // 次問題へ
    return isCorrect;
  }

  void _startPhaseTimer() {
    _phaseTimer?.cancel();
    remainingTime = 10;
    elapsedSec    = 0;
    _startAt = DateTime.now();

    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      elapsedSec    = DateTime.now().difference(_startAt).inSeconds;
      if (elapsedSec < 0) elapsedSec = 0;
      remainingTime = 10 - elapsedSec;
      if (remainingTime <= 0) {
        t.cancel();
        _handleTimeUp();
      }
      notifyListeners();
    });
  }

  void _handleTimeUp() {
    wrong++;                  // お手付き扱い
    _goNextSong();
  }

  void _goNextSong() {
    round++;                              // 進捗更新
    if (round >= maxRound) {
      finished = true;                 // 10 問終了
      _phaseTimer?.cancel();
      _saveHighScore();
      notifyListeners();
      return;
    }

    selfCards.remove(current);
    enemyCards.remove(current);
    if (_deck.isNotEmpty) {
      (selfCards.length < 3 ? selfCards : enemyCards)
          .add(_deck.removeLast());
    }

    // 新しい並べ替え（自陣⇔敵陣も再シャッフルでOK）
    final List<CardData> pool = [...selfCards, ...enemyCards]..shuffle(_rng);
    selfCards  = pool.sublist(0, 3);
    enemyCards = pool.sublist(3);

    current = pool[_rng.nextInt(6)];
    notifyListeners();
  }

  /// 3,2,1 のカウントが 0 になった瞬間に呼び出す
  void startMeasurement() {
    _startPhaseTimer();
  }

  Future<void> _saveHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    final accuracy = (correct / maxRound * 100).round();
    final avgSec   = correct == 0 ? 0.0 : totalSec / correct;
    final rank     = calcRank(accuracy, avgSec).name;
    // 例： accuracy と avgSec も保存しておく
    await prefs.setInt ('bestAccuracy', accuracy);
    await prefs.setDouble('bestAvgSec', avgSec.toDouble());
    await prefs.setString('bestRank', rank);
  }

  void resetGame() {
    _phaseTimer?.cancel();
    _started = false;
    finished = false;
    score = round = correct = wrong = totalSec = 0;
    elapsedSec = 0;
    _prepareDeck();        // 次回 startGame まで待機
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    super.dispose();
  }
}

