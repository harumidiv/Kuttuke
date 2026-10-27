// iPhone Duo 用の App Store スクリーンショットを、Simulator で撮った画面（raw-duo）から作る
// usage: swift AppStoreScreenshots/generate_duo_screenshots.swift
import AppKit

// swift で直接実行すると #filePath がモジュール名になるため、引数の0番目（このファイルのパス）から求める
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let raw = root.appendingPathComponent("raw-duo")
let out = root.appendingPathComponent("final-duo")
let appIcon = root.deletingLastPathComponent().appendingPathComponent("Kuttuke/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

// iPhone Duo（開いた状態）の画面サイズ
let width = 2007
let height = 2853

// KuttukeTheme と同じ色
func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
let ink = rgb(27, 31, 32)
let secondary = rgb(99, 102, 99)
let cream = rgb(250, 244, 227)
let orange = rgb(255, 107, 51)
let pink = rgb(240, 87, 122)
let purple = rgb(122, 92, 219)
let mint = rgb(173, 232, 194)
let sky = rgb(184, 219, 250)
let yellow = rgb(255, 205, 74)

// 開いて縦向きにした状態の画面全体を使う
let screenCrop = CGRect(x: 0, y: 0, width: 2007, height: 2853)
// AdMob のテストバナー（ゲーム画面の下）
let adBanner = CGRect(x: 470, y: 2590, width: 1070, height: 175)
let screenTop: CGFloat = 610
let screenHeight: CGFloat = 2150
let screenRadius: CGFloat = 72

struct Page {
    let source: String
    let output: String
    let title: String
    let subtitle: String
    let top: NSColor
    let bottom: NSColor
    let circles: [(CGRect, NSColor)]
    var hasAd = false
}

let pages = [
    Page(source: "04-game.png", output: "01-merge.png",
         title: "写真が、くっつく。", subtitle: "同じ素材どうしをくっつけて進化させよう",
         top: sky, bottom: cream,
         circles: [(CGRect(x: 1700, y: -150, width: 460, height: 460), yellow),
                   (CGRect(x: -210, y: 380, width: 360, height: 360), rgb(255, 255, 255, 0.45)),
                   (CGRect(x: 1780, y: 470, width: 280, height: 280), rgb(255, 255, 255, 0.35))],
         hasAd: true),
    Page(source: "03-effects.png", output: "02-rare-effects.png",
         title: "傾けると光る、キラ加工", subtitle: "ギャラクシーやステンドグラスで素材をレアに",
         top: rgb(214, 203, 250), bottom: rgb(234, 246, 255),
         circles: [(CGRect(x: -220, y: -110, width: 470, height: 470), purple.withAlphaComponent(0.55)),
                   (CGRect(x: 1760, y: 380, width: 400, height: 400), yellow)]),
    Page(source: "02-editor.png", output: "03-create-set.png",
         title: "好きな写真で進化セットをつくる", subtitle: "切り抜いた素材を、小さい順に並べるだけ",
         top: rgb(255, 214, 190), bottom: cream,
         circles: [(CGRect(x: -230, y: -120, width: 460, height: 460), orange.withAlphaComponent(0.45)),
                   (CGRect(x: 1770, y: 420, width: 360, height: 360), mint),
                   (CGRect(x: 1820, y: 70, width: 120, height: 120), yellow)]),
    Page(source: "01-home.png", output: "04-my-stages.png",
         title: "自分だけのステージで遊ぼう", subtitle: "つくった進化セットは保存してすぐプレイ",
         top: rgb(205, 240, 215), bottom: cream,
         circles: [(CGRect(x: 1740, y: -160, width: 480, height: 480), pink.withAlphaComponent(0.45)),
                   (CGRect(x: -200, y: 430, width: 370, height: 370), sky)]),
    Page(source: "05-result.png", output: "05-share-result.png",
         title: "どこまで進化できる？", subtitle: "スコアをシェアして、ランキングに挑戦",
         top: rgb(255, 208, 218), bottom: cream,
         circles: [(CGRect(x: -220, y: -100, width: 470, height: 470), purple.withAlphaComponent(0.45)),
                   (CGRect(x: 1770, y: 360, width: 410, height: 410), yellow)],
         hasAd: true),
]

func loadCG(_ url: URL) -> CGImage {
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: url))!
    return rep.cgImage!
}

/// 撮った画面からアプリ部分を切り出し、広告バナーを行ごとの背景色で塗りつぶす
func preparedScreen(_ page: Page) -> CGImage {
    let source = loadCG(raw.appendingPathComponent(page.source))
    let rep = NSBitmapImageRep(cgImage: source.cropping(to: screenCrop)!)
    if page.hasAd {
        for y in Int(adBanner.minY)..<Int(adBanner.maxY) {
            let color = rep.colorAt(x: 200, y: y)!
            for x in Int(adBanner.minX)..<Int(adBanner.maxX) {
                rep.setColor(color, atX: x, y: y)
            }
        }
    }
    return rep.cgImage!
}

func drawCentered(_ text: String, font: NSFont, color: NSColor, y: CGFloat, maxWidth: CGFloat) {
    var font = font
    var attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    // 長い見出しは1行に収まるまで小さくする
    while attributed.size().width > maxWidth {
        font = NSFont(descriptor: font.fontDescriptor, size: font.pointSize - 4)!
        attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }
    let size = attributed.size()
    attributed.draw(at: CGPoint(x: (CGFloat(width) - size.width) / 2, y: y))
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func render(_ page: Page) -> URL {
    // App Store は透過を受け付けないため、最初からアルファなしのキャンバスに描く
    let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // 左上原点で描く
    cg.translateBy(x: 0, y: CGFloat(height))
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    let gradient = NSGradient(starting: page.top, ending: page.bottom)!
    gradient.draw(in: CGRect(x: 0, y: 0, width: width, height: height), angle: 90)
    for (rect, color) in page.circles {
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    // アプリアイコンと名前
    let icon = loadCG(appIcon)
    let iconSize: CGFloat = 116
    let brand = NSAttributedString(string: "KUTTUKE", attributes: [
        .font: NSFont(name: "HiraginoSans-W8", size: 58)!, .foregroundColor: ink, .kern: 4,
    ])
    let brandWidth = iconSize + 28 + brand.size().width
    let brandX = (CGFloat(width) - brandWidth) / 2
    let iconRect = CGRect(x: brandX, y: 92, width: iconSize, height: iconSize)
    cg.saveGState()
    cg.addPath(roundedPath(iconRect, 27))
    cg.clip()
    // CGImage は下から描かれるため、反転を打ち消して置く
    cg.translateBy(x: 0, y: iconRect.maxY + iconRect.minY)
    cg.scaleBy(x: 1, y: -1)
    cg.draw(icon, in: iconRect)
    cg.restoreGState()
    brand.draw(at: CGPoint(x: brandX + iconSize + 28, y: 92 + (iconSize - brand.size().height) / 2))

    drawCentered(page.title, font: NSFont(name: "HiraginoSans-W8", size: 124)!, color: ink, y: 268, maxWidth: 1820)
    drawCentered(page.subtitle, font: NSFont(name: "HiraginoSans-W6", size: 54)!, color: secondary, y: 452, maxWidth: 1820)

    // 画面：白いフチと影をつけて角を丸める
    let screen = preparedScreen(page)
    let screenWidth = screenHeight * CGFloat(screen.width) / CGFloat(screen.height)
    let screenRect = CGRect(x: (CGFloat(width) - screenWidth) / 2, y: screenTop, width: screenWidth, height: screenHeight)
    let frameRect = screenRect.insetBy(dx: -20, dy: -20)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 26), blur: 70, color: rgb(22, 42, 52, 0.28).cgColor)
    cg.addPath(roundedPath(frameRect, screenRadius + 20))
    cg.setFillColor(NSColor.white.cgColor)
    cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(roundedPath(screenRect, screenRadius))
    cg.clip()
    cg.translateBy(x: 0, y: screenRect.maxY + screenRect.minY)
    cg.scaleBy(x: 1, y: -1)
    cg.interpolationQuality = .high
    cg.draw(screen, in: screenRect)
    cg.restoreGState()

    NSGraphicsContext.current = nil
    try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let url = out.appendingPathComponent(page.output)
    try! NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
    return url
}

for page in pages {
    print(render(page).path)
}
