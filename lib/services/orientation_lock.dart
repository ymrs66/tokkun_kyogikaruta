// lib/services/orientation_lock.dart
//
// 実践練習の画面（開始・暗記／練習・結果）を縦向きに固定する。
// 画面の切り替えで「新しい画面の固定 → 古い画面の解除」の順に呼ばれても固定が外れないよう、
// 使っている画面の数を数え、0 になってから少し待って解除する（ホームなどは縦横両方に戻る）。
//
// iPad の画面分割（Split View）など、OS が向きの固定を適用しない場合がある。
// そのときは画面側で「縦向きにしてください」と表示して練習を止める（match_play_screen）。
import 'dart:async';

import 'package:flutter/services.dart';

class OrientationLock {
  OrientationLock._();

  static int _holders = 0;
  static Timer? _release;

  /// テストで呼び出しを確かめるため（null なら SystemChrome を呼ぶ）
  static Future<void> Function(List<DeviceOrientation>)? setter;

  static Future<void> _set(List<DeviceOrientation> o) =>
      (setter ?? SystemChrome.setPreferredOrientations)(o);

  static int get holders => _holders;

  /// 解除までの待ち時間（テストでは 0 にして、その場で解除する）
  static Duration releaseDelay = const Duration(milliseconds: 100);

  /// 縦向きに固定する（画面の initState で呼ぶ）
  static void acquirePortrait() {
    _release?.cancel();
    _release = null;
    _holders++;
    if (_holders == 1) {
      _set(const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    }
  }

  /// 固定をやめる（画面の dispose で呼ぶ）。どの画面も使っていなければ、アプリの既定（縦横両方）に戻す
  static void releasePortrait() {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) {
      _release?.cancel();
      if (releaseDelay == Duration.zero) {
        _set(const []);
        return;
      }
      _release = Timer(releaseDelay, () {
        _release = null;
        if (_holders == 0) _set(const []); // 空 = アプリの既定に戻す
      });
    }
  }
}
