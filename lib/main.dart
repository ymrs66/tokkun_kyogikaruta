// lib/main.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/settings_provider.dart';
import 'services/ad_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 設定・成績を起動時に読み込む（画面から同期的に読めるようにする）
  final prefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const App(),
  ));

  // 広告：起動ごとに同意情報を確認し、許可されたときだけ SDK を初期化して読み込む。
  // 画面の表示・練習は待たせない（広告がなくてもすべての機能が動く）。
  // 同意フォーム・ATT のダイアログはホーム画面にいるときだけ表示する。
  AdService.start(waitForSafeMoment: waitUntilHome);
}
