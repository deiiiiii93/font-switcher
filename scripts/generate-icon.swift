import AppKit
import CoreText

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ns = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ns
let c = ns.cgContext
c.clear(CGRect(x: 0, y: 0, width: size, height: size))
c.setAllowsAntialiasing(true)
c.setShouldAntialias(true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}
func round(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func gradient(_ rect: CGRect, radius: CGFloat, colors: [CGColor], start: CGPoint, end: CGPoint) {
    c.saveGState()
    c.addPath(round(rect, radius)); c.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    c.drawLinearGradient(g, start: start, end: end, options: [])
    c.restoreGState()
}
func letter(_ s: String, font: String, size: CGFloat, center: CGPoint, ink: CGColor) {
    let face = CTFontCreateWithName(font as CFString, size, nil)
    let str = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): face,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink])
    let line = CTLineCreateWithAttributedString(str)
    let box = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    c.textMatrix = .identity
    c.textPosition = CGPoint(x: center.x - box.midX, y: center.y - box.midY)
    CTLineDraw(line, c)
}
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -13), blur: 28, color: color(0.03, 0.04, 0.15, 0.28))
c.setFillColor(color(0.18, 0.20, 0.38)); c.addPath(round(tile, 192)); c.fillPath()
c.restoreGState()
gradient(tile, radius: 192, colors: [color(0.12, 0.15, 0.28), color(0.25, 0.29, 0.47), color(0.36, 0.40, 0.57)], start: CGPoint(x: 210, y: 120), end: CGPoint(x: 790, y: 930))
c.addPath(round(tile.insetBy(dx: 3, dy: 3), 189)); c.setStrokeColor(color(1, 1, 1, 0.14)); c.setLineWidth(3); c.strokePath()

// Two type specimen cards: contrasting glyphs are the visual focus.
func card(rect: CGRect, angle: CGFloat, top: CGColor, bottom: CGColor, glyph: String, face: String, fontSize: CGFloat, ink: CGColor) {
    c.saveGState()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    c.translateBy(x: center.x, y: center.y); c.rotate(by: angle); c.translateBy(x: -center.x, y: -center.y)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -15), blur: 24, color: color(0.03, 0.04, 0.10, 0.35))
    c.setFillColor(bottom); c.addPath(round(rect, 39)); c.fillPath()
    c.restoreGState()
    gradient(rect, radius: 39, colors: [bottom, top], start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY))
    c.addPath(round(rect.insetBy(dx: 2, dy: 2), 37)); c.setStrokeColor(color(1, 1, 1, 0.45)); c.setLineWidth(2); c.strokePath()
    letter(glyph, font: face, size: fontSize, center: CGPoint(x: rect.midX, y: rect.midY + 12), ink: ink)
    c.restoreGState()
}
card(rect: CGRect(x: 216, y: 334, width: 300, height: 390), angle: 0.07,
     top: color(0.96, 0.94, 0.89), bottom: color(0.83, 0.84, 0.85), glyph: "A", face: "Georgia-Bold", fontSize: 240, ink: color(0.16, 0.18, 0.30))
card(rect: CGRect(x: 510, y: 300, width: 300, height: 390), angle: -0.07,
     top: color(0.98, 0.84, 0.72), bottom: color(0.91, 0.66, 0.53), glyph: "a", face: "HelveticaNeue-Medium", fontSize: 300, ink: color(0.25, 0.19, 0.25))

// A compact pill evokes switching without competing with the letterforms.
let pill = CGRect(x: 405, y: 183, width: 214, height: 74)
c.setFillColor(color(0.07, 0.09, 0.18, 0.48)); c.addPath(round(pill, 37)); c.fillPath()
c.setStrokeColor(color(1, 1, 1, 0.13)); c.setLineWidth(2); c.addPath(round(pill.insetBy(dx: 1, dy: 1), 36)); c.strokePath()
c.setFillColor(color(0.93, 0.79, 0.69)); c.fillEllipse(in: CGRect(x: 549, y: 194, width: 52, height: 52))
c.setFillColor(color(1, 1, 1, 0.45)); c.fillEllipse(in: CGRect(x: 426, y: 212, width: 16, height: 16))
NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
