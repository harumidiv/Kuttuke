import Combine
import SpriteKit
import SwiftUI
import UIKit

@MainActor
final class GameViewModel: ObservableObject {
    let scene: DropGameScene
    let images: [UIImage]
    @Published var score = 0
    @Published var bestScore: Int
    @Published var nextLevels = [0, 0, 0]
    @Published var isGameOver = false
    @Published var isPaused = false
    /// 操作説明は1つ目を落とすまで表示する
    @Published private(set) var hasDroppedOnce = false
    /// ゲームオーバー時点の盤面のスクショ（SNS共有用）
    @Published private(set) var boardSnapshot: UIImage?
    /// Game Centerのランキングに今回のスコアで載ったときの順位
    @Published private(set) var leaderboardRank: LeaderboardRank?
    private var rankTask: Task<Void, Never>?

    private let bestScoreKey: String
    /// このゲーム開始時点のベストスコア。終了時にベストを更新したかの判定に使う
    private var bestScoreAtStart: Int
    private let mergeFeedback = UIImpactFeedbackGenerator(style: .soft)
    private let mergeSound: MergeSoundPlayer
    private let gameOverFeedback = UINotificationFeedbackGenerator()

    init(images: [UIImage], stageID: UUID, mergeSoundURLs: [URL?]) {
        self.mergeSound = MergeSoundPlayer(urls: mergeSoundURLs)
        let bestScoreKey = "kuttuke.best-score.\(stageID.uuidString)"
        self.images = images
        self.bestScoreKey = bestScoreKey
        let savedBestScore = UserDefaults.standard.integer(forKey: bestScoreKey)
        self.bestScore = savedBestScore
        self.bestScoreAtStart = savedBestScore
        self.scene = DropGameScene(images: images)
        connectScene()
    }

    var didUpdateBestScore: Bool {
        score > bestScoreAtStart
    }

    /// ゲーム終了後の操作の前に、ベストスコアを更新していなければインタースティシャル広告を挟む
    func afterInterstitialIfNeeded(_ action: @escaping () -> Void) {
        guard isGameOver, !didUpdateBestScore else {
            action()
            return
        }
        InterstitialAdManager.shared.show(then: action)
    }

    func restart() {
        persistBestScore()
        bestScoreAtStart = bestScore
        boardSnapshot = nil
        rankTask?.cancel()
        leaderboardRank = nil
        hasDroppedOnce = false
        score = 0
        isGameOver = false
        isPaused = false
        scene.isPaused = false
        scene.resetGame()
    }

    func togglePause() {
        guard !isGameOver else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { isPaused.toggle() }
        scene.isPaused = isPaused
    }

    func finishCurrentGame() {
        guard !isGameOver else { return }
        isPaused = false
        scene.isPaused = false
        scene.endGame()
    }

    /// 合体のたびに書き込むと重いため、ゲームの区切りでだけ保存する
    func persistBestScore() {
        guard bestScore > UserDefaults.standard.integer(forKey: bestScoreKey) else { return }
        UserDefaults.standard.set(bestScore, forKey: bestScoreKey)
    }

    func image(for level: Int) -> UIImage? {
        guard !images.isEmpty else { return nil }
        return images[min(level, images.count - 1)]
    }

    private func connectScene() {
        scene.onScore = { [weak self] score in
            guard let self else { return }
            self.score = score
            if score > self.bestScore {
                self.bestScore = score
            }
        }
        scene.onNextLevels = { [weak self] levels in self?.nextLevels = levels }
        scene.onDrop = { [weak self] in
            guard let self, !self.hasDroppedOnce else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.hasDroppedOnce = true }
        }
        scene.onGameOver = { [weak self] in
            guard let self else { return }
            let score = self.score
            let itemCount = self.images.count
            self.rankTask = Task { [weak self] in
                guard let rank = await GameCenterManager.shared.submit(score: score, itemCount: itemCount),
                      !Task.isCancelled, let self, self.isGameOver else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { self.leaderboardRank = rank }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            self.boardSnapshot = self.scene.snapshotImage()
            self.persistBestScore()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                self.isGameOver = true
            }
            self.gameOverFeedback.notificationOccurred(.warning)
        }
        scene.onFinalVanish = { [weak self] in
            self?.gameOverFeedback.notificationOccurred(.success)
        }
        scene.onMerge = { [weak self] level in
            self?.mergeFeedback.impactOccurred(intensity: 0.9)
            self?.mergeSound.play(level: level)
        }
        mergeFeedback.prepare()
    }
}

struct GameView: View {
    @StateObject private var model: GameViewModel
    @State private var shareImage: Image?
    @State private var isShowingGameCenterSignInAlert = false
    @Environment(\.displayScale) private var displayScale
    let stageName: String
    let onExit: () -> Void

    init(
        images: [UIImage],
        stageID: UUID,
        stageName: String,
        mergeSoundURLs: [URL?] = [],
        onExit: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: GameViewModel(images: images, stageID: stageID, mergeSoundURLs: mergeSoundURLs))
        self.stageName = stageName
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [KuttukeTheme.background, Color(red: 0.91, green: 0.95, blue: 0.91)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    gameHeader
                    scoreBar
                    boardArea
                }
                .padding(.horizontal, 15)
                .padding(.top, 8)
                // 盤面とバナーの間に余白を取り、ドロップ操作での誤タップを防ぐ
                .padding(.bottom, 24)

                BannerAdView()
                    .frame(width: BannerAdView.size.width, height: BannerAdView.size.height)
            }

            if model.isPaused { pauseOverlay }
            if model.isGameOver { gameOverOverlay }
        }
        .onDisappear { model.persistBestScore() }
        .onChange(of: model.boardSnapshot) { _, snapshot in
            shareImage = snapshot.flatMap(makeShareImage)
        }
    }

    private var gameHeader: some View {
        HStack {
            Button(action: onExit) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.9), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ホームに戻る")

            Spacer()
            Text(stageName)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .lineLimit(1)
            Spacer()

            Button(action: model.togglePause) {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.9), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPaused ? "再開" : "一時停止")
        }
    }

    private var scoreBar: some View {
        HStack(spacing: 10) {
            scoreCell(label: "SCORE", value: "\(model.score)", accent: KuttukeTheme.orange)
            nextQueueCell
        }
    }

    private var nextQueueCell: some View {
        HStack(spacing: 4) {
            Text("NEXT")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)

            ForEach(Array(model.nextLevels.enumerated()), id: \.offset) { index, level in
                if let image = model.image(for: level) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: index == 0 ? 30 : 24, height: index == 0 ? 30 : 24)
                        .opacity(index == 0 ? 1 : 0.68)
                }

                if index < model.nextLevels.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(KuttukeTheme.secondaryText.opacity(0.42))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("次に落ちるアイテム3個")
    }

    private func scoreCell(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(accent)
            Text(value)
                .font(.system(size: 19, weight: .black, design: .rounded))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 15)
        .frame(height: 58)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 進化の順番を盤面の右に縦に並べる（下が最小、上へ向かって成長）
    private var evolutionColumn: some View {
        let columnWidth: CGFloat = 44
        return VStack(spacing: 4) {
            Text("進化")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)

            GeometryReader { proxy in
                let count = max(model.images.count, 1)
                let arrowHeight: CGFloat = 9
                let spacing: CGFloat = 1
                let arrowCount = CGFloat(max(count - 1, 0))
                let spacingCount = CGFloat(max(count * 2 - 2, 0))
                let availableForItems = proxy.size.height - arrowCount * arrowHeight - spacingCount * spacing
                let itemSide = min(columnWidth - 8, max(16, floor(availableForItems / CGFloat(count))))

                VStack(spacing: spacing) {
                    ForEach(Array(model.images.enumerated().reversed()), id: \.offset) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(3)
                            .frame(width: itemSide, height: itemSide)
                            .background(KuttukeTheme.cream, in: Circle())
                            .accessibilityLabel("進化レベル \(index + 1)")

                        if index > 0 {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(KuttukeTheme.orange)
                                .frame(height: arrowHeight)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
        }
        .padding(.vertical, 10)
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("進化の順番")
    }

    /// 盤面を固定の縦横比で収め、進化の列を盤面と同じ高さで右に並べる
    private var boardArea: some View {
        GeometryReader { proxy in
            let columnWidth: CGFloat = 44
            let spacing: CGFloat = 8
            let maxBoardWidth = max(proxy.size.width - columnWidth - spacing, 0)
            let boardWidth = min(maxBoardWidth, proxy.size.height * DropGameScene.boardAspectRatio)
            let boardHeight = boardWidth / DropGameScene.boardAspectRatio

            HStack(spacing: spacing) {
                board
                    .frame(width: boardWidth, height: boardHeight)
                evolutionColumn
                    .frame(height: boardHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var shareMessage: String {
        let headline = model.didUpdateBestScore ? "自己ベスト更新！" : ""
        let rankText = model.leaderboardRank.map { "\($0.itemCount)個ランキングで全国\($0.rank)位！" } ?? ""
        return "\(headline)「\(stageName)」で\(model.score)点！\(rankText) #Kuttuke"
    }

    /// 盤面のスクショにステージ名とスコアを添えたシェア用画像を作る
    private func makeShareImage(from boardSnapshot: UIImage) -> Image? {
        let renderer = ImageRenderer(content: ShareCardView(
            stageName: stageName,
            score: model.score,
            isNewBest: model.didUpdateBestScore,
            boardImage: boardSnapshot
        ))
        renderer.scale = displayScale
        return renderer.uiImage.map { Image(uiImage: $0) }
    }

    // スコア更新のたびにSpriteViewまで再評価されないよう、盤面は別のViewに切り出す
    private var board: some View {
        GameBoardView(scene: model.scene)
            .overlay {
                if !model.hasDroppedOnce {
                    instruction
                        .transition(.opacity)
                }
            }
    }

    /// 1つ目を落とすまで盤面に重ねて表示する。タップは盤面にそのまま通す
    private var instruction: some View {
        Label("左右に動かして、指を離すと落ちます", systemImage: "hand.draw.fill")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(KuttukeTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.white.opacity(0.85), in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isStaticText)
    }

    /// 結果画面と同じ大きさ・構成にそろえる
    private var pauseOverlay: some View {
        Color.black.opacity(0.32)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    Label("ひとやすみ", systemImage: "pause.fill")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(KuttukeTheme.orange)
                    Text("\(model.score)")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                    Text("いまのスコア")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)

                    Button {
                        model.togglePause()
                    } label: {
                        Label("つづける", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(KuttukeTheme.ink, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle())
                    .padding(.top, 6)

                    Button {
                        model.finishCurrentGame()
                    } label: {
                        Label("ここで終了", systemImage: "stop.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(26)
                .frame(maxWidth: 310)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var gameOverOverlay: some View {
        Color.black.opacity(0.32)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    if let rank = model.leaderboardRank {
                        RankInBanner(rank: rank)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    Text("FINISH!")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(KuttukeTheme.orange)
                    Text("\(model.score)")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                    Text("今回のスコア")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)

                    if let shareImage {
                        ShareLink(
                            item: shareImage,
                            message: Text(shareMessage),
                            preview: SharePreview("Kuttuke のスコア", image: shareImage)
                        ) {
                            Label("シェアする", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(KuttukeTheme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(BouncyButtonStyle())
                    }

                    if GameCenterManager.rankedItemCounts.contains(model.images.count) {
                        Button {
                            if !GameCenterManager.shared.showLeaderboard(itemCount: model.images.count) {
                                isShowingGameCenterSignInAlert = true
                            }
                        } label: {
                            Label("\(model.images.count)個ランキング", systemImage: "trophy.fill")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(KuttukeTheme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(BouncyButtonStyle())
                    }

                    Button {
                        model.afterInterstitialIfNeeded { model.restart() }
                    } label: {
                        Label("もう一度", systemImage: "arrow.clockwise")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(KuttukeTheme.ink, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle())

                    Button("ホームへ") {
                        model.afterInterstitialIfNeeded(onExit)
                    }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                        .frame(height: 38)
                }
                .padding(26)
                .frame(maxWidth: 310)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            // 紙吹雪は結果カードより手前に降らせる
            .overlay {
                if model.leaderboardRank != nil {
                    ConfettiView()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .alert("Game Centerにサインインしていません", isPresented: $isShowingGameCenterSignInAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("ランキングに参加するには、設定アプリの「Game Center」からサインインしてください。")
            }
    }
}

private struct GameBoardView: View {
    let scene: DropGameScene

    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: scene, options: [.allowsTransparency])
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white, lineWidth: 4)
                )
                // 毎フレーム描き変わるSpriteViewに直接影を付けると合成が重くなるため、背面の図形に付ける
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(KuttukeTheme.cream)
                        .shadow(color: .black.opacity(0.09), radius: 14, y: 8)
                )
        }
        .frame(maxHeight: .infinity)
    }
}

/// SNS共有用の画像レイアウト
private struct ShareCardView: View {
    let stageName: String
    let score: Int
    let isNewBest: Bool
    let boardImage: UIImage

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("KUTTUKE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .tracking(1.5)
                Spacer()
                Text(stageName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(KuttukeTheme.secondaryText)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                if isNewBest {
                    Text("自己ベスト更新！")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(KuttukeTheme.orange, in: Capsule())
                }

                // 桁数が多くても折り返さず、1行に収まるよう縮小する
                (Text("\(score)")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                 + Text(" 点")
                    .font(.system(size: 18, weight: .black, design: .rounded)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(uiImage: boardImage)
                .resizable()
                .aspectRatio(DropGameScene.boardAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white, lineWidth: 4)
                )
        }
        .foregroundStyle(KuttukeTheme.ink)
        .padding(24)
        .frame(width: 360)
        .background(KuttukeTheme.background)
    }
}

/// ランキングに載ったことを知らせる、結果画面の上部の帯
private struct RankInBanner: View {
    let rank: LeaderboardRank
    @State private var isShining = false

    private var medalColor: Color {
        switch rank.rank {
        case 1: Color(red: 1.0, green: 0.78, blue: 0.18)
        case 2: Color(red: 0.72, green: 0.76, blue: 0.82)
        case 3: Color(red: 0.84, green: 0.55, blue: 0.32)
        default: KuttukeTheme.orange
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: rank.rank <= 3 ? "crown.fill" : "trophy.fill")
                    .symbolEffect(.bounce, options: .repeat(2), value: isShining)
                Text("ランクイン！")
            }
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)

            Text("全国 \(Text("\(rank.rank)").font(.system(size: 30, weight: .black, design: .rounded))) 位")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("\(rank.itemCount)個ランキング・\(rank.totalPlayers)人中")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [medalColor, KuttukeTheme.pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            // 帯の上を光が横切る
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 70)
                .rotationEffect(.degrees(20))
                .offset(x: isShining ? 220 : -220)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: medalColor.opacity(0.45), radius: 12, y: 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).delay(0.3)) { isShining = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ランクイン。\(rank.itemCount)個ランキングで全国\(rank.rank)位、\(rank.totalPlayers)人中")
    }
}

/// ランクインしたときに画面の上から降らせる紙吹雪
private struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let size: CGSize
        let color: Color
        let delay: Double
        let duration: Double
        let spin: Double
        let drift: CGFloat
    }

    @State private var isFalling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pieces: [Piece] = {
        let colors: [Color] = [KuttukeTheme.orange, KuttukeTheme.pink, KuttukeTheme.purple, KuttukeTheme.mint, KuttukeTheme.sky, Color(red: 1, green: 0.8, blue: 0.2)]
        return (0..<70).map { index in
            Piece(
                id: index,
                x: .random(in: 0...1),
                size: CGSize(width: .random(in: 6...11), height: .random(in: 10...16)),
                color: colors[index % colors.count],
                delay: .random(in: 0...0.9),
                duration: .random(in: 2.2...3.6),
                spin: .random(in: 360...900) * (Bool.random() ? 1 : -1),
                drift: .random(in: -40...40)
            )
        }
    }()

    var body: some View {
        GeometryReader { proxy in
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.size.width, height: piece.size.height)
                    .rotation3DEffect(.degrees(isFalling ? piece.spin : 0), axis: (x: 1, y: 0.4, z: 0.2))
                    .position(
                        x: piece.x * proxy.size.width + (isFalling ? piece.drift : 0),
                        y: isFalling ? proxy.size.height + 40 : -30
                    )
                    .opacity(isFalling ? 0.85 : 1)
                    .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: isFalling)
            }
        }
        .opacity(reduceMotion ? 0 : 1)
        .onAppear { isFalling = true }
    }
}
