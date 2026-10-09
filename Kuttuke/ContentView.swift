import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var library = SubjectLibrary()
    @State private var editorRoute: StageEditorRoute?
    @State private var isShowingSettings = false
    @State private var playingStageID: UUID?
    @State private var stagePendingDeletion: GameStage?

    var body: some View {
        ZStack {
            KuttukeTheme.background.ignoresSafeArea()

            if let stage = playingStage {
                GameView(
                    images: library.images(for: stage),
                    stageID: stage.id,
                    stageName: stage.name
                ) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        playingStageID = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                home
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
        .sheet(item: $editorRoute) { route in
            SubjectLibraryView(
                library: library,
                stage: route.stageID.flatMap { library.stage(withID: $0) }
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .confirmationDialog(
            "「\(stagePendingDeletion?.name ?? "")」を削除しますか？",
            isPresented: Binding(
                get: { stagePendingDeletion != nil },
                set: { if !$0 { stagePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("ステージを削除", role: .destructive) {
                guard let stagePendingDeletion else { return }
                library.deleteStage(stagePendingDeletion)
                self.stagePendingDeletion = nil
            }
            Button("キャンセル", role: .cancel) {
                stagePendingDeletion = nil
            }
        } message: {
            Text("保存済みの切り抜き素材は削除されないため、別のステージで引き続き使えます。")
        }
        .alert("操作できませんでした", isPresented: Binding(
            get: { editorRoute == nil && library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private var playingStage: GameStage? {
        guard let playingStageID,
              let stage = library.stage(withID: playingStageID),
              library.isPlayable(stage) else { return nil }
        return stage
    }

    private var home: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                hero
                stagesSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("KUTTUKE")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(1.4)
                Text("じぶんの写真で、くっつけよう")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }
            Spacer()
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(KuttukeTheme.ink)
                    .background(.white.opacity(0.9), in: Circle())
                    .overlay(Circle().stroke(.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("設定")
        }
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [KuttukeTheme.mint, KuttukeTheme.sky],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(.white.opacity(0.36))
                .frame(width: 210)
                .offset(x: 125, y: -76)

            VStack(spacing: 8) {
                ZStack(alignment: .bottom) {
                    ForEach(Array(heroImages.enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: CGFloat(76 + index * 27), height: CGFloat(76 + index * 27))
                            .rotationEffect(.degrees(Double(index - 1) * 7))
                            .offset(x: CGFloat(index - 1) * 62, y: CGFloat((2 - index) * 11))
                            .shadow(color: .black.opacity(0.13), radius: 9, y: 7)
                    }

                    if heroImages.isEmpty {
                        starterGraphic
                    }
                }
                .frame(height: 166)

                Text(library.stages.isEmpty ? "お気に入りの進化セットを作ろう" : "\(library.stages.count)個のステージを保存中")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(KuttukeTheme.ink)
                Text(library.stages.isEmpty ? "一度切り抜けば、何度でも素材に使えます" : "好きなステージを選んですぐ遊べます")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(KuttukeTheme.ink.opacity(0.62))
            }
            .padding(.vertical, 21)
            .padding(.horizontal, 14)
        }
        .frame(height: 286)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(.white.opacity(0.65), lineWidth: 1)
        )
    }

    private var starterGraphic: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .fill([KuttukeTheme.orange, KuttukeTheme.pink, KuttukeTheme.purple][index])
                    .frame(width: CGFloat(75 + index * 25))
                    .overlay {
                        Image(systemName: index == 2 ? "photo.on.rectangle.angled" : "sparkle")
                            .font(.system(size: CGFloat(20 + index * 4), weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .offset(x: CGFloat(index - 1) * 60, y: CGFloat((2 - index) * 12))
                    .shadow(color: .black.opacity(0.12), radius: 9, y: 7)
            }
        }
    }

    private var heroImages: [UIImage] {
        guard let stage = library.stages.first else { return [] }
        let images = library.images(for: stage)
        guard !images.isEmpty else { return [] }
        var result = Array(images.prefix(3))
        while result.count < 3, let last = result.last {
            result.append(last)
        }
        return result
    }

    private var stagesSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MY STAGES")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(KuttukeTheme.secondaryText)
                    Text("進化セット")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                }
                Spacer()
                Button {
                    editorRoute = StageEditorRoute(stageID: nil)
                } label: {
                    Label("作る", systemImage: "plus")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(KuttukeTheme.orange, in: Capsule())
                }
                .buttonStyle(BouncyButtonStyle())
            }

            if library.stages.isEmpty {
                emptyStageCard
            } else {
                ForEach(library.stages) { stage in
                    stageCard(stage)
                }
            }
        }
    }

    private var emptyStageCard: some View {
        Button {
            editorRoute = StageEditorRoute(stageID: nil)
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.badge.automatic")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(KuttukeTheme.orange)
                Text("最初の進化セットを作成")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text("写真から切り抜くか、保存済み素材を選びます")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(KuttukeTheme.orange.opacity(0.28), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
            )
        }
        .buttonStyle(BouncyButtonStyle())
    }

    private func stageCard(_ stage: GameStage) -> some View {
        let images = library.images(for: stage)
        let isPlayable = images.count >= SubjectLibrary.minimumPlayableItems
        let remainingCount = max(0, SubjectLibrary.minimumPlayableItems - images.count)
        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                stageThumbnail(images)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.name)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .lineLimit(1)
                    Text(isPlayable ? "\(images.count)個の素材・プレイできます" : "あと\(remainingCount)個追加で遊べます")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isPlayable ? KuttukeTheme.secondaryText : KuttukeTheme.orange)
                }

                Spacer()

                Menu {
                    Button {
                        editorRoute = StageEditorRoute(stageID: stage.id)
                    } label: {
                        Label("編集", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        stagePendingDeletion = stage
                    } label: {
                        Label("ステージを削除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.045), in: Circle())
                }
            }

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    playingStageID = stage.id
                }
            } label: {
                Label(isPlayable ? "このステージであそぶ" : "6個以上であそべます", systemImage: "play.fill")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(KuttukeTheme.ink, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(BouncyButtonStyle())
            .disabled(!isPlayable)
            .opacity(isPlayable ? 1 : 0.3)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.black.opacity(0.055)))
    }

    private func stageThumbnail(_ images: [UIImage]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(KuttukeTheme.cream)

            if images.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(KuttukeTheme.secondaryText.opacity(0.5))
            } else {
                ForEach(Array(images.prefix(3).enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: CGFloat(42 + index * 6), height: CGFloat(42 + index * 6))
                        .offset(x: CGFloat(index - 1) * 12, y: CGFloat(1 - index) * 3)
                }
            }
        }
        .frame(width: 82, height: 82)
    }

}

private struct StageEditorRoute: Identifiable {
    let id = UUID()
    let stageID: UUID?
}

struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
