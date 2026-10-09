import SwiftUI
import UniformTypeIdentifiers
import UIKit
import VisionKit

enum LiftAnalysisStatus: Equatable {
    case analyzing
    case ready
    case unsupported
    case failed
}

struct SubjectLiftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let photo: UIImage
    @ObservedObject var library: SubjectLibrary
    let batchLabel: String?
    let onSaved: (UUID) -> Void

    @State private var analysisStatus: LiftAnalysisStatus = .analyzing
    @State private var liftedSubject: UIImage?
    @State private var isDropTargeted = false
    @State private var isSaving = false

    init(
        photo: UIImage,
        library: SubjectLibrary,
        batchLabel: String? = nil,
        onSaved: @escaping (UUID) -> Void = { _ in }
    ) {
        self.photo = photo
        self.library = library
        self.batchLabel = batchLabel
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KuttukeTheme.background.ignoresSafeArea()

                VStack(spacing: 14) {
                    instruction
                    photoStage
                    transferArrow
                    dropZone
                    saveButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 12)

                if analysisStatus == .analyzing {
                    analysisLoadingOverlay
                }

                if isSaving {
                    savingOverlay
                }
            }
            .navigationTitle("被写体を切り抜く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("完了") { saveSubject() }
                            .fontWeight(.bold)
                            .disabled(liftedSubject == nil)
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

    private var instruction: some View {
        HStack(spacing: 12) {
            Text("1")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 27, height: 27)
                .background(KuttukeTheme.orange, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("写真の被写体を長押し")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text("光ったら、そのまま指を離さず下へ動かします")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }
            Spacer()
            if let batchLabel {
                Text(batchLabel)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(KuttukeTheme.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(KuttukeTheme.cream, in: Capsule())
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 58)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private var photoStage: some View {
        ZStack {
            Color(red: 0.105, green: 0.11, blue: 0.12)

            LiftablePhotoView(image: photo) { status in
                withAnimation(.easeInOut(duration: 0.2)) {
                    analysisStatus = status
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(7)

            VStack {
                HStack {
                    Spacer()
                    statusBadge
                }
                Spacer()

                if analysisStatus == .unsupported ||
                    analysisStatus == .failed {
                    analysisMessage
                }
            }
            .padding(13)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 2)
                .allowsHitTesting(false)
        )
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch analysisStatus {
        case .analyzing:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("写真を準備しています")
            }
            .statusCapsule()
        case .ready:
            Label("長押しできます", systemImage: "hand.tap.fill")
                .statusCapsule()
        case .unsupported, .failed:
            Label("切り抜きできません", systemImage: "exclamationmark.triangle.fill")
                .statusCapsule()
        }
    }

    private var analysisMessage: some View {
        Text(analysisMessageText)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.black.opacity(0.68), in: Capsule())
            .padding(.bottom, 4)
    }

    private var analysisMessageText: String {
        switch analysisStatus {
        case .unsupported:
            return "この端末は被写体の切り抜きに対応していません"
        case .failed:
            return "写真の解析に失敗しました。別の写真をお試しください"
        case .analyzing, .ready:
            return ""
        }
    }

    private var transferArrow: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(KuttukeTheme.orange)
            Text("長押しした被写体をここへ")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)
        }
        .frame(height: 18)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isDropTargeted ? KuttukeTheme.orange.opacity(0.16) : .white.opacity(0.78))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isDropTargeted ? KuttukeTheme.orange : KuttukeTheme.secondaryText.opacity(0.26),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 2, dash: [8, 6])
                )

            if let liftedSubject {
                HStack(spacing: 16) {
                    Image(uiImage: liftedSubject)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.12), radius: 7, y: 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("置けました！", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.green)
                        Text("右上の「完了」で保存します")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: isDropTargeted ? "hand.point.down.fill" : "square.and.arrow.down")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(isDropTargeted ? KuttukeTheme.orange : KuttukeTheme.secondaryText)
                    Text(isDropTargeted ? "ここで指を離す" : "切り抜きを置く")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                    Text("背景が透明な画像だけが登録されます")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                }
            }

            SubjectDropReceiver(isTargeted: $isDropTargeted) { image in
                liftedSubject = image
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .frame(height: 130)
        .scaleEffect(isDropTargeted ? 1.015 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isDropTargeted)
    }

    private var saveButton: some View {
        Button {
            saveSubject()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus.circle.fill")
                Text("完了して保存")
            }
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(KuttukeTheme.ink, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(liftedSubject == nil || isSaving)
        .opacity(liftedSubject == nil ? 0.28 : 1)
    }

    private var savingOverlay: some View {
        Color.black.opacity(0.18)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(KuttukeTheme.orange)
                    Text("ゲーム用のサイズに整えています…")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
    }

    private var analysisLoadingOverlay: some View {
        Color.black.opacity(0.24)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 13) {
                    ProgressView()
                        .tint(KuttukeTheme.orange)
                        .scaleEffect(1.2)
                    Text("切り抜きを準備しています…")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("読み込みが終わるまでお待ちください")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .transition(.opacity)
    }

    private func saveSubject() {
        guard let liftedSubject else { return }
        isSaving = true
        Task {
            let savedAssetID = await library.addLiftedSubject(liftedSubject)
            isSaving = false
            if let savedAssetID {
                onSaved(savedAssetID)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}

struct LiftablePhotoView: UIViewRepresentable {
    let image: UIImage
    let onStatusChange: (LiftAnalysisStatus) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStatusChange: onStatusChange)
    }

    func makeUIView(context: Context) -> LiftImageView {
        let imageView = LiftImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.image = image
        imageView.addInteraction(context.coordinator.interaction)
        context.coordinator.analyze(image)
        return imageView
    }

    func updateUIView(_ imageView: LiftImageView, context: Context) {
        context.coordinator.onStatusChange = onStatusChange
        guard imageView.image !== image else { return }
        imageView.image = image
        context.coordinator.analyze(image)
    }

    static func dismantleUIView(_ imageView: LiftImageView, coordinator: Coordinator) {
        coordinator.analysisTask?.cancel()
        coordinator.interaction.analysis = nil
    }

    @MainActor
    final class Coordinator {
        let interaction = ImageAnalysisInteraction()
        var onStatusChange: (LiftAnalysisStatus) -> Void
        var analysisTask: Task<Void, Never>?

        init(onStatusChange: @escaping (LiftAnalysisStatus) -> Void) {
            self.onStatusChange = onStatusChange
            interaction.preferredInteractionTypes = [.imageSubject]
        }

        func analyze(_ image: UIImage) {
            analysisTask?.cancel()
            interaction.analysis = nil
            Task { @MainActor [onStatusChange] in
                onStatusChange(.analyzing)
            }

            guard ImageAnalyzer.isSupported else {
                onStatusChange(.unsupported)
                return
            }

            analysisTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let analyzer = ImageAnalyzer()
                    let configuration = ImageAnalyzer.Configuration([])
                    let analysis = try await analyzer.analyze(image, configuration: configuration)
                    guard !Task.isCancelled else { return }
                    interaction.analysis = analysis
                    interaction.preferredInteractionTypes = [.imageSubject]
                    interaction.setContentsRectNeedsUpdate()

                    // Subject Lift prepares its subject regions lazily. Warm them up while
                    // the loading overlay is still visible, but never reject an empty result.
                    _ = await interaction.subjects
                    guard !Task.isCancelled else { return }
                    interaction.setContentsRectNeedsUpdate()
                    onStatusChange(.ready)
                } catch is CancellationError {
                    return
                } catch {
                    onStatusChange(.failed)
                }
            }
        }
    }
}

final class LiftImageView: UIImageView {
    override var intrinsicContentSize: CGSize { .zero }
}

struct SubjectDropReceiver: UIViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isTargeted: $isTargeted, onDrop: onDrop)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.addInteraction(UIDropInteraction(delegate: context.coordinator))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.isTargeted = $isTargeted
        context.coordinator.onDrop = onDrop
    }

    @MainActor
    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var isTargeted: Binding<Bool>
        var onDrop: (UIImage) -> Void

        init(isTargeted: Binding<Bool>, onDrop: @escaping (UIImage) -> Void) {
            self.isTargeted = isTargeted
            self.onDrop = onDrop
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.hasItemsConforming(toTypeIdentifiers: [UTType.image.identifier])
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            isTargeted.wrappedValue = true
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            isTargeted.wrappedValue = false
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
            isTargeted.wrappedValue = false
        }

        func dropInteraction(
            _ interaction: UIDropInteraction,
            sessionDidUpdate session: UIDropSession
        ) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            isTargeted.wrappedValue = false
            guard let provider = session.items.lazy.map(\.itemProvider).first(where: {
                $0.canLoadObject(ofClass: UIImage.self)
            }) else { return }

            let dropHandler = onDrop
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in
                    dropHandler(image)
                }
            }
        }
    }
}

private extension View {
    func statusCapsule() -> some View {
        font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.black.opacity(0.66), in: Capsule())
    }
}
