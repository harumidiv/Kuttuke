import SwiftUI

/// 設定から開く、これまでに追加した切り抜き素材の一覧と削除
struct AssetManagementView: View {
    @ObservedObject var library: SubjectLibrary

    @State private var assetPendingDeletion: SubjectAsset?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            KuttukeTheme.background.ignoresSafeArea()

            if library.assets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("タップすると削除できます。ステージで使っている素材は、削除するとそのステージからも外れます。")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(KuttukeTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(library.assets) { asset in
                                assetCell(asset)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("切り抜き素材（\(library.assets.count)個）")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "この切り抜きを削除しますか？",
            isPresented: Binding(
                get: { assetPendingDeletion != nil },
                set: { if !$0 { assetPendingDeletion = nil } }
            ),
            presenting: assetPendingDeletion
        ) { asset in
            Button(library.stages(using: asset.id).isEmpty ? "削除" : "ステージから外して削除", role: .destructive) {
                withAnimation { library.remove(asset) }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            Button("キャンセル", role: .cancel) {}
        } message: { asset in
            Text(library.deletionWarning(for: asset))
        }
    }

    private func assetCell(_ asset: SubjectAsset) -> some View {
        let usageCount = library.stages(using: asset.id).count
        return Button {
            assetPendingDeletion = asset
        } label: {
            VStack(spacing: 7) {
                Image(uiImage: asset.image)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .aspectRatio(1, contentMode: .fit)
                    .background(KuttukeTheme.cream, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.red.opacity(0.85), in: Circle())
                            .padding(6)
                    }

                Text(usageCount == 0 ? "未使用" : "\(usageCount)ステージで使用中")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(usageCount == 0 ? KuttukeTheme.secondaryText : KuttukeTheme.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel(usageCount == 0 ? "未使用の切り抜き" : "\(usageCount)ステージで使用中の切り抜き")
        .accessibilityHint("タップすると削除の確認が表示されます")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(KuttukeTheme.secondaryText.opacity(0.5))
            Text("切り抜き素材はまだありません")
                .font(.system(size: 15, weight: .black, design: .rounded))
            Text("ステージを作るときに写真から切り抜くと、ここに並びます。")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(KuttukeTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
}
