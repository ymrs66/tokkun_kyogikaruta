// lib/widgets/background_scaffold.dart
import 'package:flutter/material.dart';

class BackgroundScaffold extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;
  final String backgroundAsset;
  final ImageRepeat backgroundRepeat;
  final BoxFit backgroundFit;
  final AlignmentGeometry backgroundAlignment;
  const BackgroundScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.backgroundAsset = 'assets/images/background.png',
    this.backgroundRepeat = ImageRepeat.repeat, // タイル敷きで必ずフィット
    this.backgroundFit = BoxFit.none,
    this.backgroundAlignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ── AppBar があるときは extendBodyBehindAppBar を OFF ──
      extendBodyBehindAppBar: appBar == null,
      appBar: appBar,
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(backgroundAsset),
            repeat: backgroundRepeat,
            fit: backgroundFit,
            alignment: backgroundAlignment,
          ),
        ),
        // SafeArea で上部文字切れを防止
        child: SafeArea(child: child),
      ),
    );
  }
}
