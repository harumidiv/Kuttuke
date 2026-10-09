import SwiftUI
import UniformTypeIdentifiers

/// 高度な詳細設定：進化の順番に並んだ素材ごとに、その素材へ進化したときの音を設定する
struct MergeSoundSettingsView: View {
    @ObservedObject var library: SubjectLibrary
    let assetIDs: [UUID]
    @ObservedObject var soundDraft: StageSoundDraft

    @State private var importingAssetID: UUID?

    var body: some View {
        ZStack {
            KuttukeTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("進化したときの音")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                        Text("合体してその素材に進化したときに鳴ります。録音は最大\(Int(StageSoundDraft.maximumRecordingDuration))秒、ファイルは\(Int(StageSoundDraft.maximumFileDuration))秒以内です。編集画面で「保存」すると反映されます。")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                    }
                    .padding(.horizontal, 4)

                    ForEach(Array(assetIDs.enumerated()), id: \.element) { index, assetID in
                        if let asset = library.asset(withID: assetID) {
                            soundRow(asset, level: index)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("高度な詳細設定")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(soundDraft.isRecording)
        .fileImporter(
            isPresented: Binding(
                get: { importingAssetID != nil },
                set: { if !$0 { importingAssetID = nil } }
            ),
            allowedContentTypes: [.audio]
        ) { result in
            guard let assetID = importingAssetID, case .success(let url) = result else { return }
            do {
                try soundDraft.importFile(at: url, for: assetID)
            } catch {
                library.errorMessage = error.localizedDescription
            }
        }
        .onDisappear { soundDraft.stopPreview() }
    }

    @ViewBuilder
    private func soundRow(_ asset: SubjectAsset, level: Int) -> some View {
        let isRecordingThis = soundDraft.recordingAssetID == asset.id
        let soundURL = soundDraft.url(for: asset.id)
        // レベル1は最初の姿で、合体して現れることがないため音は鳴らない
        let isFirstLevel = level == 0

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(uiImage: asset.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .padding(3)
                    .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("レベル \(level + 1)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                    Text(statusText(for: asset.id, isFirstLevel: isFirstLevel, isRecording: isRecordingThis))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isRecordingThis ? .red : KuttukeTheme.secondaryText)
                        .monospacedDigit()
                }

                Spacer(minLength: 4)

                if soundURL != nil, !isRecordingThis {
                    Button {
                        if soundDraft.playingAssetID == asset.id {
                            soundDraft.stopPreview()
                        } else {
                            soundDraft.preview(asset.id)
                        }
                    } label: {
                        Image(systemName: soundDraft.playingAssetID == asset.id ? "stop.fill" : "play.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(KuttukeTheme.ink)
                            .frame(width: 40, height: 40)
                            .background(KuttukeTheme.cream, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("レベル\(level + 1)の音を試聴")

                    Button {
                        withAnimation { soundDraft.remove(for: asset.id) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("レベル\(level + 1)の音を削除")
                }
            }

            if !isFirstLevel {
                HStack(spacing: 9) {
                    Button {
                        toggleRecording(for: asset.id)
                    } label: {
                        Label(isRecordingThis ? "停止" : "録音する", systemImage: isRecordingThis ? "stop.fill" : "mic.fill")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                isRecordingThis ? Color.red : KuttukeTheme.ink,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(BouncyButtonStyle())
                    .disabled(soundDraft.isRecording && !isRecordingThis)

                    Button {
                        importingAssetID = asset.id
                    } label: {
                        Label("ファイルから選ぶ", systemImage: "folder.fill")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(KuttukeTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle())
                    .disabled(soundDraft.isRecording)
                }
                .opacity(soundDraft.isRecording && !isRecordingThis ? 0.4 : 1)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isRecordingThis ? Color.red : .clear, lineWidth: 2)
        )
    }

    private func statusText(for assetID: UUID, isFirstLevel: Bool, isRecording: Bool) -> String {
        if isFirstLevel { return "最初の姿のため、進化音はありません" }
        if isRecording {
            return String(format: "録音中… %.1f / %.0f秒", soundDraft.recordingElapsed, StageSoundDraft.maximumRecordingDuration)
        }
        if soundDraft.hasUnsavedSound(for: assetID) { return "新しい音（保存すると反映）" }
        return soundDraft.url(for: assetID) == nil ? "未設定（無音）" : "設定済み"
    }

    private func toggleRecording(for assetID: UUID) {
        if soundDraft.recordingAssetID == assetID {
            soundDraft.stopRecording()
            return
        }
        Task {
            do {
                try await soundDraft.startRecording(for: assetID)
            } catch {
                library.errorMessage = error.localizedDescription
            }
        }
    }
}
