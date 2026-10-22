import simd
import UIKit

/// 切り抜きの形（不透明な部分）を低解像度で持つ。気泡が絵の外へはみ出さないようにするために使う
final class BubbleMask {
    private static let size = 64
    private static let cache = NSCache<UIImage, BubbleMask>()

    private let alpha: [UInt8]

    static func cached(for image: UIImage) -> BubbleMask {
        if let mask = cache.object(forKey: image) { return mask }
        let mask = BubbleMask(image: image)
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

    /// uv（左上原点の0〜1）の位置が絵の内側か
    func isInside(_ point: SIMD2<Float>) -> Bool {
        guard point.x >= 0, point.x < 1, point.y >= 0, point.y < 1 else { return false }
        let x = Int(point.x * Float(Self.size))
        let y = Int(point.y * Float(Self.size))
        return alpha[y * Self.size + x] > 128
    }
}

/// 水入りシールの気泡。端末を傾けると、重力と反対の向きへゆっくり浮いていく
final class BubbleSimulation {
    /// 気泡の半径（絵の大きさに対する割合）。シェーダー側（RareEffect.swift の waterShaderSource）と数と大きさを合わせる
    static let radii: [Float] = [0.085, 0.066, 0.052, 0.042]

    private let mask: BubbleMask
    private(set) var positions: [SIMD2<Float>]
    private var velocities: [SIMD2<Float>]
    private var lastTime: TimeInterval?

    init(mask: BubbleMask) {
        self.mask = mask
        velocities = Array(repeating: .zero, count: Self.radii.count)
        positions = []
        positions = Self.radii.map { randomPoint(radius: $0) }
    }

    /// rise: 気泡が浮かぶ向き（uv、y下向き）。端末を水平に寝かせると0に近づき、気泡はほとんど動かない
    func step(rise: SIMD2<Float>, time: TimeInterval) {
        // 画面遷移などで間が空いても、気泡が一気に飛ばないようにする
        let dt = Float(min(max(time - (lastTime ?? time), 0), 1.0 / 20))
        lastTime = time
        guard dt > 0 else { return }

        let side = SIMD2(-rise.y, rise.x)
        for index in positions.indices {
            let radius = Self.radii[index]
            var velocity = velocities[index]
            // 大きい気泡ほど速く浮く
            velocity += rise * (1.4 + radius * 8) * dt
            // まっすぐではなく、ゆらゆら揺れながら浮く
            velocity += side * sin(Float(time) * 2.3 + Float(index) * 1.7) * 0.25 * dt
            // 気泡同士は重ならないよう押し合う
            for other in positions.indices where other != index {
                let offset = positions[index] - positions[other]
                let distance = simd_length(offset)
                let minimum = radius + Self.radii[other]
                if distance < minimum, distance > 0.0001 {
                    let push: Float = (minimum - distance) * 6 / distance
                    velocity += offset * push
                }
            }
            // 水の抵抗
            velocity *= max(0, 1 - 3.5 * dt)

            let current = positions[index]
            var next = current + velocity * dt
            if !fits(next, radius: radius) {
                // 縁に当たったら、縁に沿って滑らせる
                let slideX = SIMD2(next.x, current.y)
                let slideY = SIMD2(current.x, next.y)
                if fits(slideX, radius: radius) {
                    next = slideX
                    velocity.y = 0
                } else if fits(slideY, radius: radius) {
                    next = slideY
                    velocity.x = 0
                } else {
                    next = current
                    velocity = .zero
                }
            }
            positions[index] = next
            velocities[index] = velocity
        }
    }

    /// シェーダーに渡す形（x, y, 半径の繰り返し）
    var packed: [Float] {
        zip(positions, Self.radii).flatMap { [$0.x, $0.y, $1] }
    }

    private func fits(_ point: SIMD2<Float>, radius: Float) -> Bool {
        let edge = radius * 0.9
        return mask.isInside(point)
            && mask.isInside(point + SIMD2(edge, 0))
            && mask.isInside(point - SIMD2(edge, 0))
            && mask.isInside(point + SIMD2(0, edge))
            && mask.isInside(point - SIMD2(0, edge))
    }

    private func randomPoint(radius: Float) -> SIMD2<Float> {
        for _ in 0..<60 {
            let point = SIMD2(Float.random(in: 0.1...0.9), Float.random(in: 0.1...0.9))
            if fits(point, radius: radius) { return point }
        }
        return SIMD2(0.5, 0.5)
    }
}
