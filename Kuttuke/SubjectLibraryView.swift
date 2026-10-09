import ImageIO
import PhotosUI
import SwiftUI

struct SubjectLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: SubjectLibrary
    let stage: GameStage?

    @State private var stageName: String
    @State private var selectedAssetIDs: [UUID]
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoBatch: LiftPhotoBatch?
    @State private var isLoadingPhoto = false
    @State private var loadingPhotoProgress = ""
    @State private var pendingLoadFailureCount = 0
    @State private var assetPendingDeletion: SubjectAsset?
    @State private var dropTargetAssetID: UUID?

    init(library: SubjectLibrary, stage: GameStage? = nil) {
        self.library = library
        self.stage = stage
        _stageName = State(initialValue: stage?.name ?? "")
        _selectedAssetIDs = State(initialValue: stage?.assetIDs ?? [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KuttukeTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        nameCard
                        progression
                        assetLibrary
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)

                if library.isProcessing || isLoadingPhoto {
                    processingOverlay
                }
            }
            .navigationTitle(stage == nil ? "進化セットを作成" : "進化セットを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .disabled(library.isProcessing || isLoadingPhoto)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveStage() }
                        .fontWeight(.bold)
                        .disabled(selectedAssetIDs.isEmpty || library.isProcessing || isLoadingPhoto)
                }
            }
            .alert("操作できませんでした", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { library.errorMessage = nil }
            } message: {
                Text(library.errorMessage ?? "")
            }
            .confirmationDialog(
                "この切り抜きを削除しますか？",
                isPresented: Binding(
                    get: { assetPendingDeletion != nil },
                    set: { if !$0 { assetPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("素材ライブラリから削除", role: .destructive) {
                    guard let assetPendingDeletion else { return }
                    selectedAssetIDs.removeAll { $0 == assetPendingDeletion.id }
                    library.remove(assetPendingDeletion)
                    self.assetPendingDeletion = nil
                }
                Button("キャンセル", role: .cancel) {
                    assetPendingDeletion = nil
                }
            } message: {
                Text("この素材を使用している他の進化セットからも外れます。")
            }
        }
        .interactiveDismissDisabled(library.isProcessing || isLoadingPhoto)
        .fullScreenCover(item: $photoBatch, onDismiss: handleBatchDismiss) { batch in
            SubjectLiftBatchEditorView(
                images: batch.images,
                library: library,
                maximumCutouts: remainingStageSlots
            ) { assetID in
                addToStage(assetID)
            }
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("ステージ名", systemImage: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)

            TextField("例：うちの猫", text: $stageName)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .padding(.horizontal, 15)
                .frame(height: 52)
                .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("保存するとホームからすぐ遊べます")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var progression: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("このセットの進化順")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                    Text("小さい順に並べ、右のハンドルで並べ替え")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                }
                Spacer()
                Text("\(selectedAssetIDs.count)/\(SubjectLibrary.maximumStageItems)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(KuttukeTheme.orange, in: Capsule())
            }

            if selectedAssetIDs.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(KuttukeTheme.orange)
                    Text("下の素材を選んで追加してください")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 23)
            } else {
                ForEach(Array(selectedAssetIDs.enumerated()), id: \.element) { index, assetID in
                    if let asset = library.asset(withID: assetID) {
                        progressionRow(asset, index: index)
                    }
                }

                if selectedAssetIDs.count < SubjectLibrary.minimumPlayableItems {
                    Label(
                        "あと\(SubjectLibrary.minimumPlayableItems - selectedAssetIDs.count)個追加すると遊べます",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(KuttukeTheme.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func progressionRow(_ asset: SubjectAsset, index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(levelColor(index), in: Circle())

            Image(uiImage: asset.image)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .padding(3)
                .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("レベル \(index + 1)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(index == selectedAssetIDs.count - 1 && selectedAssetIDs.count < SubjectLibrary.maximumStageItems
                     ? "以降はこの素材が大きくなります"
                     : "同じレベル同士で進化")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }

            Spacer(minLength: 4)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(KuttukeTheme.secondaryText)
                .frame(width: 34, height: 38)
                .contentShape(Rectangle())
                .draggable(asset.id.uuidString) {
                    Image(uiImage: asset.image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .frame(width: 72, height: 72)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 5)
                }
                .accessibilityLabel("レベル\(index + 1)をドラッグして並べ替え")

            Button {
                withAnimation { selectedAssetIDs.removeAll { $0 == asset.id } }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .black))
                    .frame(width: 31, height: 31)
                    .background(.black.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            dropTargetAssetID == asset.id ? KuttukeTheme.orange.opacity(0.13) : .white,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(dropTargetAssetID == asset.id ? KuttukeTheme.orange : .clear, lineWidth: 2)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let rawID = items.first,
                  let movingID = UUID(uuidString: rawID) else { return false }
            reorderSelection(movingID: movingID, targetID: asset.id)
            dropTargetAssetID = nil
            return true
        } isTargeted: { isTargeted in
            withAnimation(.easeInOut(duration: 0.14)) {
                dropTargetAssetID = isTargeted ? asset.id : nil
            }
        }
    }

    private var assetLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("保存済みの切り抜き")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                Text("一度切り抜いた素材は、どのセットでも使えます")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }

            importActions

            if library.assets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(KuttukeTheme.orange)
                    Text("まだ保存済み素材がありません")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(library.assets) { asset in
                        assetCell(asset)
                    }
                }
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var importActions: some View {
        VStack(spacing: 9) {
            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: max(1, remainingStageSlots),
                matching: .images
            ) {
                actionLabel(icon: "hand.draw.fill", title: "写真を複数選んで切り抜く", filled: true)
            }
            .disabled(remainingStageSlots == 0 || isLoadingPhoto)
            .opacity(remainingStageSlots == 0 ? 0.35 : 1)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await openPhotos(items) }
            }

            Button {
                Task {
                    if let assetID = await library.importPastedImage() {
                        addToStage(assetID)
                    }
                }
            } label: {
                actionLabel(icon: "doc.on.clipboard", title: "コピーした切り抜きを追加", filled: false)
            }
            .buttonStyle(BouncyButtonStyle())
        }
    }

    private func actionLabel(icon: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .black))
        }
        .foregroundStyle(filled ? .white : KuttukeTheme.ink)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(filled ? KuttukeTheme.ink : KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func assetCell(_ asset: SubjectAsset) -> some View {
        let selectedIndex = selectedAssetIDs.firstIndex(of: asset.id)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                toggleSelection(asset.id)
            }
        } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: asset.image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                        .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 17, style: .continuous))

                    if let selectedIndex {
                        Text("\(selectedIndex + 1)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 23, height: 23)
                            .background(KuttukeTheme.orange, in: Circle())
                            .padding(5)
                    }
                }

                Label(selectedIndex == nil ? "追加" : "選択中", systemImage: selectedIndex == nil ? "plus.circle" : "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(selectedIndex == nil ? KuttukeTheme.secondaryText : KuttukeTheme.orange)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                assetPendingDeletion = asset
            } label: {
                Label("素材を削除", systemImage: "trash")
            }
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(KuttukeTheme.orange)
                    .scaleEffect(1.2)
                Text(isLoadingPhoto ? "写真を読み込んでいます…" : "切り抜きを保存しています…")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                if isLoadingPhoto, !loadingPhotoProgress.isEmpty {
                    Text(loadingPhotoProgress)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 23)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        }
    }

    private func toggleSelection(_ assetID: UUID) {
        if selectedAssetIDs.contains(assetID) {
            selectedAssetIDs.removeAll { $0 == assetID }
        } else {
            addToStage(assetID)
        }
    }

    private func addToStage(_ assetID: UUID) {
        guard !selectedAssetIDs.contains(assetID) else { return }
        guard selectedAssetIDs.count < SubjectLibrary.maximumStageItems else {
            library.errorMessage = "1つの進化セットに追加できる素材は最大\(SubjectLibrary.maximumStageItems)個です。"
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            selectedAssetIDs.append(assetID)
        }
    }

    private func reorderSelection(movingID: UUID, targetID: UUID) {
        guard movingID != targetID,
              let sourceIndex = selectedAssetIDs.firstIndex(of: movingID),
              let targetIndex = selectedAssetIDs.firstIndex(of: targetID) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            selectedAssetIDs.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    private func saveStage() {
        guard library.saveStage(id: stage?.id, name: stageName, assetIDs: selectedAssetIDs) != nil else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private var remainingStageSlots: Int {
        max(0, SubjectLibrary.maximumStageItems - selectedAssetIDs.count)
    }

    private func openPhotos(_ items: [PhotosPickerItem]) async {
        guard !isLoadingPhoto else { return }
        isLoadingPhoto = true
        loadingPhotoProgress = "0 / \(items.count)枚"

        var images: [UIImage] = []
        var failureCount = 0

        for (index, item) in items.enumerated() {
            loadingPhotoProgress = "\(index + 1) / \(items.count)枚"
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw SubjectProcessingError.unreadableImage
                }
                let image = try await Task.detached(priority: .userInitiated) {
                    try LiftPhotoPreparer.prepare(data: data)
                }.value
                images.append(image)
            } catch {
                failureCount += 1
            }
        }

        isLoadingPhoto = false
        loadingPhotoProgress = ""
        photoItems = []

        guard !images.isEmpty else {
            library.errorMessage = SubjectProcessingError.unreadableImage.localizedDescription
            return
        }

        pendingLoadFailureCount += failureCount
        photoBatch = LiftPhotoBatch(images: images)
    }

    private func handleBatchDismiss() {
        if pendingLoadFailureCount > 0 {
            let count = pendingLoadFailureCount
            pendingLoadFailureCount = 0
            library.errorMessage = "\(count)枚の写真を読み込めませんでした。もう一度選択してください。"
        }
    }

    private func levelColor(_ index: Int) -> Color {
        [KuttukeTheme.orange, KuttukeTheme.pink, KuttukeTheme.purple, .blue, .teal, .green][index % 6]
    }
}

private struct LiftPhotoBatch: Identifiable {
    let id = UUID()
    let images: [UIImage]
}

private enum LiftPhotoPreparer {
    nonisolated static let analysisMaxPixelSize = 1600

    nonisolated static func prepare(data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw SubjectProcessingError.unreadableImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: analysisMaxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw SubjectProcessingError.unreadableImage
        }
        return UIImage(cgImage: thumbnail)
    }
}
