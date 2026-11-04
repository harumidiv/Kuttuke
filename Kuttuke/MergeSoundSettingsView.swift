import SwiftUI
import UniformTypeIdentifiers

/// 高度な詳細設定：プレイ中のBGMと、進化の順番に並んだ素材ごとに、その素材へ進化したときの音とキラ加工を設定する
struct MergeSoundSettingsView: View {
    @ObservedObject var library: SubjectLibrary
    let assetIDs: [UUID]
    @ObservedObject var soundDraft: StageSoundDraft
    @Binding var rareEffects: [UUID: RareEffect]

    /// ファイルアプリで選んだ音声をどこに使うか。`fileImporter` を2つ付けると片方しか動かないため、1つにまとめる
    @State private var importTarget: StageSoundTarget?

    var body: some View {
        ZStack {
            KuttukeTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    musicCard
                        .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("素材ごとの設定")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                        Text("合体してその素材に進化したときに鳴ります。録音は最大\(Int(StageSoundDraft.maximumRecordingDuration))秒、ファイルは\(Int(StageSoundDraft.maximumFileDuration))秒以内です。未設定の素材では標準の「ぽよん」が鳴ります。編集画面で「保存」すると反映されます。")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                        Text("キラ加工はレアカードのような加工で、端末を傾けると光が動きます。")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                    }
                    .padding(.horizontal, 4)

                    ForEach(Array(assetIDs.enumerated()), id: \.element) { index, assetID in
                        if let asset = library.asset(withID: assetID) {
                            assetCard(asset, level: index)
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
                get: { importTarget != nil },
                set: { if !$0 { importTarget = nil } }
            ),
            allowedContentTypes: [.audio]
        ) { result in
            guard let target = importTarget, case .success(let url) = result else { return }
            do {
                switch target {
                case .asset(let assetID): try soundDraft.importFile(at: url, for: assetID)
                case .music: try soundDraft.importMusic(at: url)
                }
            } catch {
                library.errorMessage = error.localizedDescription
            }
        }
        .onDisappear { soundDraft.stopPreview() }
    }

    /// 進化セット全体のBGM。録音もファイル選択もしなければ標準のBGMが流れる
    private var musicCard: some View {
        let isRecordingThis = soundDraft.isRecordingMusic

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    sectionLabel("BGM", systemImage: "music.note")
                    Text(musicStatusText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isRecordingThis ? .red : KuttukeTheme.ink)
                        .monospacedDigit()
                }

                Spacer(minLength: 4)

                if !isRecordingThis {
                    Button {
                        if soundDraft.isPlayingMusic {
                            soundDraft.stopPreview()
                        } else {
                            soundDraft.preview(.music)
                        }
                    } label: {
                        Image(systemName: soundDraft.isPlayingMusic ? "stop.fill" : "play.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(KuttukeTheme.ink)
                            .frame(width: 40, height: 40)
                            .background(KuttukeTheme.cream, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(soundDraft.isRecording)
                    .accessibilityLabel("BGMを試聴")

                    if soundDraft.musicURL != nil {
                        Button {
                            withAnimation { soundDraft.removeMusic() }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("標準のBGMに戻す")
                    }
                }
            }

            HStack(spacing: 9) {
                Button {
                    toggleRecording(for: .music)
                } label: {
                    Label(isRecordingThis ? String(localized: "停止") : String(localized: "録音する"), systemImage: isRecordingThis ? "stop.fill" : "mic.fill")
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
                    importTarget = .music
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

            Text("プレイ中にくり返し流れます。録音は最大\(Int(StageSoundDraft.maximumMusicRecordingDuration))秒、ファイルは\(Int(StageSoundDraft.maximumMusicDuration / 60))分以内です。BGMは友達への共有には含まれません。")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isRecordingThis ? Color.red : .clear, lineWidth: 2)
        )
    }

    private var musicStatusText: String {
        if soundDraft.isRecordingMusic { return recordingProgressText }
        if soundDraft.hasUnsavedMusic { return String(localized: "新しいBGM（保存すると反映）") }
        return soundDraft.musicURL == nil ? String(localized: "標準のBGM") : String(localized: "自分で選んだBGM")
    }

    /// 1つの素材の設定をまとめたカード。素材を見ながら音とキラ加工を続けて設定できるようにする
    private func assetCard(_ asset: SubjectAsset, level: Int) -> some View {
        let isRecordingThis = soundDraft.recordingAssetID == asset.id

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(uiImage: asset.image)
                    .resizable()
                    .scaledToFit()
                    .rareEffect(rareEffects[asset.id], image: asset.image)
                    .frame(width: 64, height: 64)
                    .padding(4)
                    .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("レベル \(level + 1)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
            }

            soundSection(asset, level: level)

            Divider()

            effectSection(asset, level: level)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isRecordingThis ? Color.red : .clear, lineWidth: 2)
        )
    }

    private func sectionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(KuttukeTheme.secondaryText)
    }

    @ViewBuilder
    private func soundSection(_ asset: SubjectAsset, level: Int) -> some View {
        let isRecordingThis = soundDraft.recordingAssetID == asset.id
        let soundURL = soundDraft.url(for: asset.id)
        // レベル1は最初の姿で、合体して現れることがないため音は鳴らない
        let isFirstLevel = level == 0

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    sectionLabel("進化音", systemImage: "speaker.wave.2.fill")
                    Text(statusText(for: asset.id, isFirstLevel: isFirstLevel, isRecording: isRecordingThis))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isRecordingThis ? .red : KuttukeTheme.ink)
                        .monospacedDigit()
                }

                Spacer(minLength: 4)

                if soundURL != nil, !isRecordingThis {
                    Button {
                        if soundDraft.playingAssetID == asset.id {
                            soundDraft.stopPreview()
                        } else {
                            soundDraft.preview(.asset(asset.id))
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
                        toggleRecording(for: .asset(asset.id))
                    } label: {
                        Label(isRecordingThis ? String(localized: "停止") : String(localized: "録音する"), systemImage: isRecordingThis ? "stop.fill" : "mic.fill")
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
                        importTarget = .asset(asset.id)
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
    }

    private func effectSection(_ asset: SubjectAsset, level: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("キラ加工", systemImage: "sparkles")
            // 種類が多いため、横にスクロールして選ぶ。開いたときは選んでいる加工が見える位置にする
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        effectChip(String(localized: "なし"), effect: nil, assetID: asset.id)
                        ForEach(RareEffect.allCases) { effect in
                            effectChip(effect.title, effect: effect, assetID: asset.id)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 14)
                }
                .scrollIndicators(.hidden)
                // カードの端まで広げ、続きがあることが分かるようにする
                .padding(.horizontal, -14)
                .onAppear { proxy.scrollTo(chipID(rareEffects[asset.id]), anchor: .center) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("レベル\(level + 1)のキラ加工")
        }
    }

    private func effectChip(_ title: String, effect: RareEffect?, assetID: UUID) -> some View {
        let isSelected = rareEffects[assetID] == effect
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { rareEffects[assetID] = effect }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .white : KuttukeTheme.ink)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isSelected ? KuttukeTheme.ink : KuttukeTheme.cream, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(chipID(effect))
    }

    private func chipID(_ effect: RareEffect?) -> String {
        effect?.rawValue ?? "none"
    }

    private func statusText(for assetID: UUID, isFirstLevel: Bool, isRecording: Bool) -> String {
        if isFirstLevel { return String(localized: "最初の姿のため、進化音はありません") }
        if isRecording {
            return recordingProgressText
        }
        if soundDraft.hasUnsavedSound(for: assetID) { return String(localized: "新しい音（保存すると反映）") }
        return soundDraft.url(for: assetID) == nil ? String(localized: "未設定（標準の「ぽよん」が鳴ります）") : String(localized: "設定済み")
    }

    private var recordingProgressText: String {
        String(format: String(localized: "録音中… %.1f / %.0f秒"), soundDraft.recordingElapsed, soundDraft.maximumDurationOfCurrentRecording)
    }

    private func toggleRecording(for target: StageSoundTarget) {
        if soundDraft.recordingTarget == target {
            soundDraft.stopRecording()
            return
        }
        Task {
            do {
                try await soundDraft.startRecording(for: target)
            } catch {
                library.errorMessage = error.localizedDescription
            }
        }
    }
}
