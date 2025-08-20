import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'game_state.dart';

final gameProvider =
ChangeNotifierProvider<GameState>((ref) => GameState());