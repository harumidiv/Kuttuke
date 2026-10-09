import Foundation
import UIKit

enum SubjectProcessingError: LocalizedError {
    case unreadableImage
    case subjectNotFound
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "画像を読み込めませんでした。別の写真でお試しください。"
        case .subjectNotFound:
            return "背景が透明な切り抜き画像ではありません。写真上の被写体を長押しして、下のエリアへ置いてください。"
        case .renderFailed:
            return "切り抜き画像を作成できませんでした。"
        }
    }
}

enum SubjectExtractor {
    nonisolated private static let canvasPixels = 512
    nonisolated private static let processingMaxPixels: CGFloat = 1600

    nonisolated static func prepare(data: Data) throws -> Data {
        guard let original = UIImage(data: data) else {
            throw SubjectProcessingError.unreadableImage
        }

        let oriented = original.normalizedOrientation()
        let resized = oriented.downsampled(maxDimension: processingMaxPixels)
        guard hasUsefulTransparency(resized) else {
            throw SubjectProcessingError.subjectNotFound
        }

        let normalized = try normalizeToSquare(resized)
        guard let result = normalized.pngData() else {
            throw SubjectProcessingError.renderFailed
        }
        return result
    }

    nonisolated private static func normalizeToSquare(_ image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage,
              let bounds = alphaBounds(in: cgImage),
              let cropped = cgImage.cropping(to: bounds) else {
            throw SubjectProcessingError.subjectNotFound
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: canvasPixels, height: canvasPixels),
            format: format
        )

        let padding = CGFloat(canvasPixels) * 0.07
        let available = CGFloat(canvasPixels) - padding * 2
        let scale = min(available / CGFloat(cropped.width), available / CGFloat(cropped.height))
        let drawSize = CGSize(width: CGFloat(cropped.width) * scale, height: CGFloat(cropped.height) * scale)
        let drawRect = CGRect(
            x: (CGFloat(canvasPixels) - drawSize.width) / 2,
            y: (CGFloat(canvasPixels) - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        return renderer.image { _ in
            UIImage(cgImage: cropped).draw(in: drawRect)
        }
    }

    nonisolated private static func hasUsefulTransparency(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }

        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let transparentPixelCount = stride(from: 3, to: pixels.count, by: 4)
            .reduce(into: 0) { count, index in
                if pixels[index] < 245 { count += 1 }
            }
        return transparentPixelCount > (width * height) / 100
    }

    nonisolated private static func alphaBounds(in image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where pixels[row + x * 4 + 3] > 18 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        let inset = 3
        let x = max(0, minX - inset)
        let y = max(0, minY - inset)
        let right = min(width - 1, maxX + inset)
        let top = min(height - 1, maxY + inset)
        return CGRect(x: x, y: y, width: right - x + 1, height: top - y + 1)
    }
}

private extension UIImage {
    nonisolated func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    nonisolated func downsampled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let factor = maxDimension / longest
        let newSize = CGSize(width: size.width * factor, height: size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
