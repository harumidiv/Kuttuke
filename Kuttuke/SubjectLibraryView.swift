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
    @State private var isConfirmingStageDeletion = false
    @StateObject private var soundDraft: StageSoundDraft

    init(library: SubjectLibrary, stage: GameStage? = nil) {
        self.library = library
        self.stage = stage
        _stageName = State(initialValue: stage?.name ?? "")
        _selectedAssetIDs = State(initialValue: stage?.assetIDs ?? [])
        var savedSoundURLs: [UUID: URL] = [:]
        if let stage {
            for assetID in stage.assetIDs {
                savedSoundURLs[assetID] = library.mergeSoundURL(for: stage, assetID: assetID)
            }
        }
        _soundDraft = StateObject(wrappedValue: StageSoundDraft(savedURLs: savedSoundURLs))
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
                        advancedSettings
                        if stage != nil {
                            deleteStageButton
                        }
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
                        .disabled(selectedAssetIDs.isEmpty || library.isProcessing || isLoadingPhoto || soundDraft.isRecording)
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
            .confirmationDialog(
                "「\(stage?.name ?? "")」を削除しますか？",
                isPresented: $isConfirmingStageDeletion,
                titleVisibility: .visible
            ) {
                Button("ステージを削除", role: .destructive) { deleteStage() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("保存済みの切り抜き素材は削除されないため、別のステージで引き続き使えます。")
            }
        }
        .interactiveDismissDisabled(library.isProcessing || isLoadingPhoto)
        .onDisappear { soundDraft.discardTemporaryFiles() }
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
                    Text("小さい順に並べ、矢印か長押しドラッグで並べ替え")
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
                VStack(spacing: 0) {
                    ForEach(Array(selectedAssetIDs.enumerated()), id: \.element) { index, assetID in
                        if let asset = library.asset(withID: assetID) {
                            progressionRow(asset, index: index)
                        }
                    }
                }
                .padding(.vertical, -6)

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
                Text(index == selectedAssetIDs.count - 1
                     ? "最終形態（これ以上は進化しません）"
                     : "同じレベル同士で進化")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }

            Spacer(minLength: 4)

            HStack(spacing: 0) {
                // ドラッグに気づかなくても並べ替えられるよう、1つずつ移動するボタンを置く
                VStack(spacing: 0) {
                    moveButton(
                        systemImage: "chevron.up",
                        label: "レベル\(index + 1)を1つ上へ",
                        isEnabled: index > 0
                    ) {
                        moveSelection(at: index, by: -1)
                    }
                    moveButton(
                        systemImage: "chevron.down",
                        label: "レベル\(index + 1)を1つ下へ",
                        isEnabled: index < selectedAssetIDs.count - 1
                    ) {
                        moveSelection(at: index, by: 1)
                    }
                }

                Button {
                    withAnimation { selectedAssetIDs.removeAll { $0 == asset.id } }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .frame(width: 31, height: 31)
                        .background(.black.opacity(0.055), in: Circle())
                        .frame(width: 40, height: 54)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("レベル\(index + 1)を外す")
            }
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
        // セル全体をドラッグ開始領域にする（×ボタンのタップはそのまま効く）
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .accessibilityHint("長押ししてドラッグすると並べ替えできます")
        // 行間の隙間もドロップ先に含める
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let rawID = items.first,
                  let movingID = UUID(uuidString: rawID) else { return false }
            reorderSelection(movingID: movingID, targetID: asset.id)
            dropTargetAssetID = nil
            return true
        } isTargeted: { isTargeted in
            withAnimation(.easeInOut(duration: 0.14)) {
                if isTargeted {
                    dropTargetAssetID = asset.id
                } else if dropTargetAssetID == asset.id {
                    // 隣の行へ移った直後に届く離脱通知で、新しいハイライトを消さない
                    dropTargetAssetID = nil
                }
            }
        }
    }

    private func moveButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(KuttukeTheme.secondaryText)
                .frame(width: 40, height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.25)
        .accessibilityLabel(label)
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

    private var advancedSettings: some View {
        NavigationLink {
            MergeSoundSettingsView(
                library: library,
                assetIDs: selectedAssetIDs,
                soundDraft: soundDraft
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(KuttukeTheme.orange)
                    .frame(width: 34, height: 34)
                    .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("高度な詳細設定")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                    Text("進化したときの音を素材ごとに設定")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }
            .foregroundStyle(KuttukeTheme.ink)
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(selectedAssetIDs.count < 2)
        .opacity(selectedAssetIDs.count < 2 ? 0.45 : 1)
    }

    private var deleteStageButton: some View {
        Button(role: .destructive) {
            isConfirmingStageDeletion = true
        } label: {
            Label("このステージを削除", systemImage: "trash")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(library.isProcessing || isLoadingPhoto)
        .padding(.top, 6)
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

    private func moveSelection(at index: Int, by offset: Int) {
        let destination = index + offset
        guard selectedAssetIDs.indices.contains(index),
              selectedAssetIDs.indices.contains(destination) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            selectedAssetIDs.swapAt(index, destination)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func deleteStage() {
        guard let stage, library.deleteStage(stage) else { return }
        dismiss()
    }

    private func saveStage() {
        guard library.saveStage(
            id: stage?.id,
            name: stageName,
            assetIDs: selectedAssetIDs,
            soundChanges: soundDraft.changes
        ) != nil else { return }
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
