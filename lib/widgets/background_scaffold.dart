// lib/widgets/background_scaffold.dart
import 'package:flutter/material.dart';

class BackgroundScaffold extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;
  const BackgroundScaffold({super.key, required this.child, this.appBar});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ── AppBar があるときは extendBodyBehindAppBar を OFF ──
      extendBodyBehindAppBar: appBar == null,
      appBar: appBar,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            repeat: ImageRepeat.repeat, // タイル敷きで必ずフィット
            fit: BoxFit.none,
          ),
        ),
        // SafeArea で上部文字切れを防止
        child: SafeArea(child: child),
      ),
    );
  }
}
