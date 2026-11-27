// test/interstitial_lifecycle_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/services/interstitial_lifecycle.dart';

/// テスト用の広告（AdMob の InterstitialAd の代わり）
class FakeAd {
  FakeAd(this.id);
  final int id;
  @override
  String toString() => 'FakeAd($id)';
}

/// 読み込み要求を記録し、テストから成功・失敗を返せるローダー
class FakeLoader {
  final List<(void Function(FakeAd), void Function())> pending = [];
  final List<FakeAd> disposed = [];
  int requests = 0;
  int _nextId = 1;

  void load(void Function(FakeAd) onLoaded, void Function() onFailed) {
    requests++;
    pending.add((onLoaded, onFailed));
  }

  FakeAd succeed() {
    final (onLoaded, _) = pending.removeAt(0);
    final ad = FakeAd(_nextId++);
    onLoaded(ad);
    return ad;
  }

  void fail() {
    final (_, onFailed) = pending.removeAt(0);
    onFailed();
  }
}

void main() {
  late FakeLoader loader;
  late InterstitialLifecycle<FakeAd> life;

  setUp(() {
    loader = FakeLoader();
    life = InterstitialLifecycle<FakeAd>(
      loadAd: loader.load,
      disposeAd: loader.disposed.add,
    );
  });

  group('先読み', () {
    test('読み込み中に何度 prefetch しても読み込みは1回だけ', () {
      life.prefetch();
      life.prefetch();
      life.prefetch();
      expect(loader.requests, 1);
      expect(life.isLoading, isTrue);
    });

    test('読み込み済みなら prefetch しても読み込まない', () {
      life.prefetch();
      loader.succeed();
      life.prefetch();
      expect(loader.requests, 1);
      expect(life.hasAd, isTrue);
      expect(life.isLoading, isFalse);
    });

    test('読み込みに失敗したら、次の prefetch で再度読み込める', () {
      life.prefetch();
      loader.fail();
      expect(life.isLoading, isFalse);
      expect(life.hasAd, isFalse);
      life.prefetch();
      expect(loader.requests, 2);
    });
  });

  group('表示', () {
    test('広告がないときは null（画面の進行を止めない）で、先読みを始める', () {
      expect(life.takeForShow(), isNull);
      expect(loader.requests, 1);
      expect(loader.disposed, isEmpty);
    });

    test('広告を取り出したら手元からなくなり、表示中になる', () {
      life.prefetch();
      final ad = loader.succeed();
      expect(life.takeForShow(), same(ad));
      expect(life.hasAd, isFalse);
      expect(life.isShowing, isTrue);
    });

    test('表示中は次の広告を取り出さない（重複表示の防止）', () {
      life.prefetch();
      loader.succeed();
      final first = life.takeForShow();
      expect(first, isNotNull);
      // 表示中に別の広告が読み込まれていても、表示中は出さない
      life.prefetch();
      loader.succeed();
      expect(life.takeForShow(), isNull);
    });

    test('取り出した直後には解放しない（閉じるまで待つ）', () {
      life.prefetch();
      loader.succeed();
      life.takeForShow();
      expect(loader.disposed, isEmpty);
    });
  });

  group('表示の終了（閉じた／表示に失敗した）', () {
    test('終了で1回だけ解放し、次を先読みする', () {
      life.prefetch();
      final ad = loader.succeed();
      life.takeForShow();
      life.finishShow(ad);
      expect(loader.disposed, [ad]);
      expect(life.isShowing, isFalse);
      expect(loader.requests, 2); // 次の先読み
    });

    test('同じ広告で2回終了が通知されても解放は1回', () {
      life.prefetch();
      final ad = loader.succeed();
      life.takeForShow();
      life.finishShow(ad);
      life.finishShow(ad);
      expect(loader.disposed, [ad]);
    });

    test('表示していない広告の終了通知は無視する', () {
      life.prefetch();
      final ad = loader.succeed();
      life.finishShow(ad); // まだ表示していない
      expect(loader.disposed, isEmpty);
      expect(life.hasAd, isTrue);
    });

    test('2回目の表示：閉じた後に読み込まれた広告を表示できる', () {
      life.prefetch();
      final first = loader.succeed();
      life.takeForShow();
      life.finishShow(first);
      final second = loader.succeed();
      expect(life.takeForShow(), same(second));
      life.finishShow(second);
      expect(loader.disposed, [first, second]);
    });

    test('表示中に先読みが済んでいれば、閉じた後は追加で読み込まない', () {
      life.prefetch();
      final first = loader.succeed();
      life.takeForShow();
      life.prefetch(); // 表示中の先読み（タイトル画面など）
      loader.succeed();
      life.finishShow(first);
      expect(loader.requests, 2);
      expect(life.hasAd, isTrue);
    });
  });

  test('読み込み結果が2回通知されても1回だけ扱う', () {
    void Function(FakeAd)? cb;
    final disposed = <FakeAd>[];
    final l = InterstitialLifecycle<FakeAd>(
      loadAd: (onLoaded, _) => cb = onLoaded,
      disposeAd: disposed.add,
    );
    l.prefetch();
    final a = FakeAd(1);
    cb!(a);
    cb!(FakeAd(2));
    expect(l.takeForShow(), same(a));
    expect(disposed, isEmpty);
  });

  group('破棄（同意状態の変更）', () {
    test('読み込み済みの広告を解放し、次の表示では使わない', () {
      life.prefetch();
      final a = loader.succeed();
      life.clear();
      expect(loader.disposed, [a]);
      expect(life.hasAd, isFalse);
      expect(life.isLoading, isFalse);
    });

    test('読み込み中に破棄したら、後から届いた広告は解放して使わない', () {
      life.prefetch();
      life.clear();
      final late = loader.succeed();
      expect(loader.disposed, [late]);
      expect(life.hasAd, isFalse);
      // 破棄後の先読みは新しく読み込める
      life.prefetch();
      expect(loader.requests, 2);
      final b = loader.succeed();
      expect(life.takeForShow(), same(b));
    });

    test('表示中の広告は破棄しない（閉じたときに1回だけ解放）', () {
      life.prefetch();
      final a = loader.succeed();
      expect(life.takeForShow(), same(a));
      life.clear();
      expect(loader.disposed, isEmpty);
      life.finishShow(a);
      expect(loader.disposed, [a]);
    });
  });
}
