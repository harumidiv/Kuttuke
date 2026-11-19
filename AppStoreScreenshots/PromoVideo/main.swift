// App Store の検索結果（3:2, 3840x2560）用の動画を書き出す。
// 使い方: AppStoreScreenshots/PromoVideo/render.sh [--stills]
//
// 20秒でループする4章の動画。検索結果はミュート再生なので、音は「録音中」の表示・波形・音符で見せる。
//   1. 好きな写真で遊べる   … 写真から被写体を切り抜いてシールにする
//   2. エフェクトで大変身   … 同じドーナツにエフェクトを次々かける（アプリの10種類のうち4つを CoreImage で近い見た目に）
//   3. 音も自由に変えられる … 録音してから合体させ、鳴った音を吹き出しと音符で見せる
//   4. ステージを友達に共有 … ステージのカードと共有コード・QRコードを出し、紙飛行機で送る（コードは架空）
// りんごの素材は解像度が低く拡大すると粗いので、主役には使わない。
// 検索結果では大きく切り取られるので、見出しと動きは中央の帯（previewArea）に収め、外側は飾りだけにする。
import AppKit
import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

// MARK: - 仕様

let width = 3840
let height = 2560
let fps: Int32 = 30
let duration = 20.0
let frameCount = Int(duration * Double(fps))
/// Apple のアートセーフエリア（左上原点）
let safeArea = CGRect(x: 836, y: 765, width: 2168, height: 1030)
/// App Store Connect の検索結果プレビューで実際に見えた範囲（横 27〜73%・縦 17〜62%）
let previewArea = CGRect(x: 3840 * 0.27, y: 2560 * 0.17, width: 3840 * 0.46, height: 2560 * 0.45)

// MARK: - 色（KuttukeTheme と同じ）

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
let background = rgb(246, 242, 233)
let ink = rgb(27, 31, 32)
let orange = rgb(255, 107, 51)
let pink = rgb(240, 87, 122)
let purple = rgb(122, 92, 219)
let mint = rgb(173, 232, 194)
let sky = rgb(184, 219, 250)
let yellow = rgb(255, 205, 74)

// MARK: - 素材

let assetDirectory = URL(fileURLWithPath: "AppStoreScreenshots/header-assets")

/// 素材を描きやすい大きさに縮めて読み込む（毎コマ 1200px を縮小すると遅い）
func loadSticker(_ name: String, side: Int = 720) -> CGImage {
    let url = assetDirectory.appendingPathComponent(name + ".png")
    guard let data = try? Data(contentsOf: url), let image = NSBitmapImageRep(data: data)?.cgImage else {
        fatalError("素材を読み込めません: \(url.path)")
    }
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()!
}

let subject = loadSticker("donut")
let mergedSticker = loadSticker("cat-galaxy")

// MARK: - エフェクト（アプリの RareEffect に近い見た目を CoreImage で作る）

let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

/// エフェクトをかけたあと、元の形で切り抜き直す（ぼかし系の加工で輪郭がにじまないように）
func masked(_ effected: CIImage, by original: CIImage) -> CIImage {
    effected.cropped(to: original.extent).applyingFilter("CIBlendWithAlphaMask", parameters: [
        kCIInputBackgroundImageKey: CIImage.empty(),
        kCIInputMaskImageKey: original,
    ])
}

func render(_ image: CIImage, extent: CGRect) -> CGImage {
    ciContext.createCGImage(image, from: extent)!
}

/// サーモグラフィ用の色の並び（暗い紫 → 赤 → 橙 → 黄 → 白）
func thermalGradient() -> CIImage {
    let stops: [(CGFloat, CGColor)] = [
        (0, rgb(30, 10, 80)), (0.3, rgb(140, 30, 160)), (0.55, rgb(240, 60, 60)),
        (0.75, rgb(255, 150, 30)), (0.9, rgb(255, 230, 80)), (1, rgb(255, 255, 230)),
    ]
    let ctx = CGContext(data: nil, width: 256, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 256, y: 0), options: [])
    return CIImage(cgImage: ctx.makeImage()!)
}

struct Effect {
    let name: String
    let image: CGImage
}

let effects: [Effect] = {
    let original = CIImage(cgImage: subject)
    let extent = original.extent
    let center = CIVector(x: extent.midX, y: extent.midY)
    let pixel = original.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: 34, kCIInputCenterKey: center])
    let silver = original
        .applyingFilter("CIPhotoEffectNoir")
        .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.35, kCIInputBrightnessKey: 0.12])
    let stained = original
        .applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: 30, kCIInputCenterKey: center])
        .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.6, kCIInputContrastKey: 1.1])
    let thermal = original
        .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: 0.15, kCIInputContrastKey: 1.3])
        .applyingFilter("CIColorMap", parameters: ["inputGradientImage": thermalGradient()])
    return [
        Effect(name: "ドット絵", image: render(pixel.cropped(to: extent), extent: extent)),
        Effect(name: "シルバー", image: render(masked(silver, by: original), extent: extent)),
        Effect(name: "ステンドグラス", image: render(masked(stained, by: original), extent: extent)),
        Effect(name: "サーモグラフィ", image: render(masked(thermal, by: original), extent: extent)),
    ]
}()
/// 章2でエフェクトが切り替わる時刻
let effectTimes = [4.8, 5.7, 6.6, 7.5]
let thermalSubject = effects[3].image

/// 外側の飾り（検索結果では切れてもいい）。左上原点での中心・大きさ・角度・揺れの位相
let decor: [(CGImage, CGPoint, CGFloat, CGFloat, Double)] = [
    (loadSticker("tomato-oil"), CGPoint(x: 420, y: 520), 640, -8, 0.0),
    (loadSticker("eagle-stitch"), CGPoint(x: 3440, y: 500), 600, 6, 0.3),
    (loadSticker("dog-stained"), CGPoint(x: 430, y: 2120), 620, 5, 0.55),
    (loadSticker("jump-silver"), CGPoint(x: 3450, y: 2100), 600, -6, 0.8),
    (loadSticker("sign-pixel"), CGPoint(x: 1250, y: 2270), 420, -12, 0.15),
    (loadSticker("donut-oil"), CGPoint(x: 2650, y: 2290), 480, 10, 0.65),
]

/// 背景の丸（中心・半径・色・揺れの位相）
let blobs: [(CGPoint, CGFloat, CGColor, Double)] = [
    (CGPoint(x: 250, y: 300), 560, orange.copy(alpha: 0.30)!, 0.0),
    (CGPoint(x: 3600, y: 280), 500, sky, 0.25),
    (CGPoint(x: 3560, y: 2300), 620, mint.copy(alpha: 0.8)!, 0.5),
    (CGPoint(x: 220, y: 2330), 580, purple.copy(alpha: 0.28)!, 0.75),
    (CGPoint(x: 900, y: 640), 120, yellow, 0.4),
    (CGPoint(x: 3150, y: 820), 100, pink.copy(alpha: 0.55)!, 0.9),
]

// MARK: - 動きの道具

func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(max(x, a), b) }
func progress(_ t: Double, _ start: Double, _ end: Double) -> Double { clamp((t - start) / (end - start)) }
func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func easeInCubic(_ x: Double) -> Double { x * x * x }
func easeInOutCubic(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func easeOutBack(_ x: Double) -> Double {
    let c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}
func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat { a + (b - a) * CGFloat(p) }
func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint { CGPoint(x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p)) }
/// 15秒で割り切れる周期の揺れ（ループの継ぎ目でずれない）
func wave(_ t: Double, period: Double, phase: Double) -> CGFloat { CGFloat(sin(2 * .pi * (t / period + phase))) }

// MARK: - 描画の部品（すべて左上原点の座標で描く）

/// 素材と同じ形の白いシルエット（白フチ用）。素材ごとに一度だけ作る
var silhouettes: [ObjectIdentifier: CGImage] = [:]
func silhouette(of image: CGImage) -> CGImage {
    if let cached = silhouettes[ObjectIdentifier(image)] { return cached }
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    ctx.clip(to: rect, mask: image)
    ctx.setFillColor(rgb(255, 255, 255))
    ctx.fill(rect)
    let result = ctx.makeImage()!
    silhouettes[ObjectIdentifier(image)] = result
    return result
}

func drawSticker(_ ctx: CGContext, _ image: CGImage, at p: CGPoint, size: CGFloat, angle: CGFloat = 0,
                 scaleX: CGFloat = 1, scaleY: CGFloat = 1, alpha: CGFloat = 1, halo: CGFloat = 0, shadow: Bool = true) {
    guard size > 1, alpha > 0.01 else { return }
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: angle * .pi / 180)
    ctx.scaleBy(x: scaleX, y: scaleY)
    ctx.scaleBy(x: 1, y: -1)
    let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
    // 影はフチと本体をまとめて1つの形として落とす
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    if shadow {
        // 盤面と同じく、少し下に柔らかい影を落とす（影のずれは反転前の座標で指定する）
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.06, color: rgb(40, 30, 20, 0.28))
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    if halo > 0.01 {
        // 切り抜いたシールの白いフチ（白いシルエットを周りにずらして重ねる）
        let white = silhouette(of: image)
        let r = size * 0.022
        ctx.saveGState()
        ctx.setAlpha(halo)
        for i in 0..<16 {
            let a = CGFloat(i) * .pi / 8
            ctx.draw(white, in: rect.offsetBy(dx: r * cos(a), dy: r * sin(a)))
        }
        ctx.restoreGState()
    }
    ctx.draw(image, in: rect)
    ctx.endTransparencyLayer()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// 4本の光が伸びるきらめき
func drawSparkle(_ ctx: CGContext, at p: CGPoint, size: CGFloat, color: CGColor = rgb(255, 255, 255)) {
    guard size > 1 else { return }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.5, color: rgb(255, 230, 150, 0.9))
    ctx.setFillColor(color)
    let path = CGMutablePath()
    let thin = size * 0.16
    path.move(to: CGPoint(x: p.x, y: p.y - size))
    path.addQuadCurve(to: CGPoint(x: p.x + size, y: p.y), control: CGPoint(x: p.x + thin, y: p.y - thin))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + size), control: CGPoint(x: p.x + thin, y: p.y + thin))
    path.addQuadCurve(to: CGPoint(x: p.x - size, y: p.y), control: CGPoint(x: p.x - thin, y: p.y + thin))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - size), control: CGPoint(x: p.x - thin, y: p.y - thin))
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

/// 合体の瞬間の光。p は 0→1 の進み具合
func drawFlash(_ ctx: CGContext, at c: CGPoint, p: Double, scale: CGFloat = 1) {
    guard p > 0 && p < 1 else { return }
    let fade = CGFloat(pow(1 - p, 2))
    let r = (180 + 320 * CGFloat(easeOutCubic(p))) * scale
    ctx.setFillColor(rgb(255, 255, 255, 0.85 * fade))
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    let ring = r * 1.25
    ctx.setStrokeColor(rgb(255, 205, 74, fade))
    ctx.setLineWidth(28 * fade * scale + 2)
    ctx.strokeEllipse(in: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2))
    for i in 0..<6 {
        let a = Double(i) * .pi / 3 + .pi / 12
        let d = (230 + 300 * CGFloat(easeOutCubic(p))) * scale
        drawSparkle(ctx, at: CGPoint(x: c.x + d * CGFloat(cos(a)), y: c.y + d * CGFloat(sin(a))), size: 120 * fade * scale)
    }
}

/// 文字を描く。anchor は描く範囲の中での基準（0,0 = 左上、0.5,0.5 = 中央）
func drawText(_ ctx: CGContext, _ text: String, size: CGFloat, color: CGColor, at p: CGPoint,
              anchor: CGPoint = CGPoint(x: 0.5, y: 0.5), outline: CGFloat = 0, weight: String = "HiraginoSans-W8") {
    let font = NSFont(name: weight, size: size)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let fill = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: size * 0.04,
    ])
    let s = fill.size()
    let origin = CGPoint(x: p.x - s.width * anchor.x, y: p.y - s.height * anchor.y)
    if outline > 0 {
        NSAttributedString(string: text, attributes: [
            .font: font, .strokeColor: NSColor.white, .strokeWidth: outline, .kern: size * 0.04,
        ]).draw(at: origin)
    }
    fill.draw(at: origin)
    NSGraphicsContext.restoreGraphicsState()
}

func textWidth(_ text: String, size: CGFloat) -> CGFloat {
    NSAttributedString(string: text, attributes: [
        .font: NSFont(name: "HiraginoSans-W8", size: size)!, .kern: size * 0.04,
    ]).size().width
}

/// 白い角丸の札（影つき）
func drawPill(_ ctx: CGContext, _ rect: CGRect, fill: CGColor = rgb(255, 255, 255)) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(40, 30, 20, 0.18))
    ctx.setFillColor(fill)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
}

/// 音の波形（棒）。t で揺れる
func drawWaveform(_ ctx: CGContext, center: CGPoint, bars: Int, t: Double, color: CGColor, maxHeight: CGFloat) {
    let gap: CGFloat = 26, barWidth: CGFloat = 14
    let startX = center.x - CGFloat(bars - 1) * gap / 2
    ctx.setFillColor(color)
    for i in 0..<bars {
        let h = maxHeight * CGFloat(0.25 + 0.75 * abs(sin(t * 7 + Double(i) * 0.9) * cos(t * 3.1 + Double(i) * 0.4)))
        let r = CGRect(x: startX + CGFloat(i) * gap - barWidth / 2, y: center.y - h / 2, width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.fillPath()
    }
}

/// マイクのアイコン
func drawMic(_ ctx: CGContext, center c: CGPoint, size s: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    let head = CGRect(x: c.x - s * 0.2, y: c.y - s * 0.5, width: s * 0.4, height: s * 0.62)
    ctx.addPath(CGPath(roundedRect: head, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil))
    ctx.fillPath()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(s * 0.08)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: c.x, y: c.y - s * 0.02), radius: s * 0.32, startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()
    ctx.move(to: CGPoint(x: c.x, y: c.y + s * 0.3))
    ctx.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.48))
    ctx.strokePath()
}

// MARK: - 見出し（章ごとに入れ替わる）

let headlines = ["好きな写真で遊べる", "エフェクトで大変身", "音も自由に変えられる", "ステージを友達に共有"]
/// 見出しが切り替わる時刻と、切り替わったあとの見出し
let headlineSwitches: [(Double, Int)] = [(4.4, 1), (8.9, 2), (13.9, 3), (19.3, 0)]
let headlineY: CGFloat = 520

func drawHeadline(_ ctx: CGContext, t: Double) {
    var current = 0
    var previous: Int?
    var p = 1.0
    for (time, index) in headlineSwitches where t >= time {
        previous = current
        current = index
        p = progress(t, time, time + 0.35)
    }
    func draw(_ index: Int, alpha: Double, dy: CGFloat) {
        guard alpha > 0.01 else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(alpha))
        drawText(ctx, headlines[index], size: 320, color: ink, at: CGPoint(x: 1920, y: headlineY + dy), outline: 32)
        ctx.restoreGState()
    }
    if let previous, p < 1 {
        draw(previous, alpha: 1 - p, dy: -120 * CGFloat(easeOutCubic(p)))
        draw(current, alpha: p, dy: 120 * CGFloat(1 - easeOutCubic(p)))
    } else {
        draw(current, alpha: 1, dy: 0)
    }
}

// MARK: - 章1: 好きな写真で遊べる（0〜4.5秒）

let stageCenter = CGPoint(x: 1920, y: 1380)
let itemSize: CGFloat = 500

func drawChapterPhoto(_ ctx: CGContext, t: Double) {
    guard t < 4.6 else { return }
    let appear = easeOutBack(progress(t, 0.1, 0.6))
    let cut = easeInOutCubic(progress(t, 1.8, 2.3))
    let hop = CGFloat(sin(.pi * progress(t, 2.3, 2.9))) * 110
    let photoSide: CGFloat = 600 * CGFloat(appear)
    guard photoSide > 1 else { return }

    // 写真（白い枠つき）。切り抜くと背景が消えていく
    if cut < 1 {
        ctx.saveGState()
        ctx.setAlpha(CGFloat(1 - cut))
        ctx.translateBy(x: stageCenter.x, y: stageCenter.y)
        ctx.rotate(by: -4 * .pi / 180)
        ctx.scaleBy(x: CGFloat(1 + 0.06 * cut), y: CGFloat(1 + 0.06 * cut))
        let frame = CGRect(x: -photoSide / 2, y: -photoSide / 2, width: photoSide, height: photoSide)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 40, color: rgb(40, 30, 20, 0.25))
        ctx.setFillColor(rgb(255, 255, 255))
        ctx.addPath(CGPath(roundedRect: frame, cornerWidth: 28, cornerHeight: 28, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        // 写真の中身: 壁と木のテーブル
        let inner = frame.insetBy(dx: photoSide * 0.05, dy: photoSide * 0.05)
        ctx.addPath(CGPath(roundedRect: inner, cornerWidth: 14, cornerHeight: 14, transform: nil))
        ctx.clip()
        ctx.setFillColor(rgb(214, 231, 240))
        ctx.fill(inner)
        ctx.setFillColor(rgb(201, 156, 108))
        ctx.fill(CGRect(x: inner.minX, y: inner.minY + inner.height * 0.62, width: inner.width, height: inner.height * 0.38))
        ctx.setFillColor(rgb(176, 131, 86))
        ctx.fill(CGRect(x: inner.minX, y: inner.minY + inner.height * 0.62, width: inner.width, height: 10))
        ctx.setFillColor(rgb(255, 255, 255, 0.5))
        ctx.fillEllipse(in: CGRect(x: inner.minX + inner.width * 0.62, y: inner.minY + inner.height * 0.08,
                                   width: inner.width * 0.26, height: inner.width * 0.26))
        ctx.restoreGState()
    }

    // ドーナツ（写真の一部 → 白フチのシール）
    let subjectSize = lerp(460, itemSize, cut) * CGFloat(appear)
    drawSticker(ctx, subject, at: CGPoint(x: stageCenter.x, y: stageCenter.y - hop), size: subjectSize,
                angle: lerp(-4, 0, cut), halo: CGFloat(cut), shadow: cut > 0.5)

    // 切り抜きの点線（動く点線）
    let ants = progress(t, 0.8, 1.0) * (1 - progress(t, 1.8, 2.1))
    if ants > 0.01 {
        ctx.saveGState()
        ctx.setAlpha(CGFloat(ants))
        let r = CGRect(x: stageCenter.x - 265, y: stageCenter.y - 200, width: 530, height: 420)
        ctx.setLineWidth(12)
        ctx.setStrokeColor(rgb(255, 255, 255))
        ctx.strokeEllipse(in: r)
        ctx.setStrokeColor(ink)
        ctx.setLineDash(phase: CGFloat(t * 160), lengths: [36, 24])
        ctx.strokeEllipse(in: r)
        ctx.restoreGState()
        // 切り抜き中を示すきらめき
        let a = t * 3.2
        drawSparkle(ctx, at: CGPoint(x: stageCenter.x + 235 * CGFloat(cos(a)), y: stageCenter.y + 245 * CGFloat(sin(a))),
                    size: 70 * CGFloat(ants))
    }
}

// MARK: - 章2: エフェクトで大変身（4.5〜9秒）

func currentEffectIndex(_ t: Double) -> Int? {
    effectTimes.lastIndex { t >= $0 }
}

func drawChapterEffect(_ ctx: CGContext, t: Double) {
    guard t >= 4.5 && t < 9.0 else { return }
    let index = currentEffectIndex(t)
    let image = index.map { effects[$0].image } ?? subject
    let switchedAt = index.map { effectTimes[$0] } ?? 0
    let pulse = index == nil ? 0 : 1 - easeOutCubic(progress(t, switchedAt, switchedAt + 0.4))
    drawSticker(ctx, image, at: stageCenter, size: itemSize * CGFloat(1 + 0.14 * pulse), halo: 1)

    if let index {
        // 切り替わりのきらめき
        let p = progress(t, switchedAt, switchedAt + 0.5)
        if p < 1 {
            for i in 0..<4 {
                let a = Double(i) * .pi / 2 + .pi / 4 + Double(index)
                let d = 250 + 90 * CGFloat(easeOutCubic(p))
                drawSparkle(ctx, at: CGPoint(x: stageCenter.x + d * CGFloat(cos(a)), y: stageCenter.y + d * CGFloat(sin(a))),
                            size: 90 * CGFloat(1 - p))
            }
        }
        // エフェクト名の札（右側）
        let labelIn = easeOutBack(progress(t, switchedAt, switchedAt + 0.3))
        let fadeOut = 1 - progress(t, 8.6, 8.9)
        let name = effects[index].name
        let w = textWidth(name, size: 64) + 90
        let rect = CGRect(x: 2210, y: stageCenter.y - 70, width: w, height: 140)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(fadeOut))
        ctx.translateBy(x: rect.minX, y: rect.midY)
        ctx.scaleBy(x: CGFloat(labelIn), y: CGFloat(labelIn))
        ctx.translateBy(x: -rect.minX, y: -rect.midY)
        drawPill(ctx, rect)
        drawText(ctx, name, size: 64, color: purple, at: CGPoint(x: rect.midX, y: rect.midY))
        ctx.restoreGState()
    }
    // 種類の多さ（左側）。アプリの RareEffect は10種類
    let countIn = easeOutBack(progress(t, 5.0, 5.35)) * (1 - progress(t, 8.6, 8.9))
    if countIn > 0.01 {
        let w = textWidth("全10種", size: 64) + 90
        let rect = CGRect(x: 1630 - w, y: stageCenter.y - 70, width: w, height: 140)
        ctx.saveGState()
        ctx.translateBy(x: rect.maxX, y: rect.midY)
        ctx.scaleBy(x: CGFloat(countIn), y: CGFloat(countIn))
        ctx.translateBy(x: -rect.maxX, y: -rect.midY)
        drawPill(ctx, rect, fill: orange)
        drawText(ctx, "全10種", size: 64, color: rgb(255, 255, 255), at: CGPoint(x: rect.midX, y: rect.midY))
        ctx.restoreGState()
    }
}

// MARK: - 章3: 音も自由に変えられる（9〜15秒）

let slotLeft = CGPoint(x: 1530, y: 1350)
let slotRight = CGPoint(x: 2310, y: 1350)
let mergePoint = CGPoint(x: 1920, y: 1360)
/// くっつく前の素材の大きさ。合体後は1.5倍にして「大きくなる」ことを見せる（どちらも centerScale で拡大される前の値）
let partSize: CGFloat = 600
let mergedSize: CGFloat = 900

func drawChapterSound(_ ctx: CGContext, t: Double) {
    guard t >= 9.0 && t < 14.0 else { return }

    // 音符が舞う（BGM）
    let notesAlpha = progress(t, 9.2, 9.6) * (1 - progress(t, 13.4, 13.9))
    if notesAlpha > 0.01 {
        let colors = [pink, purple, orange, rgb(79, 163, 238)]
        for i in 0..<7 {
            let rise = (t * 140 + Double(i) * 170).truncatingRemainder(dividingBy: 640)
            let y = 1600 - CGFloat(rise)
            let x = 1140 + CGFloat(i) * 260 + 30 * CGFloat(sin(t * 2 + Double(i)))
            // 中央の素材と重なる列は薄くする
            let nearCenter = abs(x - 1920) < 600 ? 0.35 : 1.0
            let edgeFade = min(1, rise / 120) * min(1, (640 - rise) / 160)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(notesAlpha * edgeFade * nearCenter))
            drawText(ctx, i % 2 == 0 ? "♪" : "♫", size: 96, color: colors[i % colors.count], at: CGPoint(x: x, y: y),
                     outline: 10, weight: "HiraginoSans-W6")
            ctx.restoreGState()
        }
    }

    // サーモグラフィのドーナツが左へ寄り、右から同じドーナツが転がってくる
    if t < 11.3 {
        let toLeft = easeInOutCubic(progress(t, 9.0, 9.5))
        var leftPoint = lerp(stageCenter, slotLeft, toLeft)
        var rightX = lerp(4200, slotRight.x, easeOutBack(progress(t, 9.9, 10.8)))
        let rightAngle = -(rightX - slotRight.x) / 220 * 20
        var squash: CGFloat = 1
        if t >= 10.9 {
            let p = easeInCubic(progress(t, 10.9, 11.3))
            leftPoint.x = lerp(slotLeft.x, 1770, p)
            rightX = lerp(slotRight.x, 2070, p)
            squash = 1 - 0.12 * CGFloat(p)
        }
        let size = lerp(itemSize, partSize, toLeft)
        drawSticker(ctx, thermalSubject, at: leftPoint, size: size, scaleX: squash, scaleY: 2 - squash, halo: 1)
        if t >= 9.9 {
            drawSticker(ctx, thermalSubject, at: CGPoint(x: rightX, y: slotRight.y), size: partSize, angle: rightAngle,
                        scaleX: squash, scaleY: 2 - squash, halo: 1)
        }
    }

    // 録音中の札（合体の音を自分の声にする）
    let recIn = easeOutBack(progress(t, 9.3, 9.65)) * (1 - easeInCubic(progress(t, 11.0, 11.3)))
    if recIn > 0.01 {
        let rect = CGRect(x: 1920 - 300, y: 990, width: 600, height: 140)
        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: CGFloat(recIn), y: CGFloat(recIn))
        ctx.translateBy(x: -rect.midX, y: -rect.midY)
        drawPill(ctx, rect)
        // 録音中の赤い点が点滅する
        let blink = 0.55 + 0.45 * sin(t * 2 * .pi * 1.5)
        ctx.setFillColor(rgb(232, 64, 64, CGFloat(blink)))
        ctx.fillEllipse(in: CGRect(x: rect.minX + 44, y: rect.midY - 18, width: 36, height: 36))
        drawMic(ctx, center: CGPoint(x: rect.minX + 140, y: rect.midY), size: 92, color: ink)
        drawText(ctx, "録音中", size: 56, color: ink, at: CGPoint(x: rect.minX + 200, y: rect.midY), anchor: CGPoint(x: 0, y: 0.5))
        drawWaveform(ctx, center: CGPoint(x: rect.maxX - 115, y: rect.midY), bars: 7, t: t, color: pink, maxHeight: 90)
        ctx.restoreGState()
    }

    // 合体して、録音した音が鳴る
    if t >= 11.3 {
        let pop = easeOutBack(progress(t, 11.3, 11.8))
        let shrink = 1 - easeInCubic(progress(t, 13.4, 13.8))
        drawSticker(ctx, mergedSticker, at: mergePoint, size: mergedSize * CGFloat(0.4 + 0.6 * pop) * CGFloat(shrink), halo: 1)

        // 音の吹き出し
        let bubbleIn = easeOutBack(progress(t, 11.45, 11.85)) * (1 - easeInCubic(progress(t, 13.2, 13.5)))
        if bubbleIn > 0.01 {
            let rect = CGRect(x: 2270, y: 1060, width: 470, height: 160)
            ctx.saveGState()
            ctx.translateBy(x: rect.minX, y: rect.maxY)
            ctx.scaleBy(x: CGFloat(bubbleIn), y: CGFloat(bubbleIn))
            ctx.translateBy(x: -rect.minX, y: -rect.maxY)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(40, 30, 20, 0.18))
            ctx.setFillColor(rgb(255, 255, 255))
            let bubble = CGMutablePath()
            bubble.addRoundedRect(in: rect, cornerWidth: 70, cornerHeight: 70)
            bubble.move(to: CGPoint(x: rect.minX + 70, y: rect.maxY - 10))
            bubble.addLine(to: CGPoint(x: rect.minX - 30, y: rect.maxY + 70))
            bubble.addLine(to: CGPoint(x: rect.minX + 150, y: rect.maxY - 10))
            ctx.addPath(bubble)
            ctx.fillPath()
            ctx.restoreGState()
            drawText(ctx, "♪", size: 104, color: pink, at: CGPoint(x: rect.minX + 95, y: rect.midY), weight: "HiraginoSans-W6")
            drawWaveform(ctx, center: CGPoint(x: rect.minX + 300, y: rect.midY), bars: 9, t: t, color: purple, maxHeight: 100)
            ctx.restoreGState()
        }
    }
    drawFlash(ctx, at: mergePoint, p: progress(t, 11.3, 11.9), scale: 1.2)
}

// MARK: - 章4: ステージを友達に共有（14〜20秒）

/// 動画用の架空の共有コード（アプリと同じく 0/O・1/I を使わない8文字）
let demoShareCode = "KUTT-UKE2"
let qrCode: CGImage = {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(Data("kuttuke://stage/KUTTUKE2".utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    return render(filter.outputImage!, extent: filter.outputImage!.extent)
}()
let stageStickers: [(CGImage, CGPoint, CGFloat, CGFloat)] = [
    (loadSticker("donut-oil"), CGPoint(x: -120, y: 150), 200, -8),
    (loadSticker("sign-pixel"), CGPoint(x: 130, y: 120), 190, 10),
    (loadSticker("cat-galaxy"), CGPoint(x: 10, y: 20), 230, -4),
]
let stageCardRect = CGRect(x: 1180, y: 1040, width: 560, height: 560)
let codeCardRect = CGRect(x: 2120, y: 1040, width: 560, height: 560)

/// 中心を基準に拡大縮小して描く
func withScale(_ ctx: CGContext, around c: CGPoint, _ s: CGFloat, _ body: () -> Void) {
    guard s > 0.01 else { return }
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: -c.x, y: -c.y)
    body()
    ctx.restoreGState()
}

func drawCard(_ ctx: CGContext, _ rect: CGRect) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: rgb(40, 30, 20, 0.22))
    ctx.setFillColor(rgb(255, 255, 255))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 56, cornerHeight: 56, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
}

/// 紙飛行機。向きは右
func drawPaperPlane(_ ctx: CGContext, at p: CGPoint, angle: CGFloat, size s: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: angle)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: rgb(40, 30, 20, 0.25))
    let wing = CGMutablePath()
    wing.move(to: CGPoint(x: s * 0.6, y: 0))
    wing.addLine(to: CGPoint(x: -s * 0.5, y: -s * 0.42))
    wing.addLine(to: CGPoint(x: -s * 0.22, y: 0))
    wing.addLine(to: CGPoint(x: -s * 0.5, y: s * 0.42))
    wing.closeSubpath()
    ctx.setFillColor(pink)
    ctx.addPath(wing)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.9))
    ctx.setLineWidth(s * 0.05)
    ctx.move(to: CGPoint(x: s * 0.6, y: 0))
    ctx.addLine(to: CGPoint(x: -s * 0.22, y: 0))
    ctx.strokePath()
    ctx.restoreGState()
}

func drawChapterShare(_ ctx: CGContext, t: Double) {
    guard t >= 14.0 else { return }
    let out = 1 - easeInCubic(progress(t, 18.9, 19.3))

    // ステージのカード（盤面に素材が積まれている）
    let stageIn = easeOutBack(progress(t, 14.1, 14.5)) * out
    withScale(ctx, around: CGPoint(x: stageCardRect.midX, y: stageCardRect.midY), CGFloat(stageIn)) {
        drawCard(ctx, stageCardRect)
        drawText(ctx, "わたしのステージ", size: 46, color: ink,
                 at: CGPoint(x: stageCardRect.midX, y: stageCardRect.minY + 70))
        let board = CGRect(x: stageCardRect.minX + 50, y: stageCardRect.minY + 130, width: stageCardRect.width - 100,
                           height: stageCardRect.height - 180)
        ctx.setFillColor(rgb(250, 244, 227))
        ctx.addPath(CGPath(roundedRect: board, cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.fillPath()
        ctx.saveGState()
        ctx.setStrokeColor(rgb(255, 150, 110))
        ctx.setLineWidth(6)
        ctx.setLineDash(phase: 0, lengths: [22, 14])
        ctx.move(to: CGPoint(x: board.minX + 30, y: board.minY + 70))
        ctx.addLine(to: CGPoint(x: board.maxX - 30, y: board.minY + 70))
        ctx.strokePath()
        ctx.restoreGState()
        let base = CGPoint(x: board.midX, y: board.midY)
        for (i, (image, offset, size, angle)) in stageStickers.enumerated() {
            let start = 14.3 + Double(i) * 0.15
            let drop = easeOutBack(progress(t, start, start + 0.4))
            guard drop > 0 else { continue }
            let p = CGPoint(x: base.x + offset.x, y: base.y + offset.y - 160 * CGFloat(1 - drop))
            drawSticker(ctx, image, at: p, size: size, angle: angle, halo: 1)
        }
    }

    // 共有コードと QR コードのカード
    let codeIn = easeOutBack(progress(t, 14.9, 15.3)) * out
    withScale(ctx, around: CGPoint(x: codeCardRect.midX, y: codeCardRect.midY), CGFloat(codeIn)) {
        drawCard(ctx, codeCardRect)
        drawText(ctx, "共有コード", size: 38, color: rgb(99, 102, 99),
                 at: CGPoint(x: codeCardRect.midX, y: codeCardRect.minY + 62))
        drawText(ctx, demoShareCode, size: 64, color: ink, at: CGPoint(x: codeCardRect.midX, y: codeCardRect.minY + 140))
        let qrReveal = easeOutCubic(progress(t, 15.1, 15.6))
        let side: CGFloat = 300
        let qrRect = CGRect(x: codeCardRect.midX - side / 2, y: codeCardRect.minY + 210, width: side, height: side)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(qrReveal))
        ctx.interpolationQuality = .none
        ctx.translateBy(x: 0, y: qrRect.minY * 2 + side)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(qrCode, in: qrRect)
        ctx.restoreGState()
    }

    // 紙飛行機がステージのカードからコードのカードへ飛ぶ（点線の軌跡つき）
    let flight = progress(t, 15.7, 16.8)
    if flight > 0 && flight < 1 {
        func point(_ s: Double) -> CGPoint {
            // 2次ベジェ: ステージのカード → 見出しの下をくぐって → コードのカード
            let a = CGPoint(x: stageCardRect.maxX + 20, y: stageCardRect.midY + 40)
            let c = CGPoint(x: 1930, y: 1000)
            let b = CGPoint(x: codeCardRect.minX + 40, y: codeCardRect.midY + 40)
            let u = CGFloat(s)
            return CGPoint(x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * c.x + u * u * b.x,
                           y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * c.y + u * u * b.y)
        }
        let s = easeInOutCubic(flight)
        ctx.saveGState()
        ctx.setStrokeColor(rgb(240, 87, 122, 0.55))
        ctx.setLineWidth(10)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [2, 34])
        ctx.move(to: point(0))
        for i in 1...40 { ctx.addLine(to: point(s * Double(i) / 40)) }
        ctx.strokePath()
        ctx.restoreGState()
        let p = point(s), q = point(min(1, s + 0.01))
        drawPaperPlane(ctx, at: p, angle: atan2(q.y - p.y, q.x - p.x), size: 150)
    }

    // 届いたしるし
    let sent = progress(t, 16.9, 17.4)
    if sent > 0 {
        let pop = easeOutBack(sent) * out
        let c = CGPoint(x: codeCardRect.maxX - 10, y: codeCardRect.minY + 10)
        withScale(ctx, around: c, CGFloat(pop)) {
            ctx.setFillColor(rgb(79, 190, 120))
            ctx.fillEllipse(in: CGRect(x: c.x - 70, y: c.y - 70, width: 140, height: 140))
            ctx.setStrokeColor(rgb(255, 255, 255))
            ctx.setLineWidth(18)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: c.x - 32, y: c.y + 2))
            ctx.addLine(to: CGPoint(x: c.x - 8, y: c.y + 26))
            ctx.addLine(to: CGPoint(x: c.x + 34, y: c.y - 22))
            ctx.strokePath()
        }
        if sent < 1 {
            for i in 0..<4 {
                let a = Double(i) * .pi / 2 + .pi / 4
                let d = 110 + 80 * CGFloat(sent)
                drawSparkle(ctx, at: CGPoint(x: c.x + d * CGFloat(cos(a)), y: c.y + d * CGFloat(sin(a))),
                            size: 70 * CGFloat(1 - sent))
            }
        }
    }
}

// MARK: - 1コマ

/// 章ごとの中央の動きを、この点を中心にこの倍率で拡大する（各章の座標は拡大前の値）
let centerPivot = CGPoint(x: 1920, y: 1220)
let centerScale: CGFloat = 2

func renderFrame(_ ctx: CGContext, t: Double) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high

    ctx.setFillColor(background)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (c, r, color, phase) in blobs {
        let p = CGPoint(x: c.x + 24 * wave(t, period: 15, phase: phase), y: c.y + 24 * wave(t, period: 5, phase: phase))
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }
    ctx.setFillColor(rgb(255, 255, 255, 0.55))
    ctx.fillEllipse(in: CGRect(x: 1920 - 1150, y: 1250 - 720, width: 2300, height: 1440))

    for (image, c, size, angle, phase) in decor {
        let p = CGPoint(x: c.x, y: c.y + 30 * wave(t, period: 5, phase: phase))
        drawSticker(ctx, image, at: p, size: size, angle: angle + 3 * wave(t, period: 3, phase: phase))
    }

    // 中央の動き（イラスト・札・カード）はまとめて拡大して描く
    withScale(ctx, around: centerPivot, centerScale) {
        drawChapterPhoto(ctx, t: t)
        drawChapterEffect(ctx, t: t)
        drawChapterSound(ctx, t: t)
        drawChapterShare(ctx, t: t)
    }
    drawHeadline(ctx, t: t)
    ctx.restoreGState()
}

// MARK: - 書き出し

let outputDirectory = URL(fileURLWithPath: "AppStoreScreenshots/PromoVideo/output")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func writeStills() {
    let directory = outputDirectory.appendingPathComponent("stills")
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for t in [1.2, 2.7, 6.2, 8.0, 9.6, 10.7, 11.2, 11.6, 12.5, 14.6, 15.4, 16.2, 17.8, 19.6] {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        renderFrame(ctx, t: t)
        // 黄色: Apple のセーフエリア、水色: 検索結果プレビューで見える範囲
        func strokeTopLeft(_ r: CGRect, _ color: CGColor) {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(8)
            ctx.stroke(CGRect(x: r.minX, y: CGFloat(height) - r.maxY, width: r.width, height: r.height))
        }
        strokeTopLeft(safeArea, rgb(255, 210, 0))
        strokeTopLeft(previewArea, rgb(0, 180, 255))
        let url = directory.appendingPathComponent("search_t\(String(format: "%04.1f", t)).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        print("still \(url.path)")
    }
}

func writeVideo(to url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    // 3840x2560 は H.264 の上限を超えることがあるので、失敗したら HEVC で書き直す
    for codec in [AVVideoCodecType.h264, .hevc] {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: 28_000_000, // GitHub の1ファイル100MBの上限に収める（20秒で約70MB）
            AVVideoMaxKeyFrameIntervalKey: Int(fps),
            AVVideoExpectedSourceFrameRateKey: Int(fps),
        ]
        if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { continue }
        writer.add(input)
        guard writer.startWriting() else {
            print("\(codec.rawValue) は使えないため次の形式を試します: \(writer.error?.localizedDescription ?? "")")
            try? FileManager.default.removeItem(at: url)
            continue
        }
        writer.startSession(atSourceTime: .zero)

        var failed = false
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { usleep(2000) }
            guard let pool = adaptor.pixelBufferPool else { failed = true; break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { failed = true; break }
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            renderFrame(ctx, t: Double(frame) / Double(fps))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            if !adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)) {
                print("フレーム \(frame) の書き込みに失敗: \(writer.error?.localizedDescription ?? "")")
                failed = true
                break
            }
            if frame % 90 == 0 { print("  \(frame)/\(frameCount)") }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if !failed && writer.status == .completed {
            print("wrote \(url.path) (\(codec.rawValue))")
            return
        }
        print("\(codec.rawValue) での書き出しに失敗: \(writer.error?.localizedDescription ?? "")")
        try? FileManager.default.removeItem(at: url)
    }
    throw NSError(domain: "promo", code: 1, userInfo: [NSLocalizedDescriptionKey: "動画を書き出せませんでした"])
}

if CommandLine.arguments.contains("--stills") {
    writeStills()
} else {
    try writeVideo(to: outputDirectory.appendingPathComponent("search_3840x2560.mp4"))
}
