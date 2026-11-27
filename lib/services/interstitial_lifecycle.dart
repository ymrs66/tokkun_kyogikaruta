// lib/services/interstitial_lifecycle.dart

/// インタースティシャル広告の「先読み → 1回表示 → 解放 → 次を先読み」の状態管理。
///
/// AdMob の SDK に依存しない形にして、単体テストできるようにしている。
/// 実際の読み込み・解放は [loadAd] / [disposeAd] として外から渡す（AdService）。
///
/// - 読み込み中・読み込み済みのときは、重ねて読み込まない
/// - 表示中は、次の表示をしない（重複表示の防止）
/// - 表示が終わったら（閉じた／表示に失敗した）、その広告を1回だけ解放し、次を先読みする
/// - 広告がないときの表示要求は何もしない（呼び出し側の画面の進行を止めない）
class InterstitialLifecycle<A extends Object> {
  InterstitialLifecycle({required this.loadAd, required this.disposeAd});

  /// 読み込みを開始する。結果は [onLoaded] / [onFailed] のどちらかで1回だけ通知する。
  final void Function(void Function(A ad) onLoaded, void Function() onFailed) loadAd;

  /// 広告を解放する。
  final void Function(A ad) disposeAd;

  A? _cached;
  A? _showing;
  bool _loading = false;

  /// [clear] のたびに増える。古い読み込みの結果を捨てるために使う
  int _epoch = 0;

  bool get hasAd => _cached != null;
  bool get isLoading => _loading;
  bool get isShowing => _showing != null;

  /// 次の表示のために先読みする（読み込み中・読み込み済みなら何もしない）。
  void prefetch() {
    if (_cached != null || _loading) return;
    _loading = true;
    var settled = false;
    final epoch = _epoch;
    loadAd(
      (ad) {
        if (settled) return;
        settled = true;
        if (epoch != _epoch) {
          disposeAd(ad); // 読み込み中に破棄された（同意状態の変更など）：使わない
          return;
        }
        _loading = false;
        if (_cached != null) {
          disposeAd(ad); // 念のため：すでに持っている場合は捨てる
          return;
        }
        _cached = ad;
      },
      () {
        if (settled) return;
        settled = true;
        if (epoch != _epoch) return;
        _loading = false;
      },
    );
  }

  /// 表示する広告を取り出す。表示中・広告なしのときは null（広告なしなら先読みを始める）。
  /// null 以外を返したら、表示が終わったときに必ず [finishShow] を呼ぶこと。
  A? takeForShow() {
    if (_showing != null) return null;
    final ad = _cached;
    if (ad == null) {
      prefetch();
      return null;
    }
    _cached = null;
    _showing = ad;
    return ad;
  }

  /// 読み込み済みの広告を解放し、読み込み中の結果も捨てる（同意状態の変更・広告の停止時）。
  /// 表示中の広告はそのまま（閉じたときに [finishShow] で解放される）。
  void clear() {
    _epoch++;
    _loading = false;
    final ad = _cached;
    _cached = null;
    if (ad != null) disposeAd(ad);
  }

  /// 表示が終わった（閉じた／表示に失敗した）ときに呼ぶ。同じ広告で2回呼ばれても1回だけ処理する。
  void finishShow(A ad) {
    if (!identical(_showing, ad)) return;
    _showing = null;
    disposeAd(ad);
    prefetch();
  }
}
