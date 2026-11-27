// test/services/audio_service_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/services/audio_service.dart';

/// 音声プレーヤーの代わり。setAsset を手動で完了させたり、失敗させたりできる。
class FakeBackend implements AudioBackend {
  final List<String> log = [];
  final Map<String, Completer<void>> pendingAsset = {};
  bool holdAssets = false;
  Set<String> failAssets = {};
  bool failResume = false;

  @override
  Future<void> setReleaseModeStop() async {}
  @override
  Future<void> setAsset(String path) {
    log.add('set:$path');
    if (failAssets.contains(path)) return Future.error(Exception('load failed'));
    if (!holdAssets) return Future.value();
    final c = Completer<void>();
    pendingAsset[path] = c;
    return c.future;
  }

  @override
  Future<void> seekToStart() async => log.add('seek');
  @override
  Future<void> pause() async => log.add('pause');
  @override
  Future<void> resume() async {
    log.add('resume');
    if (failResume) throw Exception('resume failed');
  }

  @override
  Future<void> stop() async => log.add('stop');
  @override
  Future<void> setVolume(double v) async => log.add('vol:$v');
  @override
  Future<void> dispose() async => log.add('dispose');

  int get resumes => log.where((e) => e == 'resume').length;
}

/// 準備の処理（非同期の順番待ち）を進める
Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

String asset(int id) => 'audio/${id.toString().padLeft(3, '0')}.mp3';

void main() {
  late FakeBackend b;
  late KarutaAudio audio;
  setUp(() {
    b = FakeBackend();
    audio = KarutaAudio(b);
  });

  test('準備してから再生すると、その札が再生される', () async {
    await audio.prepare(1);
    await audio.play(muted: false);
    expect(b.log, contains('set:${asset(1)}'));
    expect(b.resumes, 1);
    expect(b.log, contains('vol:1.0'));
  });

  test('ミュート中は音量0で再生する', () async {
    await audio.prepare(1);
    await audio.play(muted: true);
    expect(b.log, contains('vol:0.0'));
  });

  test('準備中に別の札へ移ったら、古い札は再生されない', () async {
    b.holdAssets = true;
    audio.prepare(1);
    final play1 = audio.play(muted: false); // 1 の準備待ち
    audio.prepare(2); // 次の問題へ（1 の読み込みが始まる前）
    await flush();
    expect(b.pendingAsset.containsKey(asset(1)), isFalse,
        reason: '古い札（1）は読み込みもしない');
    b.pendingAsset[asset(2)]!.complete();
    await play1;
    expect(b.resumes, 0, reason: '古い札（1）の再生要求は取り消される');
    await audio.play(muted: false);
    expect(b.resumes, 1);
  });

  test('読み込み中に別の札へ移ったら、読み込み済みでも古い札は再生されない', () async {
    b.holdAssets = true;
    audio.prepare(1);
    final play1 = audio.play(muted: false);
    await flush(); // 1 の読み込みが始まった
    expect(b.pendingAsset.containsKey(asset(1)), isTrue);
    audio.prepare(2); // 読み込み中に次の問題へ
    b.pendingAsset[asset(1)]!.complete();
    await play1;
    expect(b.resumes, 0);
    await flush();
    b.pendingAsset[asset(2)]!.complete();
    await audio.play(muted: false);
    expect(b.resumes, 1);
  });

  test('準備待ちの間に一時停止したら、後から再生されない', () async {
    b.holdAssets = true;
    final p = audio.prepare(1);
    final play = audio.play(muted: false);
    await audio.pause(); // 中断ダイアログ
    await flush();
    b.pendingAsset[asset(1)]!.complete();
    await p;
    await play;
    expect(b.resumes, 0);
  });

  test('準備待ちの間に停止・解放したら再生されない', () async {
    b.holdAssets = true;
    final p = audio.prepare(1);
    final play = audio.play(muted: false);
    await audio.stop();
    await flush();
    b.pendingAsset[asset(1)]?.complete(); // 停止後は読み込み自体をしない
    await p;
    await play;
    expect(b.resumes, 0);
    await audio.dispose();
    await audio.play(muted: false);
    expect(b.resumes, 0);
  });

  test('読み込みに失敗しても例外を出さず、次の札は再生できる', () async {
    b.failAssets = {asset(1)};
    await audio.prepare(1); // 失敗しても完了する
    await audio.play(muted: false); // 再生されないが例外も出ない
    expect(b.resumes, 0);
    await audio.prepare(2);
    await audio.play(muted: false);
    expect(b.resumes, 1);
  });

  test('再生の失敗も例外を外へ出さない', () async {
    b.failResume = true;
    await audio.prepare(1);
    await expectLater(audio.play(muted: false), completes);
  });
}
