import AppKit
import CoreImage
import SpriteKit

enum RainTextures {
    /// A soft vertical rain streak.
    static let streak = makeStreak()
    /// A squashed ellipse ripple ring for splash impacts.
    static let ripple = makeRipple()
    /// A large, very faint blob for ground mist.
    static let fog = makeFog()

    private static func render(
        size: CGSize,
        scale: CGFloat,
        blurSigma: CGFloat = 0,
        draw: (CGContext, CGSize) -> Void
    ) -> SKTexture {
        let pxWidth = max(1, Int(size.width * scale))
        let pxHeight = max(1, Int(size.height * scale))
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: pxWidth,
            height: pxHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: scale, y: scale)
        draw(ctx, size)
        var image = ctx.makeImage()!
        if blurSigma > 0 {
            let ci = CIImage(cgImage: image)
            let blurred = ci.applyingGaussianBlur(sigma: Double(blurSigma)).cropped(to: ci.extent)
            if let output = CIContext().createCGImage(blurred, from: ci.extent) {
                image = output
            }
        }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func gradient(
        in space: CGColorSpace,
        tint: (CGFloat, CGFloat, CGFloat),
        stops: [(location: CGFloat, alpha: CGFloat)]
    ) -> CGGradient {
        let colors = stops.map { CGColor(srgbRed: tint.0, green: tint.1, blue: tint.2, alpha: $0.alpha) }
        return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops.map { $0.location })!
    }

    private static func makeStreak() -> SKTexture {
        render(size: CGSize(width: 8, height: 64), scale: 4, blurSigma: 2.5) { ctx, size in
            let w = size.width
            let h = size.height
            let capsule = CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                cornerWidth: w / 2,
                cornerHeight: w / 2,
                transform: nil
            )
            ctx.addPath(capsule)
            ctx.clip()
            let g = gradient(
                in: ctx.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                tint: (0.85, 0.89, 0.97),
                stops: [
                    (0.0, 0.0),
                    (0.32, 0.55),
                    (0.55, 0.95),
                    (0.85, 0.35),
                    (1.0, 0.0),
                ]
            )
            ctx.drawLinearGradient(
                g,
                start: CGPoint(x: w / 2, y: 0),
                end: CGPoint(x: w / 2, y: h),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
    }

    private static func makeRipple() -> SKTexture {
        render(size: CGSize(width: 64, height: 64), scale: 2) { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let g = gradient(
                in: ctx.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                tint: (0.88, 0.92, 1.0),
                stops: [
                    (0.0, 0.0),
                    (0.72, 0.0),
                    (0.84, 0.85),
                    (1.0, 0.0),
                ]
            )
            ctx.drawRadialGradient(
                g,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: size.width / 2,
                options: []
            )
        }
    }

    private static func makeFog() -> SKTexture {
        render(size: CGSize(width: 256, height: 128), scale: 1) { ctx, size in
            ctx.saveGState()
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.scaleBy(x: 1, y: size.height / size.width)
            let g = gradient(
                in: ctx.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                tint: (0.85, 0.90, 1.0),
                stops: [
                    (0.0, 0.5),
                    (0.45, 0.22),
                    (1.0, 0.0),
                ]
            )
            ctx.drawRadialGradient(
                g,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: size.width / 2,
                options: []
            )
            ctx.restoreGState()
        }
    }
}