import Combine
import GameKit
import UIKit

/// Game Centerのサインインと、素材の個数ごとのランキングへのスコア送信・表示を扱う
@MainActor
final class GameCenterManager: ObservableObject {
    static let shared = GameCenterManager()

    /// 素材の個数ごとにランキングを分ける（個数が多いほど大きく育てられ、スコアの基準が変わるため）
    static let rankedItemCounts = SubjectLibrary.minimumPlayableItems...SubjectLibrary.maximumStageItems

    @Published private(set) var isAuthenticated = false

    private var didStartAuthentication = false

    private init() {}

    /// App Store Connectで作成するランキングのID（例：kuttuke.items6）
    static func leaderboardID(itemCount: Int) -> String? {
        guard rankedItemCounts.contains(itemCount) else { return nil }
        return "kuttuke.items\(itemCount)"
    }

    /// 起動時に一度だけ呼ぶ。未サインインならGame Centerのサインイン画面を表示する
    func authenticate() {
        guard !didStartAuthentication else { return }
        didStartAuthentication = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                if let viewController {
                    InterstitialAdManager.topViewController()?.present(viewController, animated: true)
                    return
                }
                self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            }
        }
    }

    func submit(score: Int, itemCount: Int) {
        guard isAuthenticated, score > 0, let leaderboardID = Self.leaderboardID(itemCount: itemCount) else { return }
        Task {
            try? await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [leaderboardID]
            )
        }
    }

    /// 指定した個数のランキングを開く。nilならランキングの一覧を開く
    /// - Returns: Game Centerにサインインしておらず開けなかった場合はfalse
    @discardableResult
    func showLeaderboard(itemCount: Int? = nil) -> Bool {
        guard isAuthenticated else { return false }
        if let itemCount, let leaderboardID = Self.leaderboardID(itemCount: itemCount) {
            GKAccessPoint.shared.trigger(leaderboardID: leaderboardID, playerScope: .global, timeScope: .allTime) {}
        } else {
            GKAccessPoint.shared.trigger(state: .leaderboards) {}
        }
        return true
    }
}
