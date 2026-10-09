import Combine
import Foundation
import SwiftUI
import UIKit

struct SubjectAsset: Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let image: UIImage

    static func == (lhs: SubjectAsset, rhs: SubjectAsset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct GameStage: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var assetIDs: [UUID]
    let createdAt: Date
    var updatedAt: Date
    /// 素材ごとの進化音（その素材に進化したときに鳴らす音声ファイル名）。未設定の素材は無音
    var mergeSoundFileNames: [UUID: String]?
    /// 友達に共有したときのコード（CloudKitのレコード名）。未共有ならnil
    var shareCode: String?
    var sharedAt: Date?

    /// 共有後にステージを編集していて、アップロードし直す必要があるか
    var needsShareUpload: Bool {
        guard shareCode != nil, let sharedAt else { return true }
        return updatedAt > sharedAt
    }
}

/// ステージ保存時の進化音の扱い
enum MergeSoundChange {
    case keep
    case remove
    /// 一時フォルダにある録音・選択済みファイルを本保存する
    case replace(URL)
}

@MainActor
final class SubjectLibrary: ObservableObject {
    static let minimumPlayableItems = 6
    static let maximumStageItems = 11

    @Published private(set) var assets: [SubjectAsset] = []
    @Published private(set) var stages: [GameStage] = []
    @Published var isProcessing = false
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private let assetOrderKey = "kuttuke.subject-order.v1"
    private let didMigrateLegacyStageKey = "kuttuke.did-migrate-stage.v1"

    init() {
        loadAssets()
        loadStages()
        migrateLegacySetIfNeeded()
    }

    func asset(withID id: UUID) -> SubjectAsset? {
        assets.first { $0.id == id }
    }

    func stage(withID id: UUID) -> GameStage? {
        stages.first { $0.id == id }
    }

    func images(for stage: GameStage) -> [UIImage] {
        stage.assetIDs.compactMap { asset(withID: $0)?.image }
    }

    func mergeSoundURL(for stage: GameStage, assetID: UUID) -> URL? {
        guard let fileName = stage.mergeSoundFileNames?[assetID] else { return nil }
        let url = soundsDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// `images(for:)` と同じ並び（レベル順）の進化音
    func mergeSoundURLs(for stage: GameStage) -> [URL?] {
        stage.assetIDs
            .filter { asset(withID: $0) != nil }
            .map { mergeSoundURL(for: stage, assetID: $0) }
    }

    /// `images(for:)` と同じ並びの画像ファイル
    func imageFileURLs(for stage: GameStage) -> [URL] {
        stage.assetIDs.compactMap { asset(withID: $0) }
            .map { assetsDirectory.appendingPathComponent($0.fileName) }
    }

    func isPlayable(_ stage: GameStage) -> Bool {
        images(for: stage).count >= Self.minimumPlayableItems
    }

    @discardableResult
    func importPastedImage() async -> UUID? {
        guard let image = UIPasteboard.general.image,
              let data = image.pngData() else {
            errorMessage = "コピーされた画像が見つかりません。写真アプリで被写体を長押しして「コピー」してから、もう一度お試しください。"
            return nil
        }

        return await addLiftedSubjectData(data)
    }

    @discardableResult
    func addLiftedSubject(_ image: UIImage) async -> UUID? {
        guard let data = image.pngData() else {
            errorMessage = SubjectProcessingError.renderFailed.localizedDescription
            return nil
        }
        return await addLiftedSubjectData(data)
    }

    @discardableResult
    private func addLiftedSubjectData(_ data: Data) async -> UUID? {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let asset = try await addImageData(data)
            return asset.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func saveStage(
        id: UUID?,
        name: String,
        assetIDs: [UUID],
        soundChanges: [UUID: MergeSoundChange] = [:]
    ) -> UUID? {
        let validIDs = uniqueValidAssetIDs(from: assetIDs)
        guard !validIDs.isEmpty else {
            errorMessage = "ステージには切り抜き素材を1個以上追加してください。"
            return nil
        }

        let previousSounds = id.flatMap { self.stage(withID: $0) }?.mergeSoundFileNames ?? [:]
        var sounds: [UUID: String] = [:]
        var newlyStoredFileNames: [String] = []
        for assetID in validIDs {
            switch soundChanges[assetID] ?? .keep {
            case .keep:
                sounds[assetID] = previousSounds[assetID]
            case .remove:
                break
            case .replace(let temporaryURL):
                guard let storedName = storeMergeSound(from: temporaryURL) else {
                    newlyStoredFileNames.forEach(removeMergeSoundFile)
                    return nil
                }
                newlyStoredFileNames.append(storedName)
                sounds[assetID] = storedName
            }
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stageName = trimmedName.isEmpty ? "ステージ \(stages.count + 1)" : trimmedName
        let now = Date()

        if let id, let index = stages.firstIndex(where: { $0.id == id }) {
            let previousStages = stages
            stages[index].name = stageName
            stages[index].assetIDs = validIDs
            stages[index].updatedAt = now
            stages[index].mergeSoundFileNames = sounds
            guard saveStages() else {
                stages = previousStages
                newlyStoredFileNames.forEach(removeMergeSoundFile)
                return nil
            }
            // 差し替え・削除・素材を外したことで使われなくなった音声を片付ける
            let keptFileNames = Set(sounds.values)
            previousSounds.values.filter { !keptFileNames.contains($0) }.forEach(removeMergeSoundFile)
            return id
        }

        let stage = GameStage(
            id: UUID(),
            name: stageName,
            assetIDs: validIDs,
            createdAt: now,
            updatedAt: now,
            mergeSoundFileNames: sounds
        )
        stages.insert(stage, at: 0)
        guard saveStages() else {
            stages.removeAll { $0.id == stage.id }
            newlyStoredFileNames.forEach(removeMergeSoundFile)
            return nil
        }
        return stage.id
    }

    @discardableResult
    func deleteStage(_ stage: GameStage) -> Bool {
        let previousStages = stages
        stages.removeAll { $0.id == stage.id }
        guard saveStages() else {
            stages = previousStages
            return false
        }
        stage.mergeSoundFileNames?.values.forEach(removeMergeSoundFile)
        // 共有中のステージは公開をやめる（受け取り済みの友達の手元には残る）
        if let code = stage.shareCode {
            Task { try? await StageShareService.shared.delete(code: code) }
        }
        return true
    }

    func markShared(stageID: UUID, code: String, at date: Date) {
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        stages[index].shareCode = code
        stages[index].sharedAt = date
        saveStages()
    }

    func clearShare(stageID: UUID) {
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        stages[index].shareCode = nil
        stages[index].sharedAt = nil
        saveStages()
    }

    /// 友達から受け取ったステージを、素材と進化音ごとライブラリに追加する
    @discardableResult
    func addReceivedStage(_ received: ReceivedStage) -> UUID? {
        var newAssets: [SubjectAsset] = []
        do {
            try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
            for (data, image) in zip(received.imageData, received.images) {
                let id = UUID()
                let fileName = "\(id.uuidString).png"
                try data.write(to: assetsDirectory.appendingPathComponent(fileName), options: .atomic)
                newAssets.append(SubjectAsset(id: id, fileName: fileName, image: image))
            }
        } catch {
            newAssets.forEach { try? fileManager.removeItem(at: assetsDirectory.appendingPathComponent($0.fileName)) }
            errorMessage = "ステージを追加できませんでした。"
            return nil
        }

        assets.append(contentsOf: newAssets)
        var soundChanges: [UUID: MergeSoundChange] = [:]
        for (asset, soundURL) in zip(newAssets, received.soundURLs) {
            if let soundURL { soundChanges[asset.id] = .replace(soundURL) }
        }
        guard let stageID = saveStage(id: nil, name: received.name, assetIDs: newAssets.map(\.id), soundChanges: soundChanges) else {
            let newIDs = Set(newAssets.map(\.id))
            assets.removeAll { newIDs.contains($0.id) }
            newAssets.forEach { try? fileManager.removeItem(at: assetsDirectory.appendingPathComponent($0.fileName)) }
            return nil
        }
        UserDefaults.standard.set(assets.map(\.fileName), forKey: assetOrderKey)
        return stageID
    }

    private func storeMergeSound(from temporaryURL: URL) -> String? {
        do {
            try fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
            let ext = temporaryURL.pathExtension.isEmpty ? "m4a" : temporaryURL.pathExtension
            let fileName = "\(UUID().uuidString).\(ext)"
            try fileManager.copyItem(at: temporaryURL, to: soundsDirectory.appendingPathComponent(fileName))
            return fileName
        } catch {
            errorMessage = "進化音を保存できませんでした。"
            return nil
        }
    }

    private func removeMergeSoundFile(_ fileName: String) {
        try? fileManager.removeItem(at: soundsDirectory.appendingPathComponent(fileName))
    }

    func remove(_ asset: SubjectAsset) {
        assets.removeAll { $0.id == asset.id }
        try? fileManager.removeItem(at: assetsDirectory.appendingPathComponent(asset.fileName))
        UserDefaults.standard.set(assets.map(\.fileName), forKey: assetOrderKey)

        let now = Date()
        for index in stages.indices where stages[index].assetIDs.contains(asset.id) {
            stages[index].assetIDs.removeAll { $0 == asset.id }
            if let soundFileName = stages[index].mergeSoundFileNames?.removeValue(forKey: asset.id) {
                removeMergeSoundFile(soundFileName)
            }
            stages[index].updatedAt = now
        }
        saveStages()
    }

    private func uniqueValidAssetIDs(from ids: [UUID]) -> [UUID] {
        let availableIDs = Set(assets.map(\.id))
        var seen = Set<UUID>()
        return ids.filter { availableIDs.contains($0) && seen.insert($0).inserted }
            .prefix(Self.maximumStageItems)
            .map { $0 }
    }

    private func addImageData(_ data: Data) async throws -> SubjectAsset {
        let pngData = try await Task.detached(priority: .userInitiated) {
            try SubjectExtractor.prepare(data: data)
        }.value

        guard let image = UIImage(data: pngData) else {
            throw SubjectProcessingError.unreadableImage
        }

        try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        try pngData.write(to: assetsDirectory.appendingPathComponent(fileName), options: .atomic)
        let asset = SubjectAsset(id: id, fileName: fileName, image: image)
        assets.append(asset)
        UserDefaults.standard.set(assets.map(\.fileName), forKey: assetOrderKey)
        return asset
    }

    private var applicationSupportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    private var assetsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("KuttukeSubjects", isDirectory: true)
    }

    private var soundsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("KuttukeSounds", isDirectory: true)
    }

    private var stagesURL: URL {
        applicationSupportDirectory.appendingPathComponent("KuttukeStages.json")
    }

    private func loadAssets() {
        guard let names = try? fileManager.contentsOfDirectory(atPath: assetsDirectory.path) else { return }
        let savedOrder = UserDefaults.standard.stringArray(forKey: assetOrderKey) ?? []
        let pngNames = names.filter { $0.hasSuffix(".png") }
        let sortedNames = pngNames.sorted { left, right in
            let leftIndex = savedOrder.firstIndex(of: left) ?? Int.max
            let rightIndex = savedOrder.firstIndex(of: right) ?? Int.max
            if leftIndex == rightIndex { return left < right }
            return leftIndex < rightIndex
        }

        assets = sortedNames.compactMap { name in
            let url = assetsDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data),
                  let id = UUID(uuidString: String(name.dropLast(4))) else { return nil }
            return SubjectAsset(id: id, fileName: name, image: image)
        }
    }

    private func loadStages() {
        guard fileManager.fileExists(atPath: stagesURL.path) else { return }
        do {
            let data = try Data(contentsOf: stagesURL)
            let savedStages = try JSONDecoder().decode([GameStage].self, from: data)
            let validAssetIDs = Set(assets.map(\.id))
            stages = savedStages.map { stage in
                var validStage = stage
                validStage.assetIDs = stage.assetIDs.filter { validAssetIDs.contains($0) }
                return validStage
            }
        } catch {
            errorMessage = "保存済みステージを読み込めませんでした。"
        }
    }

    @discardableResult
    private func saveStages() -> Bool {
        do {
            try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(stages)
            try data.write(to: stagesURL, options: .atomic)
            return true
        } catch {
            errorMessage = "ステージを保存できませんでした。"
            return false
        }
    }

    private func migrateLegacySetIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didMigrateLegacyStageKey) else { return }
        guard stages.isEmpty, !assets.isEmpty else {
            defaults.set(true, forKey: didMigrateLegacyStageKey)
            return
        }

        let now = Date()
        stages = [GameStage(
            id: UUID(),
            name: "マイステージ",
            assetIDs: Array(assets.prefix(Self.maximumStageItems)).map(\.id),
            createdAt: now,
            updatedAt: now
        )]
        if saveStages() {
            defaults.set(true, forKey: didMigrateLegacyStageKey)
        } else {
            stages = []
        }
    }
}
