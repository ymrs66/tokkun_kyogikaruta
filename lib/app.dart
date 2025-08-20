// app.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/title_screen.dart';
import 'screens/play_screen.dart';
import 'screens/result_screen.dart';
import 'screens/howto_screen.dart';
import 'screens/highscore_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/gallery_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/',        builder: (_, __) => const TitleScreen()),
    GoRoute(path: '/play',    builder: (_, __) => const PlayScreen()),
    GoRoute(path: '/result',  builder: (_, __) => const ResultScreen()),
    GoRoute(path: '/howto',   builder: (_, __) => const HowToScreen()),
    GoRoute(path: '/score',   builder: (_, __) => const HighScoreScreen()),
    GoRoute(path: '/privacy', builder: (_, __) => const PrivacyScreen()),
    GoRoute(path: '/gallery', builder: (_, __) => const GalleryScreen()),
  ],
);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '競技かるた練習',
      routerConfig: _router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaleFactor.clamp(1.0, 1.3);
        return MediaQuery(
          data: mq.copyWith(textScaleFactor: clamped),
          child: child ?? const SizedBox(),
        );
      },
      theme: ThemeData(useMaterial3: true),
    );
  }
}