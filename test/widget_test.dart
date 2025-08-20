// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tokkun_kyogikaruta/app.dart';

void main() {
  testWidgets('app smoke test', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    // 初期画面の「スタート」ボタンが見えることを確認
    expect(find.text('スタート'), findsOneWidget);
  });
}
