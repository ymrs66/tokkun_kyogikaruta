// lib/services/audio_service.dart
import 'package:audioplayers/audioplayers.dart';

/// 練習で使う読み上げ音声の操作（GameState から呼ぶ。テストでは差し替える）。
/// どの操作も例外を外へ出さない（音声の失敗で練習が止まらないようにする）。
abstract class PracticeAudio {
  /// 札の上の句を読み込み、再生の準備をする（最後に頼んだ札だけが有効）
  Future<void> prepare(int cardId);

  /// 準備した札を再生する。muted=true なら音量0で再生を続ける
  Future<void> play({required bool muted});

  Future<void> pause();
  Future<void> setMuted(bool muted);
  Future<void> stop();
  Future<void> dispose();
}

/// 音声プレーヤーの最小限の操作（audioplayers を包む。テストでは差し替える）
abstract class AudioBackend {
  Future<void> setReleaseModeStop();
  Future<void> setAsset(String path);
  Future<void> seekToStart();
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setVolume(double v);
  Future<void> dispose();
}

class AudioPlayersBackend implements AudioBackend {
  final AudioPlayer _player = AudioPlayer();
  @override
  Future<void> setReleaseModeStop() => _player.setReleaseMode(ReleaseMode.stop);
  @override
  Future<void> setAsset(String path) async {
    // バージョンにより setSource(AssetSource(...)) か setSourceAsset(...) を使う
    try {
      await _player.setSource(AssetSource(path));
    } catch (_) {
      await _player.setSourceAsset(path); // 古いバージョン互換
    }
  }

  @override
  Future<void> seekToStart() => _player.seek(Duration.zero);
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> resume() => _player.resume();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> setVolume(double v) => _player.setVolume(v);
  @override
  Future<void> dispose() => _player.dispose();
}

class KarutaAudio implements PracticeAudio {
  KarutaAudio([AudioBackend? backend]) : _b = backend ?? AudioPlayersBackend() {
    // 1トラックずつ再生して終わったら止まる挙動
    _guard(_b.setReleaseModeStop());
  }

  final AudioBackend _b;
  int? _requestedId; // 最後に準備を頼んだ札
  int? _preparedId; // 読み込み済みの札
  int _playToken = 0; // 再生の要求の番号（一時停止・停止・次の準備で無効にする）
  bool _disposed = false;
  Future<void> _queue = Future.value(); // 準備を順番に処理する

  /// 例外を外へ出さない
  static Future<void> _guard(Future<void> f) async {
    try {
      await f;
    } catch (_) {}
  }

  @override
  Future<void> prepare(int cardId) {
    _requestedId = cardId;
    _playToken++; // 前の札の再生要求を無効にする
    _queue = _queue.then((_) => _guard(_doPrepare(cardId)));
    return _queue;
  }

  Future<void> _doPrepare(int id) async {
    // 後から別の札の準備を頼まれていたら、この準備はしない（古い要求の無視）
    if (_disposed || _requestedId != id) return;
    if (_preparedId == id) {
      await _b.seekToStart();
      await _b.pause();
      return;
    }
    _preparedId = null;
    await _b.stop(); // 旧トラック停止
    await _b.setAsset('audio/${id.toString().padLeft(3, '0')}.mp3');
    if (_disposed || _requestedId != id) return;
    await _b.seekToStart();
    await _b.pause(); // 準備完了（無音で待機）
    _preparedId = id;
  }

  @override
  Future<void> play({required bool muted}) async {
    final id = _requestedId;
    final token = ++_playToken;
    await _queue; // 準備が終わるのを待つ（失敗しても先へ進む）
    // 待っている間に別の札・一時停止・停止になった、または準備に失敗した
    if (_disposed || id == null || token != _playToken ||
        _requestedId != id || _preparedId != id) {
      return;
    }
    await _guard(_b.setVolume(muted ? 0.0 : 1.0));
    await _guard(_b.resume());
  }

  @override
  Future<void> pause() async {
    _playToken++; // 準備待ちの再生を取り消す
    if (_disposed) return;
    await _guard(_b.pause());
  }

  /// ミュート切替：進行は止めずにボリュームだけ切る/戻す
  @override
  Future<void> setMuted(bool muted) async {
    if (_disposed) return;
    await _guard(_b.setVolume(muted ? 0.0 : 1.0));
  }

  @override
  Future<void> stop() async {
    _requestedId = null;
    _preparedId = null;
    _playToken++;
    if (_disposed) return;
    await _guard(_b.stop());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _requestedId = null;
    _playToken++;
    await _guard(_b.dispose());
  }
}
