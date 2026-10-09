import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: SubjectLibrary

    var body: some View {
        NavigationStack {
            ZStack {
                KuttukeTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        tutorialLink
                        storageInformation
                    }
                    .padding(20)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    private var tutorialLink: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("サポート")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(KuttukeTheme.secondaryText)

            NavigationLink {
                TutorialView()
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(KuttukeTheme.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("遊び方")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                        Text("切り抜きからゲーム操作まで確認")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                }
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.black.opacity(0.055)))
            }
            .buttonStyle(.plain)
        }
    }

    private var storageInformation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("データ")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(KuttukeTheme.secondaryText)

            NavigationLink {
                AssetManagementView(library: library)
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(KuttukeTheme.pink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("切り抜き素材の管理")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                        Text("\(library.assets.count)個の素材・不要なものを削除")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                }
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.black.opacity(0.055)))
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(KuttukeTheme.purple)
                    .frame(width: 42, height: 42)
                    .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("この端末に保存")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("切り抜き素材と進化セットはアプリ内に保存され、次回もそのまま使えます。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(KuttukeTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        }
    }
}

private struct TutorialView: View {
    var body: some View {
        ZStack {
            KuttukeTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 17) {
                    tutorialHero

                    tutorialStep(
                        number: 1,
                        title: "進化セットを作る",
                        details: [
                            "ホームの「作る」をタップします",
                            "保存済み素材か、新しい写真を選びます",
                            "素材を6〜11個選ぶとプレイできます"
                        ],
                        accent: KuttukeTheme.orange,
                        visual: .stage
                    )

                    tutorialStep(
                        number: 2,
                        title: "写真から切り抜く",
                        details: [
                            "写真は一度に複数選択できます",
                            "準備完了後、被写体を長押しします",
                            "光った被写体を下の枠へ運び「完了」で保存します"
                        ],
                        accent: KuttukeTheme.pink,
                        visual: .lift
                    )

                    tutorialStep(
                        number: 3,
                        title: "進化順を決める",
                        details: [
                            "上から小さい順に並びます",
                            "右側のハンドルを長押ししてドラッグすると並べ替えられます",
                            "切り抜きは別のセットでも再利用できます"
                        ],
                        accent: KuttukeTheme.purple,
                        visual: .order
                    )

                    tutorialStep(
                        number: 4,
                        title: "落として、くっつける",
                        details: [
                            "指を左右に動かし、離した位置から落とします",
                            "同じレベル同士が触れると次の姿へ進化します",
                            "積み上がってLIMITを超え続けるとゲーム終了です"
                        ],
                        accent: .green,
                        visual: .play
                    )
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("遊び方")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tutorialHero: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(KuttukeTheme.orange, in: Circle())

            Text("写真が進化するゲーム")
                .font(.system(size: 23, weight: .black, design: .rounded))
            Text("切り抜いたお気に入りを、順番に大きくしていきましょう")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .background(
            LinearGradient(
                colors: [KuttukeTheme.mint, KuttukeTheme.sky],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private func tutorialStep(
        number: Int,
        title: String,
        details: [String],
        accent: Color,
        visual: TutorialVisual
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Text("\(number)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(accent, in: Circle())
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
            }

            tutorialVisual(visual, accent: accent)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(details, id: \.self) { detail in
                    Label {
                        Text(detail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.black.opacity(0.05)))
    }

    @ViewBuilder
    private func tutorialVisual(_ visual: TutorialVisual, accent: Color) -> some View {
        HStack(spacing: 10) {
            switch visual {
            case .stage:
                tutorialSymbol("photo.on.rectangle.angled", color: KuttukeTheme.purple, size: 20)
                tutorialArrow
                tutorialSymbol("square.stack.3d.up.fill", color: accent, size: 22)
                tutorialArrow
                tutorialSymbol("play.fill", color: KuttukeTheme.ink, size: 18)
            case .lift:
                tutorialSymbol("photo.fill", color: KuttukeTheme.sky, size: 21)
                tutorialArrow
                tutorialSymbol("hand.tap.fill", color: accent, size: 21)
                tutorialArrow
                tutorialSymbol("square.and.arrow.down.fill", color: KuttukeTheme.orange, size: 20)
            case .order:
                evolutionDot(size: 25, color: KuttukeTheme.orange)
                tutorialArrow
                evolutionDot(size: 34, color: KuttukeTheme.pink)
                tutorialArrow
                evolutionDot(size: 43, color: KuttukeTheme.purple)
            case .play:
                evolutionDot(size: 31, color: accent)
                Text("+")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                evolutionDot(size: 31, color: accent)
                tutorialArrow
                evolutionDot(size: 46, color: KuttukeTheme.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(KuttukeTheme.cream.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func tutorialSymbol(_ name: String, color: Color, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var tutorialArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(KuttukeTheme.secondaryText.opacity(0.55))
    }

    private func evolutionDot(size: CGFloat, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Image(systemName: "sparkle").font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(.white))
    }
}

private enum TutorialVisual {
    case stage
    case lift
    case order
    case play
}
