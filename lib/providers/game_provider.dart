import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../services/audio_service.dart';
import '../services/score_repository.dart';
import 'game_state.dart';
import 'settings_provider.dart';

final gameProvider =
ChangeNotifierProvider<GameState>((ref) => GameState());

/// 練習画面で使う読み上げ音声（テストでは差し替える）
final practiceAudioFactoryProvider =
    Provider<PracticeAudio Function()>((ref) => KarutaAudio.new);

/// 成績（最高記録・前回の結果）の保存
final scoreRepositoryProvider = Provider<ScoreRepository>(
  (ref) => ScoreRepository(PrefsKeyValueStore(ref.watch(sharedPrefsProvider))),
);
