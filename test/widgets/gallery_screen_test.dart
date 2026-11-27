// test/widgets/gallery_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tokkun_kyogikaruta/data/reward_catalog.dart';
import 'package:tokkun_kyogikaruta/screens/gallery_screen.dart';

void main() {
  for (final size in const [Size(393, 852), Size(834, 1210), Size(1210, 834)]) {
    testWidgets('ギャラリー：各ランクの画像の行が画面の左右中央に並ぶ（$size）', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const GalleryScreen()),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // 未取得の枠（はてな画像）の矩形。S ランクの行は先頭の sIndices.length 枚
      final slots = find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          ((w.decoration as BoxDecoration).image?.image is AssetImage) &&
          ((w.decoration as BoxDecoration).image!.image as AssetImage).assetName ==
              RewardCatalog.hatena);
      final rects = slots.evaluate().map((e) => tester.getRect(find.byWidget(e.widget))).toList()
        ..sort((a, b) => a.top != b.top ? a.top.compareTo(b.top) : a.left.compareTo(b.left));
      final n = RewardCatalog.sIndices.length;
      expect(rects.length, greaterThanOrEqualTo(n));
      final row = rects.take(n).toList();
      final rowCenter = (row.first.left + row.last.right) / 2;
      expect((rowCenter - size.width / 2).abs(), lessThan(2),
          reason: '行の中心 $rowCenter が画面の中心 ${size.width / 2} からずれている');
    });
  }
}
