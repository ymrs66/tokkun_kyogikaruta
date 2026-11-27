// lib/screens/title_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/game_provider.dart';
import '../models/game_config.dart';
import '../providers/settings_provider.dart';
import '../widgets/background_scaffold.dart';
// 広告関係
import 'package:tokkun_kyogikaruta/widgets/ad_banner.dart';
import 'package:tokkun_kyogikaruta/services/ad_service.dart';


class TitleScreen extends ConsumerWidget {
  const TitleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AdService.prefetchInterstitial(); //広告

    return BackgroundScaffold(
      backgroundAsset: 'assets/images/titlebackground.png',
      backgroundRepeat: ImageRepeat.noRepeat,
      backgroundFit: BoxFit.cover, // 画面いっぱいに敷く（必要なら一部トリミング）
      backgroundAlignment: Alignment.center,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: const Offset(0, -120),
              child: const Text(
                '競技かるた特訓',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Colors.red,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final g = ref.read(gameProvider);
                g.resetGame();      // スコアなど初期化
                // 設定を練習開始時に固定する（1問目の準備。カウントダウンは練習画面で開始）
                g.startGame(GameConfig.fromSettings(ref.read(settingsProvider)));
                context.go('/play');
              },
              child: const Text('スタート', style: TextStyle(fontSize: 20)),
            ),
            _menuBtn(context,label:'遊び方説明',   onTap:()=>context.go('/howto')),
            _menuBtn(context,label:'現在のランク',onTap:()=>context.go('/score')),
            _menuBtn(context,label:'ギャラリー',   onTap:()=>context.go('/gallery')),
            _menuBtn(context,label:'スコアのリセット', onTap:() async {
              final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('スコアをリセットしますか？'),
                    actions: [
                      TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('いいえ')),
                      TextButton(onPressed: ()=>Navigator.pop(context,true),  child: const Text('はい')),
                    ],
                  ));
              if (ok ?? false) {
                // 従来どおり全データ（成績の新旧キー・ギャラリー・設定）を消す。
                // 成績だけを消すリセットは Phase 3 の設定画面で用意する。
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                // メモリ上の設定も保存値（＝初期値）に合わせる
                ref.invalidate(settingsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('リセットしました！')));
                }
              }
            }),
            // 目立たせない小ボタン
            TextButton(onPressed:()=>context.go('/privacy'),
                child: const Text('プライバシーポリシー')),
            const SizedBox(height: 12),
            const AdBanner(),   // ★ ここで常に下部にバナー
          ],
        ),
      ),
    );
  }

  Widget _menuBtn(BuildContext ctx,{required String label,required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical:8.0),
      child: SizedBox(
        width: 240,
        child: ElevatedButton(
          onPressed: onTap,
          child: Text(label,style: const TextStyle(fontSize:18)),
        ),
      ),
    );
  }
}