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
    func saveStage(id: UUID?, name: String, assetIDs: [UUID]) -> UUID? {
        let validIDs = uniqueValidAssetIDs(from: assetIDs)
        guard !validIDs.isEmpty else {
            errorMessage = "ステージには切り抜き素材を1個以上追加してください。"
            return nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stageName = trimmedName.isEmpty ? "ステージ \(stages.count + 1)" : trimmedName
        let now = Date()

        if let id, let index = stages.firstIndex(where: { $0.id == id }) {
            let previousStages = stages
            stages[index].name = stageName
            stages[index].assetIDs = validIDs
            stages[index].updatedAt = now
            guard saveStages() else {
                stages = previousStages
                return nil
            }
            return id
        }

        let stage = GameStage(
            id: UUID(),
            name: stageName,
            assetIDs: validIDs,
            createdAt: now,
            updatedAt: now
        )
        stages.insert(stage, at: 0)
        guard saveStages() else {
            stages.removeAll { $0.id == stage.id }
            return nil
        }
        return stage.id
    }

    func deleteStage(_ stage: GameStage) {
        let previousStages = stages
        stages.removeAll { $0.id == stage.id }
        if !saveStages() {
            stages = previousStages
        }
    }

    func remove(_ asset: SubjectAsset) {
        assets.removeAll { $0.id == asset.id }
        try? fileManager.removeItem(at: assetsDirectory.appendingPathComponent(asset.fileName))
        UserDefaults.standard.set(assets.map(\.fileName), forKey: assetOrderKey)

        let now = Date()
        for index in stages.indices where stages[index].assetIDs.contains(asset.id) {
            stages[index].assetIDs.removeAll { $0 == asset.id }
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
