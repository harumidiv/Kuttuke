import GoogleMobileAds
import SwiftUI
import UIKit

/// 画面下に固定表示するバナー広告（320x50）
/// アダプティブの大型バナーは盤面を圧迫するため、高さが一定の標準サイズを使う
struct BannerAdView: UIViewRepresentable {
    // 開発中に本番広告を表示するとAdMobのポリシー違反になるため、DebugではGoogle公式のテスト用IDを使う
    #if DEBUG
    private static let adUnitID = "ca-app-pub-3940256099942544/2934735716"
    #else
    private static let adUnitID = "ca-app-pub-8522231452310619/3923050594"
    #endif

    /// 広告の読み込み前からこの大きさを確保し、読み込み時に盤面のレイアウトがずれないようにする
    static let size = AdSizeBanner.size

    func makeUIView(context: Context) -> BannerView {
        let bannerView = BannerView(adSize: AdSizeBanner)
        bannerView.adUnitID = Self.adUnitID
        bannerView.rootViewController = InterstitialAdManager.topViewController()
        bannerView.load(Request())
        return bannerView
    }

    func updateUIView(_ bannerView: BannerView, context: Context) {}
}
