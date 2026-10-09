import Combine
import GameKit
import UIKit

/// ランキングに載った今回の順位
struct LeaderboardRank: Equatable {
    let rank: Int
    let totalPlayers: Int
    let itemCount: Int
}

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

    /// スコアを送り、今回のスコアがランキング上の自己ベストとして載った場合はその順位を返す
    func submit(score: Int, itemCount: Int) async -> LeaderboardRank? {
        guard isAuthenticated, score > 0, let leaderboardID = Self.leaderboardID(itemCount: itemCount) else { return nil }
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [leaderboardID]
            )
            guard let leaderboard = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]).first else { return nil }
            // 送信直後は反映が遅れることがあるため、少し待って取り直す
            for attempt in 0..<3 {
                if attempt > 0 { try await Task.sleep(for: .seconds(1.5)) }
                // 1位だけを取得する指定でも、自分の順位と参加人数が一緒に返る
                let (entry, _, totalPlayerCount) = try await leaderboard.loadEntries(
                    for: .global,
                    timeScope: .allTime,
                    range: NSRange(location: 1, length: 1)
                )
                guard let entry else { continue }
                if entry.score == score {
                    return LeaderboardRank(rank: entry.rank, totalPlayers: totalPlayerCount, itemCount: itemCount)
                }
                // 以前の自己ベストのほうが高ければ、今回はランクインではない
                if entry.score > score { return nil }
            }
        } catch {}
        return nil
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
