// lib/services/media_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class MediaService {
  static Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final bd = await rootBundle.load(assetPath);
    return bd.buffer.asUint8List();
  }

  static String _basename(String path) => path.split('/').last;

  /// 端末ギャラリーへ保存（アルバム名はお好みで）
  static Future<bool> saveAssetToGallery(String assetPath, {String? name}) async {
    try {
      if (kIsWeb) return false;
      final bytes = await _loadAssetBytes(assetPath);
      await Gal.putImageBytes(
        bytes,
        album: '競技かるた練習',
        name: (name ?? _basename(assetPath)).replaceAll('.png', ''),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 共有（X / LINE など）
  static Future<void> shareAsset(String assetPath, {String? fileName, String? text}) async {
    final bytes = await _loadAssetBytes(assetPath);
    final dir = await getTemporaryDirectory();
    final name = fileName ?? _basename(assetPath);
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(f.path, mimeType: 'image/png', name: name)], text: text);
  }
}
