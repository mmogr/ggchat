// The app icon, drawn rather than stored, so it can be regenerated at any size
// instead of being re-cut by hand. `make icon` runs this.
//
// The mark is a lowercase g whose descender leaves the letterform and ends on
// a dot: the bowl is the conversation, the tail is the pipe, and the dot is the
// machine at the other end of it. It is drawn with paths rather than typeset so
// that it does not depend on a font being installed, and the whole mark is
// centred on its own measured bounding box rather than on numbers chosen by
// eye, so a change to any curve re-centres itself.
//
// iOS wants one full-bleed 1024 square and masks it itself. macOS wants the
// rounded-rectangle shape drawn into a canvas with transparent margin around
// it, at ten sizes. Both come from the same drawing.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Violet rather than the blue every chat app already owns, and dark enough at
// the foot that a white mark holds its edge on a light home screen.
let inkTop: UInt32 = 0x7A_5C_FF
let inkBottom: UInt32 = 0x21_10_63
let mark: UInt32 = 0xFF_FF_FF

/// The mark, in a 1024 design space, as one filled path.
///
/// Strokes are converted to outlines here so the whole thing can be measured
/// and moved as a unit: a stroked path's bounding box does not include its own
/// line width, so centring on it would sit the mark a stroke off centre.
func markPath() -> CGPath {
    let weight: CGFloat = 82
    let bowl = CGPoint(x: 520, y: 640)
    let r: CGFloat = 170

    let outline = CGMutablePath()

    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: bowl.x - r, y: bowl.y - r, width: r * 2, height: r * 2))
    outline.addPath(ring.copy(
        strokingWithWidth: weight, lineCap: .round, lineJoin: .round, miterLimit: 10))

    // The stem down the bowl's right side, then the descender hooking left and
    // running out towards the far machine.
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: bowl.x + r, y: bowl.y + 26))
    stem.addLine(to: CGPoint(x: bowl.x + r, y: 352))
    stem.addCurve(
        to: CGPoint(x: 432, y: 248), control1: CGPoint(x: bowl.x + r, y: 268),
        control2: CGPoint(x: 624, y: 248))
    outline.addPath(stem.copy(
        strokingWithWidth: weight, lineCap: .round, lineJoin: .round, miterLimit: 10))

    // The far machine. Set at a little more than a stroke's gap from the
    // descender's end: touching would read as one letter, and further would
    // read as an unrelated speck.
    let dot: CGFloat = 66
    outline.addEllipse(in: CGRect(x: 306 - dot, y: 248 - dot, width: dot * 2, height: dot * 2))

    return outline
}

/// Draws the icon at `size`, either full-bleed for iOS or as the macOS
/// rounded-rectangle shape inset in a transparent canvas.
func icon(size: CGFloat, mac: Bool) -> CGImage {
    // The iOS icon is written with no alpha channel at all. App Store Connect
    // rejects an iOS app icon that carries one, and a fully opaque alpha
    // channel still counts -- so this is a property of the file rather than of
    // what is drawn into it, and it cannot be checked by looking at the image.
    // The macOS icons keep theirs: their margin is the transparency.
    let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: (mac ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    ctx.interpolationQuality = .high

    // macOS icons are the artwork inside a margin, not edge to edge.
    let inset = mac ? size * 0.096 : 0
    let plate = CGRect(
        x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

    ctx.saveGState()
    if mac {
        ctx.addPath(CGPath(
            roundedRect: plate, cornerWidth: plate.width * 0.2237,
            cornerHeight: plate.width * 0.2237, transform: nil))
        ctx.clip()
    }

    ctx.setFillColor(rgb(inkBottom))
    ctx.fill(plate)
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [rgb(inkTop), rgb(inkBottom)] as CFArray, locations: [0, 1])!
    // Both extend options, or the corners past the end point ship unpainted.
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.minX + plate.width * 0.12, y: plate.maxY - plate.height * 0.06),
        end: CGPoint(x: plate.minX + plate.width * 0.88, y: plate.minY + plate.height * 0.06),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // The mark occupies this much of the plate's width, measured across its
    // own bounding box, so the optical size stays put if a curve moves.
    let coverage: CGFloat = 0.60
    let path = markPath()
    let box = path.boundingBoxOfPath
    let scale = plate.width * coverage / max(box.width, box.height)
    var place = CGAffineTransform(translationX: plate.midX, y: plate.midY)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -box.midX, y: -box.midY)

    ctx.setFillColor(rgb(mark))
    ctx.addPath(path.copy(using: &place)!)
    ctx.fillPath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: "\(out)/\(name)") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

write(icon(size: 1024, mac: false), "icon-ios-1024.png")
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        write(icon(size: CGFloat(pixels), mac: true), "icon-mac-\(points)x\(points)@\(scale)x.png")
    }
}
print("app icon: wrote 11 files to \(out)")
