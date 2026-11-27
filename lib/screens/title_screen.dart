// lib/screens/title_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/game_provider.dart';
import '../models/game_config.dart';
import '../providers/settings_provider.dart';
import '../widgets/background_scaffold.dart';
import 'match_setup_screen.dart' show memorizeLabel;
// 広告関係
import 'package:tokkun_kyogikaruta/widgets/ad_banner.dart';
import 'package:tokkun_kyogikaruta/services/ad_service.dart';

/// ホーム画面（タイトル）
///
/// - 練習のボタン（反応練習・実践練習）の下に短い説明文と条件を表示する
/// - タイトルはレイアウトの中に置き、小型端末・横画面でも画面外に出ないようにする
/// - バナー広告は画面の下に固定し、メニューが入りきらないときはメニューだけをスクロールする
class TitleScreen extends ConsumerWidget {
  const TitleScreen({super.key});

  static const reactionLabel = '反応練習';
  static const reactionDescription = '札の認識力・判断力・反応速度を鍛える';
  static const matchLabel = '実践練習';
  static const matchDescription = '札の暗記・位置の把握・競技に近い札取りを練習する';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AdService.prefetchInterstitial(); //広告
    final settings = ref.watch(settingsProvider);

    void startReaction() {
      final g = ref.read(gameProvider);
      g.resetGame(); // スコアなど初期化
      // 設定を練習開始時に固定する（1問目の準備。カウントダウンは練習画面で開始）
      g.startGame(GameConfig.fromSettings(settings));
      context.go('/play');
    }

    final condition = settings.karafudaEnabled
        ? '空札あり ${settings.karafudaPercent}%${settings.otetsukiPenalty ? '・お手つきペナルティ' : ''}'
        : null;

    final menu = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PracticeButton(
          label: reactionLabel,
          description: reactionDescription,
          condition: condition,
          onTap: startReaction,
        ),
        const SizedBox(height: 8),
        _PracticeButton(
          label: matchLabel,
          description: matchDescription,
          condition: '暗記 ${memorizeLabel(settings.matchMemorizeSec)}・'
              '${settings.matchKarafudaPercent == 0 ? '空札なし' : '空札 ${settings.matchKarafudaPercent}%'}',
          onTap: () => context.go('/match'),
        ),
        const SizedBox(height: 6),
        _menuBtn(label: '遊び方説明', onTap: () => context.go('/howto')),
        _menuBtn(label: '成績・ランク', onTap: () => context.go('/score')),
        _menuBtn(label: 'ギャラリー', onTap: () => context.go('/gallery')),
        _menuBtn(label: '設定', icon: Icons.settings, onTap: () => context.go('/settings')),
        // 目立たせない小ボタン
        TextButton(
          onPressed: () => context.go('/privacy'),
          child: const Text('プライバシーポリシー'),
        ),
      ],
    );

    const title = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '競技かるた特訓',
        style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.red),
      ),
    );

    return BackgroundScaffold(
      backgroundAsset: 'assets/images/titlebackground.png',
      backgroundRepeat: ImageRepeat.noRepeat,
      backgroundFit: BoxFit.cover, // 画面いっぱいに敷く（必要なら一部トリミング）
      backgroundAlignment: Alignment.center,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (ctx, box) {
              final landscape = box.maxWidth > box.maxHeight;
              if (landscape) {
                // 横画面：左にタイトル、右にメニュー（入りきらなければスクロール）
                return Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Center(child: title),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: menu),
                      ),
                    ),
                  ],
                );
              }
              // 縦画面：上にタイトル、下にメニュー。小型端末ではメニューだけスクロール
              return Column(
                children: [
                  SizedBox(
                    height: (box.maxHeight * 0.28).clamp(64.0, 260.0),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Center(child: title),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Center(child: menu),
                    ),
                  ),
                ],
              );
            }),
          ),
          const AdBanner(), // ★ 常に下部にバナー
        ],
      ),
    );
  }

  Widget _menuBtn({required String label, required VoidCallback onTap, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: SizedBox(
        width: 240,
        child: ElevatedButton(
          onPressed: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 6)],
              Text(label, style: const TextStyle(fontSize: 18)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 練習のボタン＋説明文（背景画像の上でも読めるよう、説明文は半透明の帯に載せる）
class _PracticeButton extends StatelessWidget {
  const _PracticeButton({
    required this.label,
    required this.description,
    required this.onTap,
    this.condition,
  });

  final String label;
  final String description;
  final String? condition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 290,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            child: ElevatedButton(
              onPressed: onTap,
              child: Text(label, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                if (condition != null)
                  Text(condition!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFFFE082), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
