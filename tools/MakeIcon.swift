// Draws the Blinders app icon at 1024 px: a grainy, blurred Arc-style gradient
// with soft background windows, and one crisp window in front.
// Run through tools/make-icon.sh, which turns it into Resources/AppIcon.icns.
import AppKit
import CoreImage

let size = 1024
let S = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func context() -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// macOS icon grid: 824 pt body on a 1024 canvas, ~22.4% corner radius.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = rounded(body, 185)

// 1. Background windows, drawn sharp, then blurred.
let back = context()
back.setFillColor(rgb(0x2B1F7A))
back.fill(CGRect(x: 0, y: 0, width: S, height: S))
let gradient = CGGradient(colorsSpace: space,
                          colors: [rgb(0x3D2BD9), rgb(0xC2308F), rgb(0xFF7A3D)] as CFArray,
                          locations: [0, 0.55, 1])!
back.drawLinearGradient(gradient, start: CGPoint(x: 120, y: 940), end: CGPoint(x: 920, y: 90), options: [])
for (rect, alpha) in [
    (CGRect(x: 150, y: 560, width: 420, height: 300), 0.30),
    (CGRect(x: 520, y: 600, width: 360, height: 260), 0.22),
    (CGRect(x: 170, y: 150, width: 330, height: 250), 0.20),
    (CGRect(x: 560, y: 170, width: 330, height: 290), 0.26),
] {
    back.setFillColor(rgb(0xFFFFFF, alpha))
    back.addPath(rounded(rect, 40))
    back.fillPath()
}
let ci = CIImage(cgImage: back.makeImage()!)
let blurred = ci.clampedToExtent().applyingGaussianBlur(sigma: 26).cropped(to: ci.extent)
let blurredImage = CIContext().createCGImage(blurred, from: ci.extent)!

// 2. Compose inside the rounded body.
let ctx = context()
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.draw(blurredImage, in: CGRect(x: 0, y: 0, width: S, height: S))
ctx.setFillColor(rgb(0x000000, 0.04))
ctx.fill(body)

// 3. Grain over the blur only, so the front window reads as the sharp one.
var noise = [UInt8](repeating: 0, count: size * size * 4)
for i in 0..<(size * size) {
    let v = UInt8.random(in: 0...255)
    let a: UInt8 = 30   // ~12% opacity, premultiplied
    let pv = UInt8(Int(v) * Int(a) / 255)
    noise[i * 4] = pv; noise[i * 4 + 1] = pv; noise[i * 4 + 2] = pv; noise[i * 4 + 3] = a
}
let noiseImage = noise.withUnsafeMutableBytes { buf -> CGImage in
    CGContext(data: buf.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}
ctx.draw(noiseImage, in: CGRect(x: 0, y: 0, width: S, height: S))

// 4. The focus window: crisp, white, lifted by a shadow.
let card = CGRect(x: 232, y: 300, width: 560, height: 420)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: rgb(0x14082E, 0.45))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.addPath(rounded(card, 48))
ctx.fillPath()
ctx.restoreGState()

// Title bar dots.
for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
    ctx.setFillColor(rgb(UInt32(color)))
    ctx.fillEllipse(in: CGRect(x: card.minX + 42 + CGFloat(i) * 46, y: card.maxY - 66, width: 28, height: 28))
}
ctx.setFillColor(rgb(0xECE8F5))
ctx.fill(CGRect(x: card.minX, y: card.maxY - 100, width: card.width, height: 3))

// Content: a headline bar and three text lines, in the gradient's indigo.
ctx.setFillColor(rgb(0x4B3BE0))
ctx.addPath(rounded(CGRect(x: card.minX + 50, y: card.maxY - 170, width: 260, height: 34), 17))
ctx.fillPath()
ctx.setFillColor(rgb(0xD9D4EA))
for (i, w) in [440, 400, 300].enumerated() {
    ctx.addPath(rounded(CGRect(x: card.minX + 50, y: card.maxY - 240 - CGFloat(i) * 52, width: CGFloat(w), height: 24), 12))
    ctx.fillPath()
}
ctx.restoreGState()

// 5. A faint light edge around the body.
ctx.addPath(rounded(body.insetBy(dx: 1.5, dy: 1.5), 184))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.22))
ctx.setLineWidth(3)
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
