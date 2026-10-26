import simd
import UIKit
import Vision

/// 切り抜きの形（不透明な部分）を低解像度で持つ。顔が見つからない素材でぎょろ目を置く位置を決めるために使う
final class SubjectMask {
    private static let size = 64
    private static let cache = NSCache<UIImage, SubjectMask>()

    private let alpha: [UInt8]

    static func cached(for image: UIImage) -> SubjectMask {
        if let mask = cache.object(forKey: image) { return mask }
        let mask = SubjectMask(image: image)
        cache.setObject(mask, forKey: image)
        return mask
    }

    private init(image: UIImage) {
        let size = Self.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // 画像の向きを正しく反映した状態で縮小する
        let upright = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        if let cgImage = upright.cgImage {
            pixels.withUnsafeMutableBytes { buffer in
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: size,
                    height: size,
                    bitsPerComponent: 8,
                    bytesPerRow: size * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            }
        }
        alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    /// 絵（不透明な部分）を囲む範囲（uv）。何も描かれていなければ全体
    var opaqueBounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
        var minPoint = SIMD2<Float>(1, 1)
        var maxPoint = SIMD2<Float>(0, 0)
        for y in 0..<Self.size {
            for x in 0..<Self.size where alpha[y * Self.size + x] > 128 {
                let point = SIMD2(Float(x), Float(y)) / Float(Self.size)
                minPoint = simd_min(minPoint, point)
                maxPoint = simd_max(maxPoint, point + 1 / Float(Self.size))
            }
        }
        return minPoint.x < maxPoint.x ? (minPoint, maxPoint) : (.zero, SIMD2(1, 1))
    }
}

/// ぎょろ目を置く位置。centers は uv（左上原点の0〜1）、radius は画像の短い辺を1とした長さ
struct GooglyEyeLayout: Sendable {
    var centers: (SIMD2<Float>, SIMD2<Float>)
    var radius: Float
}

/// 写真の顔から目の位置を探す。顔が見つからないときは、絵の上の方に並べて置く
enum GooglyEyeDetector {
    private final class Box {
        let layout: GooglyEyeLayout
        init(_ layout: GooglyEyeLayout) { self.layout = layout }
    }

    private static let cache = NSCache<UIImage, Box>()

    static func layout(for image: UIImage) async -> GooglyEyeLayout {
        if let cached = cache.object(forKey: image) { return cached.layout }
        let fallback = fallbackLayout(for: image)
        guard let cgImage = image.cgImage else { return fallback }
        let aspect = Float(image.size.width / max(image.size.height, 1))
        let detected = await Task.detached(priority: .userInitiated) {
            detectEyes(in: cgImage, aspect: aspect)
        }.value
        let layout = detected ?? fallback
        cache.setObject(Box(layout), forKey: image)
        return layout
    }

    /// 顔が見つからない素材では、絵の上から3割くらいの高さに目を2つ並べる
    private static func fallbackLayout(for image: UIImage) -> GooglyEyeLayout {
        let bounds = SubjectMask.cached(for: image).opaqueBounds
        let size = bounds.max - bounds.min
        let y = bounds.min.y + size.y * 0.28
        let centerX = (bounds.min.x + bounds.max.x) / 2
        let aspect = Float(image.size.width / max(image.size.height, 1))
        let unitWidth = size.x * max(aspect, 1)
        return GooglyEyeLayout(
            centers: (SIMD2(centerX - size.x * 0.17, y), SIMD2(centerX + size.x * 0.17, y)),
            radius: min(max(unitWidth * 0.12, 0.04), 0.15)
        )
    }

    private nonisolated static func detectEyes(in cgImage: CGImage, aspect: Float) -> GooglyEyeLayout? {
        let request = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        // いちばん大きく写っている顔を使う
        guard let face = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            return nil
        }
        let box = face.boundingBox
        func toUV(_ point: CGPoint) -> SIMD2<Float> {
            // Visionは左下原点なので、上下を反転する
            SIMD2(Float(box.minX + point.x * box.width), Float(1 - (box.minY + point.y * box.height)))
        }
        func center(of region: VNFaceLandmarkRegion2D?) -> SIMD2<Float>? {
            guard let points = region?.normalizedPoints, !points.isEmpty else { return nil }
            let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return toUV(CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count)))
        }
        let left = center(of: face.landmarks?.leftEye) ?? toUV(CGPoint(x: 0.3, y: 0.62))
        let right = center(of: face.landmarks?.rightEye) ?? toUV(CGPoint(x: 0.7, y: 0.62))
        // 短い辺を1とした長さで目の間隔を測り、ほぼくっつくくらい大きな目にする
        let unitScale = aspect >= 1 ? SIMD2<Float>(aspect, 1) : SIMD2<Float>(1, 1 / aspect)
        let distance = simd_length((right - left) * unitScale)
        return GooglyEyeLayout(centers: (left, right), radius: min(max(distance * 0.42, 0.04), 0.2))
    }
}

/// ぎょろ目の黒目。重力の向きへ転がり、端末を振ったりアイテムがぶつかったりすると目の中で跳ねる
final class GooglyEyesSimulation {
    var layout: GooglyEyeLayout?
    private var pupils: [SIMD2<Float>] = [.zero, .zero]
    private var velocities: [SIMD2<Float>] = [.zero, .zero]
    private var lastTime: TimeInterval?
    /// 左右の目で少し動きを変え、そろって動きすぎないようにする
    private let damping: [Float] = [1.0, 1.5]

    /// fall: 黒目が転がる向き（uv、y下向き）。jolt: 揺さぶられた加速度（uv）。黒目は反対向きに取り残される
    func step(fall: SIMD2<Float>, jolt: SIMD2<Float>, time: TimeInterval) {
        let dt = Float(min(max(time - (lastTime ?? time), 0), 1.0 / 20))
        lastTime = time
        guard dt > 0, let layout else { return }

        // 黒目の半径は白目の半分なので、動ける範囲は半径の半分
        let travel = layout.radius * 0.5
        for index in pupils.indices {
            var velocity = velocities[index] + (fall * 3.0 - jolt * 2.5) * dt
            velocity *= max(0, 1 - damping[index] * dt)
            var pupil = pupils[index] + velocity * dt
            let distance = simd_length(pupil)
            if distance > travel {
                // 白目のふちで跳ね返る
                let normal = pupil / distance
                pupil = normal * travel
                let outward = simd_dot(velocity, normal)
                if outward > 0 { velocity -= normal * outward * 1.45 }
            }
            pupils[index] = pupil
            velocities[index] = velocity
        }
    }

    var eyeCenters: SIMD4<Float> {
        guard let layout else { return .zero }
        return SIMD4(layout.centers.0.x, layout.centers.0.y, layout.centers.1.x, layout.centers.1.y)
    }

    var radius: Float { layout?.radius ?? 0 }

    var pupilOffsets: SIMD4<Float> {
        SIMD4(pupils[0].x, pupils[0].y, pupils[1].x, pupils[1].y)
    }
}
