// lib/domain/question_plan.dart
import 'dart:math';

/// 問題の種類。
enum QuestionKind {
  /// 場にある札を読む
  field,

  /// 場にない札（空札）を読む
  karafuda,
}

/// 空札の割合として選べる値（0 = 空札なし）。
const List<int> karafudaPercentOptions = [0, 20, 30, 50];

/// [total] 問のうち空札にする問題数。割合が選択肢にない値なら 0。
int karafudaCountFor({required int percent, required int total}) {
  if (!karafudaPercentOptions.contains(percent)) return 0;
  return (total * percent / 100).round();
}

/// 出題計画（取り札・空札の並び）を開始時に作る。
/// 空札の問題数は割合から決まり（毎回同じ）、順番だけをシャッフルする。
List<QuestionKind> buildQuestionPlan({
  required int total,
  required int karafudaPercent,
  required Random rng,
}) {
  final k = karafudaCountFor(percent: karafudaPercent, total: total);
  return <QuestionKind>[
    for (var i = 0; i < k; i++) QuestionKind.karafuda,
    for (var i = 0; i < total - k; i++) QuestionKind.field,
  ]..shuffle(rng);
}
