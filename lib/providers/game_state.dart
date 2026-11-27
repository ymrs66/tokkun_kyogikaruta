// lib/providers/game_state.dart
//
// 反応練習の進行（1問：準備 → カウントダウン → 受付 → 判定 → 判定表示）。
// 判定・出題・集計・ランクは lib/domain/ の純粋なロジックを使う。
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/cards.dart';
import '../domain/field_deck.dart';
import '../domain/judge.dart';
import '../domain/practice_record.dart';
import '../domain/question_plan.dart';
import '../domain/rank_policy.dart';
import '../domain/session_stats.dart';
import '../domain/verdict.dart';
import '../models/card_data.dart';
import '../models/game_config.dart';
import '../services/audio_service.dart';
import '../services/score_repository.dart';

// 既存コード（ギャラリー・成績画面など）は game_state.dart から Rank / calcRank を参照している
export '../domain/rank_policy.dart' show Rank, calcRank;

/// 1問の状態
enum PlayPhase {
  /// 開始前（練習画面の表示を待っている）
  ready,
  countdown,
  accepting,
  feedback,
  paused,
  finished,

  /// 練習をしていない（リセット後・中断後）
  idle,
}

/// 経過時間の計測（テストで差し替える）
abstract class ElapsedClock {
  void start();
  void stop();
  void reset();
  int get elapsedMs;
}

class StopwatchClock implements ElapsedClock {
  final Stopwatch _sw = Stopwatch();
  @override
  void start() => _sw.start();
  @override
  void stop() => _sw.stop();
  @override
  void reset() => _sw.reset();
  @override
  int get elapsedMs => _sw.elapsedMilliseconds;
}

/// ギャラリーの付与（結果画面から渡す）。戻り値：(付与した画像の番号, コンプリートを今回解禁したか)
typedef GalleryGrant = Future<(int?, bool)> Function(Rank rank);

/// 練習結果の確定（保存・ギャラリー付与）の結果
class ResultOutcome {
  const ResultOutcome({
    required this.record,
    required this.save,
    required this.grantedGalleryId,
    required this.completeUnlocked,
  });
  final PracticeRecord record;
  final SaveOutcome save;
  final int? grantedGalleryId;
  final bool completeUnlocked;
}

class GameState extends ChangeNotifier {
  GameState({
    List<CardData>? cardSet,
    Random? rng,
    ElapsedClock? clock,
    this.feedbackDuration = const Duration(milliseconds: 650),
    this.countdownStep = const Duration(seconds: 1),
  })  : _cards = cardSet ?? cards,
        _rng = rng ?? Random(),
        _clock = clock ?? StopwatchClock() {
    _setup(const GameConfig());
    phase = PlayPhase.idle;
  }

  /// 反応練習の問題数（既存コード互換）
  static const int maxRound = 10;

  final List<CardData> _cards;
  final Random _rng;
  final ElapsedClock _clock;
  final Duration feedbackDuration;
  final Duration countdownStep;

  // ── 練習の状態 ──
  GameConfig config = const GameConfig();
  PlayPhase phase = PlayPhase.idle;
  late FieldDeck _deck;
  late List<QuestionKind> _plan;
  late SessionStats stats;

  /// 練習の識別子（開始のたびに変わる。古い処理の混入防止・重複保存の防止）
  String sessionId = '';
  int _sessionSeq = 0;

  /// 問題の通し番号（準備・出し直しのたびに +1。古い入力・タイマー・音声を捨てる）
  int questionSeq = 0;

  /// 判定済みの問題数（0〜10）
  int round = 0;

  /// 中断から「続ける」を選んだ練習（参考記録）
  bool isReference = false;

  /// 読み上げ音声を再生できなかった（この練習中は上の句の文字を必ず表示する）
  bool audioUnavailable = false;

  CardData? _current;
  QuestionKind? _currentKind;
  (CardData, QuestionKind)? _pendingRetire; // 判定表示が終わってから場を整える

  /// カウントダウンの表示（3,2,1）
  int countdown = 3;

  /// 「読みはじめから N 秒」。カウントダウン中・準備中は null（「—」と表示）
  int? elapsedSec;

  /// 直前の判定（判定表示用）
  Verdict? lastVerdict;
  int? lastElapsedMs;
  int lastVerdictSeq = -1;

  /// 判定表示中に強調する札（取り札の問題で正解できなかったときの出札）
  int? highlightCardId;

  PracticeAudio? _audio;
  bool _muted = false;

  Timer? _countdownTimer;
  Timer? _tickTimer;
  Timer? _timeoutTimer;
  Timer? _feedbackTimer;

  Future<ResultOutcome>? _finalizeFuture;

  // ── 既存コード互換の読み取り ──
  List<CardData> get selfCards => _deck.selfCards;
  List<CardData> get enemyCards => _deck.enemyCards;
  CardData get current => _current ?? _deck.field.first;
  QuestionKind? get currentKind => _currentKind;
  bool get finished => phase == PlayPhase.finished;
  int get correct => stats.count(Verdict.correct);
  int get totalQuestions => config.totalQuestions;
  bool get isPaused => phase == PlayPhase.paused;
  bool get canAcceptInput => phase == PlayPhase.accepting;

  /// 残りの計画（判定前の問題を含む）
  int get _remainingKarafuda =>
      _plan.skip(round).where((k) => k == QuestionKind.karafuda).length;
  int get _remainingField =>
      _plan.skip(round).where((k) => k == QuestionKind.field).length;

  void _setup(GameConfig cfg) {
    config = cfg;
    _plan = buildQuestionPlan(
        total: cfg.totalQuestions,
        karafudaPercent: cfg.karafudaPercent,
        rng: _rng);
    _deck = FieldDeck(allCards: _cards, rng: _rng);
    stats = SessionStats(
        totalQuestions: cfg.totalQuestions, otetsukiPenalty: cfg.otetsukiPenalty);
    round = 0;
    isReference = false;
    audioUnavailable = false;
    _current = null;
    _currentKind = null;
    _pendingRetire = null;
    elapsedSec = null;
    lastVerdict = null;
    lastElapsedMs = null;
    highlightCardId = null;
    countdown = 3;
    _finalizeFuture = null;
  }

  /// 出題計画（テスト用）
  @visibleForTesting
  List<QuestionKind> get plan => List.unmodifiable(_plan);

  /// 練習を準備する（タイトル画面の「スタート」）。音声とカウントダウンは [begin] で始める。
  void startGame([GameConfig cfg = const GameConfig()]) {
    _cancelTimers();
    _sessionSeq++;
    sessionId = '${DateTime.now().microsecondsSinceEpoch}-$_sessionSeq';
    _setup(cfg);
    phase = PlayPhase.ready;
    _current = _deck.draw(_plan[0]);
    _currentKind = _plan[0];
    notifyListeners();
  }

  /// 練習をやめて初期状態に戻す（結果画面の「スタートへ戻る」・中断の確定）
  void resetGame() {
    _cancelTimers();
    _audioCall((a) => a.stop());
    _sessionSeq++;
    _setup(config);
    phase = PlayPhase.idle;
    notifyListeners();
  }

  /// 練習画面が表示されたら音声をつなぐ
  void attachAudio(PracticeAudio audio) => _audio = audio;

  /// 練習画面を閉じるとき（音声の解放は画面側）
  void detachAudio(PracticeAudio audio) {
    if (identical(_audio, audio)) _audio = null;
  }

  /// 1問目を始める（練習画面の表示後）
  void begin() {
    if (phase != PlayPhase.ready) return;
    _startQuestion(drawNew: false);
  }

  void setMuted(bool muted) {
    _muted = muted;
    _audioCall((a) => a.setMuted(muted));
  }

  /// 音声の操作は待たずに進める。失敗（例外）しても練習の進行は止めない。
  void _audioCall(Future<void> Function(PracticeAudio a) op) {
    final a = _audio;
    if (a == null) return;
    try {
      op(a).catchError((Object _) {});
    } catch (_) {}
  }

  // ── 1問の流れ ──

  void _startQuestion({bool drawNew = true}) {
    _cancelTimers();
    final pending = _pendingRetire;
    if (pending != null) {
      _deck.retire(pending.$1, pending.$2,
          reserveForKarafuda: _remainingKarafuda);
      _pendingRetire = null;
    }
    if (round >= totalQuestions) {
      _finish();
      return;
    }
    if (drawNew) {
      final kind = _plan[round];
      final card = _deck.draw(kind);
      if (card == null) {
        // 札が足りない（通常は起きない）：ここで終える
        _finish();
        return;
      }
      _current = card;
      _currentKind = kind;
    }
    questionSeq++;
    final seq = questionSeq;
    elapsedSec = null; // B10：前の問題の秒数を残さない
    lastVerdict = null;
    lastElapsedMs = null;
    highlightCardId = null;
    countdown = 3;
    phase = PlayPhase.countdown;
    _audioCall((a) => a.prepare(_current!.id));
    _countdownTimer = Timer.periodic(countdownStep, (t) {
      if (seq != questionSeq || phase != PlayPhase.countdown) {
        t.cancel();
        return;
      }
      countdown -= 1;
      if (countdown <= 0) {
        t.cancel();
        _beginAccepting(seq);
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void _beginAccepting(int seq) {
    if (seq != questionSeq) return;
    phase = PlayPhase.accepting;
    elapsedSec = 0;
    _clock
      ..reset()
      ..start();
    _audioCall((a) async {
      try {
        await a.play(muted: _muted);
      } catch (_) {}
      // 音声の読み込みに失敗していたら、文字で問題が分かるようにする
      if (seq == questionSeq && a.preparationFailed && !audioUnavailable) {
        audioUnavailable = true;
        notifyListeners();
      }
    });
    _scheduleTimeout(seq, config.timeLimitMs);
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (seq != questionSeq || phase != PlayPhase.accepting) {
        t.cancel();
        return;
      }
      elapsedSec = _clock.elapsedMs ~/ 1000;
      notifyListeners();
    });
    notifyListeners();
  }

  void _scheduleTimeout(int seq, int afterMs) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(Duration(milliseconds: max(0, afterMs)), () {
      if (seq != questionSeq || phase != PlayPhase.accepting) return;
      // Timer の呼ばれる順番に頼らず、実際の経過時間で判断する
      final e = _clock.elapsedMs;
      if (e < config.timeLimitMs) {
        _scheduleTimeout(seq, config.timeLimitMs - e);
        return;
      }
      _judge(const TimeUp(), seq, e);
    });
  }

  /// 札を押した。[seq] は画面が表示していた問題の番号（違えば無視）
  void onCardTap(int cardId, {int? seq}) => _onAction(TapCard(cardId), seq);

  /// 見送りを押した
  void onPass({int? seq}) => _onAction(const PressPass(), seq);

  void _onAction(PlayerAction action, int? seq) {
    if (phase != PlayPhase.accepting) return; // カウントダウン中・判定表示中・一時停止中は無視
    if (seq != null && seq != questionSeq) return; // 古い問題への入力
    final e = _clock.elapsedMs;
    // 制限時間ちょうど以降の入力は時間切れとして扱う（9999ms は有効、10000ms は時間切れ）
    _judge(e >= config.timeLimitMs ? const TimeUp() : action, questionSeq, e);
  }

  /// 判定（1問につき1回だけ）
  void _judge(PlayerAction action, int seq, int elapsedMs) {
    if (seq != questionSeq || phase != PlayPhase.accepting) return;
    phase = PlayPhase.feedback;
    _clock.stop();
    _cancelTimers();
    _audioCall((a) => a.stop());

    final card = _current!;
    final kind = _currentKind!;
    final v = judgeNormal(
      isKarafuda: kind == QuestionKind.karafuda,
      action: action,
      currentCardId: card.id,
      timeoutPolicy: config.timeoutPolicy,
    );
    final timed = action is! TimeUp;
    stats.record(v, elapsedMs: timed ? elapsedMs : null);
    round++;
    lastVerdict = v;
    elapsedSec = elapsedMs ~/ 1000; // 判定した時点の秒数を表示（時間切れなら 10）
    lastElapsedMs = (timed && v.isSuccess) ? elapsedMs : null;
    lastVerdictSeq = seq;
    highlightCardId =
        (kind == QuestionKind.field && v != Verdict.correct) ? card.id : null;
    _pendingRetire = (card, kind); // 判定表示中は札の位置を変えない
    _feedbackTimer = Timer(feedbackDuration, () {
      if (seq != questionSeq || phase != PlayPhase.feedback) return;
      _startQuestion();
    });
    notifyListeners();
  }

  void _finish() {
    _cancelTimers();
    _audioCall((a) => a.stop());
    final pending = _pendingRetire;
    if (pending != null) {
      _deck.retire(pending.$1, pending.$2, reserveForKarafuda: 0);
      _pendingRetire = null;
    }
    phase = PlayPhase.finished;
    notifyListeners();
  }

  // ── 中断・再開 ──

  /// 一時停止する（中断ダイアログ・バックグラウンド化）。新しく止めたときだけ true。
  bool requestPause() {
    if (phase != PlayPhase.countdown &&
        phase != PlayPhase.accepting &&
        phase != PlayPhase.feedback) {
      return false;
    }
    _cancelTimers();
    _clock.stop();
    _audioCall((a) => a.pause());
    // 判定済みの札・読みかけの札は、ここで使用済みにする（同じ札では読み直さない）
    final pending = _pendingRetire;
    if (pending != null) {
      _deck.retire(pending.$1, pending.$2,
          reserveForKarafuda: _remainingKarafuda);
      _pendingRetire = null;
    }
    if (phase == PlayPhase.countdown || phase == PlayPhase.accepting) {
      _deck.retire(_current!, _currentKind!,
          reserveForKarafuda: _remainingKarafuda);
    }
    questionSeq++; // 止める前の入力・タイマー・音声を無効にする
    phase = PlayPhase.paused;
    notifyListeners();
    return true;
  }

  /// 残りの出題計画を続けられるだけの札があるか（実際の山札・場の残数から判断）
  bool get canResume {
    if (phase != PlayPhase.paused) return false;
    if (round >= totalQuestions) return true;
    return _deck.canServe(
        remainingField: _remainingField, remainingKarafuda: _remainingKarafuda);
  }

  /// 「続ける」：同じ種類の別の札で、カウントダウンから出し直す。参考記録になる。
  bool resume() {
    if (!canResume) return false;
    isReference = true;
    _startQuestion(); // round は進めない（中断した問題は判定していない）
    return true;
  }

  /// 「中断する」：タイマー・音声を止めて練習を終える（成績は保存しない）
  void abort() => resetGame();

  void _cancelTimers() {
    _countdownTimer?.cancel();
    _tickTimer?.cancel();
    _timeoutTimer?.cancel();
    _feedbackTimer?.cancel();
    _countdownTimer = _tickTimer = _timeoutTimer = _feedbackTimer = null;
  }

  // ── 結果の確定 ──

  /// この練習の結果
  PracticeRecord buildRecord() => PracticeRecord(
        rank: calcRank(stats.accuracyPercent, stats.avgTakeMs),
        accuracy: stats.accuracyPercent,
        avgMs: stats.avgTakeMs,
        successCount: stats.successCount,
        deduction: stats.deduction,
        totalQuestions: totalQuestions,
        karafudaPercent: config.karafudaPercent,
        otetsukiPenalty: config.otetsukiPenalty,
        timingVersion: RankPolicy.currentTimingVersion,
        isReference: isReference,
        sessionId: sessionId,
        playedAt: DateTime.now(),
        counts: stats.countsByName(),
      );

  /// 保存とギャラリー付与を1回だけ行う（結果画面が作り直されても重複しない）。
  /// 参考記録はギャラリーを付与しない。
  Future<ResultOutcome> finalizeResult({
    required ScoreRepository repository,
    required GalleryGrant grantGallery,
  }) {
    return _finalizeFuture ??= () async {
      final record = buildRecord();
      final save = await repository.save(record);
      int? granted;
      var complete = false;
      if (!record.isReference && !save.duplicate) {
        (granted, complete) = await grantGallery(record.rank);
      }
      return ResultOutcome(
        record: record,
        save: save,
        grantedGalleryId: granted,
        completeUnlocked: complete,
      );
    }();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }

  bool _disposed = false;

  /// 破棄後に呼ばれても（画面を閉じた後の後始末など）例外にしない
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}
