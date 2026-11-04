import AVFoundation
import Foundation

/// プレイ中に流すBGM。一時停止・広告・ゲームオーバーでは止め、再開時は続きから鳴らす
@MainActor
final class BackgroundMusicPlayer {
    /// 設定画面のBGMオン/オフ。未設定のときはオン
    nonisolated static let isEnabledKey = "kuttuke.bgm-enabled"
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: isEnabledKey) as? Bool ?? true
    }

    /// 進化セットでBGMを選んでいないときに流す標準のBGM
    static let defaultURL = Bundle.main.url(forResource: "kuttuke_bgm_pop", withExtension: "m4a")
    /// 合体音が聞こえるよう控えめにする
    private static let volume: Float = 0.4

    private let player: AVAudioPlayer?
    private var playTask: Task<Void, Never>?

    /// - Parameter url: 進化セットで選んだBGM。nilや読み込めないときは標準のBGMを流す
    init(url: URL?) {
        player = [url, Self.defaultURL].lazy
            .compactMap { $0.flatMap { try? AVAudioPlayer(contentsOf: $0) } }
            .first
        player?.numberOfLoops = -1
        player?.volume = Self.volume
        player?.prepareToPlay()
    }

    func play() {
        guard Self.isEnabled, let player, !player.isPlaying, playTask == nil else { return }
        playTask = Task { [weak self] in
            // 切り替え前に鳴らすと消音スイッチで鳴らないことがあるため、完了を待つ
            await MergeSoundAudioSession.activateForGameAndWait()
            guard let self, !Task.isCancelled else { return }
            self.playTask = nil
            // ほかのアプリで音楽を聴いている人には、その音楽を優先してBGMは鳴らさない
            guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else { return }
            player.play()
        }
    }

    func pause() {
        playTask?.cancel()
        playTask = nil
        player?.pause()
    }

    /// 新しいゲームでは頭から流す
    func rewind() {
        player?.currentTime = 0
    }
}
