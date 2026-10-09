import GoogleMobileAds
import UIKit

/// ゲーム終了後に表示するインタースティシャル広告の読み込みと表示を管理する
@MainActor
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {
    static let shared = InterstitialAdManager()

    // 開発中に本番広告を表示するとAdMobのポリシー違反になるため、DebugではGoogle公式のテスト用IDを使う
    #if DEBUG
    private static let adUnitID = "ca-app-pub-3940256099942544/4411468910"
    #else
    private static let adUnitID = "ca-app-pub-8522231452310619/1262420202"
    #endif

    private var interstitial: InterstitialAd?
    private var isLoading = false
    private var onDismiss: (() -> Void)?

    private override init() {
        super.init()
    }

    func start() {
        MobileAds.shared.start(completionHandler: nil)
        load()
    }

    func load() {
        guard interstitial == nil, !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let ad = try await InterstitialAd.load(with: Self.adUnitID, request: Request())
                ad.fullScreenContentDelegate = self
                interstitial = ad
            } catch {
                interstitial = nil
            }
        }
    }

    /// 広告を表示し、閉じられたら `completion` を呼ぶ。広告の準備ができていなければすぐに `completion` を呼ぶ
    func show(then completion: @escaping () -> Void) {
        guard onDismiss == nil else { return }
        guard let interstitial, let rootViewController = Self.topViewController() else {
            completion()
            load()
            return
        }
        onDismiss = completion
        interstitial.present(from: rootViewController)
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finishPresentation()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        finishPresentation()
    }

    private func finishPresentation() {
        interstitial = nil
        let completion = onDismiss
        onDismiss = nil
        completion?()
        load()
    }

    static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
