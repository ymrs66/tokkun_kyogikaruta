// lib/data/reward_catalog.dart
import '../providers/game_state.dart'; // Rank を使う

class RewardCatalog {
  // 未取得枠
  static const String hatena = 'assets/images/gallery/hatena.png';

  // コンプリート画像
  static const String completeImage = 'assets/images/gallery/complete.png';

  /// ギャラリーの固定スロット（インデックスが位置を表す）
  /// 例: Sが2枚, Aが2枚, ... Dが2枚, 最後がコンプリート
  static const List<String> slots = [
    'assets/images/gallery/S_01.png', // 0
    'assets/images/gallery/S_02.png', // 1
    'assets/images/gallery/A_01.png', // 2
    'assets/images/gallery/A_02.png', // 3
    'assets/images/gallery/B_01.png', // 4
    'assets/images/gallery/B_02.png', // 5
    'assets/images/gallery/C_01.png', // 6
    'assets/images/gallery/C_02.png', // 7
    'assets/images/gallery/D_01.png', // 8
    'assets/images/gallery/D_02.png', // 9
    completeImage,                    // 10 = コンプリート枠
  ];

  static const int completeIndex = 10;

  // ランク→スロット位置
  static const Map<Rank, List<int>> byRank = {
    Rank.S: [0, 1],
    Rank.A: [2, 3],
    Rank.B: [4, 5],
    Rank.C: [6, 7],
    Rank.D: [8, 9],
  };

  // 旧コードが参照しているシンプルな別名
  static List<int> get sIndices => byRank[Rank.S]!;
  static List<int> get aIndices => byRank[Rank.A]!;
  static List<int> get bIndices => byRank[Rank.B]!;
  static List<int> get cIndices => byRank[Rank.C]!;
  static List<int> get dIndices => byRank[Rank.D]!;

  // コンプリート条件: 全ランク画像が揃っている
  static bool isComplete(Set<int> owned) {
    for (final group in byRank.values) {
      for (final i in group) {
        if (!owned.contains(i)) return false;
      }
    }
    return true;
  }

  // index -> 表示名（S-1 / A-2 / ... / コンプリート）
  static String labelOf(int index) {
    if (index == completeIndex) return 'コンプリート';
    for (final entry in byRank.entries) {
      final pos = entry.value.indexOf(index);
      if (pos != -1) {
        final n = pos + 1;
        return '${entry.key.name}-$n'; // 例: S-1, D-2
      }
    }
    return '#${index + 1}';
  }

  // 通常スロット(= コンプリート以外)
  static List<int> get normalIndices =>
      List<int>.generate(slots.length - 1, (i) => i);
}
