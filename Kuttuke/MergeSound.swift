import AVFoundation
import Combine
import Foundation

/// 音声セッションの切り替え。`setActive` はシステムの応答待ちで時間がかかることがあり、
/// メインスレッドで呼ぶと画面が固まるおそれがあるため、専用のキューで順番に実行する
nonisolated enum MergeSoundAudioSession {
    private static let queue = DispatchQueue(label: "kuttuke.audio-session", qos: .userInitiated)

    /// ゲーム中：消音スイッチがオンでも鳴らす。他アプリの音楽は止めずに重ねて鳴らす。
    /// 最初の合体まで間があるため、切り替えの完了は待たない
    static func activateForGame() {
        queue.async {
            try? activate(.playback, options: [.mixWithOthers])
        }
    }

    /// 試聴：設定画面では音を確かめたいので、消音スイッチがオンでも鳴らす。
    /// 切り替え前に鳴らすと消音で鳴らないことがあるため、完了を待ってから再生すること
    static func activateForPreview() async {
        try? await perform { try activate(.playback, options: [.mixWithOthers]) }
    }

    static func activateForRecording() async throws {
        try await perform { try activate(.playAndRecord, options: [.defaultToSpeaker]) }
    }

    private static func activate(_ category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(category, mode: .default, options: options)
        try session.setActive(true)
    }

    private static func perform(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}

/// 合体で進化したとき、進化先のレベルの音を鳴らす。連続で合体しても途切れないよう、レベルごとに複数のプレイヤーを順番に使う
@MainActor
final class MergeSoundPlayer {
    /// 進化音を設定していない素材で鳴らす標準の音
    static let defaultSoundURL = Bundle.main.url(forResource: "poyon", withExtension: "wav")

    private static let poolSize = 3
    private var playersByLevel: [Int: [AVAudioPlayer]] = [:]
    /// 標準の音のプレイヤー。未設定のレベルすべてで共有する
    private var defaultPlayers: [AVAudioPlayer] = []
    private var nextIndexByLevel: [Int: Int] = [:]

    /// - Parameter urls: レベル順（進化の順番）の音。nilの素材は標準の音を鳴らす
    init(urls: [URL?]) {
        for (level, url) in urls.enumerated() {
            guard let url else { continue }
            let players = Self.makePlayers(url: url)
            if !players.isEmpty {
                playersByLevel[level] = players
            }
        }
        if let defaultSoundURL = Self.defaultSoundURL {
            defaultPlayers = Self.makePlayers(url: defaultSoundURL)
        }
        if !playersByLevel.isEmpty || !defaultPlayers.isEmpty {
            MergeSoundAudioSession.activateForGame()
        }
    }

    func play(level: Int) {
        // 設定した音が読み込めなかった場合も標準の音を鳴らす
        let key = playersByLevel[level] == nil ? -1 : level
        let players = playersByLevel[level] ?? defaultPlayers
        guard !players.isEmpty else { return }
        let index = nextIndexByLevel[key, default: 0] % players.count
        nextIndexByLevel[key] = (index + 1) % players.count
        let player = players[index]
        player.currentTime = 0
        player.play()
    }

    private static func makePlayers(url: URL) -> [AVAudioPlayer] {
        (0..<poolSize).compactMap { _ -> AVAudioPlayer? in
            let player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            return player
        }
    }
}

enum MergeSoundError: LocalizedError {
    case microphoneDenied
    case recordingFailed
    case unreadableFile
    case tooLong

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            String(localized: "マイクへのアクセスが許可されていません。設定アプリの「Kuttuke」からマイクを許可してください。")
        case .recordingFailed:
            String(localized: "録音を開始できませんでした。")
        case .unreadableFile:
            String(localized: "この音声ファイルは読み込めませんでした。")
        case .tooLong:
            String(localized: "\(Int(StageSoundDraft.maximumFileDuration))秒以内の音声ファイルを選んでください。")
        }
    }
}

/// ステージ編集中の素材ごとの進化音（録音・ファイル選択・試聴）を扱う。保存されるまでは一時フォルダに置く
@MainActor
final class StageSoundDraft: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let maximumRecordingDuration: TimeInterval = 5
    static let maximumFileDuration: TimeInterval = 10

    /// 保存済みの音（編集前の状態）
    private let savedURLs: [UUID: URL]
    /// 録音・ファイル選択で用意した、まだ保存していない音
    @Published private(set) var pendingURLs: [UUID: URL] = [:]
    @Published private(set) var removedAssetIDs: Set<UUID> = []
    @Published private(set) var recordingAssetID: UUID?
    @Published private(set) var recordingElapsed: TimeInterval = 0
    @Published private(set) var playingAssetID: UUID?

    private var recorder: AVAudioRecorder?
    private var previewPlayer: AVAudioPlayer?
    private var previewTask: Task<Void, Never>?
    private var timer: AnyCancellable?
    private var isDiscarded = false

    init(savedURLs: [UUID: URL]) {
        self.savedURLs = savedURLs
    }

    var isRecording: Bool { recordingAssetID != nil }

    /// その素材に現在設定されている音
    func url(for assetID: UUID) -> URL? {
        if let pending = pendingURLs[assetID] { return pending }
        return removedAssetIDs.contains(assetID) ? nil : savedURLs[assetID]
    }

    func hasUnsavedSound(for assetID: UUID) -> Bool {
        pendingURLs[assetID] != nil
    }

    var changes: [UUID: MergeSoundChange] {
        var changes: [UUID: MergeSoundChange] = [:]
        for (assetID, url) in pendingURLs {
            changes[assetID] = .replace(url)
        }
        for assetID in removedAssetIDs where pendingURLs[assetID] == nil {
            changes[assetID] = .remove
        }
        return changes
    }

    // MARK: 録音

    func startRecording(for assetID: UUID) async throws {
        guard !isRecording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw MergeSoundError.microphoneDenied
        }
        stopPreview()
        try await MergeSoundAudioSession.activateForRecording()

        let url = Self.makeTemporaryURL(extension: "m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record(forDuration: Self.maximumRecordingDuration) else {
            await MergeSoundAudioSession.activateForPreview()
            throw MergeSoundError.recordingFailed
        }
        self.recorder = recorder
        recordingAssetID = assetID
        recordingElapsed = 0
        timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            self.recordingElapsed = recorder.currentTime
        }
    }

    func stopRecording() {
        recorder?.stop()
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor in
            self.finishRecording(url: url, succeeded: flag)
        }
    }

    private func finishRecording(url: URL, succeeded: Bool) {
        let assetID = recordingAssetID
        timer = nil
        recorder = nil
        recordingAssetID = nil
        guard succeeded, !isDiscarded, let assetID else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        setPending(url, for: assetID)
        preview(assetID)
    }

    // MARK: ファイル選択

    /// ファイルアプリで選んだ音声を一時フォルダにコピーして使う
    func importFile(at url: URL, for assetID: UUID) throws {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            throw MergeSoundError.unreadableFile
        }
        guard player.duration <= Self.maximumFileDuration else {
            throw MergeSoundError.tooLong
        }
        let destination = Self.makeTemporaryURL(extension: url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            throw MergeSoundError.unreadableFile
        }
        setPending(destination, for: assetID)
        preview(assetID)
    }

    func remove(for assetID: UUID) {
        if playingAssetID == assetID { stopPreview() }
        setPending(nil, for: assetID)
        removedAssetIDs.insert(assetID)
    }

    // MARK: 試聴

    func preview(_ assetID: UUID) {
        guard let url = url(for: assetID) else { return }
        stopPreview()
        previewTask = Task { [weak self] in
            // 録音直後は録音用のセッションのままだと受話口から小さく鳴る・消音で鳴らないことがあるため、再生用に切り替えてから鳴らす
            await MergeSoundAudioSession.activateForPreview()
            guard let self, !Task.isCancelled else { return }
            self.startPreviewPlayer(url: url, assetID: assetID)
        }
    }

    private func startPreviewPlayer(url: URL, assetID: UUID) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.prepareToPlay()
        guard player.play() else { return }
        previewPlayer = player
        playingAssetID = assetID
        let duration = player.duration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.1))
            guard let self, self.previewPlayer === player else { return }
            self.playingAssetID = nil
        }
    }

    func stopPreview() {
        // 音声セッションの切り替え待ちで、まだ鳴っていない試聴も取り消す
        previewTask?.cancel()
        previewTask = nil
        previewPlayer?.stop()
        previewPlayer = nil
        playingAssetID = nil
    }

    /// 画面を閉じるときに一時ファイルを片付ける（保存時は本保存先へコピー済み）
    func discardTemporaryFiles() {
        isDiscarded = true
        stopPreview()
        recorder?.stop()
        for url in pendingURLs.values {
            try? FileManager.default.removeItem(at: url)
        }
        pendingURLs = [:]
    }

    private func setPending(_ url: URL?, for assetID: UUID) {
        if let old = pendingURLs[assetID] {
            try? FileManager.default.removeItem(at: old)
        }
        pendingURLs[assetID] = url
        if url != nil { removedAssetIDs.remove(assetID) }
    }

    private static func makeTemporaryURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("merge-sound-\(UUID().uuidString)")
            .appendingPathExtension(ext.isEmpty ? "m4a" : ext)
    }
}
