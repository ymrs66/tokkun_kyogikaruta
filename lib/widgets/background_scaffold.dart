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
        // 背景は中身の高さに関係なく画面いっぱいに敷く（中身が短い画面で背景が切れないように）
        constraints: const BoxConstraints.expand(),
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(backgroundAsset),
            repeat: backgroundRepeat,
            fit: backgroundFit,
            alignment: backgroundAlignment,
          ),
        ),
        // SafeArea で上部文字切れを防止（iPhone のノッチ・ホームインジケーターも避ける）
        child: SafeArea(child: child),
      ),
    );
  }
}
