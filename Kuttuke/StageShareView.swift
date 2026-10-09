import SwiftUI
import UIKit

/// ステージを友達に共有する画面。アップロードして共有コードとリンクを発行する
struct StageShareView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: SubjectLibrary
    let stageID: UUID

    private enum Phase {
        case confirm
        case uploading
        case shared(String)
        case failed(String)
    }

    @State private var phase: Phase = .confirm
    @State private var didCopy = false
    @State private var isConfirmingStop = false
    @State private var isStopping = false

    var body: some View {
        NavigationStack {
            ZStack {
                KuttukeTheme.background.ignoresSafeArea()

                if let stage = library.stage(withID: stageID) {
                    ScrollView {
                        VStack(spacing: 18) {
                            stageHeader(stage)
                            content(for: stage)
                        }
                        .padding(20)
                        .padding(.bottom, 30)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("友達に共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .disabled(isBusy)
                }
            }
            .interactiveDismissDisabled(isBusy)
        }
        .onAppear(perform: showCurrentCode)
    }

    private var isBusy: Bool {
        if case .uploading = phase { return true }
        return isStopping
    }

    private func stageHeader(_ stage: GameStage) -> some View {
        let images = library.images(for: stage)
        return VStack(spacing: 10) {
            HStack(spacing: -10) {
                ForEach(Array(images.prefix(6).enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                        .padding(3)
                        .background(KuttukeTheme.cream, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            Text(stage.name)
                .font(.system(size: 19, weight: .black, design: .rounded))
                .lineLimit(1)
            Text("\(images.count)個の素材")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    @ViewBuilder
    private func content(for stage: GameStage) -> some View {
        switch phase {
        case .confirm:
            confirmCard(stage)
        case .uploading:
            VStack(spacing: 14) {
                ProgressView()
                    .tint(KuttukeTheme.orange)
                    .scaleEffect(1.2)
                Text("アップロードしています…")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        case .shared(let code):
            sharedCard(stage, code: code)
        case .failed(let message):
            VStack(spacing: 14) {
                Text(message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
                    .multilineTextAlignment(.center)
                primaryButton("もう一度ためす", systemImage: "arrow.clockwise") { upload(stage) }
            }
            .padding(.top, 6)
        }
    }

    private func confirmCard(_ stage: GameStage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("共有のしくみ", systemImage: "person.2.fill")
                .font(.system(size: 15, weight: .black, design: .rounded))
            VStack(alignment: .leading, spacing: 8) {
                bullet("切り抜き画像と進化音をiCloudにアップロードし、共有コードを発行します。")
                bullet("友達はKuttukeのホームの「受け取る」からコードを入れるか、送ったリンクを開くと同じステージで遊べます。")
                bullet("コードを知っている人なら誰でも受け取れます。人に見られて困る写真は含めないでください。")
            }
            primaryButton("共有コードを発行", systemImage: "square.and.arrow.up") { upload(stage) }
                .padding(.top, 4)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private func sharedCard(_ stage: GameStage, code: String) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("共有コード")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
                Text(StageShareCode.formatted(code))
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .tracking(2)
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            ShareLink(item: shareMessage(stage, code: code)) {
                Label("友達に送る", systemImage: "paperplane.fill")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(KuttukeTheme.orange, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle())

            Button {
                UIPasteboard.general.string = StageShareCode.formatted(code)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation { didCopy = true }
            } label: {
                Label(didCopy ? "コピーしました" : "コードをコピー", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(KuttukeTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle())

            Text("ステージを編集したら、もう一度この画面を開くと同じコードの内容が最新になります。")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)
                .multilineTextAlignment(.center)

            Button(role: .destructive) {
                isConfirmingStop = true
            } label: {
                Group {
                    if isStopping {
                        ProgressView()
                    } else {
                        Text("共有をやめる")
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isStopping)
            .alert("共有をやめますか？", isPresented: $isConfirmingStop) {
                Button("共有をやめる", role: .destructive) { stopSharing(code: code) }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("このコードでは受け取れなくなります。すでに受け取った友達のステージは消えません。")
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(KuttukeTheme.orange)
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(KuttukeTheme.ink, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
    }

    private func shareMessage(_ stage: GameStage, code: String) -> String {
        "Kuttukeでわたしのステージ「\(stage.name)」を遊んでみて！\nホームの「受け取る」でコード \(StageShareCode.formatted(code)) を入力するか、このリンクを開いてね\n\(StageShareCode.url(for: code).absoluteString)"
    }

    /// 共有済みで編集もしていなければ、アップロードせずにコードを表示する
    private func showCurrentCode() {
        guard let stage = library.stage(withID: stageID),
              let code = stage.shareCode,
              !stage.needsShareUpload else { return }
        phase = .shared(code)
    }

    private func upload(_ stage: GameStage) {
        phase = .uploading
        let startedAt = Date()
        Task {
            do {
                let code = try await StageShareService.shared.upload(
                    name: stage.name,
                    imageURLs: library.imageFileURLs(for: stage),
                    soundURLs: library.mergeSoundURLs(for: stage),
                    existingCode: stage.shareCode
                )
                library.markShared(stageID: stage.id, code: code, at: startedAt)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation { phase = .shared(code) }
            } catch {
                withAnimation { phase = .failed(error.localizedDescription) }
            }
        }
    }

    private func stopSharing(code: String) {
        isStopping = true
        Task {
            defer { isStopping = false }
            do {
                try await StageShareService.shared.delete(code: code)
                library.clearShare(stageID: stageID)
                withAnimation { phase = .confirm }
            } catch {
                withAnimation { phase = .failed(error.localizedDescription) }
            }
        }
    }
}

/// 友達から教えてもらった共有コードでステージを受け取る画面
struct StageReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: SubjectLibrary
    let initialCode: String?
    var onAdded: (UUID) -> Void = { _ in }

    @State private var codeText = ""
    @State private var isLoading = false
    @State private var received: ReceivedStage?
    @State private var errorMessage: String?
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                KuttukeTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        codeCard
                        if let received {
                            previewCard(received)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("ステージを受け取る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .onAppear {
            if let initialCode {
                codeText = StageShareCode.formatted(initialCode)
                search()
            } else {
                isCodeFocused = true
            }
        }
        .onDisappear { received?.discardTemporaryFiles() }
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("共有コード")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text("友達から届いたコードを入力してください。メッセージをそのまま貼り付けても大丈夫です。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }

            HStack(spacing: 9) {
                TextField("ABCD-EFGH", text: $codeText)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .monospaced()
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isCodeFocused)
                    .onSubmit(search)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                Button(action: search) {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("探す")
                        }
                    }
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 50)
                    .background(KuttukeTheme.ink, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle())
                .disabled(isLoading || codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private func previewCard(_ received: ReceivedStage) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(received.name)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .lineLimit(1)
                Text(received.hasSounds ? "\(received.images.count)個の素材・進化音つき" : "\(received.images.count)個の素材")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(received.images.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .aspectRatio(1, contentMode: .fit)
                        .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            Button {
                add(received)
            } label: {
                Label("このステージを追加", systemImage: "plus")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(KuttukeTheme.orange, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle())
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private func search() {
        guard !isLoading else { return }
        guard let code = StageShareCode.normalize(codeText) else {
            errorMessage = StageShareError.invalidCode.localizedDescription
            return
        }
        codeText = StageShareCode.formatted(code)
        isCodeFocused = false
        errorMessage = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let stage = try await StageShareService.shared.fetch(code: code)
                received?.discardTemporaryFiles()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { received = stage }
            } catch {
                withAnimation {
                    received?.discardTemporaryFiles()
                    received = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func add(_ received: ReceivedStage) {
        guard let stageID = library.addReceivedStage(received) else {
            errorMessage = library.errorMessage
            library.errorMessage = nil
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onAdded(stageID)
        dismiss()
    }
}
