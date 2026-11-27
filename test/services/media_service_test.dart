// test/services/media_service_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/services/media_service.dart';

void main() {
  group('MediaService.validOrigin（iPad の共有ポップオーバーの起点）', () {
    test('大きさが正の矩形はそのまま使う', () {
      const r = Rect.fromLTWH(100, 200, 120, 40);
      expect(MediaService.validOrigin(r), r);
    });
    test('null・大きさ 0・無限の矩形は使わない（null）', () {
      expect(MediaService.validOrigin(null), isNull);
      expect(MediaService.validOrigin(const Rect.fromLTWH(10, 10, 0, 40)), isNull);
      expect(MediaService.validOrigin(const Rect.fromLTWH(10, 10, 40, 0)), isNull);
      expect(MediaService.validOrigin(const Rect.fromLTWH(0, 0, double.infinity, 40)), isNull);
    });
  });

  testWidgets('originOf は押したボタンの画面上の矩形を返す', (tester) async {
    late BuildContext buttonContext;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Builder(builder: (c) {
            buttonContext = c;
            return const SizedBox(width: 120, height: 40);
          }),
        ),
      ),
    ));
    final rect = MediaService.originOf(buttonContext)!;
    final expected = tester.getRect(find.byType(SizedBox).last);
    expect(rect, expected);
    expect(rect.size, const Size(120, 40));
  });
}
