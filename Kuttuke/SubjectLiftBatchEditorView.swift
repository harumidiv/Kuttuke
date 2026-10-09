import SwiftUI
import UIKit

struct SubjectLiftBatchEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: SubjectLibrary
    let onSaved: (UUID) -> Void

    private let photos: [BatchLiftPhoto]
    private let maximumCutouts: Int

    @State private var currentIndex = 0
    @State private var analysisStatuses: [UUID: LiftAnalysisStatus]
    @State private var liftedSubjects: [UUID: [BatchLiftedSubject]] = [:]
    @State private var isDropTargeted = false
    @State private var isSaving = false
    @State private var savingProgress = ""

    init(
        images: [UIImage],
        library: SubjectLibrary,
        maximumCutouts: Int = SubjectLibrary.maximumStageItems,
        onSaved: @escaping (UUID) -> Void = { _ in }
    ) {
        let photos = Array(images.prefix(SubjectLibrary.maximumStageItems)).map {
            BatchLiftPhoto(image: $0)
        }
        self.photos = photos
        self.library = library
        self.maximumCutouts = min(max(maximumCutouts, 1), SubjectLibrary.maximumStageItems)
        self.onSaved = onSaved
        _analysisStatuses = State(initialValue: Dictionary(
            uniqueKeysWithValues: photos.map { ($0.id, LiftAnalysisStatus.analyzing) }
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KuttukeTheme.background.ignoresSafeArea()

                VStack(spacing: 12) {
                    instruction
                    photoPager
                    transferArrow
                    dropZone
                    saveButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 9)
                .padding(.bottom, 12)

                if isSaving {
                    savingOverlay
                }
            }
            .navigationTitle("被写体を切り抜く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("完了") { saveSubjects() }
                            .fontWeight(.bold)
                            .disabled(totalLiftedSubjectCount == 0)
                    }
                }
            }
            .alert("登録できませんでした", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { library.errorMessage = nil }
            } message: {
                Text(library.errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var currentPhoto: BatchLiftPhoto {
        photos[min(max(currentIndex, 0), photos.count - 1)]
    }

    private var currentStatus: LiftAnalysisStatus {
        analysisStatuses[currentPhoto.id] ?? .analyzing
    }

    private var currentLiftedSubjects: [BatchLiftedSubject] {
        liftedSubjects[currentPhoto.id] ?? []
    }

    private var totalLiftedSubjectCount: Int {
        liftedSubjects.values.reduce(0) { $0 + $1.count }
    }

    private var instruction: some View {
        HStack(spacing: 11) {
            Text("1")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 27, height: 27)
                .background(KuttukeTheme.orange, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("被写体を長押しして下へ")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text("横スワイプで写真を切り替えられます")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }

            Spacer(minLength: 4)

            Text("\(currentIndex + 1) / \(photos.count)")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(KuttukeTheme.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(KuttukeTheme.cream, in: Capsule())
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private var photoPager: some View {
        VStack(spacing: 8) {
            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    photoPage(photo, index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            thumbnailStrip
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 225, maxHeight: .infinity)
    }

    private func photoPage(_ photo: BatchLiftPhoto, index: Int) -> some View {
        let status = analysisStatuses[photo.id] ?? .analyzing
        return ZStack {
            Color(red: 0.105, green: 0.11, blue: 0.12)

            LiftablePhotoView(image: photo.image, isActive: index == currentIndex) { newStatus in
                withAnimation(.easeInOut(duration: 0.2)) {
                    analysisStatuses[photo.id] = newStatus
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(7)

            VStack {
                HStack {
                    Spacer()
                    statusBadge(status)
                }
                Spacer()

                if status == .unsupported || status == .failed {
                    analysisMessage(status)
                }
            }
            .padding(13)
            .allowsHitTesting(false)

            if status == .analyzing {
                pageLoadingOverlay
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 2)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
        .padding(.horizontal, 1)
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                currentIndex = index
                            }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: photo.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 38, height: 38)
                                    .clipped()
                                    .background(.black.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                currentIndex == index ? KuttukeTheme.orange : .clear,
                                                lineWidth: 3
                                            )
                                    )

                                if let count = liftedSubjects[photo.id]?.count, count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(.green, in: Circle())
                                        .overlay(Circle().stroke(.white, lineWidth: 2))
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(photo.id)
                        .accessibilityLabel("\(index + 1)枚目")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
            .onChange(of: currentIndex) { _, newIndex in
                guard photos.indices.contains(newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(photos[newIndex].id, anchor: .center)
                }
            }
        }
        .frame(height: 48)
    }

    @ViewBuilder
    private func statusBadge(_ status: LiftAnalysisStatus) -> some View {
        switch status {
        case .analyzing:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("準備中")
            }
            .batchStatusCapsule()
        case .ready:
            Label("長押しできます", systemImage: "hand.tap.fill")
                .batchStatusCapsule()
        case .unsupported, .failed:
            Label("切り抜きできません", systemImage: "exclamationmark.triangle.fill")
                .batchStatusCapsule()
        }
    }

    private func analysisMessage(_ status: LiftAnalysisStatus) -> some View {
        Text(status == .unsupported
             ? "この端末は被写体の切り抜きに対応していません"
             : "写真の解析に失敗しました")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(.black.opacity(0.68), in: Capsule())
    }

    private var pageLoadingOverlay: some View {
        Color.black.opacity(0.72)
            .overlay {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(KuttukeTheme.orange)
                    Text("被写体を解析しています…")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("長押しできるまでお待ちください")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
    }

    private var transferArrow: some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(KuttukeTheme.orange)
                Text("同じ写真から複数追加できます")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }

            Spacer()

            if !currentLiftedSubjects.isEmpty {
                Button("この写真をリセット") {
                    withAnimation { liftedSubjects[currentPhoto.id] = [] }
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(KuttukeTheme.orange)
                .buttonStyle(.plain)
            }
        }
        .frame(height: 17)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isDropTargeted ? KuttukeTheme.orange.opacity(0.16) : .white.opacity(0.78))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isDropTargeted ? KuttukeTheme.orange : KuttukeTheme.secondaryText.opacity(0.26),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 2, dash: [8, 6])
                )

            if !currentLiftedSubjects.isEmpty {
                HStack(spacing: 10) {
                    HStack(spacing: -8) {
                        ForEach(Array(currentLiftedSubjects.prefix(4).enumerated()), id: \.element.id) { index, subject in
                            Image(uiImage: subject.image)
                                .resizable()
                                .scaledToFit()
                                .padding(3)
                                .frame(width: 57, height: 57)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                                .zIndex(Double(currentLiftedSubjects.count - index))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("この写真から\(currentLiftedSubjects.count)個", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.green)
                        Text("さらに別の被写体も追加できます")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                    }
                }
            } else {
                VStack(spacing: 5) {
                    Image(systemName: isDropTargeted ? "hand.point.down.fill" : "square.and.arrow.down")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(isDropTargeted ? KuttukeTheme.orange : KuttukeTheme.secondaryText)
                    Text(isDropTargeted ? "ここで指を離す" : "切り抜きを置く")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
            }

            let destinationPhotoID = currentPhoto.id
            SubjectDropReceiver(isTargeted: $isDropTargeted) { image in
                guard totalLiftedSubjectCount < maximumCutouts else {
                    library.errorMessage = "切り抜きは最大\(maximumCutouts)個まで追加できます。"
                    return
                }
                liftedSubjects[destinationPhotoID, default: []].append(BatchLiftedSubject(image: image))
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .frame(height: 108)
        .scaleEffect(isDropTargeted ? 1.015 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isDropTargeted)
    }

    private var saveButton: some View {
        Button { saveSubjects() } label: {
            Label(
                totalLiftedSubjectCount == 0 ? "切り抜きを選択してください" : "\(totalLiftedSubjectCount)個の切り抜きを保存",
                systemImage: "checkmark.circle.fill"
            )
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 53)
            .background(KuttukeTheme.ink, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(totalLiftedSubjectCount == 0 || isSaving)
        .opacity(totalLiftedSubjectCount == 0 ? 0.28 : 1)
    }

    private var savingOverlay: some View {
        Color.black.opacity(0.22)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(KuttukeTheme.orange)
                    Text("切り抜きを保存しています…")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    if !savingProgress.isEmpty {
                        Text(savingProgress)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 27)
                .padding(.vertical, 22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
    }

    private func saveSubjects() {
        let pending = photos.flatMap { photo in
            (liftedSubjects[photo.id] ?? []).map { subject in
                (photoID: photo.id, subject: subject)
            }
        }
        guard !pending.isEmpty else { return }

        isSaving = true
        Task {
            for (index, item) in pending.enumerated() {
                savingProgress = "\(index + 1) / \(pending.count)個"
                guard let assetID = await library.addLiftedSubject(item.subject.image) else {
                    isSaving = false
                    savingProgress = ""
                    return
                }
                onSaved(assetID)
                liftedSubjects[item.photoID]?.removeAll { $0.id == item.subject.id }
            }

            isSaving = false
            savingProgress = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }
}

private struct BatchLiftPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct BatchLiftedSubject: Identifiable {
    let id = UUID()
    let image: UIImage
}

private extension View {
    func batchStatusCapsule() -> some View {
        font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.66), in: Capsule())
    }
}
