// lib/services/media_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class MediaService {
  static Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final bd = await rootBundle.load(assetPath);
    return bd.buffer.asUint8List();
  }

  static String _basename(String path) => path.split('/').last;

  /// 共有（X / LINE など）
  static Future<void> shareAsset(String assetPath, {String? fileName, String? text}) async {
    final bytes = await _loadAssetBytes(assetPath);
    final dir = await getTemporaryDirectory();
    final name = fileName ?? _basename(assetPath);
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    // share_plus 11 以降の API（Share.shareXFiles は非推奨）
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'image/png', name: name)],
      text: text,
    ));
  }
}
