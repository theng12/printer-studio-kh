#!/usr/bin/swift
//
// Draws the Printer Studio KH app icon and writes it as a PNG.
//
// Run via app/make-icon.sh, which turns the PNG into the .icns the app uses.
//
// Drawn in code rather than shipped as artwork so the icon can be regenerated
// and adjusted without a design tool, and so the repository stays text-only.
//
// Two things follow Apple's conventions deliberately:
//
//   * the rounded square does NOT fill the canvas — macOS icons sit inside a
//     margin, roughly 10% on each side, so icons line up in the Dock and Finder
//   * everything inside is centred on the canvas, horizontally and vertically
//
// Usage:  swift make-icon.swift <output.png> [size]

import AppKit

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "icon.png"
let side = arguments.count > 2 ? (Double(arguments[2]) ?? 1024) : 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(side), pixelsHigh: Int(side),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("could not create bitmap\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.shouldAntialias = true

let s = CGFloat(side)

// MARK: - Rounded square background

let margin = s * 0.09
let card = NSRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
let corner = card.width * 0.2237                      // matches the macOS squircle closely

let cardPath = NSBezierPath(roundedRect: card, xRadius: corner, yRadius: corner)
let background = NSGradient(colors: [
    NSColor(srgbRed: 0.29, green: 0.51, blue: 0.96, alpha: 1),
    NSColor(srgbRed: 0.11, green: 0.24, blue: 0.66, alpha: 1),
])!
background.draw(in: cardPath, angle: -90)

// A soft highlight along the top edge, which is what gives Big Sur icons depth.
NSGraphicsContext.saveGraphicsState()
cardPath.addClip()
let sheen = NSGradient(colors: [
    NSColor(white: 1, alpha: 0.22),
    NSColor(white: 1, alpha: 0.0),
])!
sheen.draw(in: NSRect(x: card.minX, y: card.midY, width: card.width, height: card.height / 2),
           angle: -90)
NSGraphicsContext.restoreGraphicsState()

// MARK: - The printer, centred

// Everything below is laid out as fractions of the card, then centred on the
// canvas, so the artwork stays put whatever the output size.
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: card.minX + card.width * x,
           y: card.minY + card.height * y,
           width: card.width * w,
           height: card.height * h)
}

let paperWhite = NSColor(white: 1.0, alpha: 1.0)
let shellWhite = NSColor(white: 0.97, alpha: 1.0)

// Sheet standing in the feed, behind the body.
let feed = box(0.315, 0.545, 0.370, 0.255)
paperWhite.setFill()
NSBezierPath(roundedRect: feed, xRadius: s * 0.014, yRadius: s * 0.014).fill()

// A couple of faint text lines so the sheet reads as paper, not a blank card.
NSColor(srgbRed: 0.60, green: 0.66, blue: 0.80, alpha: 1).setFill()
for offset in [CGFloat(0.185), 0.135] {
    NSRect(x: feed.minX + feed.width * 0.14,
           y: feed.minY + feed.height * offset,
           width: feed.width * 0.72,
           height: s * 0.016).fill()
}

// The printer body.
let body = box(0.215, 0.275, 0.570, 0.310)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: s * 0.038, yRadius: s * 0.038)
shellWhite.setFill()
bodyPath.fill()

// The output slot across the body.
NSColor(srgbRed: 0.16, green: 0.30, blue: 0.68, alpha: 1).setFill()
NSRect(x: body.minX + body.width * 0.12,
       y: body.midY - s * 0.008,
       width: body.width * 0.62,
       height: s * 0.022).fill()

// Status light, in green so it reads as "ready".
NSColor(srgbRed: 0.20, green: 0.78, blue: 0.45, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: body.maxX - body.width * 0.22,
                            y: body.midY - s * 0.014,
                            width: s * 0.028, height: s * 0.028)).fill()

// The sheet coming out, in front of the body.
let out = box(0.315, 0.155, 0.370, 0.150)
paperWhite.setFill()
NSBezierPath(roundedRect: out, xRadius: s * 0.014, yRadius: s * 0.014).fill()
NSColor(srgbRed: 0.60, green: 0.66, blue: 0.80, alpha: 1).setFill()
NSRect(x: out.minX + out.width * 0.14,
       y: out.minY + out.height * 0.38,
       width: out.width * 0.72,
       height: s * 0.016).fill()

NSGraphicsContext.restoreGraphicsState()

// MARK: - Write it out

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode PNG\n".utf8))
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("wrote \(outputPath) (\(Int(side))x\(Int(side)), \(png.count) bytes)")
} catch {
    FileHandle.standardError.write(Data("could not write \(outputPath): \(error)\n".utf8))
    exit(1)
}
