// lib/domain/field_deck.dart
import 'dart:math';

import '../models/card_data.dart';
import 'question_plan.dart';

/// 反応練習の場（6枚）と山札の管理。Flutter に依存しない。
///
/// - 読んだ札・読みかけて中断した札は「使用済み」にし、二度と読まない
/// - 取り札の問題：場から1枚を選ぶ。判定後（または中断して出し直すとき）に場から外し、
///   山札から1枚補充する（残りの空札の分は山札に残しておく）
/// - 空札の問題：山札から1枚取り出す（場にも使用済みにも含まれない札）
class FieldDeck {
  FieldDeck({
    required List<CardData> allCards,
    required Random rng,
    this.fieldSize = 6,
  }) : _rng = rng {
    _deck = List<CardData>.of(allCards)..shuffle(_rng);
    while (_field.length < fieldSize && _deck.isNotEmpty) {
      _field.add(_deck.removeLast());
    }
    _relayout();
  }

  final int fieldSize;
  final Random _rng;
  late final List<CardData> _deck;
  final List<CardData> _field = [];
  final Set<int> _usedIds = {};

  List<CardData> _self = const [];
  List<CardData> _enemy = const [];

  /// 自陣（見た目だけ。手前の3枚）
  List<CardData> get selfCards => _self;

  /// 敵陣（見た目だけ。奥の3枚）
  List<CardData> get enemyCards => _enemy;

  /// 場の札
  List<CardData> get field => List.unmodifiable(_field);

  /// 山札の残り
  int get deckRemaining => _deck.length;

  /// 使用済み（読んだ・読みかけた）札の ID
  Set<int> get usedIds => Set.unmodifiable(_usedIds);

  /// 次に読む札を選ぶ。選べないときは null。
  CardData? draw(QuestionKind kind) {
    switch (kind) {
      case QuestionKind.field:
        if (_field.isEmpty) return null;
        return _field[_rng.nextInt(_field.length)];
      case QuestionKind.karafuda:
        if (_deck.isEmpty) return null;
        return _deck.removeLast(); // 場にも使用済みにもない札
    }
  }

  /// 読み終えた（または読みかけて出し直す）札を使用済みにし、場を整える。
  /// [reserveForKarafuda]：残りの空札の問題のために山札に残しておく枚数。
  void retire(
    CardData card,
    QuestionKind kind, {
    required int reserveForKarafuda,
  }) {
    _usedIds.add(card.id);
    if (kind == QuestionKind.field) {
      _field.removeWhere((c) => c.id == card.id);
      if (_deck.length > reserveForKarafuda) {
        _field.add(_deck.removeLast());
      }
    }
    _relayout();
  }

  /// 残りの出題計画（[remainingField] 問の取り札・[remainingKarafuda] 問の空札）を
  /// 出せるだけの札があるか。中断から出し直すときの判定に使う。
  bool canServe({required int remainingField, required int remainingKarafuda}) {
    if (remainingField > 0 && _field.isEmpty) return false;
    final needFromDeck =
        remainingKarafuda + max(0, remainingField - _field.length);
    return _deck.length >= needFromDeck;
  }

  /// 場の並び替え（反応練習は毎問並べ替える：既存の仕様）
  void _relayout() {
    final pool = List<CardData>.of(_field)..shuffle(_rng);
    final half = (pool.length / 2).ceil();
    _self = pool.sublist(0, min(3, half));
    _enemy = pool.sublist(_self.length);
  }
}
