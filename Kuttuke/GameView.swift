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

    private let bestScoreKey: String
    private let mergeFeedback = UIImpactFeedbackGenerator(style: .soft)
    private let gameOverFeedback = UINotificationFeedbackGenerator()

    init(images: [UIImage], stageID: UUID) {
        let bestScoreKey = "kuttuke.best-score.\(stageID.uuidString)"
        self.images = images
        self.bestScoreKey = bestScoreKey
        self.bestScore = UserDefaults.standard.integer(forKey: bestScoreKey)
        self.scene = DropGameScene(images: images)
        connectScene()
    }

    func restart() {
        persistBestScore()
        score = 0
        isGameOver = false
        isPaused = false
        scene.isPaused = false
        scene.resetGame()
    }

    func togglePause() {
        guard !isGameOver else { return }
        isPaused.toggle()
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
        scene.onGameOver = { [weak self] in
            self?.persistBestScore()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                self?.isGameOver = true
            }
            self?.gameOverFeedback.notificationOccurred(.warning)
        }
        scene.onMerge = { [weak self] in
            self?.mergeFeedback.impactOccurred(intensity: 0.9)
        }
        mergeFeedback.prepare()
    }
}

struct GameView: View {
    @StateObject private var model: GameViewModel
    let stageName: String
    let onExit: () -> Void

    init(images: [UIImage], stageID: UUID, stageName: String, onExit: @escaping () -> Void) {
        _model = StateObject(wrappedValue: GameViewModel(images: images, stageID: stageID))
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

            VStack(spacing: 12) {
                gameHeader
                scoreBar
                boardArea
                instruction
            }
            .padding(.horizontal, 15)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if model.isPaused { pauseOverlay }
            if model.isGameOver { gameOverOverlay }
        }
        .onDisappear { model.persistBestScore() }
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

    // スコア更新のたびにSpriteViewまで再評価されないよう、盤面は別のViewに切り出す
    private var board: some View {
        GameBoardView(scene: model.scene)
    }

    private var instruction: some View {
        Label("左右に動かして、指を離すと落ちます", systemImage: "hand.draw.fill")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(KuttukeTheme.secondaryText)
            .frame(height: 28)
    }

    private var pauseOverlay: some View {
        Color.black.opacity(0.24)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 15) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 26, weight: .black))
                    Text("ひとやすみ")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                    Button("つづける") { model.togglePause() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .frame(height: 48)
                        .background(KuttukeTheme.ink, in: Capsule())

                    Button {
                        model.finishCurrentGame()
                    } label: {
                        Label("ここで終了", systemImage: "stop.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 22)
                            .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
    }

    private var gameOverOverlay: some View {
        Color.black.opacity(0.32)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    Text("FINISH!")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(KuttukeTheme.orange)
                    Text("\(model.score)")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                    Text("今回のスコア")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)

                    Button {
                        model.restart()
                    } label: {
                        Label("もう一度", systemImage: "arrow.clockwise")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(KuttukeTheme.ink, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle())

                    Button("ホームへ", action: onExit)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                        .frame(height: 38)
                }
                .padding(26)
                .frame(maxWidth: 310)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
