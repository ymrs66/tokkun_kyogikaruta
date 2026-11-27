// lib/providers/match_state.dart
//
// 実践練習（12枚固定）の進行：暗記 → 読み（カウントダウン → 受付 → 判定表示）→ … → 結果。
// 配置・読み順・判定・集計は lib/domain/match_*.dart の純粋なロジックを使う。
//
// - 札の位置は最後まで変わらない。取った札・取り逃した札は判定表示の後に空白にする
// - 同陣ミスは減点なしで受付を続ける（時間の計測は続ける）
// - 一時停止中は札を隠す（画面側）。暗記中の再開は参考記録にしない。読みの途中の再開は参考記録
// - 結果の保存・ギャラリー付与は1回だけ（参考記録は付与しない）
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/cards.dart';
import '../domain/match_judge.dart';
import '../domain/match_plan.dart';
import '../domain/match_stats.dart';
import '../domain/practice_record.dart';
import '../domain/rank_policy.dart';
import '../models/card_data.dart';
import '../services/audio_service.dart';
import '../services/score_repository.dart';
import 'game_state.dart' show ElapsedClock, StopwatchClock, GalleryGrant, ResultOutcome;

enum MatchPhase {
  /// 練習をしていない
  idle,

  /// 準備済み（画面の表示を待っている）
  ready,
  memorizing,
  countdown,
  accepting,
  feedback,
  paused,
  finished,
}

/// 練習開始時に固定する条件
@immutable
class MatchConfig {
  const MatchConfig({
    this.memorizeSec = 60,
    this.karafudaPercent = 30,
    this.timeLimitMs = 10000,
  });
  final int memorizeSec;
  final int karafudaPercent;

  /// 1回の読みの制限時間（読み上げ開始から。暫定10秒）
  final int timeLimitMs;

  int get totalReads => matchTotalReads(karafudaPercent);
}

/// 判定表示で札に付ける枠
enum SlotMark {
  /// 取った（緑）
  taken,

  /// 取り逃した札の位置（赤）
  missed,

  /// 押した札（お手つき・同陣ミス。橙）
  touched,
}

class MatchState extends ChangeNotifier {
  MatchState({
    List<CardData>? cardSet,
    Random? rng,
    ElapsedClock Function()? clockFactory,
    this.feedbackDuration = const Duration(milliseconds: 650),
    this.countdownStep = const Duration(seconds: 1),
    this.sameSideFlash = const Duration(milliseconds: 600),
  })  : _cards = cardSet ?? cards,
        _rng = rng ?? Random(),
        _readClock = (clockFactory ?? StopwatchClock.new)(),
        _memClock = (clockFactory ?? StopwatchClock.new)();

  final List<CardData> _cards;
  final Random _rng;
  final ElapsedClock _readClock;
  final ElapsedClock _memClock;

  /// 判定表示の長さ（取り逃した札の位置を示す時間）
  final Duration feedbackDuration;
  final Duration countdownStep;

  /// 同陣ミスで押した札に枠を付ける時間
  final Duration sameSideFlash;

  // ── 練習の状態 ──
  MatchConfig config = const MatchConfig();
  MatchPhase phase = MatchPhase.idle;
  MatchPhase? _pausedFrom;
  List<MatchSlot> slots = const [];

  /// 札が残っている位置
  final Set<int> occupied = {};
  List<ReadItem> _queue = [];
  ReadItem? current;
  MatchStats stats = MatchStats();

  String sessionId = '';
  int _sessionSeq = 0;

  /// 読みの通し番号（読みの開始・中断のたびに +1。古い入力・タイマー・音声を捨てる）
  int questionSeq = 0;

  /// 判定を終えた読みの数
  int readsDone = 0;
  bool isReference = false;

  /// 同じ配置でもう一度（参考記録）
  bool samePlacement = false;
  bool audioUnavailable = false;

  int countdown = 3;
  int? elapsedSec;

  /// 暗記の残り（ミリ秒）と、実際に使った暗記時間
  int memorizeRemainingMs = 0;
  int? memorizeUsedMs;

  MatchOutcome? lastOutcome;
  int lastOutcomeSeq = 0;
  int? lastElapsedMs;

  /// 判定表示・同陣ミスの枠（位置 → 種類）
  final Map<int, SlotMark> marks = {};

  /// 同陣ミスの表示（中央の情報欄に出す）。回数が変わるたびに +1
  int sameSideSeq = 0;
  bool showSameSide = false;

  int _sameSideThisRead = 0;
  int? _pendingRemoval;

  PracticeAudio? _audio;
  bool _muted = false;

  Timer? _memTick;
  Timer? _memEnd;
  Timer? _countdownTimer;
  Timer? _tickTimer;
  Timer? _timeoutTimer;
  Timer? _feedbackTimer;
  Timer? _sameSideTimer;

  Future<ResultOutcome>? _finalizeFuture;

  int get totalReads => config.totalReads;
  bool get isPaused => phase == MatchPhase.paused;
  bool get finished => phase == MatchPhase.finished;
  bool get canAcceptInput => phase == MatchPhase.accepting;
  bool get pausedDuringMemorize => isPaused && _pausedFrom == MatchPhase.memorizing;

  /// 最後の読みの判定が確定した後に止めた（残りの読みがない）。続けても中断しても通常の記録として結果へ進む
  bool get pausedAfterFinalJudgement =>
      isPaused && _pausedFrom == MatchPhase.feedback && _queue.isEmpty;

  /// 札を見せるか（一時停止中は隠す）
  bool get fieldVisible => phase != MatchPhase.paused && phase != MatchPhase.idle;

  /// 表示中の問番号（1〜総出題数）
  int get readNo =>
      min(readsDone + (phase == MatchPhase.feedback ? 0 : 1), max(1, totalReads));

  /// 残っている札の数
  int get remainingCards => occupied.length;

  @visibleForTesting
  List<ReadItem> get queue => List.unmodifiable(_queue);

  // ── 開始 ──

  /// 新しい配置で練習を準備する（暗記は [begin] で始める）
  void start(MatchConfig cfg) => _prepare(cfg, keepSlots: null, reference: false);

  /// 同じ配置でもう一度（参考記録）
  void restartSamePlacement() {
    if (slots.isEmpty) return;
    _prepare(config, keepSlots: slots, reference: true);
  }

  void _prepare(MatchConfig cfg, {List<MatchSlot>? keepSlots, required bool reference}) {
    _cancelTimers();
    _audioCall((a) => a.stop());
    _sessionSeq++;
    sessionId = 'm${DateTime.now().microsecondsSinceEpoch}-$_sessionSeq';
    config = cfg;
    final plan = buildMatchPlan(
        allCards: _cards, karafudaPercent: cfg.karafudaPercent, rng: _rng, keepSlots: keepSlots);
    slots = plan.slots;
    _queue = [...plan.reads];
    occupied
      ..clear()
      ..addAll(slots.map((s) => s.index));
    current = null;
    stats = MatchStats();
    readsDone = 0;
    isReference = reference;
    samePlacement = reference;
    audioUnavailable = false;
    countdown = 3;
    elapsedSec = null;
    memorizeRemainingMs = cfg.memorizeSec * 1000;
    memorizeUsedMs = null;
    lastOutcome = null;
    lastElapsedMs = null;
    marks.clear();
    showSameSide = false;
    _sameSideThisRead = 0;
    _pendingRemoval = null;
    _pausedFrom = null;
    _finalizeFuture = null;
    _memClock.reset();
    _memClock.stop();
    phase = MatchPhase.ready;
    notifyListeners();
  }

  /// 練習をやめて初期状態に戻す
  void reset() {
    _cancelTimers();
    _audioCall((a) => a.stop());
    _sessionSeq++;
    questionSeq++;
    phase = MatchPhase.idle;
    _pausedFrom = null;
    notifyListeners();
  }

  /// 中断を確定する（記録しない）
  void abort() => reset();

  void attachAudio(PracticeAudio audio) => _audio = audio;
  void detachAudio(PracticeAudio audio) {
    if (identical(_audio, audio)) _audio = null;
  }

  void setMuted(bool muted) {
    _muted = muted;
    _audioCall((a) => a.setMuted(muted));
  }

  void _audioCall(Future<void> Function(PracticeAudio a) op) {
    final a = _audio;
    if (a == null) return;
    try {
      op(a).catchError((Object _) {});
    } catch (_) {}
  }

  // ── 暗記 ──

  /// 暗記を始める（練習画面の表示後）
  void begin() {
    if (phase != MatchPhase.ready) return;
    _startMemorize();
  }

  void _startMemorize() {
    _cancelTimers();
    phase = MatchPhase.memorizing;
    _memClock.start();
    final seq = ++questionSeq;
    _scheduleMemorizeEnd(seq);
    _memTick = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (seq != questionSeq || phase != MatchPhase.memorizing) {
        t.cancel();
        return;
      }
      final remain = max(0, config.memorizeSec * 1000 - _memClock.elapsedMs);
      if ((remain + 999) ~/ 1000 != (memorizeRemainingMs + 999) ~/ 1000) {
        memorizeRemainingMs = remain;
        notifyListeners();
      } else {
        memorizeRemainingMs = remain;
      }
    });
    notifyListeners();
  }

  void _scheduleMemorizeEnd(int seq) {
    _memEnd?.cancel();
    final remain = config.memorizeSec * 1000 - _memClock.elapsedMs;
    _memEnd = Timer(Duration(milliseconds: max(0, remain)), () {
      if (seq != questionSeq || phase != MatchPhase.memorizing) return;
      if (_memClock.elapsedMs < config.memorizeSec * 1000) {
        _scheduleMemorizeEnd(seq);
        return;
      }
      endMemorize();
    });
  }

  /// 暗記を終えて練習を始める（「暗記終了」・時間切れ）。暗記中以外は何もしない（二重に始めない）
  void endMemorize() {
    if (phase != MatchPhase.memorizing) return;
    _memClock.stop();
    memorizeUsedMs = min(_memClock.elapsedMs, config.memorizeSec * 1000);
    memorizeRemainingMs = 0;
    _startRead();
  }

  // ── 1回の読み ──

  void _applyPendingRemoval() {
    final p = _pendingRemoval;
    if (p != null) {
      occupied.remove(p);
      _pendingRemoval = null;
    }
    marks.clear();
  }

  void _startRead() {
    _cancelTimers();
    _applyPendingRemoval();
    showSameSide = false;
    if (_queue.isEmpty) {
      _finish();
      return;
    }
    current = _queue.removeAt(0);
    _sameSideThisRead = 0;
    final seq = ++questionSeq;
    elapsedSec = null;
    lastOutcome = null;
    lastElapsedMs = null;
    countdown = 3;
    phase = MatchPhase.countdown;
    _audioCall((a) => a.prepare(current!.card.id));
    _countdownTimer = Timer.periodic(countdownStep, (t) {
      if (seq != questionSeq || phase != MatchPhase.countdown) {
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
    phase = MatchPhase.accepting;
    elapsedSec = 0;
    _readClock
      ..reset()
      ..start();
    _audioCall((a) async {
      try {
        await a.play(muted: _muted);
      } catch (_) {}
      if (seq == questionSeq && a.preparationFailed && !audioUnavailable) {
        audioUnavailable = true;
        notifyListeners();
      }
    });
    _scheduleTimeout(seq, config.timeLimitMs);
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (seq != questionSeq || phase != MatchPhase.accepting) {
        t.cancel();
        return;
      }
      elapsedSec = _readClock.elapsedMs ~/ 1000;
      notifyListeners();
    });
    notifyListeners();
  }

  void _scheduleTimeout(int seq, int afterMs) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(Duration(milliseconds: max(0, afterMs)), () {
      if (seq != questionSeq || phase != MatchPhase.accepting) return;
      final e = _readClock.elapsedMs;
      if (e < config.timeLimitMs) {
        _scheduleTimeout(seq, config.timeLimitMs - e);
        return;
      }
      _act(const TimeUpMatch(), seq, e);
    });
  }

  /// 札の位置を押した。[seq] は画面が表示していた読みの番号（違えば無視）
  void onSlotTap(int slotIndex, {int? seq}) => _onAction(TapSlot(slotIndex), seq);

  /// 見送りを押した
  void onPass({int? seq}) => _onAction(const PressPassMatch(), seq);

  void _onAction(MatchAction action, int? seq) {
    if (phase != MatchPhase.accepting) return;
    if (seq != null && seq != questionSeq) return;
    final e = _readClock.elapsedMs;
    // 制限時間ちょうど以降の入力は時間切れとして扱う（9999ms は有効、10000ms は時間切れ）
    _act(e >= config.timeLimitMs ? const TimeUpMatch() : action, questionSeq, e);
  }

  void _act(MatchAction action, int seq, int elapsedMs) {
    if (seq != questionSeq || phase != MatchPhase.accepting) return;
    final read = current!;
    final o = judgeMatch(read: read, action: action, slots: slots, occupied: occupied);
    if (o == null) return; // 空白の位置：何も起きない
    final side = read.slotIndex == null ? null : slots[read.slotIndex!].side;

    if (o == MatchOutcome.sameSide) {
      // 減点なし・受付を続ける（時間の計測もそのまま）
      stats.record(o, side: side);
      _sameSideThisRead++;
      final tapped = (action as TapSlot).slotIndex;
      marks[tapped] = SlotMark.touched;
      showSameSide = true;
      final flashSeq = ++sameSideSeq;
      _sameSideTimer?.cancel();
      _sameSideTimer = Timer(sameSideFlash, () {
        if (flashSeq != sameSideSeq || phase != MatchPhase.accepting) return;
        marks.remove(tapped);
        showSameSide = false;
        notifyListeners();
      });
      notifyListeners();
      return;
    }

    phase = MatchPhase.feedback;
    _readClock.stop();
    _cancelTimers();
    _audioCall((a) => a.stop());
    showSameSide = false;
    marks.clear();
    stats.record(o, side: side, elapsedMs: o == MatchOutcome.correct ? elapsedMs : null);
    readsDone++;
    lastOutcome = o;
    lastOutcomeSeq++;
    lastElapsedMs = o == MatchOutcome.correct ? elapsedMs : null;
    elapsedSec = elapsedMs ~/ 1000;
    final target = read.slotIndex;
    if (target != null) {
      marks[target] = o == MatchOutcome.correct ? SlotMark.taken : SlotMark.missed;
      _pendingRemoval = target; // 判定表示の後に空白にする（それまで位置を示す）
    }
    if (action is TapSlot && action.slotIndex != target) {
      marks[action.slotIndex] = SlotMark.touched;
    }
    _feedbackTimer = Timer(feedbackDuration, () {
      if (seq != questionSeq || phase != MatchPhase.feedback) return;
      _startRead();
    });
    notifyListeners();
  }

  void _finish() {
    _cancelTimers();
    _audioCall((a) => a.stop());
    _applyPendingRemoval();
    current = null;
    phase = MatchPhase.finished;
    notifyListeners();
  }

  // ── 中断・再開 ──

  /// 一時停止する（中断ダイアログ・inactive・画面が小さすぎるとき）。新しく止めたときだけ true。
  bool requestPause() {
    switch (phase) {
      case MatchPhase.memorizing:
        _cancelTimers();
        _memClock.stop();
        _pausedFrom = MatchPhase.memorizing;
      case MatchPhase.countdown:
      case MatchPhase.accepting:
      case MatchPhase.feedback:
        _cancelTimers();
        _readClock.stop();
        _audioCall((a) => a.pause());
        _pausedFrom = phase;
        if (phase == MatchPhase.feedback) {
          _applyPendingRemoval(); // 判定済みの札はそのまま空白に（再出題・再集計しない）
        } else {
          // 判定前の読みは取り消し、残りの読み順に入れ直す（同陣ミスの回数も取り消す）
          stats.undoSameSide(_sameSideThisRead);
          _sameSideThisRead = 0;
          _queue = reinsertInterrupted(_queue, current!, _rng);
          marks.clear();
        }
        current = null;
        showSameSide = false;
      default:
        return false;
    }
    questionSeq++; // 止める前の入力・タイマー・音声を無効にする
    phase = MatchPhase.paused;
    notifyListeners();
    return true;
  }

  /// 「続ける」。暗記中なら残り時間から再開（参考記録にしない）。読みの途中なら参考記録にして次の読みへ。
  bool resume() {
    if (phase != MatchPhase.paused) return false;
    if (_pausedFrom == MatchPhase.memorizing) {
      _pausedFrom = null;
      _startMemorize();
      return true;
    }
    _pausedFrom = null;
    // 最後の読みの判定表示中に止めた場合は、取り消した読みがないので参考記録にしない
    if (_queue.isNotEmpty) isReference = true;
    _startRead();
    return true;
  }

  void _cancelTimers() {
    for (final t in [_memTick, _memEnd, _countdownTimer, _tickTimer, _timeoutTimer, _feedbackTimer, _sameSideTimer]) {
      t?.cancel();
    }
    _memTick = _memEnd = _countdownTimer = _tickTimer = _timeoutTimer = _feedbackTimer = _sameSideTimer = null;
  }

  // ── 結果 ──

  PracticeRecord buildRecord() => PracticeRecord(
        mode: PracticeMode.match,
        memorizeSec: config.memorizeSec,
        memorizeUsedSec: memorizeUsedMs == null ? null : (memorizeUsedMs! / 1000).round(),
        rank: stats.rank,
        accuracy: stats.accuracyPercent,
        avgMs: stats.avgTakeMs,
        successCount: stats.taken,
        deduction: min(stats.otetsuki, stats.taken),
        totalQuestions: totalReads,
        karafudaPercent: config.karafudaPercent,
        otetsukiPenalty: true,
        timingVersion: RankPolicy.currentTimingVersion,
        isReference: isReference,
        sessionId: sessionId,
        playedAt: DateTime.now(),
        counts: stats.countsByName(),
      );

  /// 保存とギャラリー付与を1回だけ行う（参考記録は付与しない）
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
          record: record, save: save, grantedGalleryId: granted, completeUnlocked: complete);
    }();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}
