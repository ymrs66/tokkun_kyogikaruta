// lib/widgets/back_to_home.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 練習以外の画面で、Android の「戻る」（キー・スワイプ）をホームへ戻る操作にする。
///
/// - 画面遷移は `context.go` なので、通常の「戻る」ではアプリが閉じてしまう。それを防ぐ
/// - ダイアログ（ギャラリーの拡大・獲得演出など）が開いているときは、ダイアログを閉じるだけ
/// - go_router 13 は画面が1つのとき PopScope のコールバックを呼ばないので、
///   BackButtonListener で Router より先に受け取る（練習画面と同じ方式）
class BackToHome extends StatelessWidget {
  const BackToHome({super.key, required this.child, this.onBack});

  final Widget child;

  /// 戻るときの処理（省略時はホームへ）
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: BackButtonListener(
        onBackButtonPressed: () async {
          if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
          (onBack ?? () => context.go('/'))();
          return true;
        },
        child: child,
      ),
    );
  }
}

/// ホームへ戻る矢印つきの AppBar
AppBar homeAppBar(BuildContext context, String title, {VoidCallback? onBack}) =>
    AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'ホームへ戻る',
        onPressed: onBack ?? () => context.go('/'),
      ),
      title: Text(title),
    );
