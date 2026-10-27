// App Store のプロダクトページのヘッダー画像を作る（16:9 5244x2950 と 21:9 3840x1646）
// usage: swift AppStoreScreenshots/generate_header.swift
//
// 16:9 はヘッダー（21:9）と検索結果（3:2）の両方に切り抜かれて使われる。
// 大事な要素は両方に残る中央（約4425x2247）に収め、端は切れてもいい飾りだけにする
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let assets = root.appendingPathComponent("header-assets")
let out = root.appendingPathComponent("header")

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
// KuttukeTheme と同じ色
let background = rgb(246, 242, 233)
let ink = rgb(27, 31, 32)
let orange = rgb(255, 107, 51)
let pink = rgb(240, 87, 122)
let purple = rgb(122, 92, 219)
let mint = rgb(173, 232, 194)
let sky = rgb(184, 219, 250)
let yellow = rgb(255, 205, 74)

/// 素材1つの置き方。座標は 16:9（5244x2950）での中心、size は素材の正方形の一辺
struct Sticker {
    let name: String
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let angle: CGFloat
}

// 奥から順に描く。合体した瞬間のように、少しずつ重ねて山にする
let pile = [
    Sticker(name: "vr-thermal", x: 3760, y: 1640, size: 1100, angle: 6),
    Sticker(name: "eagle-stitch", x: 3180, y: 1300, size: 920, angle: -4),
    Sticker(name: "jump-silver", x: 2580, y: 1180, size: 820, angle: 10),
    Sticker(name: "sign-pixel", x: 1380, y: 1330, size: 720, angle: -14),
    Sticker(name: "cat-galaxy", x: 1980, y: 1360, size: 980, angle: -10),
    Sticker(name: "dog-stained", x: 1700, y: 1830, size: 980, angle: -5),
    Sticker(name: "tomato-oil", x: 2640, y: 1880, size: 1020, angle: 3),
    Sticker(name: "donut", x: 3330, y: 2120, size: 720, angle: 10),
    Sticker(name: "apple", x: 3960, y: 2200, size: 560, angle: -6),
    // 犬の写真は下端がまっすぐ切れているので、手前のドーナツで隠す
    Sticker(name: "donut-oil", x: 1640, y: 2190, size: 820, angle: -8),
]

/// 合体したところに出すきらめき（16:9 での中心と大きさ）
let sparkles: [(CGFloat, CGFloat, CGFloat)] = [
    (2330, 1250, 160), (2150, 1800, 120), (3000, 2060, 130), (3460, 1560, 100), (1160, 1720, 80),
]

/// 背景の丸（16:9 での中心、半径、色）。端のものは切り抜かれてもいい
let blobs: [(CGFloat, CGFloat, CGFloat, CGColor)] = [
    (330, 420, 620, orange.copy(alpha: 0.30)!),
    (4980, 380, 560, sky),
    (4900, 2620, 700, mint.copy(alpha: 0.8)!),
    (260, 2650, 640, purple.copy(alpha: 0.28)!),
    (2622, 1780, 1500, rgb(255, 255, 255, 0.55)),
    (1000, 900, 150, yellow),
    (4350, 950, 120, pink.copy(alpha: 0.55)!),
]

struct Layout {
    let name: String
    let width: Int
    let height: Int
    /// 16:9 の配置をこの画像に写すときの拡大率と、写したあとの中心
    let scale: CGFloat
    let center: CGPoint
    let titleSize: CGFloat
    let titleY: CGFloat
}

let layouts = [
    Layout(name: "header-16x9-5244x2950.png", width: 5244, height: 2950,
           scale: 1, center: CGPoint(x: 2622, y: 1475), titleSize: 300, titleY: 470),
    // 21:9 は高さが足りないので、山を縮めて少し下げる
    Layout(name: "header-21x9-3840x1646.png", width: 3840, height: 1646,
           scale: 0.56, center: CGPoint(x: 1920, y: 900), titleSize: 190, titleY: 175),
]

func load(_ name: String) -> CGImage {
    NSBitmapImageRep(data: try! Data(contentsOf: assets.appendingPathComponent(name + ".png")))!.cgImage!
}

/// 4本の光が伸びるきらめき
func drawSparkle(_ cg: CGContext, at p: CGPoint, size: CGFloat) {
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: size * 0.5, color: rgb(255, 230, 150, 0.9))
    cg.setFillColor(rgb(255, 255, 255))
    let path = CGMutablePath()
    let thin = size * 0.16
    path.move(to: CGPoint(x: p.x, y: p.y - size))
    path.addQuadCurve(to: CGPoint(x: p.x + size, y: p.y), control: CGPoint(x: p.x + thin, y: p.y - thin))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + size), control: CGPoint(x: p.x + thin, y: p.y + thin))
    path.addQuadCurve(to: CGPoint(x: p.x - size, y: p.y), control: CGPoint(x: p.x - thin, y: p.y + thin))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - size), control: CGPoint(x: p.x - thin, y: p.y - thin))
    cg.addPath(path)
    cg.fillPath()
    cg.restoreGState()
}

func render(_ layout: Layout) -> URL {
    let w = CGFloat(layout.width), h = CGFloat(layout.height)
    // App Store はアルファチャンネルを受け付けないため、アルファなしで描く
    let cg = CGContext(data: nil, width: layout.width, height: layout.height, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // 左上原点で考える
    cg.translateBy(x: 0, y: h)
    cg.scaleBy(x: 1, y: -1)
    cg.interpolationQuality = .high

    // 16:9 での座標を、この画像の座標に写す
    func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: layout.center.x + (x - 2622) * layout.scale, y: layout.center.y + (y - 1475) * layout.scale)
    }

    cg.setFillColor(background)
    cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for (x, y, r, color) in blobs {
        // 端の丸は画像の端に貼りつけ、大きさだけ縮める
        let isEdge = r < 1000 && (x < 600 || x > 4600)
        var p = map(x, y)
        if isEdge {
            p.x = x < 2622 ? x * layout.scale : w - (5244 - x) * layout.scale
            p.y = y < 1475 ? y * layout.scale : h - (2950 - y) * layout.scale
        }
        let radius = r * layout.scale
        cg.setFillColor(color)
        cg.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
    }

    for sticker in pile {
        let image = load(sticker.name)
        let p = map(sticker.x, sticker.y)
        let side = sticker.size * layout.scale
        cg.saveGState()
        cg.translateBy(x: p.x, y: p.y)
        cg.rotate(by: sticker.angle * .pi / 180)
        // 盤面と同じく、少し下に柔らかい影を落とす
        cg.setShadow(offset: CGSize(width: 0, height: side * 0.025), blur: side * 0.05, color: rgb(40, 30, 20, 0.28))
        // 反転を打ち消して、画像を正しい向きで置く
        cg.scaleBy(x: 1, y: -1)
        cg.draw(image, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
        cg.restoreGState()
    }
    for (x, y, size) in sparkles {
        drawSparkle(cg, at: map(x, y), size: size * layout.scale)
    }

    // 短いフレーズ。色は濃く、背景の丸に重なっても読めるよう白いフチをつける
    let font = NSFont(name: "HiraginoSans-W8", size: layout.titleSize)!
    let title = "写真が、くっつく。"
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    let outline = NSAttributedString(string: title, attributes: [
        .font: font, .strokeColor: NSColor.white, .strokeWidth: 16, .kern: layout.titleSize * 0.04,
    ])
    let fill = NSAttributedString(string: title, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: ink)!, .kern: layout.titleSize * 0.04,
    ])
    let origin = CGPoint(x: (w - fill.size().width) / 2, y: layout.titleY)
    outline.draw(at: origin)
    fill.draw(at: origin)
    NSGraphicsContext.current = nil

    try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let url = out.appendingPathComponent(layout.name)
    try! NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
    return url
}

for layout in layouts {
    print(render(layout).path)
}
