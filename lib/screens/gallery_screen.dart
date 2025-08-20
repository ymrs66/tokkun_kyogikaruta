// lib/screens/gallery_screen.dart
import 'package:flutter/material.dart';
import '../widgets/background_scaffold.dart';
import '../data/reward_catalog.dart';
import '../services/gallery_service.dart';
import '../providers/game_state.dart'; // Rank 見出し用
import 'package:go_router/go_router.dart';
import '../services/media_service.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  Set<int> _owned = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await GalleryService.loadOwned();
    if (mounted) setState(() => _owned = s);
  }

  Widget _slot(int index) {
    final got = _owned.contains(index) ||
        (index == RewardCatalog.completeIndex && RewardCatalog.isComplete(_owned));
    final path = got ? RewardCatalog.slots[index] : RewardCatalog.hatena;
    final isPlaceholder = !got; // 未取得 or まだコンプリート解禁前

    return GestureDetector(
      // 未取得はタップ不可（拡大/保存の導線なし）
      onTap: isPlaceholder ? null : () {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            backgroundColor: Colors.transparent,
            child: Stack(
              children: [
                // 画像本体
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: Colors.black.withOpacity(0.85),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // タイトル（S-1 など）
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            RewardCatalog.labelOf(index),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Flexible(child: Image.asset(path, fit: BoxFit.contain)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.download),
                              label: const Text('保存'),
                              onPressed: () async {
                                final ok = await MediaService.saveAssetToGallery(path, name: RewardCatalog.labelOf(index));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(ok ? '保存しました' : '保存に失敗しました')),
                                  );
                                }
                              },
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.ios_share),
                              label: const Text('共有'),
                              onPressed: () async {
                                await MediaService.shareAsset(
                                  path,
                                  fileName: '${RewardCatalog.labelOf(index)}.png',
                                  text: '百人一首 練習アプリのギャラリー画像',
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
                // 閉じる
                Positioned(
                  right: 0, top: 0,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black12,
            image: DecorationImage(image: AssetImage(path), fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<int> indices, {int crossAxisCount = 3}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          GridView.count(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: indices.map(_slot).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundScaffold(
      appBar: AppBar(title: const Text('ギャラリー')),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                _section('S ランク', RewardCatalog.sIndices),
                _section('A ランク', RewardCatalog.aIndices),
                _section('B ランク', RewardCatalog.bIndices),
                _section('C ランク', RewardCatalog.cIndices),
                _section('D ランク', RewardCatalog.dIndices),
                _section('コンプリート', [RewardCatalog.completeIndex], crossAxisCount: 1),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => context.go('/'),
            child: const Text('スタートに戻る'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
