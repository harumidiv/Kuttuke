import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var library = SubjectLibrary()
    @State private var editorRoute: StageEditorRoute?
    @State private var isShowingSettings = false
    @State private var playingStageID: UUID?
    @State private var sharingStage: ShareRoute?
    @State private var receiveRoute: ReceiveRoute?
    @State private var isShowingGameCenterSignInAlert = false

    var body: some View {
        ZStack {
            KuttukeTheme.background.ignoresSafeArea()

            if let stage = playingStage {
                GameView(
                    images: library.images(for: stage),
                    stageID: stage.id,
                    stageName: stage.name,
                    mergeSoundURLs: library.mergeSoundURLs(for: stage),
                    rareEffects: library.rareEffects(for: stage)
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
                stage: route.stage
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(library: library)
        }
        .sheet(item: $sharingStage) { route in
            StageShareView(library: library, stageID: route.id)
        }
        .sheet(item: $receiveRoute) { route in
            StageReceiveView(library: library, initialCode: route.code)
        }
        .onAppear { GameCenterManager.shared.authenticate() }
        .alert("Game Centerにサインインしていません", isPresented: $isShowingGameCenterSignInAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("ランキングを見るには、設定アプリの「Game Center」からサインインしてください。")
        }
        .onOpenURL { url in
            // 友達から届いた共有リンク（kuttuke://stage/コード）で開かれたら受け取り画面を出す
            guard let code = StageShareCode.code(from: url) else { return }
            editorRoute = nil
            sharingStage = nil
            isShowingSettings = false
            withAnimation { playingStageID = nil }
            receiveRoute = ReceiveRoute(code: code)
        }
        .alert("操作できませんでした", isPresented: Binding(
            get: { editorRoute == nil && sharingStage == nil && receiveRoute == nil && library.errorMessage != nil },
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
                Text("じぶんの写真を、くっつけよう")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
            }
            Spacer()
            Button {
                if !GameCenterManager.shared.showLeaderboard() {
                    isShowingGameCenterSignInAlert = true
                }
            } label: {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(KuttukeTheme.ink)
                    .background(.white.opacity(0.9), in: Circle())
                    .overlay(Circle().stroke(.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ランキング")
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                Button {
                    receiveRoute = ReceiveRoute(code: nil)
                } label: {
                    Label("受け取る", systemImage: "tray.and.arrow.down.fill")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(KuttukeTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(.white, in: Capsule())
                        .overlay(Capsule().stroke(.black.opacity(0.06)))
                }
                .buttonStyle(BouncyButtonStyle())
                Button {
                    editorRoute = StageEditorRoute(stage: nil)
                } label: {
                    Label("作る", systemImage: "plus")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
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
            editorRoute = StageEditorRoute(stage: nil)
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
                stageThumbnail(stage, images: images)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.name)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .lineLimit(1)
                    Text(isPlayable ? String(localized: "\(images.count)個の素材・プレイできます") : String(localized: "あと\(remainingCount)個追加で遊べます"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isPlayable ? KuttukeTheme.secondaryText : KuttukeTheme.orange)
                }

                Spacer()

                if isPlayable {
                    Button {
                        sharingStage = ShareRoute(id: stage.id)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.045), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("「\(stage.name)」を友達に共有")
                }

                Button {
                    editorRoute = StageEditorRoute(stage: stage)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.045), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("「\(stage.name)」を編集")
            }

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    playingStageID = stage.id
                }
            } label: {
                Label(isPlayable ? String(localized: "このステージであそぶ") : String(localized: "6個以上であそべます"), systemImage: "play.fill")
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

    private static let thumbnailSide: CGFloat = 82

    /// ステージで使っている素材を、サムネイルの中にステッカーのように散らして貼る
    private func stageThumbnail(_ stage: GameStage, images: [UIImage]) -> some View {
        let placements = StageThumbnailLayout.placements(count: images.count, seed: stage.id, side: Self.thumbnailSide)
        return ZStack {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(KuttukeTheme.cream)

            if images.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(KuttukeTheme.secondaryText.opacity(0.5))
            } else {
                // 大きい（レベルの高い）素材から先に描き、小さい素材が隠れにくいようにする
                ForEach(Array(zip(images, placements).enumerated()).reversed(), id: \.offset) { _, item in
                    let (image, placement) = item
                    Image(uiImage: ThumbnailCache.thumbnail(for: image))
                        .resizable()
                        .scaledToFit()
                        .frame(width: placement.size, height: placement.size)
                        .rotationEffect(.degrees(placement.rotation))
                        .position(placement.center)
                }
            }
        }
        .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

}

/// サムネイルに散らして貼る位置。ステージのIDから乱数を作るため、同じステージはいつも同じ配置になる
private enum StageThumbnailLayout {
    struct Placement {
        let center: CGPoint
        let size: CGFloat
        let rotation: Double
    }

    static func placements(count: Int, seed: UUID, side: CGFloat) -> [Placement] {
        var random = SeededRandom(seed: seed)
        return (0..<count).map { level in
            // レベルが高いほど少し大きく貼る
            let progress = count > 1 ? CGFloat(level) / CGFloat(count - 1) : 1
            let size = side * (0.38 + 0.2 * progress)
            // 素材の画像は周りに余白があるため、少しだけ枠からはみ出してもよい
            let margin = size * 0.4
            let center = CGPoint(
                x: CGFloat.random(in: margin...(side - margin), using: &random),
                y: CGFloat.random(in: margin...(side - margin), using: &random)
            )
            return Placement(center: center, size: size, rotation: Double.random(in: -18...18, using: &random))
        }
    }
}

/// ステージのIDから作る乱数（SplitMix64）。起動のたびに配置が変わらないよう、Swift標準のハッシュ値は使わない
private struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UUID) {
        let bytes = withUnsafeBytes(of: seed.uuid) { Array($0) }
        state = bytes.prefix(8).reduce(0) { $0 << 8 | UInt64($1) } ^ bytes.suffix(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// ホームのサムネイル用に縮めた素材。元の512pxのまま並べるとメモリを多く使うため
private enum ThumbnailCache {
    private static let cache = NSCache<UIImage, UIImage>()
    private static let pixelSize: CGFloat = 160

    static func thumbnail(for image: UIImage) -> UIImage {
        if let cached = cache.object(forKey: image) { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: pixelSize, height: pixelSize)
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        cache.setObject(thumbnail, forKey: image)
        return thumbnail
    }
}

private struct StageEditorRoute: Identifiable {
    let id = UUID()
    // 開いた時点のステージを保持し、削除後に閉じるアニメーション中も編集画面のまま表示する
    let stage: GameStage?
}

private struct ShareRoute: Identifiable {
    let id: UUID
}

private struct ReceiveRoute: Identifiable {
    let id = UUID()
    /// 共有リンクから開いたときのコード。手入力ならnil
    let code: String?
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
