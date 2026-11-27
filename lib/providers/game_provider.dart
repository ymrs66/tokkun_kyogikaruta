import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../services/audio_service.dart';
import '../services/score_repository.dart';
import 'game_state.dart';
import 'match_state.dart';
import 'settings_provider.dart';

final gameProvider =
ChangeNotifierProvider<GameState>((ref) => GameState());

/// 実践練習の進行
///
/// debug ビルドだけ、起動引数で配置・読み順の乱数を固定できる（エミュレータでの画面確認用）。
///   flutter run --dart-define=DEBUG_MATCH_SEED=42
/// release・profile では [kDebugMode] が false なので使われない。
final matchProvider = ChangeNotifierProvider<MatchState>((ref) {
  const seed = int.fromEnvironment('DEBUG_MATCH_SEED', defaultValue: -1);
  return MatchState(rng: kDebugMode && seed >= 0 ? Random(seed) : null);
});

/// 練習画面で使う読み上げ音声（テストでは差し替える）
final practiceAudioFactoryProvider =
    Provider<PracticeAudio Function()>((ref) => KarutaAudio.new);

/// 成績（最高記録・前回の結果）の保存
final scoreRepositoryProvider = Provider<ScoreRepository>(
  (ref) => ScoreRepository(PrefsKeyValueStore(ref.watch(sharedPrefsProvider))),
);
