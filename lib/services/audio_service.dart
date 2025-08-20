// lib/services/audio_service.dart
import 'package:audioplayers/audioplayers.dart';

class KarutaAudio {
  final AudioPlayer _player = AudioPlayer();
  int? _preparedId; // どの札をロード済みか

  KarutaAudio() {
    // 1トラックずつ再生して終わったら止まる挙動
    _player.setReleaseMode(ReleaseMode.stop);
  }

  /// 事前ロードして一時停止。0の瞬間に resume で即再生できる
  Future<void> prepareUpper(int id) async {
    final file = 'audio/${id.toString().padLeft(3, '0')}.mp3';
    if (_preparedId == id) {
      await _player.seek(Duration.zero);
      await _player.pause();
      return;
    }
    _preparedId = id;
    await _player.stop();                      // 旧トラック停止
    // バージョンにより setSource(AssetSource(...)) か setSourceAsset(...) を使います
    try {
      await _player.setSource(AssetSource(file));
    } catch (_) {
      await _player.setSourceAsset(file);      // 古いバージョン互換
    }
    await _player.seek(Duration.zero);
    await _player.pause();                     // 準備完了（無音で待機）
  }

  /// 準備済みを即再生。muted=true ならボリューム0で再生し続ける
  Future<void> playPrepared({required bool muted}) async {
    await _player.setVolume(muted ? 0.0 : 1.0);
    await _player.resume();
  }

  /// ミュート切替：進行は止めずにボリュームだけ切る/戻す
  Future<void> setMuted(bool muted) => _player.setVolume(muted ? 0.0 : 1.0);

  Future<void> stop() async {
    _preparedId = null;
    await _player.stop();
  }

  Future<void> dispose() => _player.dispose();
}
