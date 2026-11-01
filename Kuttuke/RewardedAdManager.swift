import Combine
import GoogleMobileAds
import UIKit

/// アイテムチェンジの前に見てもらうリワード広告の読み込みと表示を管理する。
/// SDKの初期化は `InterstitialAdManager.start()` が行うため、その後に `load()` を呼ぶこと
@MainActor
final class RewardedAdManager: NSObject, ObservableObject, FullScreenContentDelegate {
    static let shared = RewardedAdManager()

    // 開発中に本番広告を表示するとAdMobのポリシー違反になるため、DebugではGoogle公式のテスト用IDを使う
    #if DEBUG
    private static let adUnitID = "ca-app-pub-3940256099942544/1712485313"
    #else
    private static let adUnitID = "ca-app-pub-8522231452310619/4028073946"
    #endif

    /// 広告を表示できる状態か。チェンジボタンの有効・無効に使う
    @Published private(set) var isReady = false

    private var rewardedAd: RewardedAd?
    private var isLoading = false
    private var didEarnReward = false
    private var onDismiss: ((Bool) -> Void)?

    private override init() {
        super.init()
    }

    func load() {
        guard rewardedAd == nil, !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let ad = try await RewardedAd.load(with: Self.adUnitID, request: Request())
                ad.fullScreenContentDelegate = self
                rewardedAd = ad
                isReady = true
            } catch {
                rewardedAd = nil
                isReady = false
            }
        }
    }

    /// 広告を表示し、閉じられたら最後まで見て報酬を得たかを `completion` に渡す。
    /// 広告の準備ができていなければすぐに `false` を渡す
    func show(then completion: @escaping (_ didEarnReward: Bool) -> Void) {
        guard onDismiss == nil else { return }
        guard let rewardedAd, let rootViewController = InterstitialAdManager.topViewController() else {
            completion(false)
            load()
            return
        }
        didEarnReward = false
        onDismiss = completion
        rewardedAd.present(from: rootViewController) { [weak self] in
            self?.didEarnReward = true
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finishPresentation()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        didEarnReward = false
        finishPresentation()
    }

    private func finishPresentation() {
        rewardedAd = nil
        isReady = false
        let completion = onDismiss
        let earned = didEarnReward
        onDismiss = nil
        didEarnReward = false
        completion?(earned)
        load()
    }
}
