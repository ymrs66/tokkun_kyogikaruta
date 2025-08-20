// lib/screens/title_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/game_provider.dart';
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
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '競技かるた特訓',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final g = ref.read(gameProvider);
                g.resetGame();      // スコアなど初期化
                g.startGame();      // ← ここで初めて 1 問目を作成しタイマー開始
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
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
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