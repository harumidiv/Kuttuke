import Combine
import SpriteKit
import SwiftUI
import UIKit

@MainActor
final class GameViewModel: ObservableObject {
    let scene: DropGameScene
    let images: [UIImage]
    /// 進化の列に並べる、透明な余白を除いた素材
    let evolutionImages: [UIImage]
    /// `images` と同じ並びのキラ加工
    let rareEffects: [RareEffect?]
    @Published var score = 0
    @Published var bestScore: Int
    @Published var nextLevels = [0, 0, 0]
    @Published var isGameOver = false { didSet { updateBackgroundMusic() } }
    @Published var isPaused = false { didSet { updateBackgroundMusic() } }
    /// 操作説明は1つ目を落とすまで表示する
    @Published private(set) var hasDroppedOnce = false
    /// ゲームオーバー時点の盤面のスクショ（SNS共有用）
    @Published private(set) var boardSnapshot: UIImage?
    /// Game Centerのランキングに今回のスコアで載ったときの順位
    @Published private(set) var leaderboardRank: LeaderboardRank?
    private var rankTask: Task<Void, Never>?
    /// 1ゲームでアイテムチェンジを使える回数。使いすぎるとランキングの公平さが崩れるため絞る
    static let itemChangeLimitPerGame = 2
    @Published private(set) var itemChangesLeft = GameViewModel.itemChangeLimitPerGame
    /// ルーレットを表示中なら、その候補のレベル
    @Published private(set) var itemRouletteCandidates: [Int]?
    /// チェンジ用のリワード広告を表示中か
    @Published private(set) var isWatchingRewardedAd = false { didSet { updateBackgroundMusic() } }
    /// このゲームでリワード広告を見たか。見てくれた人には終了後のインタースティシャルを出さない
    private var didWatchRewardedAd = false

    private let bestScoreKey: String
    /// このゲーム開始時点のベストスコア。終了時にベストを更新したかの判定に使う
    private var bestScoreAtStart: Int
    private let mergeFeedback = UIImpactFeedbackGenerator(style: .soft)
    private let mergeSound: MergeSoundPlayer
    private let backgroundMusic: BackgroundMusicPlayer
    /// ゲーム画面が表示されていて、アプリが前面にあるか
    private var isOnScreen = false { didSet { updateBackgroundMusic() } }
    private let gameOverFeedback = UINotificationFeedbackGenerator()

    init(images: [UIImage], stageID: UUID, mergeSoundURLs: [URL?], backgroundMusicURL: URL?, rareEffects: [RareEffect?]) {
        self.mergeSound = MergeSoundPlayer(urls: mergeSoundURLs)
        self.backgroundMusic = BackgroundMusicPlayer(url: backgroundMusicURL)
        let bestScoreKey = "kuttuke.best-score.\(stageID.uuidString)"
        self.images = images
        self.evolutionImages = images.map(SubjectExtractor.trimmedToContent)
        self.rareEffects = rareEffects
        self.bestScoreKey = bestScoreKey
        let savedBestScore = UserDefaults.standard.integer(forKey: bestScoreKey)
        self.bestScore = savedBestScore
        self.bestScoreAtStart = savedBestScore
        self.scene = DropGameScene(images: images, rareEffects: rareEffects)
        connectScene()
    }

    var didUpdateBestScore: Bool {
        score > bestScoreAtStart
    }

    /// ゲーム終了後の操作の前に、ベストスコアを更新していなければインタースティシャル広告を挟む
    func afterInterstitialIfNeeded(_ action: @escaping () -> Void) {
        guard isGameOver, !didUpdateBestScore, !didWatchRewardedAd else {
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
        itemChangesLeft = Self.itemChangeLimitPerGame
        itemRouletteCandidates = nil
        didWatchRewardedAd = false
        backgroundMusic.rewind()
        isGameOver = false
        isPaused = false
        scene.isPaused = false
        scene.resetGame()
    }

    var canChangeItem: Bool {
        itemChangesLeft > 0 && !isGameOver && !isPaused && itemRouletteCandidates == nil && !isWatchingRewardedAd
    }

    /// 盤面を止めてリワード広告を見せ、最後まで見てもらえたらアイテムチェンジのルーレットを出す
    func openItemRoulette() {
        guard canChangeItem, RewardedAdManager.shared.isReady else { return }
        scene.isPaused = true
        isWatchingRewardedAd = true
        RewardedAdManager.shared.show { [weak self] didEarnReward in
            guard let self else { return }
            self.isWatchingRewardedAd = false
            guard didEarnReward, !self.isGameOver else {
                // 途中で閉じたときは何も変えずに再開する
                self.scene.isPaused = false
                return
            }
            self.didWatchRewardedAd = true
            // 広告から戻ったときにSKViewが盤面を再開させることがあるため、止め直す
            self.scene.isPaused = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                self.itemRouletteCandidates = self.scene.itemChangeCandidates()
            }
        }
    }

    /// ルーレットで止めたアイテムに差し替えて、ゲームを再開する
    func finishItemRoulette(with level: Int) {
        guard itemRouletteCandidates != nil else { return }
        itemChangesLeft -= 1
        scene.replaceNextItem(with: level)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            itemRouletteCandidates = nil
        }
        scene.isPaused = false
    }

    func togglePause() {
        guard !isGameOver, itemRouletteCandidates == nil else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { isPaused.toggle() }
        scene.isPaused = isPaused
    }

    func finishCurrentGame() {
        guard !isGameOver else { return }
        isPaused = false
        scene.isPaused = false
        scene.endGame()
    }

    func setOnScreen(_ isOnScreen: Bool) {
        self.isOnScreen = isOnScreen
    }

    private func updateBackgroundMusic() {
        if isOnScreen && !isGameOver && !isPaused && !isWatchingRewardedAd {
            backgroundMusic.play()
        } else {
            backgroundMusic.pause()
        }
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

    func rareEffect(for level: Int) -> RareEffect? {
        guard !images.isEmpty else { return nil }
        let index = min(level, images.count - 1)
        return index < rareEffects.count ? rareEffects[index] : nil
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
    @ObservedObject private var rewardedAds = RewardedAdManager.shared
    @State private var shareImage: Image?
    @State private var isShowingGameCenterSignInAlert = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    let stageName: String
    let onExit: () -> Void

    init(
        images: [UIImage],
        stageID: UUID,
        stageName: String,
        mergeSoundURLs: [URL?] = [],
        backgroundMusicURL: URL? = nil,
        rareEffects: [RareEffect?] = [],
        onExit: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: GameViewModel(
            images: images,
            stageID: stageID,
            mergeSoundURLs: mergeSoundURLs,
            backgroundMusicURL: backgroundMusicURL,
            rareEffects: rareEffects
        ))
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
                // 盤面とバナーの間には進化の列があるため、列とバナーの間は詰める
                .padding(.bottom, 4)

                BannerAdView()
                    .frame(width: BannerAdView.size.width, height: BannerAdView.size.height)
            }

            if model.isPaused { pauseOverlay }
            if let candidates = model.itemRouletteCandidates {
                ItemRouletteView(
                    candidates: candidates,
                    image: model.image(for:),
                    rareEffect: model.rareEffect(for:),
                    onFinish: model.finishItemRoulette(with:)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            if model.isGameOver { gameOverOverlay }
        }
        .onAppear { model.setOnScreen(scenePhase == .active) }
        .onDisappear {
            model.setOnScreen(false)
            model.persistBestScore()
        }
        .onChange(of: scenePhase) { _, phase in
            model.setOnScreen(phase == .active)
        }
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
            .accessibilityLabel(model.isPaused ? String(localized: "再開") : String(localized: "一時停止"))
        }
    }

    private var scoreBar: some View {
        HStack(spacing: 10) {
            scoreCell(label: "SCORE", value: "\(model.score)", accent: KuttukeTheme.orange)
            nextQueueCell
            itemChangeButton
        }
    }

    private var itemChangeButton: some View {
        let isAvailable = model.itemChangesLeft > 0 && rewardedAds.isReady
        return Button(action: model.openItemRoulette) {
            VStack(spacing: 3) {
                Image(systemName: "dice.fill")
                    .font(.system(size: 19, weight: .black))
                // 広告を見ることが押す前にわかるようにする
                Label("チェンジ", systemImage: "play.rectangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 8, weight: .black, design: .rounded))
            }
            .foregroundStyle(isAvailable ? KuttukeTheme.purple : KuttukeTheme.secondaryText.opacity(0.35))
            .frame(width: 58, height: 58)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if model.itemChangesLeft > 0 {
                    Text("\(model.itemChangesLeft)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(KuttukeTheme.pink, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(!model.canChangeItem || !rewardedAds.isReady)
        .accessibilityLabel("広告を見てアイテムチェンジ。残り\(model.itemChangesLeft)回")
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
                        .rareEffect(model.rareEffect(for: level), image: image)
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

    /// 進化列の高さ（最大レベルの素材の大きさ + 上下の余白）
    private static let evolutionRowHeight: CGFloat = 70
    /// 進化列の素材と背景の間の余白
    private static let evolutionRowInset: CGFloat = 3

    /// 進化の順番を盤面の下に横に並べる（左が最小、右へ向かって大きくなる）
    private var evolutionRow: some View {
        GeometryReader { proxy in
            let inset = Self.evolutionRowInset
            let layout = EvolutionRowLayout(
                count: model.evolutionImages.count,
                maxHeight: proxy.size.height,
                availableWidth: proxy.size.width,
                inset: inset
            )
            let sides = layout.itemSides

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(model.evolutionImages.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .rareEffect(model.rareEffect(for: index), image: image)
                        // 余白を除いた素材を枠の下端に置き、すべての素材の底を揃える
                        .frame(width: sides[index], height: sides[index], alignment: .bottom)
                        .accessibilityLabel("進化レベル \(index + 1)")
                }
            }
            .padding(inset)
            .background(
                EvolutionBackdrop(layout: layout)
                    .fill(.white.opacity(0.9))
            )
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("進化の順番")
    }

    /// 盤面を固定の縦横比で収め、進化の列を盤面と同じ幅で下に並べる
    private var boardArea: some View {
        GeometryReader { proxy in
            let rowHeight = Self.evolutionRowHeight
            let spacing: CGFloat = 8
            let maxBoardHeight = max(proxy.size.height - rowHeight - spacing, 0)
            let boardWidth = min(proxy.size.width, maxBoardHeight * DropGameScene.boardAspectRatio)
            let boardHeight = boardWidth / DropGameScene.boardAspectRatio

            VStack(spacing: spacing) {
                board
                    .frame(width: boardWidth, height: boardHeight)
                evolutionRow
                    .frame(width: boardWidth, height: rowHeight)
            }
            // 余った高さは上に回し、進化の列とバナーの間を端末によらず一定にする
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
    }

    private var shareMessage: String {
        let headline = model.didUpdateBestScore ? String(localized: "自己ベスト更新！") : ""
        let rankText = model.leaderboardRank.map { String(localized: "\($0.itemCount)個ランキングで全国\($0.rank)位！") } ?? ""
        let scoreText = String(localized: "「\(stageName)」で\(model.score)点！")
        return "\(headline)\(scoreText)\(rankText) #Kuttuke\n\(AppStoreLink.url.absoluteString)"
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

/// 次に落ちるアイテムを選び直すルーレット。候補を順に光らせ、ストップを押した瞬間のものに決まる（目押し）
private struct ItemRouletteView: View {
    let candidates: [Int]
    let image: (Int) -> UIImage?
    let rareEffect: (Int) -> RareEffect?
    let onFinish: (Int) -> Void

    /// 1コマの長さ。速すぎると狙えず、遅すぎると簡単すぎる
    private static let stepInterval: Duration = .milliseconds(130)
    private static let rowWidth: CGFloat = 258
    private static let rowSpacing: CGFloat = 6

    @State private var index: Int
    @State private var isStopped = false
    @State private var landed = false
    private let tickFeedback = UISelectionFeedbackGenerator()

    init(candidates: [Int], image: @escaping (Int) -> UIImage?, rareEffect: @escaping (Int) -> RareEffect?, onFinish: @escaping (Int) -> Void) {
        self.candidates = candidates
        self.image = image
        self.rareEffect = rareEffect
        self.onFinish = onFinish
        _index = State(initialValue: Int.random(in: 0..<max(candidates.count, 1)))
    }

    private var rowItemSide: CGFloat {
        let count = CGFloat(max(candidates.count, 1))
        return min(40, (Self.rowWidth - Self.rowSpacing * (count - 1)) / count)
    }

    var body: some View {
        Color.black.opacity(0.32)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 14) {
                    Label("アイテムチェンジ", systemImage: "dice.fill")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(KuttukeTheme.purple)
                    Text(isStopped ? "これに決定！" : "タイミングよく止めてね")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)

                    slot
                    candidateRow

                    Button(action: stop) {
                        Label("ストップ！", systemImage: "hand.tap.fill")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(isStopped ? KuttukeTheme.secondaryText.opacity(0.5) : KuttukeTheme.ink, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle())
                    .disabled(isStopped)
                    .padding(.top, 4)
                }
                .padding(26)
                .frame(maxWidth: 310)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .task { await spin() }
    }

    private var slot: some View {
        let level = candidates.isEmpty ? 0 : candidates[index]
        return ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(KuttukeTheme.cream)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(isStopped ? KuttukeTheme.orange : .white, lineWidth: 4)
            if let image = image(level) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .rareEffect(rareEffect(level), image: image)
                    .padding(18)
            }
        }
        .frame(width: 150, height: 150)
        .scaleEffect(landed ? 1.08 : 1)
        .accessibilityLabel("進化レベル \(level + 1)")
    }

    private var candidateRow: some View {
        HStack(spacing: Self.rowSpacing) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { offset, level in
                if let image = image(level) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                        .frame(width: rowItemSide, height: rowItemSide)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(offset == index ? KuttukeTheme.purple.opacity(0.22) : .white.opacity(0.7))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(offset == index ? KuttukeTheme.purple : .clear, lineWidth: 2)
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func spin() async {
        guard candidates.count > 1 else { return }
        tickFeedback.prepare()
        while !isStopped, !Task.isCancelled {
            try? await Task.sleep(for: Self.stepInterval)
            guard !isStopped else { break }
            index = (index + 1) % candidates.count
            tickFeedback.selectionChanged()
        }
    }

    private func stop() {
        guard !isStopped, !candidates.isEmpty else { return }
        isStopped = true
        let level = candidates[index]
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) { landed = true }
        Task {
            try? await Task.sleep(for: .milliseconds(750))
            onFinish(level)
        }
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

/// 進化の列の並べ方。上辺のカーブを先に決め、各素材をカーブの下に収まる大きさで左から詰めていく
private struct EvolutionRowLayout {
    /// 左端の高さを右端の何割にするか
    static let leftHeightRatio: CGFloat = 0.4

    /// 背景の幅と、右端でのカーブの高さ
    let width: CGFloat
    let topHeight: CGFloat
    let inset: CGFloat
    let itemSides: [CGFloat]

    init(count: Int, maxHeight: CGFloat, availableWidth: CGFloat, inset: CGFloat) {
        self.inset = inset
        let maxHeight = max(maxHeight, 0)
        let availableWidth = max(availableWidth, 0)
        guard count > 0, maxHeight > 0, availableWidth > 0 else {
            (width, topHeight, itemSides) = (0, 0, [])
            return
        }

        // 最大の高さで並べて幅が余るなら、ちょうど詰まる幅まで背景を縮める。はみ出すなら高さを縮める
        var width = availableWidth
        var topHeight = maxHeight
        if Self.filledWidth(count: count, width: availableWidth, topHeight: maxHeight, inset: inset) <= availableWidth {
            var low: CGFloat = 0
            var high = availableWidth
            for _ in 0..<30 {
                let mid = (low + high) / 2
                if Self.filledWidth(count: count, width: mid, topHeight: maxHeight, inset: inset) > mid { low = mid } else { high = mid }
            }
            width = high
        } else {
            var low: CGFloat = 0
            var high = maxHeight
            for _ in 0..<30 {
                let mid = (low + high) / 2
                if Self.filledWidth(count: count, width: availableWidth, topHeight: mid, inset: inset) > availableWidth { high = mid } else { low = mid }
            }
            topHeight = low
        }
        self.width = width
        self.topHeight = topHeight
        self.itemSides = Self.sides(count: count, width: width, topHeight: topHeight, inset: inset)
    }

    /// 左端からxの位置でのカーブの高さ。右へ行くほど急に高くなる（下にたわむ）
    static func curveHeight(at x: CGFloat, width: CGFloat, topHeight: CGFloat) -> CGFloat {
        let progress = min(max(x / max(width, 1), 0), 1)
        return topHeight * (leftHeightRatio + (1 - leftHeightRatio) * progress * progress)
    }

    func curveHeight(at x: CGFloat) -> CGFloat {
        Self.curveHeight(at: x, width: width, topHeight: topHeight)
    }

    /// 素材の大きさを、その素材の左端からこの割合だけ右の位置でのカーブの高さに合わせる。
    /// 0なら素材の上端がカーブに一切かからないが、右端の素材の上が空きすぎるため少し右で合わせる
    private static let fitPosition: CGFloat = 0.35

    private static func sides(count: Int, width: CGFloat, topHeight: CGFloat, inset: CGFloat) -> [CGFloat] {
        var x = inset
        return (0..<count).map { _ in
            // 大きさで合わせる位置が変わるので、数回くり返して落ち着かせる
            var side = curveHeight(at: x, width: width, topHeight: topHeight) - inset * 2
            for _ in 0..<6 {
                side = curveHeight(at: x + side * fitPosition, width: width, topHeight: topHeight) - inset * 2
            }
            side = max(floor(side), 1)
            x += side
            return side
        }
    }

    private static func filledWidth(count: Int, width: CGFloat, topHeight: CGFloat, inset: CGFloat) -> CGFloat {
        sides(count: count, width: width, topHeight: topHeight, inset: inset).reduce(0, +) + inset * 2
    }
}

/// 進化の列の背景。底辺は平らで、上辺は右へ向かって下にたわみながら高くなるカーブ
private struct EvolutionBackdrop: Shape {
    var layout: EvolutionRowLayout

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let step: CGFloat = 2
        var x: CGFloat = 0
        while x < rect.width {
            path.addLine(to: CGPoint(x: rect.minX + x, y: rect.maxY - layout.curveHeight(at: x)))
            x += step
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - layout.curveHeight(at: rect.width)))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
