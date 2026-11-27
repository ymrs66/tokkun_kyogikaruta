// lib/services/media_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show BuildContext, Rect, Offset;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class MediaService {
  static Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final bd = await rootBundle.load(assetPath);
    return bd.buffer.asUint8List();
  }

  static String _basename(String path) => path.split('/').last;

  /// 共有の起点（iPad の共有ポップオーバーの矢印が指す位置）として、[context] のウィジェットの
  /// 画面上の矩形を返す。押した時点のレイアウトから計算するので、回転・画面分割の後も正しい。
  /// 大きさが 0・画面外などで使えないときは null（share_plus が既定の位置を使う）。
  static Rect? originOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return validOrigin(rect);
  }

  /// share_plus に渡せる矩形か（大きさが正で、座標が有限）
  static Rect? validOrigin(Rect? rect) {
    if (rect == null || !rect.isFinite || rect.width <= 0 || rect.height <= 0) return null;
    return rect;
  }

  /// 共有（X / LINE など）。iPad では [sharePositionOrigin]（共有ボタンの矩形）を渡す
  static Future<void> shareAsset(String assetPath,
      {String? fileName, String? text, Rect? sharePositionOrigin}) async {
    final bytes = await _loadAssetBytes(assetPath);
    final dir = await getTemporaryDirectory();
    final name = fileName ?? _basename(assetPath);
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    // share_plus 11 以降の API（Share.shareXFiles は非推奨）
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'image/png', name: name)],
      text: text,
      sharePositionOrigin: validOrigin(sharePositionOrigin),
    ));
  }
}
