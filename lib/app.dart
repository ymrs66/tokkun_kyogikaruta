// app.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/title_screen.dart';
import 'screens/play_screen.dart';
import 'screens/result_screen.dart';
import 'screens/howto_screen.dart';
import 'screens/highscore_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/match_setup_screen.dart';
import 'screens/match_play_screen.dart';
import 'screens/match_result_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/',        builder: (_, _) => const TitleScreen()),
    GoRoute(path: '/play',    builder: (_, _) => const PlayScreen()),
    GoRoute(path: '/result',  builder: (_, _) => const ResultScreen()),
    GoRoute(path: '/howto',   builder: (_, _) => const HowToScreen()),
    GoRoute(path: '/score',   builder: (_, _) => const HighScoreScreen()),
    GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
    GoRoute(path: '/gallery', builder: (_, _) => const GalleryScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    // 実践練習（開始 → 暗記・練習 → 結果）
    GoRoute(path: '/match', builder: (_, _) => const MatchSetupScreen()),
    GoRoute(path: '/match/play', builder: (_, _) => const MatchPlayScreen()),
    GoRoute(path: '/match/result', builder: (_, _) => const MatchResultScreen()),
  ],
);

/// ホーム画面が表示されるまで待つ（すでにホームならすぐ戻る）。
/// 広告の同意フォーム・ATT のダイアログを、練習中に重ねないために使う（main.dart）。
Future<void> waitUntilHome() async {
  bool atHome() => _router.routerDelegate.currentConfiguration.uri.path == '/';
  if (atHome()) return;
  final done = Completer<void>();
  void check() {
    if (atHome() && !done.isCompleted) done.complete();
  }
  _router.routerDelegate.addListener(check);
  try {
    await done.future;
  } finally {
    _router.routerDelegate.removeListener(check);
  }
}

/// テストで画面の位置をホームに戻すため（ルーターはアプリ全体で1つ）
@visibleForTesting
GoRouter get appRouter => _router;

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '競技かるた特訓',
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // 端末の文字サイズ設定は 1.0〜1.3 倍の範囲で反映する（大きすぎるとレイアウトが崩れるため）
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
              textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3)),
          child: child ?? const SizedBox(),
        );
      },
      theme: ThemeData(useMaterial3: true),
    );
  }
}